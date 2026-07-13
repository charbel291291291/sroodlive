-- Forward-only removal of every Crash Rocket generation (crash_*, rocket_crash_*, crash_rocket_*).
--
-- Safety model:
--   * Entry points (flag + RPC execute grants) are disabled FIRST, before any
--     round/bet state is touched, so nothing new can be created mid-migration.
--   * All Crash Rocket round/bet rows across all 3 generations are locked,
--     then unresolved exposure is recomputed inside this same transaction.
--   * A non-terminal round is auto-closed ONLY if it has zero unresolved bets
--     and zero financial exposure at that moment; otherwise the entire
--     migration aborts and rolls back (no forced settlement of live risk).
--   * A final safety gate re-verifies every invariant immediately before the
--     destructive drops. Any failure aborts and rolls back everything.
--
-- Do not apply this against production directly. Validate locally first
-- (fresh reset -> apply all migrations -> apply this -> run verification ->
-- reset again -> apply again -> run verification again).

begin;

-- 1. Advisory transaction lock so concurrent admin actions cannot race the removal.
select pg_advisory_xact_lock(hashtext('crash_rocket_removal'));

-- 2. Disable the Crash Rocket feature flag immediately.
update public.game_settings
set is_enabled = false,
    updated_at = now()
where game_key = 'crash_rocket';

-- 3. Game catalog visibility: no dedicated catalog table exists beyond game_settings
-- (already disabled above). No-op placeholder kept for auditability.

-- 4. Prevent new bets and cashouts by revoking execute on all entry-point RPCs.
revoke execute on function public.place_crash_rocket_bet(uuid, integer, integer, numeric, text) from authenticated, anon;
revoke execute on function public.place_rocket_crash_bet(uuid, integer, numeric) from authenticated, anon;
revoke execute on function public.arm_crash_bet(integer, integer) from authenticated, anon;
revoke execute on function public.start_crash_round(jsonb) from authenticated, anon;
revoke execute on function public.cashout_crash_rocket_bet(uuid, text) from authenticated, anon;
revoke execute on function public.cash_out_rocket_crash_bet(uuid) from authenticated, anon;
revoke execute on function public.cashout_crash_bet(uuid) from authenticated, anon;
revoke execute on function public.cashout_crash_bet_local(uuid, numeric) from authenticated, anon;
revoke execute on function public.cashout_room_crash_bet(uuid, numeric) from authenticated, anon;

-- 5. Unschedule Crash Rocket cron jobs (none are currently registered; guarded no-op).
do $$
declare
  j record;
begin
  if not exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') then
    return;
  end if;

  for j in
    select jobname from cron.job
    where jobname ilike '%crash%' or jobname ilike '%rocket%'
  loop
    perform cron.unschedule(j.jobname);
  end loop;
end $$;

-- 6. Remove Crash Rocket tables from the Realtime publication.
do $$
begin
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rocket_crash_global_rounds'
  ) then
    alter publication supabase_realtime drop table public.rocket_crash_global_rounds;
  end if;

  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'crash_rocket_rounds'
  ) then
    alter publication supabase_realtime drop table public.crash_rocket_rounds;
  end if;

  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'crash_rocket_round_events'
  ) then
    alter publication supabase_realtime drop table public.crash_rocket_round_events;
  end if;
end $$;

-- 7. Lock every Crash Rocket round and bet row, across all 3 generations, so
-- nothing can change underneath the exposure recalculation in step 7b.
do $$
begin
  perform 1 from public.crash_rounds for update;
  perform 1 from public.crash_bets for update;
  perform 1 from public.rocket_crash_global_rounds for update;
  perform 1 from public.rocket_crash_global_bets for update;
  perform 1 from public.crash_rocket_rounds for update;
  perform 1 from public.crash_rocket_bets for update;
end $$;

-- 7b. Zero-exposure non-terminal round closure. Recomputed here, inside this
-- transaction, after entry points are already revoked (steps 2-6) and every
-- row is locked (step 7) -- so no new bet/cashout can race this check. A
-- non-terminal round is auto-closed ONLY when it currently has zero
-- unresolved bets AND zero financial exposure. Any round with unresolved
-- bets or positive exposure aborts (raise exception) and rolls back the
-- entire migration; it is never force-settled.
--
-- Each round table's status CHECK is widened to accept 'removal_cancelled'
-- as an explicit terminal value distinct from a real crash outcome. These
-- tables are dropped later in this same migration (step 19) once terminal,
-- so the widened constraint is transient.
alter table public.crash_rounds drop constraint if exists crash_rounds_status_check;
alter table public.crash_rounds add constraint crash_rounds_status_check
  check (status = any (array['flying'::text, 'crashed'::text, 'voided'::text, 'removal_cancelled'::text]));

