-- =============================================================================
-- Crash Rocket v2 — executable validation suite (local container / stack).
-- Run AFTER crash_v2_local_bootstrap.sql, as a superuser (test harness only).
-- Actors are impersonated via request.jwt.claim.sub (local auth.uid source).
-- Time is controlled by shifting round timestamps as superuser — a capability
-- that exists only for the test harness, never through any RPC.
--
-- Concurrency tests (double cashout race, engine double execution) run from
-- the bash driver with parallel sessions; everything else is in this script.
-- =============================================================================
\set ON_ERROR_STOP 0
\pset pager off
\set QUIET on

\set userA 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
\set userB 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
\set admin 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'

-- ── Clean slate ───────────────────────────────────────────────────────────────
truncate public.crash_v2_bets, public.crash_v2_round_events,
         public.crash_v2_round_secrets, public.crash_v2_rounds cascade;
delete from public.crash_v2_admin_actions;
update public.wallets set coins_balance = 1000000
where user_id in (:'userA', :'userB', :'admin');
update public.crash_v2_config
set is_paused = false, maintenance_message = null,
    min_bet = 100, max_bet = 1000000, betting_seconds = 8, waiting_seconds = 3,
    lock_seconds = 1, crash_display_seconds = 4
where singleton;
update public.game_settings set is_enabled = true where game_key = 'crash_rocket_v2';

create temp table if not exists t(k text primary key, v text);
truncate t;

-- ── T0: feature flag disabled -> game hidden, bets refused ───────────────────
update public.game_settings set is_enabled = false where game_key = 'crash_rocket_v2';
select set_config('request.jwt.claim.sub', :'userA', false);
do $$
declare s jsonb;
begin
  s := public.crash_v2_get_state(null);
  raise notice 'T0a %: disabled state enabled=% (want false)',
    case when (s->>'enabled') = 'false' then 'PASS' else 'FAIL' end, s->>'enabled';
end $$;
do $$
begin
  perform public.crash_v2_place_bet(null, 1, 1000, null, 'flagoff-12345678');
  raise notice 'T0b FAIL: bet accepted while disabled';
exception when others then
  raise notice 'T0b %: %', case when sqlerrm = 'game_disabled' then 'PASS' else 'FAIL' end, sqlerrm;
end $$;
update public.game_settings set is_enabled = true where game_key = 'crash_rocket_v2';

-- ── T1: engine creates + opens a round ────────────────────────────────────────
do $$
declare r jsonb; st text;
begin
  r := public.crash_v2_tick(null);          -- creates round in 'waiting'
  update public.crash_v2_rounds set betting_open_at = now() - interval '1 second'
  where status = 'waiting' and room_id is null;
  r := public.crash_v2_tick(null);          -- waiting -> betting_open
  select status into st from public.crash_v2_rounds
  where room_id is null order by public_round_number desc limit 1;
  raise notice 'T1 %: round status=% (want betting_open)',
    case when st = 'betting_open' then 'PASS' else 'FAIL' end, st;
end $$;

-- Pin the crash target for determinism (test-harness superuser write).
update public.crash_v2_round_secrets set target_multiplier = 100.00
where round_id = (select id from public.crash_v2_rounds
                  where room_id is null order by public_round_number desc limit 1);

-- ── T2: place bet (happy path + ledger) ───────────────────────────────────────
do $$
declare res jsonb; bal int; led int;
begin
  res := public.crash_v2_place_bet(null, 1, 1000, null, 'a-slot1-00000001');
  select coins_balance into bal from public.wallets where user_id = auth.uid();
  select count(*) into led from public.wallet_transactions
  where user_id = auth.uid() and type = 'crash_rocket_bet'
    and coins_delta = -1000 and (metadata->>'v') = '2';
  raise notice 'T2 %: status=% wallet=% ledger=% (want placed/999000/1)',
    case when res->'bet'->>'status' = 'placed' and bal = 999000 and led = 1
         then 'PASS' else 'FAIL' end,
    res->'bet'->>'status', bal, led;
  insert into t values ('betA1', res->'bet'->>'id');
end $$;

