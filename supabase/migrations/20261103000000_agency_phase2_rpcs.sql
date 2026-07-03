-- ────────────────────────────────────────────────────────────────────────────
-- Agency / Hostess — Phase 2: owner + admin read/management RPCs.
--
-- Builds on the Phase 1 foundation (agency_hosts, agency_applications hardening,
-- agency_audit_log, _agency_audit). No commission changes, no games, no IAP, no
-- recharge_agencies. These operate ONLY on the host-agency tables — recharge
-- agencies are a separate system and are never referenced here.
--
-- All functions are SECURITY DEFINER with a fixed search_path; every owner
-- action is scoped by agencies.owner_user_id = auth.uid(), every admin action by
-- profile_hub_admin_access().
-- ────────────────────────────────────────────────────────────────────────────


-- ── 1. agency_owner_list_hosts: active roster of the caller's agency ────────
create or replace function public.agency_owner_list_hosts()
returns table (
  user_id      uuid,
  display_name text,
  avatar_url   text,
  status       text,
  joined_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare v_owner uuid := auth.uid();
begin
  if v_owner is null then raise exception 'not_authenticated'; end if;
  return query
  select h.host_user_id, p.display_name, p.avatar_url, h.status, h.joined_at
  from public.agency_hosts h
  join public.agencies a on a.id = h.agency_id and a.owner_user_id = v_owner
  left join public.profiles p on p.id = h.host_user_id
  where h.status = 'active'
  order by h.joined_at desc;
end;
$$;
revoke all on function public.agency_owner_list_hosts() from public, anon;
grant execute on function public.agency_owner_list_hosts() to authenticated;


-- ── 2. agency_owner_list_pending_applications: join apps to caller's agency ──
create or replace function public.agency_owner_list_pending_applications()
returns table (
  application_id uuid,
  user_id        uuid,
  display_name   text,
  avatar_url     text,
  message        text,
  phone          text,
  country        text,
  created_at     timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare v_owner uuid := auth.uid();
begin
  if v_owner is null then raise exception 'not_authenticated'; end if;
  return query
  select ap.id, ap.user_id, p.display_name, p.avatar_url,
         ap.message, ap.phone, ap.country, ap.created_at
  from public.agency_applications ap
  -- Owner scope: only applications whose target agency the caller owns. Apps
  -- for other agencies are never returned.
  join public.agencies a on a.id = ap.agency_id and a.owner_user_id = v_owner
  left join public.profiles p on p.id = ap.user_id
  where ap.application_type = 'join_agency'
    and ap.status = 'pending'
  order by ap.created_at desc;
end;
$$;
revoke all on function public.agency_owner_list_pending_applications() from public, anon;
grant execute on function public.agency_owner_list_pending_applications() to authenticated;


-- ── 3. admin_list_host_agency_applications: admin review feed ────────────────
-- HOST-agency applications only (become_host / join_agency / create_agency).
-- Deliberately separate from recharge_agencies, which are never queried here.
create or replace function public.admin_list_host_agency_applications(
  p_status text default null,
  p_limit  int  default 50
)
returns table (
  application_id   uuid,
  user_id          uuid,
  display_name     text,
  avatar_url       text,
  application_type text,
  agency_id        uuid,
  agency_name      text,
  agency_code      text,
  status           text,
  message          text,
  created_at       timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare v_admin uuid := auth.uid();
begin
  if v_admin is null or not public.profile_hub_admin_access() then
    raise exception 'not_authorized';
  end if;
  return query
  select ap.id, ap.user_id, p.display_name, p.avatar_url, ap.application_type,
         ap.agency_id, ag.name, ag.agency_code, ap.status, ap.message, ap.created_at
  from public.agency_applications ap
  left join public.profiles p on p.id = ap.user_id
  left join public.agencies ag on ag.id = ap.agency_id
  where ap.application_type in ('become_host', 'join_agency', 'create_agency')
    and (p_status is null or ap.status = p_status)
  order by ap.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;
revoke all on function public.admin_list_host_agency_applications(text, int) from public, anon;
grant execute on function public.admin_list_host_agency_applications(text, int) to authenticated;


-- ── 4. admin_assign_host_to_agency ──────────────────────────────────────────
create or replace function public.admin_assign_host_to_agency(
  p_agency_id uuid, p_host_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_admin uuid := auth.uid(); v_agency public.agencies;
begin
  if v_admin is null or not public.profile_hub_admin_access() then
    raise exception 'not_authorized';
  end if;
  select * into v_agency from public.agencies where id = p_agency_id and status = 'active';
  if v_agency.id is null then raise exception 'agency_not_found_or_inactive'; end if;
  if v_agency.owner_user_id = p_host_user_id then raise exception 'cannot_assign_owner_as_host'; end if;

  -- Close any existing active membership at a different agency (transfer).
  update public.agency_hosts
  set status = 'transferred', left_at = now()
  where host_user_id = p_host_user_id and status = 'active' and agency_id <> p_agency_id;

  if not exists (
    select 1 from public.agency_hosts
    where host_user_id = p_host_user_id and status = 'active' and agency_id = p_agency_id
  ) then
    insert into public.agency_hosts (agency_id, host_user_id, status, approved_by)
    values (p_agency_id, p_host_user_id, 'active', v_admin);
  end if;

  -- Sync legacy agency_members.
  if not exists (
    select 1 from public.agency_members where agency_id = p_agency_id and user_id = p_host_user_id
  ) then
    insert into public.agency_members (agency_id, user_id, role, status, joined_at)
    values (p_agency_id, p_host_user_id, 'host', 'active', now());
  else
    update public.agency_members set status = 'active', updated_at = now()
    where agency_id = p_agency_id and user_id = p_host_user_id;
  end if;

  perform public._agency_audit(v_admin, 'host_assigned', p_agency_id, p_host_user_id, null,
    jsonb_build_object('by', 'admin'));
  return true;
end;
$$;
revoke all on function public.admin_assign_host_to_agency(uuid, uuid) from public, anon;
grant execute on function public.admin_assign_host_to_agency(uuid, uuid) to authenticated;


-- ── 5. admin_remove_host_from_agency ────────────────────────────────────────
create or replace function public.admin_remove_host_from_agency(
  p_host_user_id uuid, p_reason text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_admin uuid := auth.uid(); v_agency uuid;
begin
  if v_admin is null or not public.profile_hub_admin_access() then
    raise exception 'not_authorized';
  end if;

  select agency_id into v_agency
  from public.agency_hosts
  where host_user_id = p_host_user_id and status = 'active'
  limit 1;

  update public.agency_hosts
  set status = 'left', left_at = now()
  where host_user_id = p_host_user_id and status = 'active';

  -- Sync legacy agency_members (valid status: pending/active/suspended/removed).
  update public.agency_members
  set status = 'removed', updated_at = now()
  where user_id = p_host_user_id and status = 'active';

  perform public._agency_audit(v_admin, 'host_removed', v_agency, p_host_user_id, null,
    jsonb_build_object('reason', p_reason));
  return true;
end;
$$;
revoke all on function public.admin_remove_host_from_agency(uuid, text) from public, anon;
grant execute on function public.admin_remove_host_from_agency(uuid, text) to authenticated;