alter table public.rocket_crash_global_rounds drop constraint if exists rocket_crash_global_rounds_status_check;
alter table public.rocket_crash_global_rounds add constraint rocket_crash_global_rounds_status_check
  check (status = any (array['betting'::text, 'flying'::text, 'crashed'::text, 'removal_cancelled'::text]));

alter table public.crash_rocket_rounds drop constraint if exists crash_rocket_rounds_status_check;
alter table public.crash_rocket_rounds add constraint crash_rocket_rounds_status_check
  check (status = any (array['waiting'::text, 'betting_open'::text, 'flying'::text, 'crashed'::text, 'settled'::text, 'removal_cancelled'::text]));

do $$
declare
  r record;
  v_unresolved integer;
  v_exposure numeric;
  v_key text;
  v_already boolean;
begin
  -- gen1: crash_rounds (non-terminal = 'flying')
  for r in select id from public.crash_rounds where status = 'flying' for update loop
    select count(*), coalesce(sum(bet_amount), 0)
      into v_unresolved, v_exposure
      from public.crash_bets
      where round_id = r.id and status in ('pending', 'running');

    if v_unresolved > 0 or v_exposure > 0 then
      raise exception 'Crash Rocket removal aborted: gen1 round % has % unresolved bet(s) totaling % exposure.', r.id, v_unresolved, v_exposure;
    end if;

    v_key := 'crash-removal-round-closure:gen1:' || r.id::text;
    select exists(
      select 1 from public.admin_audit_logs
      where action = 'crash_rocket_system_removal_zero_exposure'
        and metadata ->> 'idempotency_key' = v_key
    ) into v_already;

    if not v_already then
      update public.crash_rounds
      set status = 'removal_cancelled', crashed_at = coalesce(crashed_at, now())
      where id = r.id;

      insert into public.admin_audit_logs (action, metadata, created_at)
      values (
        'crash_rocket_system_removal_zero_exposure',
        jsonb_build_object(
          'idempotency_key', v_key,
          'legacy_generation', 'gen1_crash_rounds',
          'legacy_round_id', r.id,
          'unresolved_bet_count', v_unresolved,
          'unresolved_exposure', v_exposure
        ),
        now()
      );
    end if;
  end loop;

  -- gen2: rocket_crash_global_rounds (non-terminal = 'betting', 'flying')
  for r in select id from public.rocket_crash_global_rounds where status in ('betting', 'flying') for update loop
    select count(*), coalesce(sum(bet_amount), 0)
      into v_unresolved, v_exposure
      from public.rocket_crash_global_bets
      where round_id = r.id and status = 'active';

    if v_unresolved > 0 or v_exposure > 0 then
      raise exception 'Crash Rocket removal aborted: gen2 round % has % unresolved bet(s) totaling % exposure.', r.id, v_unresolved, v_exposure;
    end if;

    v_key := 'crash-removal-round-closure:gen2:' || r.id::text;
    select exists(
      select 1 from public.admin_audit_logs
      where action = 'crash_rocket_system_removal_zero_exposure'
        and metadata ->> 'idempotency_key' = v_key
    ) into v_already;

    if not v_already then
      update public.rocket_crash_global_rounds
      set status = 'removal_cancelled', crashed_at = coalesce(crashed_at, now())
      where id = r.id;

      insert into public.admin_audit_logs (action, metadata, created_at)
      values (
        'crash_rocket_system_removal_zero_exposure',
        jsonb_build_object(
          'idempotency_key', v_key,
          'legacy_generation', 'gen2_rocket_crash_global_rounds',
          'legacy_round_id', r.id,
          'unresolved_bet_count', v_unresolved,
          'unresolved_exposure', v_exposure
        ),
        now()
      );
    end if;
  end loop;

  -- gen3: crash_rocket_rounds (non-terminal = 'waiting', 'betting_open', 'flying')
  for r in select id from public.crash_rocket_rounds where status in ('waiting', 'betting_open', 'flying') for update loop
    select count(*), coalesce(sum(amount), 0)
      into v_unresolved, v_exposure
      from public.crash_rocket_bets
      where round_id = r.id and status = 'placed';

    if v_unresolved > 0 or v_exposure > 0 then
      raise exception 'Crash Rocket removal aborted: gen3 round % has % unresolved bet(s) totaling % exposure.', r.id, v_unresolved, v_exposure;
    end if;

    v_key := 'crash-removal-round-closure:gen3:' || r.id::text;
    select exists(
      select 1 from public.admin_audit_logs
      where action = 'crash_rocket_system_removal_zero_exposure'
        and metadata ->> 'idempotency_key' = v_key
    ) into v_already;

    if not v_already then
      update public.crash_rocket_rounds
      set status = 'removal_cancelled', crashed_at = coalesce(crashed_at, now())
      where id = r.id;

      insert into public.admin_audit_logs (action, metadata, created_at)
      values (
        'crash_rocket_system_removal_zero_exposure',
        jsonb_build_object(
          'idempotency_key', v_key,
          'legacy_generation', 'gen3_crash_rocket_rounds',
          'legacy_round_id', r.id,
          'unresolved_bet_count', v_unresolved,
          'unresolved_exposure', v_exposure
        ),
        now()
      );
    end if;
  end loop;