-- ── T3: duplicate idempotency key returns the SAME bet, no double debit ──────
do $$
declare res jsonb; bal int;
begin
  res := public.crash_v2_place_bet(null, 1, 1000, null, 'a-slot1-00000001');
  select coins_balance into bal from public.wallets where user_id = auth.uid();
  raise notice 'T3 %: idempotent=% same_bet=% wallet=% (want true/true/999000)',
    case when (res->>'idempotent') = 'true'
              and res->'bet'->>'id' = (select v from t where k = 'betA1')
              and bal = 999000
         then 'PASS' else 'FAIL' end,
    res->>'idempotent',
    (res->'bet'->>'id' = (select v from t where k = 'betA1')), bal;
end $$;

-- ── T4: same slot, new key -> slot_taken ─────────────────────────────────────
do $$
begin
  perform public.crash_v2_place_bet(null, 1, 500, null, 'a-slot1-00000002');
  raise notice 'T4 FAIL: duplicate slot accepted';
exception when others then
  raise notice 'T4 %: %', case when sqlerrm = 'slot_taken' then 'PASS' else 'FAIL' end, sqlerrm;
end $$;

-- ── T5: insufficient balance -> full rollback (no bet, no ledger, no debit) ──
select set_config('request.jwt.claim.sub', :'userB', false);
update public.wallets set coins_balance = 50 where user_id = :'userB';
do $$
declare bal int; bets int; led int;
begin
  begin
    perform public.crash_v2_place_bet(null, 1, 1000, null, 'b-poor-00000001');
    raise notice 'T5 FAIL: bet accepted without funds';
  exception when others then
    select coins_balance into bal from public.wallets where user_id = auth.uid();
    select count(*) into bets from public.crash_v2_bets where user_id = auth.uid();
    select count(*) into led from public.wallet_transactions
    where user_id = auth.uid() and (metadata->>'v') = '2';
    raise notice 'T5 %: err=% wallet=% bets=% ledger=% (want insufficient_balance/50/0/0)',
      case when sqlerrm = 'insufficient_balance' and bal = 50 and bets = 0 and led = 0
           then 'PASS' else 'FAIL' end, sqlerrm, bal, bets, led;
  end;
end $$;
update public.wallets set coins_balance = 1000000 where user_id = :'userB';

-- ── T6: input validation ─────────────────────────────────────────────────────
do $$
declare ok int := 0;
begin
  begin perform public.crash_v2_place_bet(null, 1, 5, null, 'b-bad-000000001');
  exception when others then if sqlerrm = 'invalid_bet_amount' then ok := ok + 1; end if; end;
  begin perform public.crash_v2_place_bet(null, 7, 1000, null, 'b-bad-000000002');
  exception when others then if sqlerrm = 'invalid_bet_slot' then ok := ok + 1; end if; end;
  begin perform public.crash_v2_place_bet(null, 1, 1000, 0.5, 'b-bad-000000003');
  exception when others then if sqlerrm = 'invalid_auto_cashout' then ok := ok + 1; end if; end;
  begin perform public.crash_v2_place_bet(null, 1, 1000, null, 'x');
  exception when others then if sqlerrm = 'invalid_idempotency_key' then ok := ok + 1; end if; end;
  raise notice 'T6 %: % of 4 validations enforced', case when ok = 4 then 'PASS' else 'FAIL' end, ok;
end $$;

-- ── T7: auto-cashout bet + a doomed bet placed before lock ───────────────────
do $$
declare res jsonb;
begin
  res := public.crash_v2_place_bet(null, 1, 2000, 1.50, 'b-auto-00000001');
  insert into t values ('betB1', res->'bet'->>'id');
  raise notice 'T7a %: B auto bet placed (auto=1.50)',
    case when res->'bet'->>'status' = 'placed' then 'PASS' else 'FAIL' end;
end $$;
select set_config('request.jwt.claim.sub', :'userA', false);
do $$
declare res jsonb;
begin
  res := public.crash_v2_place_bet(null, 2, 500, null, 'a-slot2-00000001');
  insert into t values ('betA2', res->'bet'->>'id');
  raise notice 'T7b %: A second-slot bet placed',
    case when res->'bet'->>'status' = 'placed' then 'PASS' else 'FAIL' end;
end $$;

-- ── T8: betting after lock -> betting_closed ─────────────────────────────────
-- Push BOTH timestamps back (keep close > open, satisfying the table CHECK) so
-- the window is closed and the flight starts ~3s ago (curve > 1 for T9b).
update public.crash_v2_rounds
set betting_open_at = now() - interval '30 seconds',
    betting_close_at = now() - interval '4 seconds'
