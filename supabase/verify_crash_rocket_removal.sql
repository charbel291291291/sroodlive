-- Local-only verification for 20261110000000_remove_crash_rocket_backend.sql.
-- Run against a disposable local Supabase stack ONLY (never remote):
--   psql "$LOCAL_DB_URL" -f supabase/verify_crash_rocket_removal.sql
-- Every check either passes silently (raise notice) or raises an exception
-- that aborts the script, so a clean exit code means every invariant holds.

do $$
declare
  v_count integer;
  v_sum numeric;
begin
  -- 1. Zero remaining Crash Rocket tables (all generations).
  select count(*) into v_count
  from information_schema.tables
  where table_schema = 'public'
    and table_name in (
      'crash_bets', 'crash_rounds', 'crash_transactions',
      'rocket_crash_global_bets', 'rocket_crash_global_rounds', 'rocket_crash_round_secrets',
      'crash_rocket_bets', 'crash_rocket_rounds', 'crash_rocket_round_events', 'crash_rocket_round_secrets'
    );
  if v_count <> 0 then
    raise exception 'FAIL: % Crash Rocket table(s) still exist.', v_count;
  end if;
  raise notice 'PASS: zero Crash Rocket tables remain.';

  -- 2. legacy_crash_financial_archive exists with 65 rows and correct totals.
  select count(*) into v_count from public.legacy_crash_financial_archive;
  if v_count <> 65 then
    raise exception 'FAIL: legacy_crash_financial_archive has % rows, expected 65.', v_count;
  end if;
  raise notice 'PASS: legacy_crash_financial_archive row count = 65.';

  select coalesce(sum(amount), 0) into v_sum from public.legacy_crash_financial_archive where type = 'bet';
  if v_sum <> 47100 then
    raise exception 'FAIL: legacy_crash_financial_archive debit total is %, expected 47100.', v_sum;
  end if;
  raise notice 'PASS: legacy_crash_financial_archive debit total = 47100.';

  select coalesce(sum(amount), 0) into v_sum from public.legacy_crash_financial_archive where type = 'win';
  if v_sum <> 29307 then
    raise exception 'FAIL: legacy_crash_financial_archive credit total is %, expected 29307.', v_sum;
  end if;
  raise notice 'PASS: legacy_crash_financial_archive credit total = 29307.';

  -- 3. Archive access is locked down to service_role only.
  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'public'
    and table_name = 'legacy_crash_financial_archive'
    and grantee in ('authenticated', 'anon')
    and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');
  if v_count <> 0 then
    raise exception 'FAIL: % client-facing grant(s) remain on legacy_crash_financial_archive.', v_count;
  end if;
  raise notice 'PASS: legacy_crash_financial_archive has no authenticated/anon read or write grants.';

  -- 4. Zero remaining Crash Rocket functions.
  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and (p.proname ilike '%crash%' or p.proname ilike '%rocket%');
  if v_count <> 0 then
    raise exception 'FAIL: % Crash Rocket function(s) still exist.', v_count;
  end if;
  raise notice 'PASS: zero Crash Rocket functions remain.';

  -- 5. Zero remaining Crash Rocket policies.
  select count(*) into v_count
  from pg_policies
  where schemaname = 'public'
    and (policyname ilike '%crash%' or tablename ilike '%crash%' or tablename ilike '%rocket%')
    and tablename <> 'legacy_crash_financial_archive';
  if v_count <> 0 then
    raise exception 'FAIL: % Crash Rocket policy(ies) still exist.', v_count;
  end if;
  raise notice 'PASS: zero Crash Rocket policies remain.';

  -- 6. Zero remaining Crash Rocket Realtime publication entries.
  select count(*) into v_count
  from pg_publication_tables
  where pubname = 'supabase_realtime'
    and (tablename ilike '%crash%' or tablename ilike '%rocket%');
  if v_count <> 0 then
    raise exception 'FAIL: % Crash Rocket table(s) still in supabase_realtime publication.', v_count;
  end if;
  raise notice 'PASS: zero Crash Rocket Realtime publication entries remain.';

  -- 7. Zero remaining Crash Rocket cron jobs.
  select count(*) into v_count
  from cron.job
  where jobname ilike '%crash%' or jobname ilike '%rocket%';
  if v_count <> 0 then
    raise exception 'FAIL: % Crash Rocket cron job(s) still scheduled.', v_count;
  end if;
  raise notice 'PASS: zero Crash Rocket cron jobs remain.';

  -- 8. Feature flag row removed.
  select count(*) into v_count from public.game_settings where game_key = 'crash_rocket';
  if v_count <> 0 then
    raise exception 'FAIL: game_settings still has a crash_rocket row.';
  end if;
  raise notice 'PASS: crash_rocket game_settings row removed.';

  -- 9. Wallet reconciliation: the 5 no-debit-evidence bets caused zero wallet mutation.
  select count(*) into v_count
  from public.admin_audit_logs aal
  where aal.action = 'crash_rocket_removal_bet_reconciled'
    and aal.metadata ->> 'decision' = 'no_refund_no_debit_evidence';
  if v_count <> 5 then
    raise exception 'FAIL: expected 5 no-debit-evidence reconciliation records, found %.', v_count;
  end if;
  raise notice 'PASS: 5 no-debit-evidence bets reconciled via audit-only records.';

  select count(*) into v_count
  from public.admin_audit_logs aal
  where aal.action = 'crash_rocket_removal_bet_reconciled'
    and aal.metadata ->> 'decision' = 'no_refund_no_debit_evidence'
    and exists (
      select 1 from public.wallet_transactions wt
      where wt.type = 'crash_rocket_refund'
        and wt.metadata ->> 'legacy_bet_id' = aal.metadata ->> 'legacy_bet_id'
    );
  if v_count <> 0 then
    raise exception 'FAIL: % no-debit-evidence bet(s) have an unexpected wallet refund transaction.', v_count;
  end if;
  raise notice 'PASS: zero wallet mutation for the 5 no-debit-evidence bets.';

  -- 10. Shared room_game_rounds constraint narrowed correctly and Hungry Cat
  -- rows (if any exist locally) still satisfy it.
  select count(*) into v_count
  from public.room_game_rounds
  where game_code <> 'hungry_cat';
  if v_count <> 0 then
    raise exception 'FAIL: % room_game_rounds row(s) violate the narrowed hungry_cat-only constraint.', v_count;
  end if;
  raise notice 'PASS: room_game_rounds constraint narrowed; no non-hungry_cat rows.';

  select count(*) into v_count
  from pg_constraint
  where conname = 'room_game_rounds_game_code_check'
    and pg_get_constraintdef(oid) = 'CHECK ((game_code = ANY (ARRAY[''hungry_cat''::text])))';
  if v_count <> 1 then
    raise exception 'FAIL: room_game_rounds_game_code_check does not match the expected hungry_cat-only definition.';
  end if;
  raise notice 'PASS: room_game_rounds_game_code_check is exactly hungry_cat-only.';

  raise notice '=== ALL AUTOMATED CHECKS PASSED ===';
end $$;