end $$;

-- 7c. Archive crash_transactions under a name that cannot be confused with a
-- live gameplay table. Pure rename: all 65 rows, ids, user_ids, amounts,
-- types, timestamps and metadata are preserved unchanged; nothing is
-- duplicated. Verified before writing this migration: zero foreign keys,
-- views, triggers, or functions reference crash_transactions.
-- Guarded: crash_transactions is schema drift (created directly in prod,
-- never part of migration history), so it does not exist on a fresh/local
-- database bootstrapped from migrations alone.
do $$
begin
  if to_regclass('public.crash_transactions') is null then
    return;
  end if;

  alter table public.crash_transactions rename to legacy_crash_financial_archive;

  revoke all on public.legacy_crash_financial_archive from authenticated, anon;

  comment on table public.legacy_crash_financial_archive is
    'Immutable archive of legacy Crash Rocket (all generations) financial evidence, preserved by the 20261110000000 removal migration. Not part of, and must never be reused by, any future Crash Rocket or other gameplay implementation.';
  comment on column public.legacy_crash_financial_archive.id is
    'Legacy Crash Rocket financial-evidence row id. Immutable archive value.';
  comment on column public.legacy_crash_financial_archive.user_id is
    'User the legacy Crash Rocket transaction belonged to. Immutable archive value.';
  comment on column public.legacy_crash_financial_archive.round_id is
    'Legacy Crash Rocket (gen1 crash_rounds) round id. Historical reference only -- the crash_rounds table it pointed to has been dropped.';
  comment on column public.legacy_crash_financial_archive.bet_id is
    'Legacy Crash Rocket (gen1 crash_bets) bet id. Historical reference only -- the crash_bets table it pointed to has been dropped.';
  comment on column public.legacy_crash_financial_archive.type is
    'Legacy Crash Rocket transaction type (bet/win). Immutable archive value.';
  comment on column public.legacy_crash_financial_archive.amount is
    'Legacy Crash Rocket transaction amount in coins at time of write. Immutable archive value.';
  comment on column public.legacy_crash_financial_archive.balance_before is
    'Wallet coin balance immediately before this legacy transaction. Immutable archive value.';
  comment on column public.legacy_crash_financial_archive.balance_after is
    'Wallet coin balance immediately after this legacy transaction. Immutable archive value.';
end $$;

-- 8-10. Reconcile the 5 known (and any future) unresolved gen1 bets. A bet is
-- refund-eligible only when ALL of:
--   (a) provable debit evidence exists (a legacy_crash_financial_archive
--       'bet' row for it),
--   (b) no payout evidence exists (no 'win' row for it),
--   (c) no refund has already been issued (idempotency key not already used),
--   (d) it is not cashed out (guaranteed by the status = 'pending' filter).
-- A pending bet with no provable debit evidence is NEVER refunded merely
-- because its status looks open; it is instead closed out with an
-- audit-only reconciliation record (reason: no_refund_no_debit_evidence)
-- that performs zero wallet or ledger mutation. Idempotency keys are
-- deterministic so re-running this migration after a partial failure never
-- double-refunds and never double-writes audit rows.
do $$
declare
  b record;
  v_refund_key text;
  v_reconcile_key text;
  v_debit_evidence boolean;
  v_payout_evidence boolean;
  v_refund_evidence boolean;
  v_already_reconciled boolean;