where room_id is null and status = 'betting_open';
do $$
begin
  -- place_bet ticks internally first, which locks+launches the closed round.
  perform public.crash_v2_place_bet(null, 2, 1000, null, 'a-late-00000001');
  raise notice 'T8 FAIL: bet accepted after lock';
exception when others then
  raise notice 'T8 %: %', case when sqlerrm = 'betting_closed' then 'PASS' else 'FAIL' end, sqlerrm;
end $$;

-- ── T9: flight started; manual cashout pays curve multiplier ─────────────────
-- Flight started at betting_close_at + lock (≈ now-3s) -> multiplier ≈ e^{0.09·3}.
do $$
declare r jsonb; st text;
begin
  r := public.crash_v2_tick(null);
  select status into st from public.crash_v2_rounds
  where room_id is null order by public_round_number desc limit 1;
  raise notice 'T9a %: status=% (want flying)',
    case when st = 'flying' then 'PASS' else 'FAIL' end, st;
end $$;
do $$
declare res jsonb; m numeric; p int; bal_before int; bal_after int;
begin
  select coins_balance into bal_before from public.wallets where user_id = auth.uid();
  res := public.crash_v2_cash_out((select v from t where k = 'betA1')::uuid, 'a-co1-00000001');
  m := (res->'bet'->>'cashout_multiplier')::numeric;
  p := (res->'bet'->>'payout')::int;
  select coins_balance into bal_after from public.wallets where user_id = auth.uid();
  insert into t values ('payoutA1', p::text), ('walletA_afterCO', bal_after::text);
  raise notice 'T9b %: mult=% payout=% credited=% (want mult>1, payout=floor(1000*m), wallet+payout)',
    case when m > 1.00 and m < 100.00 and p = floor(1000 * m)::int
              and bal_after = bal_before + p
         then 'PASS' else 'FAIL' end, m, p, bal_after - bal_before;
end $$;

-- ── T10: double cashout (same bet, new key) -> idempotent, no second credit ──
do $$
declare res jsonb; bal int;
begin
  res := public.crash_v2_cash_out((select v from t where k = 'betA1')::uuid, 'a-co2-00000002');
  select coins_balance into bal from public.wallets where user_id = auth.uid();
  raise notice 'T10 %: idempotent=% wallet=% (want true, unchanged=%)',
    case when (res->>'idempotent') = 'true'
              and bal = (select v from t where k = 'walletA_afterCO')::int
         then 'PASS' else 'FAIL' end,
    res->>'idempotent', bal, (select v from t where k = 'walletA_afterCO');
end $$;

-- ── T11: auto-cashout settles server-side at exactly its threshold ───────────
-- Move flight start far enough back that the curve is past 1.50.
update public.crash_v2_rounds set started_at = now() - interval '6 seconds'
where room_id is null and status = 'flying';
update public.crash_v2_round_secrets s
set target_crashed_at = r.started_at + make_interval(secs => ln(100.00) / 0.09)
from public.crash_v2_rounds r
where r.id = s.round_id and r.room_id is null and r.status = 'flying';
do $$
declare r jsonb; st text; m numeric; p int;
begin
  r := public.crash_v2_tick(null);
  select b.status, b.cashout_multiplier, b.payout into st, m, p
  from public.crash_v2_bets b where b.id = (select v from t where k = 'betB1')::uuid;
  raise notice 'T11 %: B auto bet status=% mult=% payout=% (want cashed_out/1.50/3000)',
    case when st = 'cashed_out' and m = 1.50 and p = 3000 then 'PASS' else 'FAIL' end,
    st, m, p;
end $$;

-- ── T12: cashout attempted at/after the derived crash instant -> refused ─────
-- Round row still says 'flying', but the server clock is past target_crashed_at.
update public.crash_v2_round_secrets s
set target_crashed_at = now() - interval '1 second'
from public.crash_v2_rounds r
where r.id = s.round_id and r.room_id is null and r.status = 'flying';
do $$
begin
  perform public.crash_v2_cash_out((select v from t where k = 'betA2')::uuid, 'a-co3-00000003');
  raise notice 'T12 FAIL: cashout after crash instant accepted';
