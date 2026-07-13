-- Run after applying 20260711021359_harden_admin_audit_and_vip_privacy.sql.
-- This script is read-only and fails closed when effective grants regress.
do $$
begin
  if has_table_privilege('anon', 'public.admin_audit_logs', 'insert')
     or has_table_privilege('authenticated', 'public.admin_audit_logs', 'insert')
     or has_table_privilege('anon', 'public.admin_audit_logs', 'update')
     or has_table_privilege('authenticated', 'public.admin_audit_logs', 'update')
     or has_table_privilege('anon', 'public.admin_audit_logs', 'delete')
     or has_table_privilege('authenticated', 'public.admin_audit_logs', 'delete') then
    raise exception 'admin_audit_logs still permits API-role mutation';
  end if;

  if has_function_privilege('anon', 'public.get_user_vip(uuid)', 'execute')
     or has_function_privilege(
       'authenticated', 'public.get_user_vip(uuid)', 'execute'
     )
     or has_function_privilege(
       'anon', 'public.get_users_with_vip(uuid[])', 'execute'
     )
     or has_function_privilege(
       'authenticated', 'public.get_users_with_vip(uuid[])', 'execute'
     ) then
    raise exception 'deprecated private VIP RPC remains executable';
  end if;

  if has_function_privilege(
       'anon', 'public.get_public_user_vip(uuid)', 'execute'
     )
     or not has_function_privilege(
       'authenticated', 'public.get_public_user_vip(uuid)', 'execute'
     )
     or not has_function_privilege(
       'authenticated', 'public.get_public_users_vip(uuid[])', 'execute'
     ) then
    raise exception 'public VIP presentation RPC grants are incorrect';
  end if;
end;
$$;

select
  'admin_audit_vip_privileges_verified' as verification,
  statement_timestamp() as checked_at;
