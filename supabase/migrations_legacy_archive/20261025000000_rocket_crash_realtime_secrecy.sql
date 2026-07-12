-- ────────────────────────────────────────────────────────────────────────────
-- Rocket Crash — close two realtime/RLS exposure gaps on the LIVE global
-- Crash Rocket tables (rocket_crash_global_rounds / rocket_crash_global_bets).
-- This is a NEW migration; it does not edit any prior migration file. It
-- leaves the retired legacy tables (crash_rounds/crash_bets, handled in
-- 20261024000000_retire_legacy_crash_direct_rls.sql) untouched.
--
-- Audited gaps (read-only investigation, see conversation):
--
--   1) rocket_crash_global_bets is realtime-published with REPLICA IDENTITY
--      FULL (20260904000000_rocket_crash_realtime_replica_identity.sql) even
--      though no Flutter client subscribes to it — bets are only ever read
--      via the anonymizing get_rocket_crash_round_bets RPC (which returns
--      display_name + is_own, never raw user_id). Leaving the table in the
--      publication is pure unused attack surface.
--
--      Separately, its RLS SELECT policy "rcgb_select" is `using (true)`
--      (20260728000000_rocket_crash_global_rounds.sql:53-55), so any
--      authenticated client can bypass the anonymizing RPC entirely and read
--      raw user_id straight from the table via PostgREST.
--
--   2) rocket_crash_global_rounds.crash_multiplier is written to the REAL,
--      final value the moment a round transitions betting -> flying, inside
--      advance_rocket_crash_rounds() (see 20260905000000_...sql /
--      20260902000002_...sql). Because the table is realtime-published with
--      REPLICA IDENTITY FULL, that full row — including the true multiplier —
--      is broadcast to every subscribed client the instant that UPDATE
--      commits, well before status flips to 'crashed'. All existing RPCs
--      (get_or_create_rocket_crash_round, get_rocket_crash_current_round) and
--      the Flutter client's own realtime callback only *read* crash_multiplier
--      when status == 'crashed' — but that is a UI/RPC convention, not a
--      security boundary, since the raw realtime payload already carries the
--      real value regardless of status. A modified client can read the true
--      crash point the instant flight starts and cash out at the last safe
--      instant every round.
--
-- Fix:
--   A) Remove rocket_crash_global_bets from the supabase_realtime
--      publication (no client depends on it) and tighten its SELECT policy
--      to own-rows-only (cross-user visibility already goes through the
--      anonymizing RPC).
--   B) Move the true crash multiplier into a new, non-realtime, RLS-locked
--      table (rocket_crash_round_secrets — same pattern already used
--      elsewhere in this codebase for room_game_round_secrets). The public,
--      realtime-published rocket_crash_global_rounds.crash_multiplier column
--      now stays NULL through 'betting' and 'flying' and is only populated at
--      the exact moment a round is marked 'crashed'. advance_rocket_crash_rounds
--      is redefined to read/write the secret from the new table instead of
--      the public row while a round is still flying.
--
-- Verified safe for existing readers:
--   - get_or_create_rocket_crash_round and get_rocket_crash_current_round
--     already mask with `case when status = 'crashed' then crash_multiplier
--     else null end` — with the column now genuinely null pre-crash, their
--     behavior is unchanged.
--   - lib/features/games/screens/rocket_crash_webview_screen.dart only reads
--     crash_multiplier from RPC/realtime payloads when phase/status ==
--     'crashed' (confirmed at the INIT_GAME build, the lock-free refresh
--     path, and the realtime channel callback) — no client code path expects
--     a value during 'betting'/'flying', so leaving it NULL there changes
--     nothing observable.
--   - The settlement-scheduling index on (flight_starts_at, crash_multiplier)
--     where status='flying' (20260929000000_rocket_crash_indexes.sql) simply
--     goes unused now that the column is null during flying; harmless.
-- ────────────────────────────────────────────────────────────────────────────

-- ── A1. Drop rocket_crash_global_bets from the realtime publication ─────────
-- No Flutter client subscribes to this table (confirmed: only
-- rocket_crash_global_rounds has a .channel(...) subscription in lib/).
do $$
begin
  if exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'rocket_crash_global_bets'
  ) then
    alter publication supabase_realtime drop table public.rocket_crash_global_bets;
  end if;
end $$;

