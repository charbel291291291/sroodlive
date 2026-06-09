-- Fix: PostgrestException(message: permission denied for table vip_plans, code: 42501)
--
-- The VIP Center screen reads vip_plans via the anon/authenticated Supabase client.
-- Previously no RLS policy or role grant existed, causing 42501 for all users.
--
-- Scope: SELECT only. INSERT / UPDATE / DELETE remain admin-only (no policy added).

-- 1. Allow the authenticated role to read rows.
grant select on public.vip_plans to authenticated;

-- 2. Enable RLS so future policies are enforced (safe to run if already enabled).
alter table public.vip_plans enable row level security;

-- 3. SELECT policy: any logged-in user may read active VIP plans.
drop policy if exists "vip_plans_select_authenticated" on public.vip_plans;

create policy "vip_plans_select_authenticated"
  on public.vip_plans
  for select
  to authenticated
  using (true);
