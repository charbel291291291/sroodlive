-- Hotfix: My Agency screen calls get_my_agency_membership(), but some deployed
-- databases were missing this read RPC in the schema cache. Keep this migration
-- narrow and read-only: no wallet, commission, application, or membership writes.

create or replace function public.get_my_agency_membership()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select jsonb_build_object(
    'role', 'host',
    'status', h.status,
    'joined_at', h.joined_at,
    'agencies', jsonb_build_object(
      'id', a.id,
      'name', a.name,
      'country', a.country,
      'commission_rate', a.commission_rate,
      'monthly_target_coins', a.monthly_target_coins,
      'monthly_target_hours', a.monthly_target_hours
    )
  )
  into v_result
  from public.agency_hosts h
  join public.agencies a on a.id = h.agency_id
  where h.host_user_id = v_uid
    and h.status = 'active'
    and a.status = 'active'
  order by h.joined_at desc
  limit 1;

  return v_result;
end;
$$;

revoke all on function public.get_my_agency_membership()
  from public, anon;
grant execute on function public.get_my_agency_membership()
  to authenticated;

comment on function public.get_my_agency_membership() is
  'Returns the authenticated user active host-agency membership from agency_hosts.';

notify pgrst, 'reload schema';
