-- Read-only Agency Phase 2 verification. Safe to run against linked production.

-- Exact counts.
select 'agency_applications' table_name, count(*) exact_count from public.agency_applications
union all select 'agency_audit_log', count(*) from public.agency_audit_log
union all select 'agency_hosts', count(*) from public.agency_hosts
union all select 'agency_members', count(*) from public.agency_members
union all select 'approved_hosts', count(*) from public.approved_hosts
union all select 'host_availability', count(*) from public.host_availability
union all select 'host_targets', count(*) from public.host_targets
union all select 'recharge_agencies', count(*) from public.recharge_agencies
union all select 'recharge_agents', count(*) from public.recharge_agents
union all select 'recharge_packages', count(*) from public.recharge_packages
union all select 'recharge_requests', count(*) from public.recharge_requests
union all select 'recharge_transactions', count(*) from public.recharge_transactions
union all select 'withdrawal_requests', count(*) from public.withdrawal_requests
order by table_name;

-- Financial and status totals.
select 'recharge_requests' source, status, count(*) records,
  coalesce(sum(requested_coins), 0)::numeric coin_total,
  coalesce(sum(requested_amount_usd), 0)::numeric usd_total,
  0::numeric diamond_total
from public.recharge_requests group by status
union all
select 'recharge_transactions', status, count(*),
  coalesce(sum(total_coins), 0), coalesce(sum(price_usd), 0), 0
from public.recharge_transactions group by status
union all
select 'withdrawal_requests', status, count(*), 0,
  coalesce(sum(gross_usd), 0), coalesce(sum(diamonds), 0)
from public.withdrawal_requests group by status
order by source, status;

select count(*) package_count,
  coalesce(sum(coins_amount), 0) package_coins,
  coalesce(sum(bonus_coins), 0) package_bonus,
  coalesce(sum(total_coins), 0) package_total,
  coalesce(sum(price_usd), 0) package_usd
from public.recharge_packages;

select coalesce(sum(target_coins), 0) target_coins,
  coalesce(sum(actual_coins), 0) actual_coins,
  coalesce(sum(reward_coins), 0) reward_coins,
  coalesce(sum(target_hours), 0) target_hours,
  coalesce(sum(actual_hours), 0) actual_hours
from public.host_targets;

-- Duplicate references.
select reference_code, count(*) duplicate_count
from public.recharge_requests where reference_code is not null
group by reference_code having count(*) > 1;
select payment_reference, count(*) duplicate_count
from public.recharge_transactions where payment_reference is not null
group by payment_reference having count(*) > 1;

-- User and ownership orphans.
select r.id from public.recharge_requests r left join auth.users u on u.id=r.user_id where u.id is null;
select r.id from public.recharge_transactions r left join auth.users u on u.id=r.user_id where u.id is null;
select w.id from public.withdrawal_requests w left join auth.users u on u.id=w.user_id where u.id is null;
select m.id from public.agency_members m left join auth.users u on u.id=m.user_id where u.id is null;
select h.id from public.agency_hosts h left join auth.users u on u.id=h.host_user_id where u.id is null;
select a.id from public.recharge_agents a left join auth.users u on u.id=a.user_id where a.user_id is not null and u.id is null;
select a.id from public.recharge_agents a left join public.recharge_agencies g on g.id=a.agency_id where a.agency_id is not null and g.id is null;
select r.id from public.recharge_requests r left join public.recharge_agencies g on g.id=r.agency_id where r.agency_id is not null and g.id is null;
select r.id from public.recharge_requests r left join public.recharge_agents a on a.id=r.agent_id where r.agent_id is not null and a.id is null;

-- Invalid/null/negative financial values.
select id from public.recharge_requests where requested_coins is null or requested_coins < 0 or coalesce(requested_amount_usd,0) < 0;
select id from public.recharge_transactions where price_usd is null or coins_amount is null or bonus_coins is null or total_coins is null or price_usd < 0 or coins_amount < 0 or bonus_coins < 0 or total_coins < 0;
select id from public.withdrawal_requests where diamonds is null or gross_usd is null or host_share_usd is null or agency_share_usd is null or platform_share_usd is null or diamonds < 0 or gross_usd < 0 or host_share_usd < 0 or agency_share_usd < 0 or platform_share_usd < 0;

-- Policy inventory.
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies where schemaname='public'
  and (tablename like '%agency%' or tablename like '%host%'
    or tablename like '%recharge%' or tablename like '%withdrawal%'
    or tablename like '%commission%' or tablename like '%settlement%')
order by tablename, policyname;

-- Function privilege and search-path inventory.
select p.proname, pg_get_function_identity_arguments(p.oid) identity_args,
  p.prosecdef security_definer, p.proconfig,
  has_function_privilege('public',p.oid,'execute') public_execute,
  has_function_privilege('anon',p.oid,'execute') anon_execute,
  has_function_privilege('authenticated',p.oid,'execute') authenticated_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and (p.proname like '%agency%'
  or p.proname like '%host%' or p.proname like '%recharge%'
  or p.proname like '%withdrawal%' or p.proname like '%commission%'
  or p.proname like '%settlement%') order by p.proname;

-- Table privileges and RLS.
select c.relname, c.relrowsecurity,
  has_table_privilege('anon',c.oid,'select') anon_select,
  has_table_privilege('anon',c.oid,'insert') anon_insert,
  has_table_privilege('anon',c.oid,'update') anon_update,
  has_table_privilege('anon',c.oid,'delete') anon_delete,
  has_table_privilege('authenticated',c.oid,'select') auth_select,
  has_table_privilege('authenticated',c.oid,'insert') auth_insert,
  has_table_privilege('authenticated',c.oid,'update') auth_update,
  has_table_privilege('authenticated',c.oid,'delete') auth_delete
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind in ('r', 'p') and (c.relname like '%agency%'
  or c.relname like '%host%' or c.relname like '%recharge%'
  or c.relname like '%withdrawal%' or c.relname like '%commission%'
  or c.relname like '%settlement%') order by c.relname;

-- Trigger and view inventory.
select event_object_table, trigger_name, event_manipulation, action_statement
from information_schema.triggers where trigger_schema='public'
  and (event_object_table like '%agency%' or event_object_table like '%host%'
    or event_object_table like '%recharge%' or event_object_table like '%withdrawal%')
order by event_object_table, trigger_name;
select schemaname, viewname, viewowner, definition
from pg_views where schemaname='public' and (viewname like '%agency%'
  or viewname like '%host%' or viewname like '%recharge%'
  or viewname like '%withdrawal%' or viewname like '%commission%'
  or viewname like '%settlement%') order by viewname;