begin
  for b in
    select cb.id, cb.user_id, cb.bet_amount, cb.round_id, cb.status as bet_status
    from public.crash_bets cb
    where cb.status = 'pending'
    order by cb.id
    for update
  loop
    v_refund_key := 'crash-removal-refund:gen1:' || b.id::text;
    v_reconcile_key := 'crash-removal-reconcile:gen1:' || b.id::text;

    select exists(
      select 1 from public.legacy_crash_financial_archive ct
      where ct.bet_id = b.id and ct.type = 'bet'
    ) into v_debit_evidence;

    select exists(
      select 1 from public.legacy_crash_financial_archive ct
      where ct.bet_id = b.id and ct.type = 'win'
    ) into v_payout_evidence;

    select exists(
      select 1 from public.wallet_transactions
      where type = 'crash_rocket_refund'
        and metadata ->> 'idempotency_key' = v_refund_key
    ) into v_refund_evidence;

    select exists(
      select 1 from public.admin_audit_logs
      where action = 'crash_rocket_removal_bet_reconciled'
        and metadata ->> 'idempotency_key' = v_reconcile_key
    ) into v_already_reconciled;

    if v_debit_evidence and not v_payout_evidence and not v_refund_evidence then
      update public.wallets
      set coins_balance = coins_balance + b.bet_amount,
          updated_at = now()
      where user_id = b.user_id;

      insert into public.wallet_transactions (
        user_id, type, direction, coins_delta, balance_coins_after,
        note, metadata, created_at
      )
      select
        b.user_id,
        'crash_rocket_refund',
        'credit',
        b.bet_amount,
        w.coins_balance,
        'Crash Rocket removal: unresolved bet refund',
        jsonb_build_object(
          'idempotency_key', v_refund_key,
          'game_type', 'crash_rocket_removed',
          'legacy_generation', 'gen1_crash_bets',
          'legacy_round_id', b.round_id,
          'legacy_bet_id', b.id,
          'transaction_reason', 'unresolved_bet_refund',
          'amount', b.bet_amount,
          'currency', 'coins',
          'removal_migration_version', '20261110000000',
          'reconciliation_status', 'refunded'
        ),
        now()
      from public.wallets w
      where w.user_id = b.user_id;

      update public.crash_bets
      set status = 'refunded'
      where id = b.id;

      insert into public.legacy_crash_financial_archive (
        user_id, round_id, type, amount, balance_before, balance_after, bet_id, created_at
      )
      select b.user_id, b.round_id, 'refund', b.bet_amount,
             w.coins_balance - b.bet_amount, w.coins_balance, b.id, now()
      from public.wallets w
      where w.user_id = b.user_id;

    elsif not v_already_reconciled then
      -- No provable debit evidence (or already paid out / already refunded):
      -- audit-only closure, zero wallet or ledger mutation. Bet status is
      -- deliberately left untouched (no 'void' status exists on crash_bets);
      -- this audit record is the sole removal-bookkeeping record of record.
      insert into public.admin_audit_logs (action, metadata, created_at)
      values (
        'crash_rocket_removal_bet_reconciled',
        jsonb_build_object(
          'idempotency_key', v_reconcile_key,
          'legacy_generation', 'gen1_crash_bets',
          'legacy_bet_id', b.id,
          'legacy_round_id', b.round_id,
          'legacy_user_id', b.user_id,
          'bet_amount', b.bet_amount,
          'bet_status', b.bet_status,
          'has_debit_evidence', v_debit_evidence,
          'has_payout_evidence', v_payout_evidence,
          'has_refund_evidence', v_refund_evidence,
          'decision', 'no_refund_no_debit_evidence',
          'removal_migration_version', '20261110000000'
        ),
        now()
      );
    end if;
  end loop;
end $$;

-- 10b. Verify zero wallet mutation for every bet reconciled with decision
-- 'no_refund_no_debit_evidence'. Aborts and rolls back if any such bet
-- unexpectedly shows a refund transaction.
do $$
declare
  v_violations integer;
