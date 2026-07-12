-- Read-only catalog assertions plus staging test guidance.
select p.oid::regprocedure::text signature,
  p.prosecdef,
  p.proconfig,
  has_function_privilege('public', p.oid, 'execute') as public_execute,
  has_function_privilege('anon', p.oid, 'execute') as anon_execute,
  has_function_privilege('authenticated', p.oid, 'execute') as authenticated_execute
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname = 'public' and p.proname in (
  'admin_approve_withdrawal','admin_reject_withdrawal',
  'approve_recharge_transaction','create_recharge_transaction',
  'apply_vip_recharge_exp','preview_withdrawal_split','request_withdrawal'))
   or n.nspname = 'agency_finance_v3'
order by signature;

select table_schema, table_name, privilege_type, grantee
from information_schema.role_table_grants
where table_schema = 'agency_finance_v3'
order by table_name, grantee, privilege_type;

-- Must return zero after hardening/foundation are applied.
select p.oid::regprocedure::text as exposed_sensitive_function
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where ((n.nspname = 'public' and p.proname in (
  'admin_approve_withdrawal','admin_reject_withdrawal',
  'approve_recharge_transaction','create_recharge_transaction',
  'apply_vip_recharge_exp','preview_withdrawal_split','request_withdrawal'))
  or n.nspname = 'agency_finance_v3')
and (has_function_privilege('public',p.oid,'execute')
  or has_function_privilege('anon',p.oid,'execute'));

-- Mutation, impersonation, cross-Agency, self-approval, replay, invalid-state,
-- append-only and negative-value tests require transaction-scoped staging role
-- fixtures and are intentionally not executed against production.
