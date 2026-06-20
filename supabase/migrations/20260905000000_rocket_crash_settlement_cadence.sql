-- Rocket Crash - settlement cadence fix
--
-- ROOT CAUSE of stuck flying rounds
-- The settlement logic in advance_rocket_crash_rounds() is already correct and
-- idempotent: it settles every 'flying' round whose server crash moment has
-- passed (now() >= flight_starts_at + ln(crash_multiplier)/0.055 seconds),
-- pays auto-cashout winners, marks the rest lost, and flips the round to
-- 'crashed'. The problem is purely CADENCE: the pg_cron job runs only every
-- 15 seconds (or every minute on the fallback path).
--
-- A round with crash_multiplier = 1.05 reaches its crash point at
--   ln(1.05) / 0.055 = about 0.89 seconds
-- after flight start. With a 15-second tick it can therefore stay 'flying' for
-- up to ~15 seconds before the next tick settles it - exactly the ~13 seconds
-- observed in the stuck-round sample (round 667).
--
-- FIX
-- 1. Re-assert advance_rocket_crash_rounds() verbatim (insurance: migrations are
--    applied manually here and may have drifted; this guarantees the correct,
--    idempotent settlement function is present).
-- 2. Reschedule the cron to run every SECOND (pg_cron >= 1.4 second precision),
--    with a safe fallback cascade to coarser intervals if the finer syntax is
--    unsupported on this instance.
--
-- This does NOT expose crash_multiplier to the client during flight: settlement
-- happens entirely server-side; get_or_create_rocket_crash_round still masks the
-- crash point until 'crashed'. No wallet/coins math is changed. Fully idempotent.

-- 1. advance_rocket_crash_rounds() (verbatim, idempotent)

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
  -- Same lock key as get_or_create_rocket_crash_round -> mutual exclusion.
  perform pg_advisory_xact_lock(hashtext('rocket_crash_global_round'));

  -- (1) Settle due flying rounds.
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

  -- (2) Transition recently-expired betting rounds to flying.
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

  -- (3) Ensure an active round exists (create new betting if none).
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

-- Intentionally NOT granted to authenticated - only the cron job runs this.

-- 2. Reschedule the cron to a 1-second cadence.
-- A 1.05 round crashes ~0.9s after launch, so a sub-second-to-1s tick keeps the
-- maximum stuck-flying time near 1 second. Cascade to coarser intervals only if
-- the finer syntax is unsupported by this instance's pg_cron version.

do $$
declare
  v_job_name text := 'rocket_crash_auto_advance';
  v_scheduled boolean := false;
  v_cmd text := $cron$ select public.advance_rocket_crash_rounds(); $cron$;
begin
  if not exists (
    select 1 from pg_catalog.pg_extension where extname = 'pg_cron'
  ) then
    raise notice 'pg_cron not available — Rocket Crash auto-advance will rely on client triggers';
    return;
  end if;

  -- Remove any existing job with this name before re-adding (idempotent).
  if exists (select 1 from cron.job where jobname = v_job_name) then
    perform cron.unschedule(v_job_name);
  end if;

  -- Try progressively coarser schedules until one is accepted.
  begin
    perform cron.schedule(v_job_name, '1 second', v_cmd);
    v_scheduled := true;
    raise notice 'Rocket Crash auto-advance scheduled (every 1 second)';
  exception when others then null;
  end;

  if not v_scheduled then
    begin
      perform cron.schedule(v_job_name, '5 seconds', v_cmd);
      v_scheduled := true;
      raise notice 'Rocket Crash auto-advance scheduled (every 5 seconds)';
    exception when others then null;
    end;
  end if;

  if not v_scheduled then
    begin
      perform cron.schedule(v_job_name, '15 seconds', v_cmd);
      v_scheduled := true;
      raise notice 'Rocket Crash auto-advance scheduled (every 15 seconds)';
    exception when others then null;
    end;
  end if;

  if not v_scheduled then
    perform cron.schedule(v_job_name, '* * * * *', v_cmd);
    raise notice 'Rocket Crash auto-advance scheduled (every minute — seconds syntax unavailable)';
  end if;
end;
$$;
