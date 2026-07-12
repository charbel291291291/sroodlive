-- Agency / Hostess production contract.
-- Completes approval side effects, makes agency_hosts the client read source,
-- and protects host availability behind authenticated RPCs.

alter table public.agency_applications
  add column if not exists agency_name text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.agency_applications'::regclass
      and conname = 'agency_applications_agency_name_length'
  ) then
    alter table public.agency_applications
      add constraint agency_applications_agency_name_length
      check (
        agency_name is null
        or length(trim(agency_name)) between 3 and 80
      );
  end if;
end;
$$;

create table if not exists public.approved_hosts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active', 'suspended', 'removed')),
  approved_by uuid references auth.users(id),
  application_id uuid references public.agency_applications(id),
  approved_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists approved_hosts_status_idx
  on public.approved_hosts (status, approved_at desc);

alter table public.approved_hosts enable row level security;

drop policy if exists "approved_hosts_read" on public.approved_hosts;
create policy "approved_hosts_read"
  on public.approved_hosts for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.profile_hub_admin_access()
  );

revoke all on public.approved_hosts from public, anon, authenticated;
grant select on public.approved_hosts to authenticated;

insert into public.approved_hosts (
  user_id, status, approved_by, application_id, approved_at, updated_at
)
select
  h.host_user_id,
  'active',
  h.approved_by,
  h.application_id,
  h.joined_at,
  now()
from public.agency_hosts h
where h.status = 'active'
on conflict (user_id) do nothing;

insert into public.approved_hosts (
  user_id, status, approved_by, application_id, approved_at, updated_at
)
select
  ap.user_id,
  'active',
  ap.reviewed_by,
  ap.id,
  coalesce(ap.reviewed_at, ap.updated_at, ap.created_at),
  now()
from public.agency_applications ap
where ap.application_type = 'become_host'
  and ap.status = 'approved'
on conflict (user_id) do nothing;

create table if not exists public.host_availability (
  user_id uuid primary key references auth.users(id) on delete cascade,
  schedule jsonb not null default '[]'::jsonb
    check (jsonb_typeof(schedule) = 'array'),
  updated_at timestamptz not null default now()
);

alter table public.host_availability enable row level security;

drop policy if exists "host_availability_read_own" on public.host_availability;
create policy "host_availability_read_own"
  on public.host_availability for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.profile_hub_admin_access()
  );

revoke all on public.host_availability from public, anon, authenticated;
grant select on public.host_availability to authenticated;

create or replace function public._activate_approved_host(
  p_user_id uuid,
  p_approver uuid,
  p_application_id uuid
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.approved_hosts (
    user_id, status, approved_by, application_id, approved_at, updated_at
  )
  values (
    p_user_id, 'active', p_approver, p_application_id, now(), now()
  )
  on conflict (user_id) do update
    set status = 'active',
        approved_by = excluded.approved_by,
        application_id = excluded.application_id,
        approved_at = excluded.approved_at,
        updated_at = now();
$$;

revoke all on function public._activate_approved_host(uuid, uuid, uuid)
  from public, anon, authenticated;

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

create or replace function public.get_my_host_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_host public.approved_hosts;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into v_host
  from public.approved_hosts
  where user_id = v_uid;

  return jsonb_build_object(
    'is_approved_host', coalesce(v_host.status = 'active', false),
    'status', coalesce(v_host.status, 'not_approved'),
    'approved_at', v_host.approved_at
  );
end;
$$;

revoke all on function public.get_my_host_status()
  from public, anon;
grant execute on function public.get_my_host_status()
  to authenticated;

create or replace function public.get_my_host_availability()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_schedule jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (
    select 1 from public.approved_hosts
    where user_id = v_uid and status = 'active'
  ) then
    raise exception 'host_not_approved';
  end if;

  select schedule into v_schedule
  from public.host_availability
  where user_id = v_uid;

  return coalesce(v_schedule, '[]'::jsonb);
end;
$$;

create or replace function public.save_my_host_availability(p_schedule jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (
    select 1 from public.approved_hosts
    where user_id = v_uid and status = 'active'
  ) then
    raise exception 'host_not_approved';
  end if;
  if p_schedule is null
     or jsonb_typeof(p_schedule) <> 'array'
     or jsonb_array_length(p_schedule) <> 7 then
    raise exception 'invalid_schedule';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_schedule) entry
    where jsonb_typeof(entry) <> 'object'
      or jsonb_typeof(entry -> 'enabled') <> 'boolean'
      or coalesce(entry ->> 'start', '') !~
        '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      or coalesce(entry ->> 'end', '') !~
        '^([01][0-9]|2[0-3]):[0-5][0-9]$'
  ) then
    raise exception 'invalid_schedule';
  end if;

  insert into public.host_availability (user_id, schedule, updated_at)
  values (v_uid, p_schedule, now())
  on conflict (user_id) do update
    set schedule = excluded.schedule,
        updated_at = now();

  return p_schedule;
