-- ─────────────────────────────────────────────────────────────────────────────
-- Rocket Crash — Phase R1: backend-authoritative 24/7 rounds
--
-- Problem (audit): round LIFECYCLE for Rocket Crash was 100% client-driven.
-- The crash result was already server-generated, but no round was created,
-- flown, or settled unless a client had the screen open driving timers. With
-- nobody inside, rounds never advanced and the history bar (which only shows
-- crashed rounds) stayed empty. Hungry Cat avoids this with a pg_cron job;
-- Rocket Crash had no equivalent.
--
-- This migration adds a self-contained, SECURITY DEFINER advance function plus
-- a pg_cron job that drives the full lifecycle server-side, exactly like
-- hungry_cat_auto_advance. It also masks the crash multiplier until a round
-- has crashed (fairness), and makes the realtime publication adds idempotent.
--
-- Coexistence: existing client RPCs (start_rocket_crash_flight,
-- settle_rocket_crash_round, get_or_create_rocket_crash_round) are NOT removed
-- and remain idempotent, so the live client and this cron run side by side.
--
-- Wallet/coins math is UNCHANGED. The settlement logic below is copied
-- verbatim from settle_rocket_crash_round (same payout formula, same
-- wallet_transactions rows); the flight crash distribution is copied verbatim
-- from start_rocket_crash_flight. No new or different balance math is
-- introduced.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. advance_rocket_crash_rounds() ─────────────────────────────────────────
-- Drives the full lifecycle once per tick. Idempotent + concurrency-safe via
-- the SAME advisory lock key used by get_or_create_rocket_crash_round, so a
-- cron tick and a client call can never create duplicate rounds.
--
-- Per tick, in order:
--   (1) Settle every 'flying' round whose server crash moment has passed
--       (now >= flight_starts_at + ln(crash_multiplier)/0.055 seconds). This
--       pays auto-cashout winners and marks the rest lost, then sets 'crashed'.
--       Also resolves rounds orphaned by a client that left mid-flight.
--   (2) Transition recently-expired 'betting' rounds to 'flying' (commit the
--       crash point) so the lifecycle keeps moving when nobody is inside.
--       Scoped to the last 2 minutes so a backlog of ancient abandoned betting
--       rounds is left untouched for the Phase R3 sweeper (no thundering herd).
--   (3) If no active round remains (no unexpired betting, no recent flying),
--       open a fresh 8-second betting round — identical to get_or_create.
--
-- Not granted to authenticated: only the cron (definer/owner) runs it.

create or replace function public.advance_rocket_crash_rounds()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now      timestamptz := now();
  v_round    public.rocket_crash_global_rounds;
  v_bet      record;
  v_win      integer;
  v_rand     numeric;
  v_crash    numeric;
  v_rnum     bigint;
  v_settled  int := 0;
  v_flew     int := 0;
  v_created  boolean := false;
  c_bet_s    constant int := 8;
