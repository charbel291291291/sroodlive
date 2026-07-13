-- Align legacy VIP administration RPCs with the current admin role system.
--
-- The VIP Center shows its administration panel to O/P/Super Admin roles and
-- callers with an explicit vip.grant permission. Older VIP RPCs still use
-- _vip_caller_is_admin(), whose legacy implementation only recognizes
-- super_admin/support_admin. Keep the RPCs protected while making both sides
-- use the same authorization contract.

create or replace function public._vip_caller_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    public.get_admin_role((select auth.uid())) in (
      'o_super_admin',
      'p_super_admin',
      'super_admin'
    )
    or public.has_admin_permission(
      'vip.grant',
      (select auth.uid())
    ),
    false
  );
$$;

revoke all on function public._vip_caller_is_admin()
  from public, anon, authenticated;

comment on function public._vip_caller_is_admin() is
  'Internal guard for VIP administration. Uses current admin roles and vip.grant permission.';