end;
$$;

revoke all on function public.get_my_host_availability()
  from public, anon;
grant execute on function public.get_my_host_availability()
  to authenticated;
revoke all on function public.save_my_host_availability(jsonb)
  from public, anon;
grant execute on function public.save_my_host_availability(jsonb)
  to authenticated;

drop function if exists public.apply_to_create_agency(text, text, text, text);

create function public.apply_to_create_agency(
  p_message text default null,
  p_phone text default null,
  p_country text default null,
  p_experience text default null,
  p_agency_name text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_name text := nullif(trim(coalesce(p_agency_name, '')), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));
  if v_name is null or length(v_name) not between 3 and 80 then
    raise exception 'invalid_agency_name';
  end if;
  if exists (
    select 1 from public.agencies
    where owner_user_id = v_uid and status in ('pending', 'active')
  ) then
    raise exception 'agency_already_owned';
  end if;
  if exists (
    select 1 from public.agency_applications
    where user_id = v_uid
      and application_type = 'create_agency'
      and status = 'pending'
  ) then
    raise exception 'duplicate_pending_application';
  end if;

  insert into public.agency_applications (
    user_id, application_type, agency_name, status,
    message, phone, country, experience
  )
  values (
    v_uid, 'create_agency', v_name, 'pending',
    p_message, p_phone, p_country, p_experience
  )
  returning id into v_id;

  perform public._agency_audit(
    v_uid, 'application_submitted', null, v_uid, v_id,
    jsonb_build_object('type', 'create_agency')
  );
  return v_id;
end;
$$;

revoke all on function public.apply_to_create_agency(
  text, text, text, text, text
) from public, anon;
grant execute on function public.apply_to_create_agency(
  text, text, text, text, text
) to authenticated;