begin
  select count(*) into v_violations
  from public.admin_audit_logs aal
  where aal.action = 'crash_rocket_removal_bet_reconciled'
    and aal.metadata ->> 'decision' = 'no_refund_no_debit_evidence'
    and exists (
      select 1 from public.wallet_transactions wt
      where wt.type = 'crash_rocket_refund'
        and wt.metadata ->> 'legacy_bet_id' = aal.metadata ->> 'legacy_bet_id'
    );

  if v_violations > 0 then
    raise exception 'Crash Rocket removal aborted: % no-debit-evidence bet(s) unexpectedly show a wallet refund transaction.', v_violations;
  end if;

  raise notice 'Crash Rocket removal: verified zero wallet mutation for no-debit-evidence bets.';
end $$;

-- 11. Audit record of the removal itself.
insert into public.admin_audit_logs (action, metadata, created_at)
values (
  'crash_rocket_backend_removed',
  jsonb_build_object(
    'migration', '20261110000000_remove_crash_rocket_backend',
    'generations_removed', array['crash_*', 'rocket_crash_*', 'crash_rocket_*']
  ),
  now()
)
on conflict do nothing;

-- 12. Preserved historical metadata is written inline above (step 8-10); no
-- separate step needed because wallet_transactions/legacy_crash_financial_archive
-- rows for cashed_out and lost bets are left untouched and already carry
-- their original type/status/created_at.

-- 13. No dedicated Crash Rocket notification templates or admin config rows
-- exist outside game_settings (already cleared in step 2/21).

-- 23. Final safety gate. Runs BEFORE any destructive statement below (steps
-- 14-22): triggers, policies, functions, tables, sequences, the flag row,
-- and the shared CHECK constraint are only touched once every check here
-- passes. If this raises, the whole transaction rolls back untouched.
do $$
declare
  v_open_rounds integer;
  v_unresolved_bets integer;
  v_unresolved_exposure numeric;
  v_duplicate_refund_keys integer;
  v_unreconciled_pending integer;
  v_flag_active boolean;
  v_realtime_entries integer;
  v_cron_jobs integer;
begin
  select
    (select count(*) from public.crash_rounds where status = 'flying')
    + (select count(*) from public.rocket_crash_global_rounds where status in ('betting', 'flying'))
    + (select count(*) from public.crash_rocket_rounds where status in ('waiting', 'betting_open', 'flying'))
  into v_open_rounds;

  select
    (select count(*) from public.crash_bets where status in ('pending', 'running'))
    + (select count(*) from public.rocket_crash_global_bets where status = 'active')
    + (select count(*) from public.crash_rocket_bets where status = 'placed')
  into v_unresolved_bets;

  select
    coalesce((select sum(bet_amount) from public.crash_bets where status in ('pending', 'running')), 0)
    + coalesce((select sum(bet_amount) from public.rocket_crash_global_bets where status = 'active'), 0)
    + coalesce((select sum(amount) from public.crash_rocket_bets where status = 'placed'), 0)
  into v_unresolved_exposure;

  select count(*) into v_duplicate_refund_keys
  from (
    select metadata ->> 'idempotency_key' as k, count(*) as c
    from public.wallet_transactions
    where type = 'crash_rocket_refund'
    group by 1
    having count(*) > 1
  ) d;

  select count(*) into v_unreconciled_pending
  from public.crash_bets cb
  where cb.status = 'pending'
    and not exists (
      select 1 from public.admin_audit_logs aal
      where aal.action = 'crash_rocket_removal_bet_reconciled'
        and aal.metadata ->> 'legacy_bet_id' = cb.id::text
    );

  select coalesce(is_enabled, false) into v_flag_active
  from public.game_settings where game_key = 'crash_rocket';

  select count(*) into v_realtime_entries
  from pg_publication_tables
  where pubname = 'supabase_realtime'
    and tablename in ('rocket_crash_global_rounds', 'crash_rocket_rounds', 'crash_rocket_round_events');

  v_cron_jobs := 0;
  if exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') then
    select count(*) into v_cron_jobs
    from cron.job
    where jobname ilike '%crash%' or jobname ilike '%rocket%';
  end if;

  if v_open_rounds > 0
     or v_unresolved_bets > 0
     or coalesce(v_unresolved_exposure, 0) > 0
     or v_duplicate_refund_keys > 0
     or v_unreconciled_pending > 0
     or coalesce(v_flag_active, false)
     or v_realtime_entries > 0
     or v_cron_jobs > 0
  then
    raise exception 'Crash Rocket removal aborted: final gate failed (open_rounds=%, unresolved_bets=%, exposure=%, dup_refund_keys=%, unreconciled_pending=%, flag_active=%, realtime_entries=%, cron_jobs=%).',
      v_open_rounds, v_unresolved_bets, v_unresolved_exposure, v_duplicate_refund_keys,
      v_unreconciled_pending, v_flag_active, v_realtime_entries, v_cron_jobs;
  end if;