-- ── A2. Tighten rocket_crash_global_bets RLS to own-rows-only ───────────────
-- Cross-user visibility (the public "who's betting" feed) already goes
-- through get_rocket_crash_round_bets, which anonymizes user_id via
-- display_name + is_own. Direct table SELECT no longer needs to expose other
-- players' rows at all.
drop policy if exists "rcgb_select" on public.rocket_crash_global_bets;
create policy "rcgb_select_own"
  on public.rocket_crash_global_bets for select to authenticated
  using (user_id = auth.uid());

comment on table public.rocket_crash_global_bets is
  'Live Rocket Crash bet rows. Not in the supabase_realtime publication — no '
  'client needs raw-row realtime; use get_rocket_crash_round_bets for the '
  'anonymized public bet feed. Direct SELECT is restricted to own rows.';

-- ── B1. Private secrets table for the true crash multiplier ─────────────────
create table if not exists public.rocket_crash_round_secrets (
  round_id         uuid primary key
                     references public.rocket_crash_global_rounds(id) on delete cascade,
  crash_multiplier numeric(10,2) not null,
  created_at       timestamptz not null default now()
);

alter table public.rocket_crash_round_secrets enable row level security;
-- Intentionally no policies: RLS-enabled with zero policies denies all access
-- to anon/authenticated by default. Only SECURITY DEFINER functions (which
-- bypass RLS) may read or write this table.
revoke all on public.rocket_crash_round_secrets from anon, authenticated, public;

comment on table public.rocket_crash_round_secrets is
  'Private pre-committed crash multiplier per round, written the instant a '
  'round starts flying. Never exposed to anon/authenticated (no RLS policy, '
  'all grants revoked) and never added to the realtime publication. '
  'advance_rocket_crash_rounds() copies the value into the public, '
  'realtime-published rocket_crash_global_rounds.crash_multiplier column only '
  'once the round is marked crashed.';

-- ── B2. Redefine advance_rocket_crash_rounds to use the secrets table ───────
create or replace function public.advance_rocket_crash_rounds()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now        timestamptz := now();
  v_round      public.rocket_crash_global_rounds;
  v_bet        record;
  v_win        integer;
  v_rand       numeric;
  v_crash      numeric;
  v_secret_cm  numeric;
  v_rnum       bigint;
  v_settled    int := 0;
  v_flew       int := 0;
  v_created    boolean := false;
  c_bet_s      constant int := 8;
begin
  -- Same lock key as get_or_create_rocket_crash_round -> mutual exclusion.
  perform pg_advisory_xact_lock(hashtext('rocket_crash_global_round'));

  -- (1) Settle due flying rounds. The true crash multiplier lives only in
  -- rocket_crash_round_secrets while the round is flying; it is copied into
  -- the public row's crash_multiplier column at the moment of settlement.
  for v_round in
    select r.*
    from public.rocket_crash_global_rounds r
    where r.status = 'flying'
      and exists (
        select 1
        from public.rocket_crash_round_secrets s
        where s.round_id = r.id
          and v_now >= r.flight_starts_at
                       + (ln(s.crash_multiplier::float8) / 0.055) * interval '1 second'
      )
    order by r.created_at
    for update of r
  loop
    select s.crash_multiplier into v_secret_cm
    from public.rocket_crash_round_secrets s
    where s.round_id = v_round.id;

    if v_secret_cm is null then
      -- Should be unreachable (secret is always inserted alongside the
      -- betting->flying transition below) — skip rather than fail the batch.
      continue;
    end if;

    -- Pay auto-cashout bets whose target is at or below the crash multiplier
    for v_bet in
      select b.* from public.rocket_crash_global_bets b
      where b.round_id = v_round.id
        and b.status = 'active'
        and b.auto_cashout_multiplier is not null
        and b.auto_cashout_multiplier <= v_secret_cm
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

    -- Reveal the multiplier on the public, realtime-published row only now,
    -- at the exact same moment the round is marked crashed.
    update public.rocket_crash_global_rounds
    set status = 'crashed', crashed_at = now(), crash_multiplier = v_secret_cm
    where id = v_round.id;

    v_settled := v_settled + 1;
  end loop;

  -- (2) Transition recently-expired betting rounds to flying. The true crash
  -- multiplier is written ONLY to the private secrets table here — the public
  -- row's crash_multiplier column stays NULL until settlement (step 1 above).
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
        flight_starts_at = v_now
    where id = v_round.id
      and status = 'betting';   -- re-check: client may have flown it first

    insert into public.rocket_crash_round_secrets (round_id, crash_multiplier)
    values (v_round.id, v_crash)
    on conflict (round_id) do nothing;

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

-- Intentionally NOT granted to authenticated - only the cron job runs this
-- (matches the original function's grant posture; unchanged here).