create or replace function public.admin_review_agency_application(
  p_application_id uuid,
  p_approve boolean,
  p_reply text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := auth.uid();
  v_app public.agency_applications;
  v_agency_id uuid;
begin
  if v_admin is null or not public.profile_hub_admin_access() then
    raise exception 'not_authorized';
  end if;

  select *
  into v_app
  from public.agency_applications
  where id = p_application_id
  for update;

  if v_app.id is null then raise exception 'application_not_found'; end if;
  if v_app.status <> 'pending' then raise exception 'application_not_pending'; end if;

  if p_approve then
    if v_app.application_type = 'join_agency' then
      perform public._agency_grant_membership(v_app.id, v_admin);
      perform public._activate_approved_host(v_app.user_id, v_admin, v_app.id);
    elsif v_app.application_type = 'become_host' then
      perform public._activate_approved_host(v_app.user_id, v_admin, v_app.id);
    elsif v_app.application_type = 'create_agency' then
      perform pg_advisory_xact_lock(
        hashtextextended(v_app.user_id::text, 0)
      );
      if nullif(trim(coalesce(v_app.agency_name, '')), '') is null then
        raise exception 'agency_name_required';
      end if;
      if exists (
        select 1 from public.agencies
        where owner_user_id = v_app.user_id and status in ('pending', 'active')
      ) then
        raise exception 'agency_already_owned';
      end if;

      insert into public.agencies (
        name, owner_user_id, country, status, agency_code
      )
      values (
        trim(v_app.agency_name),
        v_app.user_id,
        nullif(trim(coalesce(v_app.country, '')), ''),
        'active',
        public._gen_agency_code()
      )
      returning id into v_agency_id;

      insert into public.agency_members (
        agency_id, user_id, role, status, joined_at
      )
      values (
        v_agency_id, v_app.user_id, 'owner', 'active', now()
      )
      on conflict (agency_id, user_id) do update
        set role = 'owner', status = 'active', updated_at = now();

      update public.agency_applications
      set agency_id = v_agency_id
      where id = v_app.id;

      perform public._agency_audit(
        v_admin, 'agency_created', v_agency_id, v_app.user_id, v_app.id,
        jsonb_build_object('name', trim(v_app.agency_name))
      );
    else
      raise exception 'unsupported_application_type';
    end if;

    update public.agency_applications
    set status = 'approved',
        admin_reply = p_reply,
        reviewed_by = v_admin,
        reviewed_at = now(),
        updated_at = now()
    where id = v_app.id;

    perform public._agency_audit(
      v_admin, 'application_approved',
      coalesce(v_agency_id, v_app.agency_id),
      v_app.user_id, v_app.id,
      jsonb_build_object('type', v_app.application_type)
    );
  else
    update public.agency_applications
    set status = 'rejected',
        admin_reply = p_reply,
        reviewed_by = v_admin,
        reviewed_at = now(),
        updated_at = now()
    where id = v_app.id;

    perform public._agency_audit(
      v_admin, 'application_rejected',
      v_app.agency_id, v_app.user_id, v_app.id,
      jsonb_build_object('type', v_app.application_type)
    );
  end if;

  return true;
end;
$$;

create or replace function public.agency_owner_review_application(
  p_application_id uuid,
  p_approve boolean,
  p_reply text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := auth.uid();
  v_app public.agency_applications;
  v_agency public.agencies;
begin
  if v_owner is null then raise exception 'not_authenticated'; end if;

  select *
  into v_app
  from public.agency_applications
  where id = p_application_id
  for update;

  if v_app.id is null then raise exception 'application_not_found'; end if;
  if v_app.application_type <> 'join_agency' or v_app.agency_id is null then
    raise exception 'not_owner_reviewable';
  end if;

  select *
  into v_agency
  from public.agencies
  where id = v_app.agency_id
    and status = 'active';

  if v_agency.id is null or v_agency.owner_user_id is distinct from v_owner then
    raise exception 'not_agency_owner';
  end if;
  if v_app.status <> 'pending' then raise exception 'application_not_pending'; end if;

  if p_approve then
    perform public._agency_grant_membership(v_app.id, v_owner);
    perform public._activate_approved_host(v_app.user_id, v_owner, v_app.id);
  end if;

  update public.agency_applications
  set status = case when p_approve then 'approved' else 'rejected' end,
      admin_reply = p_reply,
      reviewed_by = v_owner,
      reviewed_at = now(),
      updated_at = now()
  where id = v_app.id;

  perform public._agency_audit(
    v_owner,
    case when p_approve then 'application_approved' else 'application_rejected' end,
    v_app.agency_id,
    v_app.user_id,
    v_app.id,
    jsonb_build_object('by', 'owner')
  );

  return true;
end;
$$;

revoke all on function public.admin_review_agency_application(
  uuid, boolean, text
) from public, anon;
grant execute on function public.admin_review_agency_application(
  uuid, boolean, text
) to authenticated;
revoke all on function public.agency_owner_review_application(
  uuid, boolean, text
) from public, anon;
grant execute on function public.agency_owner_review_application(
  uuid, boolean, text
) to authenticated;

drop function if exists public.admin_list_host_agency_applications(text, int);

create function public.admin_list_host_agency_applications(
  p_status text default null,
  p_limit int default 50
)
returns table (
  application_id uuid,
  user_id uuid,
  display_name text,
  avatar_url text,
  application_type text,
  agency_id uuid,
  agency_name text,
  agency_code text,
  requested_agency_name text,
  status text,
  message text,
  phone text,
  country text,
  experience text,
  admin_reply text,
  created_at timestamptz,
  reviewed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_admin uuid := auth.uid();
begin
  if v_admin is null or not public.profile_hub_admin_access() then
    raise exception 'not_authorized';
  end if;

  return query
  select
    ap.id,
    ap.user_id,
    p.display_name,
    p.avatar_url,
    ap.application_type,
    ap.agency_id,
    ag.name,
    ag.agency_code,
    ap.agency_name,
    ap.status,
    ap.message,
    ap.phone,
    ap.country,
    ap.experience,
    ap.admin_reply,
    ap.created_at,
    ap.reviewed_at
  from public.agency_applications ap
  left join public.profiles p on p.id = ap.user_id
  left join public.agencies ag on ag.id = ap.agency_id
  where ap.application_type in (
    'become_host', 'join_agency', 'create_agency'
  )
    and (p_status is null or ap.status = p_status)
  order by ap.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;

revoke all on function public.admin_list_host_agency_applications(text, int)
  from public, anon;
grant execute on function public.admin_list_host_agency_applications(text, int)
  to authenticated;

comment on function public.get_my_agency_membership() is
  'Returns the authenticated user active agency membership from agency_hosts.';
comment on function public.get_my_host_status() is
  'Returns the authenticated user approved-host status.';
comment on function public.save_my_host_availability(jsonb) is
  'Validates and saves a seven-day schedule for an approved host.';