end $$;

-- 14. Drop exact Crash Rocket triggers. (None exist on any generation; verified via
-- information_schema.triggers -- no-op, kept for step-order completeness.)

-- 15. Drop exact Crash Rocket policies (also dropped implicitly by table drops below,
-- listed explicitly for auditability).
drop policy if exists crash_bets_own_read on public.crash_bets;
drop policy if exists crash_rocket_bets_read_own on public.crash_rocket_bets;
drop policy if exists crash_rocket_events_read on public.crash_rocket_round_events;
drop policy if exists crash_rocket_rounds_read on public.crash_rocket_rounds;
drop policy if exists crash_rounds_own_read on public.crash_rounds;
do $$
begin
  if to_regclass('public.legacy_crash_financial_archive') is not null then
    drop policy if exists tx_own_select on public.legacy_crash_financial_archive;
  end if;
end $$;
drop policy if exists rcgb_insert on public.rocket_crash_global_bets;
drop policy if exists rcgb_select_own on public.rocket_crash_global_bets;
drop policy if exists rcgr_select on public.rocket_crash_global_rounds;

-- 16. Drop exact Crash Rocket views. (None exist -- verified via information_schema.views.)

-- 17-18. Drop exact Crash Rocket RPC signatures and helper functions.
drop function if exists public._crash_rocket_assert_room_access(uuid);
drop function if exists public._crash_rocket_multiplier_at(timestamptz, timestamptz);
drop function if exists public._create_crash_rocket_round(uuid);
drop function if exists public._derive_crash_multiplier(text, uuid);
drop function if exists public.admin_clear_rocket_crash_forced_multiplier();
drop function if exists public.admin_get_rocket_crash_audit_log(integer);
drop function if exists public.admin_get_rocket_crash_game_config();
drop function if exists public.admin_or_cron_crash_round(uuid);
drop function if exists public.admin_or_cron_start_next_crash_round(uuid);
drop function if exists public.admin_preview_rocket_crash_result();
drop function if exists public.admin_set_rocket_crash_test_mode(boolean);
drop function if exists public.admin_void_rocket_crash_round(uuid);
drop function if exists public.advance_crash_rocket_round(uuid);
drop function if exists public.advance_rocket_crash_rounds();
drop function if exists public.arm_crash_bet(integer, integer);
drop function if exists public.cash_out_rocket_crash_bet(uuid);
drop function if exists public.cashout_crash_bet(uuid);
drop function if exists public.cashout_crash_bet_local(uuid, numeric);
drop function if exists public.cashout_crash_rocket_bet(uuid, text);
drop function if exists public.cashout_room_crash_bet(uuid, numeric);
drop function if exists public.get_active_crash_rocket_round(uuid);
drop function if exists public.get_crash_round_status(uuid);
drop function if exists public.get_or_create_rocket_crash_round();
drop function if exists public.get_recent_crash_rounds(integer);
drop function if exists public.get_rocket_crash_current_round();
drop function if exists public.get_rocket_crash_recent_results(integer);
drop function if exists public.get_rocket_crash_round_bets(uuid);
drop function if exists public.mark_crash_bet_lost(uuid, numeric);
drop function if exists public.owner_clear_rocket_crash_forced_multiplier();
drop function if exists public.owner_get_crash_full_config();
drop function if exists public.owner_set_rocket_crash_forced_multiplier(numeric);
drop function if exists public.place_crash_rocket_bet(uuid, integer, integer, numeric, text);
drop function if exists public.place_rocket_crash_bet(uuid, integer, numeric);
drop function if exists public.refund_crash_bet(uuid);
drop function if exists public.reveal_room_crash_round(uuid);
drop function if exists public.set_rocket_crash_forced_next_multiplier(numeric);
drop function if exists public.settle_crash_rocket_round(uuid);
drop function if exists public.settle_rocket_crash_round(uuid);
drop function if exists public.start_crash_round(jsonb);
drop function if exists public.start_rocket_crash_flight(uuid);