exception when others then
  raise notice 'T12 %: %', case when sqlerrm = 'round_crashed' then 'PASS' else 'FAIL' end, sqlerrm;
end $$;

-- ── T13: crash settles doomed bets; reveal happens on completion ─────────────
do $$
declare r jsonb; st text; bet_st text; crash numeric; seed text; ev int;
begin
  r := public.crash_v2_tick(null);   -- -> crashed (target passed)
  select status, crash_multiplier into st, crash from public.crash_v2_rounds
  where room_id is null order by public_round_number desc limit 1;
  select status into bet_st from public.crash_v2_bets
  where id = (select v from t where k = 'betA2')::uuid;
  raise notice 'T13a %: round=% crash=% lostbet=% (want crashed/100.00/lost)',
    case when st = 'crashed' and crash = 100.00 and bet_st = 'lost'
         then 'PASS' else 'FAIL' end, st, crash, bet_st;

  -- fast-forward the display window -> settling -> completed (+seed reveal)
  update public.crash_v2_rounds set crashed_at = now() - interval '10 seconds'
  where room_id is null and status = 'crashed';
  r := public.crash_v2_tick(null);
  select r2.status, r2.server_seed into st, seed from public.crash_v2_rounds r2
  where r2.room_id is null and r2.crash_multiplier is not null
  order by r2.public_round_number desc limit 1;
  select count(*) into ev from public.crash_v2_round_events e
  join public.crash_v2_rounds r3 on r3.id = e.round_id
  where r3.room_id is null and e.event_type = 'round_crashed';
  raise notice 'T13b %: settled round=% seed_revealed=% crash_events=% (want completed/true/1)',
    case when st = 'completed' and seed is not null and ev = 1
         then 'PASS' else 'FAIL' end, st, (seed is not null), ev;
end $$;

-- ── T14: settlement retry is idempotent (repeat ticks change nothing) ────────
do $$
declare before_led int; after_led int; r jsonb;
begin
  select count(*) into before_led from public.wallet_transactions where (metadata->>'v') = '2';
  r := public.crash_v2_tick(null);
  r := public.crash_v2_tick(null);
  select count(*) into after_led from public.wallet_transactions where (metadata->>'v') = '2';
  raise notice 'T14 %: ledger rows before=% after=% (must be equal)',
    case when before_led = after_led then 'PASS' else 'FAIL' end, before_led, after_led;
end $$;

-- ── T15: provably-fair verification of the completed round ───────────────────
do $$
declare rn bigint; v jsonb;
begin
  select public_round_number into rn from public.crash_v2_rounds
  where room_id is null and status = 'completed' and crash_multiplier is not null
  order by public_round_number desc limit 1;
  v := public.crash_v2_verify_round(rn, null);
  raise notice 'T15 %: hash_matches=% result_matches=% (want true/true — note: pinned target diverges from seed, so result_matches false is EXPECTED here; checking hash only)',
    case when (v->>'hash_matches') = 'true' then 'PASS' else 'FAIL' end,
    v->>'hash_matches', v->>'result_matches';
end $$;

-- ── T16: restart recovery — stale flying round fast-forwards safely ──────────
do $$
declare r jsonb; cnt_active int; st text;
begin
  r := public.crash_v2_tick(null);  -- ensure a fresh round exists
  update public.crash_v2_rounds
  set status = 'flying',
      started_at = now() - interval '2 hours',
      betting_open_at = now() - interval '2 hours' - interval '9 seconds',
      betting_close_at = now() - interval '2 hours' - interval '1 second'
  where room_id is null and status in ('waiting','betting_open');
  update public.crash_v2_round_secrets s
  set target_crashed_at = now() - interval '119 minutes',
      target_multiplier = 2.00
  from public.crash_v2_rounds r2
  where r2.id = s.round_id and r2.room_id is null and r2.status = 'flying'
    and s.target_crashed_at is null;
  r := public.crash_v2_tick(null);  -- one tick fast-forwards everything
  select count(*) into cnt_active from public.crash_v2_rounds
  where room_id is null and status not in ('completed');
  select status into st from public.crash_v2_rounds
  where room_id is null order by public_round_number desc limit 1;
  raise notice 'T16 %: active_rounds=% latest=% (want 1 fresh round after recovery)',
    case when cnt_active = 1 and st in ('waiting','betting_open') then 'PASS' else 'FAIL' end,
    cnt_active, st;
