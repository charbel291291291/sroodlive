-- =============================================================================
-- Retire ALL legacy Crash Rocket generations (forward-only, non-destructive).
--
-- Three generations coexist in production:
--   Gen 1 "crash_*"        : crash_rounds / crash_bets / crash_transactions
--                            (+ room_game engine crash variant) — dead in app.
--   Gen 2 "rocket_crash_*" : rocket_crash_global_rounds / _global_bets /
--                            _round_secrets + admin forced-multiplier tools —
--                            superseded; only forced-multiplier admin RPCs were
--                            still wired in the admin panel (removed in app).
--   Gen 3 "crash_rocket_*" : crash_rocket_rounds / _bets / _round_events /
--                            _round_secrets — the game live in the app until
--                            this cutover.
--
-- This migration:
--   1. Revokes API-role execution on every legacy crash RPC (no new bets or
--      cashouts through any old endpoint). Function bodies are kept for
--      forensic/history purposes; they simply become uncallable by clients.
--   2. Voids Gen-3 in-flight rounds and refunds their un-settled bets
--      atomically through the shared wallet + immutable ledger
--      (type 'crash_rocket_refund'). Idempotent set-based sweep.
--   3. Unschedules any legacy crash cron job if one exists (none known in
--      prod; guarded for drifted environments).
--   4. Marks legacy tables deprecated via COMMENT. NO table is dropped and NO
--      historical financial or round record is modified.
--
-- Cutover sequencing note (production): apply together with the app release
-- that ships Crash Rocket v2 (which stays behind the disabled
-- 'crash_rocket_v2' game_settings flag). Old app builds lose the game at
-- apply time by design. Gen-1/Gen-2 tables may contain stale 'placed'/'armed'
-- bets from before their retirement months ago; they are intentionally NOT
-- auto-refunded here (accounting review first). Review query documented at
-- the bottom of this file.
--
-- Later cleanup (only after verified cutover + retention window): a separate
-- migration may drop the deprecated tables/functions. NOT done here.
-- =============================================================================

-- ── 1. Revoke client execution on every legacy crash RPC (all overloads) ─────
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any (array[
        -- Gen 1
        'arm_crash_bet','cashout_crash_bet','cashout_crash_bet_local',
        'start_crash_round','get_crash_round_status','get_recent_crash_rounds',
        'mark_crash_bet_lost','refund_crash_bet',
        'admin_or_cron_crash_round','admin_or_cron_start_next_crash_round',
        'owner_get_crash_full_config','_derive_crash_multiplier',
        -- Gen 1 room_game-engine crash variant
        'cashout_room_crash_bet','reveal_room_crash_round',
        -- Gen 2
        'place_rocket_crash_bet','cash_out_rocket_crash_bet',
        'advance_rocket_crash_rounds','settle_rocket_crash_round',
        'start_rocket_crash_flight','get_or_create_rocket_crash_round',
        'get_rocket_crash_current_round','get_rocket_crash_recent_results',
        'get_rocket_crash_round_bets','set_rocket_crash_forced_next_multiplier',
        'owner_set_rocket_crash_forced_multiplier',
        'owner_clear_rocket_crash_forced_multiplier',
        'admin_set_rocket_crash_test_mode','admin_preview_rocket_crash_result',
        'admin_void_rocket_crash_round',
        'admin_clear_rocket_crash_forced_multiplier',
        'admin_get_rocket_crash_audit_log','admin_get_rocket_crash_game_config',
        -- Gen 3 (live until this cutover)
        'advance_crash_rocket_round','place_crash_rocket_bet',
        'cashout_crash_rocket_bet','get_active_crash_rocket_round',
        'settle_crash_rocket_round','_create_crash_rocket_round',
        '_crash_rocket_assert_room_access','_crash_rocket_multiplier_at'
      ])
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

-- ── 2. Void Gen-3 in-flight rounds and refund un-settled bets ────────────────
-- Idempotent: only touches bets still 'placed' inside rounds not yet settled.
do $$
declare
  v_bet record;
  v_balance integer;
begin
  if to_regclass('public.crash_rocket_bets') is null then
    return;
  end if;

  for v_bet in
    select b.id, b.user_id, b.amount, b.round_id
    from public.crash_rocket_bets b
    join public.crash_rocket_rounds r on r.id = b.round_id
    where b.status = 'placed'
      and r.status <> 'settled'
    order by b.id
    for update of b
  loop
    insert into public.wallets(user_id) values (v_bet.user_id)
    on conflict (user_id) do nothing;

    update public.wallets
    set coins_balance = coins_balance + v_bet.amount,
        updated_at = now()
    where user_id = v_bet.user_id
    returning coins_balance into v_balance;

    update public.crash_rocket_bets
    set status = 'refunded'
    where id = v_bet.id;

    insert into public.wallet_transactions(
      user_id, type, direction, coins_delta, diamonds_delta,
      balance_coins_after, note, metadata
    ) values (
      v_bet.user_id, 'crash_rocket_refund', 'credit', v_bet.amount, 0,
      v_balance, 'Crash Rocket retired: open bet refunded',
      jsonb_build_object('round_id', v_bet.round_id, 'bet_id', v_bet.id,
                         'reason', 'legacy_game_retirement')
    );
  end loop;

  -- Close any non-settled legacy rounds (history preserved; no result forged).
  update public.crash_rocket_rounds
  set status = 'settled', updated_at = now()
  where status <> 'settled';
end $$;

-- ── 3. Unschedule legacy crash cron jobs if any exist (guarded) ──────────────
do $$
declare
  v_job text;
begin
  if to_regnamespace('cron') is null then
    return;
  end if;
  for v_job in
    select jobname from cron.job
    where jobname in ('crash_rocket_auto_advance','rocket_crash_auto_advance',
                      'crash_auto_advance')
  loop
    perform cron.unschedule(v_job);
  end loop;
end $$;

-- ── 4. Mark legacy tables deprecated (kept for history; drop is a later,
--       separately-approved cleanup migration after verified cutover) ─────────
do $$
declare
  v_tbl text;
begin
  foreach v_tbl in array array[
    'crash_rounds','crash_bets','crash_transactions',
    'rocket_crash_global_rounds','rocket_crash_global_bets',
    'rocket_crash_round_secrets',
    'crash_rocket_rounds','crash_rocket_bets','crash_rocket_round_events',
    'crash_rocket_round_secrets'
  ] loop
    if to_regclass('public.' || v_tbl) is not null then
      execute format(
        'comment on table public.%I is
         ''DEPRECATED (Crash Rocket legacy, retired 2026-11-07). Read-only history.
           Replaced by crash_v2_* tables. Do not write. Scheduled for drop after
           verified cutover + retention window.''', v_tbl);
    end if;
  end loop;
end $$;

-- ── Gen-1 / Gen-2 stale-bet accounting review (DOCUMENTATION ONLY) ───────────
-- Run manually before any future cleanup migration; refund via admin tooling if
-- owed:
--   select 'gen2' src, count(*), coalesce(sum(bet_amount),0) from
--     public.rocket_crash_global_bets where status = 'active'
--   union all
--   select 'gen1', count(*), coalesce(sum(bet_amount),0) from
--     public.crash_bets where status in ('pending','running');