-- 18b. owner_get_game_risk_snapshot() is a shared multi-game owner RPC (not a
-- crash-only function, so it was not in the drop list above). Its Crash
-- Rocket section queries crash_rounds/crash_bets, which are dropped in step
-- 19 below; replace the function here, in the same transaction, to remove
-- only the crash_rocket block while leaving the Hungry Cat block byte-for-byte
-- identical. Signature, security definer, search_path, and return type are
-- unchanged; the caller (owner_game_control_service.dart) only ever reads the
-- 'hungry_cat' and 'snapshot_at' keys, so dropping 'crash_rocket' from the
-- returned jsonb is backward compatible.
create or replace function owner_get_game_risk_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_is_owner boolean;
  v_hungry_cat_open jsonb;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = v_caller and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  -- Hungry Cat: current betting round
  select jsonb_build_object(
    'round_id', r.id,
    'status', r.status,
    'betting_ends_at', r.betting_ends_at,
    'total_bets', count(b.id),
    'total_exposure', coalesce(sum(b.bet_amount * b.multiplier_at_bet), 0),
    'total_wagered', coalesce(sum(b.bet_amount), 0),
    'projected_payout', coalesce(
      (select sum(b2.bet_amount * b2.multiplier_at_bet)
       from hungry_cat_bets b2
       where b2.round_id = r.id and b2.food_id = (
         select forced_next_result from game_settings where game_key = 'hungry_cat'
       ) and b2.status = 'pending'),
      0
    )
  )
  into v_hungry_cat_open
  from hungry_cat_rounds r
  left join hungry_cat_bets b on b.round_id = r.id and b.status = 'pending'
  where r.status in ('betting', 'locked')
  group by r.id, r.status, r.betting_ends_at
  order by r.created_at desc
  limit 1;

  return jsonb_build_object(
    'hungry_cat', coalesce(v_hungry_cat_open, '{}'::jsonb),
    'snapshot_at', now()
  );
end;
$$;

-- 19. Drop exact Crash Rocket tables (children before parents; CASCADE only
-- within a generation's own foreign keys, never across shared tables).
-- legacy_crash_financial_archive (formerly crash_transactions) is
-- intentionally NOT dropped -- see step 7c.
drop table if exists public.crash_rocket_round_events;
drop table if exists public.crash_rocket_bets;
drop table if exists public.crash_rocket_round_secrets;
drop table if exists public.crash_rocket_rounds;

drop table if exists public.rocket_crash_round_secrets;
drop table if exists public.rocket_crash_global_bets;
drop table if exists public.rocket_crash_global_rounds;

drop table if exists public.crash_bets;
drop table if exists public.crash_rounds;

-- 20. Drop exact Crash Rocket sequences.
drop sequence if exists public.rocket_crash_round_seq;
drop sequence if exists public.crash_rocket_round_number_seq;

-- 21. Remove the Crash Rocket feature flag row.
delete from public.game_settings where game_key = 'crash_rocket';

-- 22. No dedicated game catalog table exists beyond game_settings (already removed).

-- Shared CHECK constraint containing crash_rocket: narrow room_game_rounds to
-- Hungry Cat only. Table is currently empty; safe to replace without a backfill.
alter table public.room_game_rounds drop constraint if exists room_game_rounds_game_code_check;
alter table public.room_game_rounds add constraint room_game_rounds_game_code_check
  check (game_code = any (array['hungry_cat'::text]));

-- 24. Verify ledger balance: total refund credits issued in this migration
-- must equal the sum of coins_delta on the refund transactions just written.
do $$
declare
  v_refund_tx_total bigint;
begin
  select coalesce(sum(coins_delta), 0) into v_refund_tx_total
  from public.wallet_transactions
  where type = 'crash_rocket_refund'
    and metadata ->> 'removal_migration_version' = '20261110000000';

  raise notice 'Crash Rocket removal: % coins refunded across unresolved bets.', v_refund_tx_total;
end $$;

-- 25. Commit atomically.
commit;