end $$;

-- ── T17: cancel bet -> refund; cancel after lock -> refused ──────────────────
do $$
declare res jsonb; bal_before int; bal_after int; bid uuid;
begin
  update public.crash_v2_rounds set betting_open_at = now() - interval '1 second',
                                    betting_close_at = now() + interval '30 seconds'
  where room_id is null and status = 'waiting';
  perform public.crash_v2_tick(null);
  select coins_balance into bal_before from public.wallets where user_id = auth.uid();
  res := public.crash_v2_place_bet(null, 1, 1000, null, 'a-cxl-00000001');
  bid := (res->'bet'->>'id')::uuid;
  res := public.crash_v2_cancel_bet(bid);
  select coins_balance into bal_after from public.wallets where user_id = auth.uid();
  raise notice 'T17a %: canceled status=% wallet_net=% (want canceled/0)',
    case when res->'bet'->>'status' = 'canceled' and bal_after = bal_before
         then 'PASS' else 'FAIL' end, res->'bet'->>'status', bal_after - bal_before;
  res := public.crash_v2_cancel_bet(bid);
  raise notice 'T17b %: repeat cancel idempotent=%',
    case when (res->>'idempotent') = 'true' then 'PASS' else 'FAIL' end, res->>'idempotent';
end $$;
do $$
declare res jsonb; bid uuid;
begin
  res := public.crash_v2_place_bet(null, 2, 700, null, 'a-cxl-00000002');
  bid := (res->'bet'->>'id')::uuid;
  update public.crash_v2_rounds
  set betting_open_at = now() - interval '30 seconds',
      betting_close_at = now() - interval '1 second'
  where room_id is null and status = 'betting_open';
  begin
    perform public.crash_v2_cancel_bet(bid);
    raise notice 'T17c FAIL: cancel after lock accepted';
  exception when others then
    raise notice 'T17c %: %', case when sqlerrm = 'bet_not_cancelable' then 'PASS' else 'FAIL' end, sqlerrm;
  end;
end $$;

-- ── T18: pause blocks new bets; admin gate enforced; audited ─────────────────
select set_config('request.jwt.claim.sub', :'admin', false);
do $$
declare c jsonb;
begin
  c := public.crash_v2_admin_pause_game('Scheduled maintenance');
  raise notice 'T18a %: paused=% (want true)',
    case when (c->>'is_paused') = 'true' then 'PASS' else 'FAIL' end, c->>'is_paused';
end $$;
select set_config('request.jwt.claim.sub', :'userA', false);
do $$
begin
  perform public.crash_v2_place_bet(null, 1, 1000, null, 'a-paused-0000001');
  raise notice 'T18b FAIL: bet accepted while paused';
exception when others then
  raise notice 'T18b %: %', case when sqlerrm in ('game_paused','betting_closed') then 'PASS' else 'FAIL' end, sqlerrm;
end $$;
do $$
begin
  perform public.crash_v2_admin_pause_game('hax');
  raise notice 'T18c FAIL: non-admin pause accepted';
exception when others then
  raise notice 'T18c %: %', case when sqlerrm = 'not_authorized' then 'PASS' else 'FAIL' end, sqlerrm;
end $$;
select set_config('request.jwt.claim.sub', :'admin', false);
do $$
declare c jsonb; log jsonb;
begin
  c := public.crash_v2_admin_resume_game();
  begin
    perform public.crash_v2_admin_update_config('{"house_edge_factor": 0.5}'::jsonb);
    raise notice 'T18d FAIL: fairness-critical key accepted';
  exception when others then
    raise notice 'T18d %: %', case when sqlerrm like 'config_key_not_allowed%' then 'PASS' else 'FAIL' end, sqlerrm;
  end;
  log := public.crash_v2_admin_get_audit_log(10);
  raise notice 'T18e %: audit entries=% (want >=2)',
    case when jsonb_array_length(log) >= 2 then 'PASS' else 'FAIL' end, jsonb_array_length(log);
end $$;

