-- ────────────────────────────────────────────────────────────────────────────
-- Rocket Crash — close the legacy direct-write RLS gap on retired tables
--
--   public.crash_rounds / public.crash_bets are the OLD per-user-round Crash
--   design (see 20260613170000_crash_rocket_schema_reconcile.sql). Rocket Crash
--   has since moved to the shared, global-round design (crash_rounds/crash_bets
--   were explicitly called out as retired in
--   20260728000000_rocket_crash_global_rounds.sql), and every current write to
--   these two tables happens exclusively inside SECURITY DEFINER RPCs
--   (start_crash_round, place/cashout/lose bet RPCs, admin_void_rocket_crash_round,
--   etc. — see 20260614200000_rocket_crash_local_rpcs.sql and
--   20260614260000_rocket_crash_admin_tools.sql), which run as the function
--   owner and are unaffected by table-level RLS/GRANTs.
--
--   The tables, however, still carry their original "_own" policies:
--     create policy "crash_rounds_own" on public.crash_rounds
--       for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
--     create policy "crash_bets_own" on public.crash_bets
--       for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
--   "for all" + a same-column "with check" means any authenticated user can, via
--   PostgREST, directly INSERT/UPDATE/DELETE their own rows in these retired
--   tables — including forging crash_multiplier, cashout_multiplier, win_amount,
--   and status fields that are supposed to be server-decided secrets/results.
--
--   This migration removes that write surface entirely. It does NOT touch the
--   live, global Rocket Crash tables (rocket_crash_global_rounds /
--   rocket_crash_global_bets) or any of their policies/publication membership —
--   those are a separate, still-active system handled by finding #1.
-- ────────────────────────────────────────────────────────────────────────────

-- ── 1. crash_rounds (retired legacy table) ───────────────────────────────────

drop policy if exists "crash_rounds_own" on public.crash_rounds;

-- Read-only, own-row access only — kept in case any legacy code path still
-- reads historical rows for this user. No write policy is created: every
-- write path is a SECURITY DEFINER RPC, so RLS write policies are unnecessary
-- and were the actual hole.
create policy "crash_rounds_own_read"
  on public.crash_rounds for select to authenticated
  using (user_id = auth.uid());

revoke insert, update, delete on public.crash_rounds from anon, authenticated;
revoke insert, update, delete on public.crash_rounds from public;

comment on table public.crash_rounds is
  'Retired legacy Crash Rocket table (superseded by rocket_crash_global_rounds). '
  'Client access is read-only (own rows); all writes happen exclusively through '
  'SECURITY DEFINER RPCs and must never be exposed to anon/authenticated via '
  'direct INSERT/UPDATE/DELETE.';

-- ── 2. crash_bets (retired legacy table) ─────────────────────────────────────

drop policy if exists "crash_bets_own" on public.crash_bets;

create policy "crash_bets_own_read"
  on public.crash_bets for select to authenticated
  using (user_id = auth.uid());

revoke insert, update, delete on public.crash_bets from anon, authenticated;
revoke insert, update, delete on public.crash_bets from public;

comment on table public.crash_bets is
  'Retired legacy Crash Rocket table (superseded by rocket_crash_global_bets). '
  'Client access is read-only (own rows); all writes (bet_amount, '
  'cashout_multiplier, win_amount, status, etc.) happen exclusively through '
  'SECURITY DEFINER RPCs and must never be exposed to anon/authenticated via '
  'direct INSERT/UPDATE/DELETE.';

-- ── 3. service_role / admin functionality is unaffected ──────────────────────
-- REVOKE above only targets anon/authenticated/public. service_role retains
-- its implicit RLS-bypass superuser-equivalent access, and every existing
-- SECURITY DEFINER RPC (which runs as the function owner, not as the calling
-- role) continues to read/write these tables exactly as before.