begin
  -- Same lock key as get_or_create_rocket_crash_round → mutual exclusion.
  perform pg_advisory_xact_lock(hashtext('rocket_crash_global_round'));

  -- ── (1) Settle due flying rounds ───────────────────────────────────────────
  -- Mirrors settle_rocket_crash_round exactly (payout formula + tx rows).
  for v_round in
    select *
    from public.rocket_crash_global_rounds
    where status = 'flying'
      and crash_multiplier is not null
      and v_now >= flight_starts_at
                   + (ln(crash_multiplier::float8) / 0.055) * interval '1 second'
    order by created_at
    for update
  loop
    -- Pay auto-cashout bets whose target is at or below the crash multiplier
    for v_bet in
      select b.* from public.rocket_crash_global_bets b
      where b.round_id = v_round.id
        and b.status = 'active'
        and b.auto_cashout_multiplier is not null
        and b.auto_cashout_multiplier <= v_round.crash_multiplier
    loop
      v_win := floor(v_bet.bet_amount * v_bet.auto_cashout_multiplier)::integer;

      update public.rocket_crash_global_bets
      set status             = 'cashed_out',
          cashout_multiplier = v_bet.auto_cashout_multiplier,
          win_amount         = v_win,
          cashed_out_at      = now()
      where id = v_bet.id;

      update public.wallets
      set coins_balance = coins_balance + v_win, updated_at = now()
      where user_id = v_bet.user_id;

      insert into public.wallet_transactions
        (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
      values
        (v_bet.user_id, 'crash_rocket_win', 'credit', v_win, 0,
         'Rocket Crash auto-cashout at ' || v_bet.auto_cashout_multiplier || 'x',
         jsonb_build_object('bet_id', v_bet.id, 'round_id', v_round.id,
                            'multiplier', v_bet.auto_cashout_multiplier,
                            'auto', true, 'settled_by', 'cron'));
    end loop;

    -- Mark remaining active bets as lost
    update public.rocket_crash_global_bets
    set status = 'lost'
    where round_id = v_round.id and status = 'active';

    update public.rocket_crash_global_rounds
    set status = 'crashed', crashed_at = now()
    where id = v_round.id;

    v_settled := v_settled + 1;
  end loop;

  -- ── (2) Transition recently-expired betting rounds to flying ───────────────
  -- Mirrors start_rocket_crash_flight's crash distribution exactly.
  for v_round in
    select *
    from public.rocket_crash_global_rounds
    where status = 'betting'
      and betting_ends_at <= v_now
      and betting_ends_at >  v_now - interval '2 minutes'  -- skip ancient backlog
    order by created_at
    for update
  loop
    -- Idempotent guard (row may have changed under a concurrent client call)
    if v_round.status <> 'betting' then
      continue;
    end if;

    v_rand := random();
    if v_rand < 0.04 then
      v_crash := 1.00;
    elsif v_rand < 0.08 then
      v_crash := round((1.00 + random() * 0.04)::numeric, 2);
    else
      v_crash := round(greatest(1.01, least(200.00, 0.96 / (1 - v_rand)))::numeric, 2);
    end if;

    update public.rocket_crash_global_rounds
    set status           = 'flying',
        flight_starts_at = v_now,
        crash_multiplier = v_crash
    where id = v_round.id
      and status = 'betting';   -- re-check: client may have flown it first

    v_flew := v_flew + 1;
  end loop;

  -- ── (3) Ensure an active round exists (create new betting if none) ─────────
  -- Active-round detection mirrors get_or_create_rocket_crash_round exactly.
  if not exists (
    select 1 from public.rocket_crash_global_rounds
    where status = 'betting' and betting_ends_at > v_now
  ) and not exists (
    select 1 from public.rocket_crash_global_rounds
    where status = 'flying'
      and flight_starts_at > v_now - interval '120 seconds'
  ) then
    v_rnum := nextval('public.rocket_crash_round_seq');
    insert into public.rocket_crash_global_rounds
      (round_number, status, betting_starts_at, betting_ends_at)
    values
      (v_rnum, 'betting', v_now, v_now + (c_bet_s || ' seconds')::interval);
    v_created := true;
  end if;

  return jsonb_build_object(
    'settled', v_settled,
    'flew',    v_flew,
    'created', v_created,
    'now',     extract(epoch from v_now) * 1000
  );
end;
$$;

-- Intentionally NOT granted to authenticated — only the cron job runs this.

-- ── 2. pg_cron auto-advance job ──────────────────────────────────────────────
-- Mirrors hungry_cat_auto_advance. Installed only if pg_cron is available.
-- Tries the finest cadence (15-second, pg_cron >= 1.4 second-precision); if the
-- seconds syntax is unsupported, falls back to the standard 1-minute schedule.

do $$
declare
  v_job_name text := 'rocket_crash_auto_advance';
begin
  if not exists (
    select 1 from pg_catalog.pg_extension where extname = 'pg_cron'
  ) then
    raise notice 'pg_cron not available — Rocket Crash auto-advance will rely on client triggers';
    return;
  end if;

  -- Remove any existing job with this name before re-adding
  if exists (select 1 from cron.job where jobname = v_job_name) then
    perform cron.unschedule(v_job_name);
  end if;

  begin
    -- Finest cadence: every 15 seconds (requires pg_cron >= 1.4)
    perform cron.schedule(
      v_job_name,
      '15 seconds',
      $cron$ select public.advance_rocket_crash_rounds(); $cron$
    );
    raise notice 'Rocket Crash auto-advance cron job scheduled (every 15 seconds)';
  exception when others then
    -- Fall back to standard 1-minute granularity
    perform cron.schedule(
      v_job_name,
      '* * * * *',
      $cron$ select public.advance_rocket_crash_rounds(); $cron$
    );
    raise notice 'Rocket Crash auto-advance cron job scheduled (every minute — seconds syntax unavailable)';
  end;
end;
$$;

-- ── 3. Mask crash_multiplier until crashed (fairness) ────────────────────────
-- Re-create get_or_create_rocket_crash_round identically EXCEPT that the
-- multiplier is never exposed while a round is still 'betting'/'flying'. Only a
-- 'crashed' round (never returned by this function) would carry it. This closes
-- the pre-reveal leak where a mid-flight poller learned the exact crash point.
-- Behaviour is otherwise unchanged; flight_starts_at is still exposed so the
-- client can drive animation timing.

create or replace function public.get_or_create_rocket_crash_round()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round  public.rocket_crash_global_rounds;
  v_now    timestamptz := now();
  v_rnum   bigint;
  c_bet_s  constant int := 8;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  perform pg_advisory_xact_lock(hashtext('rocket_crash_global_round'));

  -- Current betting round (not expired)
  select * into v_round
  from public.rocket_crash_global_rounds
  where status = 'betting' and betting_ends_at > v_now
  order by created_at desc
  limit 1;

  if v_round.id is null then
    -- Current flying round (not stale — max flight ~95s for 200x crash)
    select * into v_round
    from public.rocket_crash_global_rounds
    where status = 'flying'
      and flight_starts_at > v_now - interval '120 seconds'
    order by created_at desc
    limit 1;
  end if;

  if v_round.id is not null then
    return json_build_object(
      'round_id',          v_round.id,
      'round_number',      v_round.round_number,
      'status',            v_round.status,
      'betting_ends_at',   extract(epoch from v_round.betting_ends_at) * 1000,
      'flight_starts_at',  case when v_round.flight_starts_at is not null
                               then extract(epoch from v_round.flight_starts_at) * 1000
                               else null end,
      -- Fairness: never reveal the crash point before the round has crashed.
      'crash_multiplier',  case when v_round.status = 'crashed'
                               then v_round.crash_multiplier
                               else null end,
      'server_now',        extract(epoch from v_now) * 1000
    );
  end if;

  -- Create new betting round
  v_rnum := nextval('public.rocket_crash_round_seq');
  insert into public.rocket_crash_global_rounds
    (round_number, status, betting_starts_at, betting_ends_at)
  values
    (v_rnum, 'betting', v_now, v_now + (c_bet_s || ' seconds')::interval)
  returning * into v_round;

  return json_build_object(
    'round_id',         v_round.id,
    'round_number',     v_round.round_number,
    'status',           'betting',
    'betting_ends_at',  extract(epoch from v_round.betting_ends_at) * 1000,
    'flight_starts_at', null,
    'crash_multiplier', null,
    'server_now',       extract(epoch from v_now) * 1000
  );
end;
$$;
grant execute on function public.get_or_create_rocket_crash_round() to authenticated;

-- ── 4. Idempotent realtime publication ───────────────────────────────────────
-- The original migration added rocket_crash_global_rounds with a non-idempotent
-- ALTER PUBLICATION. Re-add both the rounds and bets tables only if missing, so
-- this is safe to run on a DB where the publication membership may have drifted.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'rocket_crash_global_rounds'
  ) then
    alter publication supabase_realtime add table public.rocket_crash_global_rounds;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'rocket_crash_global_bets'
  ) then
    alter publication supabase_realtime add table public.rocket_crash_global_bets;
  end if;
end $$;