-- ── T19: room access gate ─────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', :'userA', false);
do $$
begin
  perform public.crash_v2_place_bet('deadbeef-dead-4bad-8bad-deadbeefdead', 1, 1000, null, 'a-room-00000001');
  raise notice 'T19 FAIL: non-member room bet accepted';
exception when others then
  raise notice 'T19 %: %', case when sqlerrm = 'not_room_member' then 'PASS' else 'FAIL' end, sqlerrm;
end $$;

-- ── T20: unauthenticated access refused ───────────────────────────────────────
select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  perform public.crash_v2_get_state(null);
  raise notice 'T20 FAIL: unauthenticated state allowed';
exception when others then
  raise notice 'T20 %: %', case when sqlerrm = 'not_authenticated' then 'PASS' else 'FAIL' end, sqlerrm;
end $$;

-- ── T21: RLS isolation + secrets/config lockdown (as API role) ────────────────
select set_config('request.jwt.claim.sub', :'userA', false);
set role authenticated;
do $$
declare other_visible int; ok_secrets boolean := false; ok_config boolean := false;
begin
  select count(*) into other_visible from public.crash_v2_bets
  where user_id <> auth.uid();
  begin
    perform count(*) from public.crash_v2_round_secrets;
  exception when insufficient_privilege then ok_secrets := true; end;
  begin
    perform count(*) from public.crash_v2_config;
  exception when insufficient_privilege then ok_config := true; end;
  raise notice 'T21 %: foreign_bets_visible=% secrets_blocked=% config_blocked=% (want 0/true/true)',
    case when other_visible = 0 and ok_secrets and ok_config then 'PASS' else 'FAIL' end,
    other_visible, ok_secrets, ok_config;
end $$;
reset role;

-- ── T22: PUBLIC / anon execute denial + legacy RPC retirement ─────────────────
do $$
declare v2_anon boolean; v2_auth boolean; legacy_auth boolean; tick_auth boolean;
begin
  v2_anon := has_function_privilege('anon',
    'public.crash_v2_place_bet(uuid,integer,integer,numeric,text)', 'execute');
  v2_auth := has_function_privilege('authenticated',
    'public.crash_v2_place_bet(uuid,integer,integer,numeric,text)', 'execute');
  tick_auth := has_function_privilege('authenticated',
    'public.crash_v2_tick(uuid)', 'execute');
  legacy_auth := has_function_privilege('authenticated',
    'public.place_crash_rocket_bet(uuid,integer,integer,numeric,text)', 'execute');
  raise notice 'T22 %: v2_anon=% v2_auth=% tick_auth=% legacy_auth=% (want f/t/f/f)',
    case when not v2_anon and v2_auth and not tick_auth and not legacy_auth
         then 'PASS' else 'FAIL' end,
    v2_anon, v2_auth, tick_auth, legacy_auth;
end $$;

-- ── T23: wallet zero-net invariant (wallets == bets ledger arithmetic) ────────
do $$
declare expA bigint; expB bigint; balA int; balB int;
begin
  -- Canceled bets are debit-then-refund (net zero); every other bet debits its
  -- amount; cashed-out bets credit their payout.
  select 1000000
       - coalesce(sum(amount) filter (where status <> 'canceled'), 0)
       + coalesce(sum(payout) filter (where status = 'cashed_out'), 0)
  into expA from public.crash_v2_bets where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  select 1000000
       - coalesce(sum(amount) filter (where status <> 'canceled'), 0)
       + coalesce(sum(payout) filter (where status = 'cashed_out'), 0)
  into expB from public.crash_v2_bets where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  select coins_balance into balA from public.wallets where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  select coins_balance into balB from public.wallets where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  raise notice 'T23 %: A wallet=% expected=% | B wallet=% expected=%',
    case when balA = expA and balB = expB then 'PASS' else 'FAIL' end,
    balA, expA, balB, expB;
end $$;

-- ── T24: every v2 ledger row balances its bet row (audit consistency) ─────────
do $$
declare orphans int;
begin
  select count(*) into orphans
  from public.wallet_transactions wt
  where (wt.metadata->>'v') = '2'
    and not exists (select 1 from public.crash_v2_bets b
                    where b.id = (wt.metadata->>'bet_id')::uuid);
  raise notice 'T24 %: orphan ledger rows=% (want 0)',
    case when orphans = 0 then 'PASS' else 'FAIL' end, orphans;
end $$;
