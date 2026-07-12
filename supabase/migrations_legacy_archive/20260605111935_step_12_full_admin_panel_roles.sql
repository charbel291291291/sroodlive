alter table public.app_user_roles
drop constraint if exists app_user_roles_role_check;

alter table public.app_user_roles
add constraint app_user_roles_role_check check (
  role in (
    'super_admin',
    'finance_admin',
    'bd_admin',
    'content_admin',
    'room_admin',
    'support_admin',
    'admin',
    'support',
    'moderator',
    'viewer'
  )
);

create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid null references auth.users(id) on delete set null,
  target_user_id uuid null references auth.users(id) on delete set null,
  action text not null,
  entity_type text null,
  entity_id text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.admin_audit_logs enable row level security;

drop policy if exists "Admins can view audit logs" on public.admin_audit_logs;
create policy "Admins can view audit logs"
on public.admin_audit_logs
for select
to authenticated
using (public.has_admin_access());

grant select on public.admin_audit_logs to authenticated;

create or replace function public.has_admin_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_app_role('super_admin')
      or public.has_app_role('finance_admin')
      or public.has_app_role('bd_admin')
      or public.has_app_role('content_admin')
      or public.has_app_role('room_admin')
      or public.has_app_role('support_admin')
      or public.has_app_role('admin')
      or public.has_app_role('support')
      or public.has_app_role('moderator')
      or public.has_app_role('viewer');
$$;

create or replace function public.has_finance_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_app_role('super_admin')
      or public.has_app_role('finance_admin');
$$;

create or replace function public.has_bd_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_app_role('super_admin')
      or public.has_app_role('bd_admin');
$$;

create or replace function public.has_content_admin_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_app_role('super_admin')
      or public.has_app_role('content_admin');
$$;

create or replace function public.has_room_admin_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_app_role('super_admin')
      or public.has_app_role('room_admin')
      or public.has_app_role('moderator');
$$;

create or replace function public.admin_record_audit(
  p_action text,
  p_entity_type text default null,
  p_entity_id text default null,
  p_target_user_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.has_admin_access() then
    raise exception 'not_authorized';
  end if;

  insert into public.admin_audit_logs (
    admin_user_id,
    target_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    auth.uid(),
    p_target_user_id,
    p_action,
    p_entity_type,
    p_entity_id,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.admin_search_users(
  p_query text default null,
  p_limit integer default 50
)
returns table (
  user_id uuid,
  public_user_id text,
  display_name text,
  username text,
  avatar_url text,
  vip_level integer,
  coins_balance integer,
  diamonds_balance integer,
  roles text[],
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.public_user_id,
    p.display_name,
    p.username,
    p.avatar_url,
    coalesce(p.vip_level, 0),
    coalesce(w.coins_balance, 0),
    coalesce(w.diamonds_balance, 0),
    coalesce(
      array_remove(array_agg(distinct aur.role), null),
      array[]::text[]
    ),
    p.created_at
  from public.profiles p
  left join public.wallets w on w.user_id = p.id
  left join public.app_user_roles aur on aur.user_id = p.id
  where public.has_admin_access()
    and (
      nullif(trim(coalesce(p_query, '')), '') is null
      or p.public_user_id ilike '%' || trim(p_query) || '%'
      or p.display_name ilike '%' || trim(p_query) || '%'
      or p.username ilike '%' || trim(p_query) || '%'
      or p.id::text ilike '%' || trim(p_query) || '%'
    )
  group by
    p.id,
    p.public_user_id,
    p.display_name,
    p.username,
    p.avatar_url,
    p.vip_level,
    w.coins_balance,
    w.diamonds_balance,
    p.created_at
  order by p.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

create or replace function public.admin_assign_user_role(
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := lower(trim(coalesce(p_role, '')));
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  if p_user_id is null then
    raise exception 'missing_user_id';
  end if;

  if v_role not in (
    'super_admin',
    'finance_admin',
    'bd_admin',
    'content_admin',
    'room_admin',
    'support_admin',
    'admin',
    'support',
    'moderator',
    'viewer'
  ) then
    raise exception 'invalid_role';
  end if;

  insert into public.app_user_roles (user_id, role)
  values (p_user_id, v_role)
  on conflict (user_id, role) do nothing;

  perform public.admin_record_audit(
    'assign_role',
    'app_user_roles',
    p_user_id::text,
    p_user_id,
    jsonb_build_object('role', v_role)
  );
end;
$$;

create or replace function public.admin_remove_user_role(
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := lower(trim(coalesce(p_role, '')));
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  if p_user_id is null then
    raise exception 'missing_user_id';
  end if;

  if p_user_id = auth.uid() and v_role = 'super_admin' then
    raise exception 'cannot_remove_own_super_admin_role';
  end if;

  delete from public.app_user_roles
  where user_id = p_user_id
    and role = v_role;

  perform public.admin_record_audit(
    'remove_role',
    'app_user_roles',
    p_user_id::text,
    p_user_id,
    jsonb_build_object('role', v_role)
  );
end;
$$;

create or replace function public.admin_list_rooms(
  p_limit integer default 50
)
returns table (
  id uuid,
  name text,
  description text,
  owner_id uuid,
  owner_public_user_id text,
  owner_name text,
  language text,
  max_seats integer,
  is_private boolean,
  is_locked boolean,
  active_members bigint,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.name,
    r.description,
    r.owner_id,
    p.public_user_id,
    coalesce(nullif(p.display_name, ''), nullif(p.username, '')),
    r.language,
    r.max_seats,
    r.is_private,
    coalesce(r.is_locked, false),
    (
      select count(*)
      from public.room_members rm
      where rm.room_id = r.id
        and rm.left_at is null
        and rm.last_seen_at >= now() - interval '60 seconds'
    ),
    r.created_at
  from public.rooms r
  left join public.profiles p on p.id = r.owner_id
  where public.has_admin_access()
  order by r.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

create or replace function public.admin_list_gifts(
  p_limit integer default 100
)
returns table (
  id uuid,
  code text,
  name text,
  arabic_name text,
  price_coins integer,
  icon text,
  is_active boolean,
  sort_order integer,
  sent_count bigint,
  coins_spent bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    g.id,
    g.code,
    g.name,
    g.arabic_name,
    g.price_coins,
    g.icon,
    g.is_active,
    g.sort_order,
    coalesce(count(gt.id), 0),
    coalesce(sum(gt.gift_price_coins), 0)::bigint
  from public.gifts g
  left join public.gift_transactions gt on gt.gift_id = g.id
  where public.has_admin_access()
  group by
    g.id,
    g.code,
    g.name,
    g.arabic_name,
    g.price_coins,
    g.icon,
    g.is_active,
    g.sort_order
  order by g.sort_order asc, g.price_coins asc
  limit greatest(1, least(coalesce(p_limit, 100), 200));
$$;

create or replace function public.admin_set_gift_active(
  p_gift_id uuid,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_content_admin_access() then
    raise exception 'not_authorized';
  end if;

  update public.gifts
  set is_active = coalesce(p_is_active, true)
  where id = p_gift_id;

  perform public.admin_record_audit(
    'set_gift_active',
    'gifts',
    p_gift_id::text,
    null,
    jsonb_build_object('is_active', coalesce(p_is_active, true))
  );
end;
$$;

create or replace function public.admin_set_recharge_agency_active(
  p_agency_id uuid,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_bd_access() then
    raise exception 'not_authorized';
  end if;

  update public.recharge_agencies
  set is_active = coalesce(p_is_active, true),
      updated_at = now()
  where id = p_agency_id;

  perform public.admin_record_audit(
    'set_agency_active',
    'recharge_agencies',
    p_agency_id::text,
    null,
    jsonb_build_object('is_active', coalesce(p_is_active, true))
  );
end;
$$;

create or replace function public.admin_set_recharge_agent_active(
  p_agent_id uuid,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_bd_access() then
    raise exception 'not_authorized';
  end if;

  update public.recharge_agents
  set is_active = coalesce(p_is_active, true),
      updated_at = now()
  where id = p_agent_id;

  perform public.admin_record_audit(
    'set_agent_active',
    'recharge_agents',
    p_agent_id::text,
    null,
    jsonb_build_object('is_active', coalesce(p_is_active, true))
  );
end;
$$;

create or replace function public.admin_list_audit_logs(
  p_limit integer default 50
)
returns table (
  id uuid,
  admin_user_id uuid,
  admin_public_user_id text,
  admin_name text,
  target_user_id uuid,
  target_public_user_id text,
  target_name text,
  action text,
  entity_type text,
  entity_id text,
  metadata jsonb,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    al.id,
    al.admin_user_id,
    ap.public_user_id,
    coalesce(nullif(ap.display_name, ''), nullif(ap.username, '')),
    al.target_user_id,
    tp.public_user_id,
    coalesce(nullif(tp.display_name, ''), nullif(tp.username, '')),
    al.action,
    al.entity_type,
    al.entity_id,
    al.metadata,
    al.created_at
  from public.admin_audit_logs al
  left join public.profiles ap on ap.id = al.admin_user_id
  left join public.profiles tp on tp.id = al.target_user_id
  where public.has_admin_access()
  order by al.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

grant execute on function public.has_bd_access() to authenticated;
grant execute on function public.has_content_admin_access() to authenticated;
grant execute on function public.has_room_admin_access() to authenticated;
grant execute on function public.admin_record_audit(text, text, text, uuid, jsonb) to authenticated;
grant execute on function public.admin_search_users(text, integer) to authenticated;
grant execute on function public.admin_assign_user_role(uuid, text) to authenticated;
grant execute on function public.admin_remove_user_role(uuid, text) to authenticated;
grant execute on function public.admin_list_rooms(integer) to authenticated;
grant execute on function public.admin_list_gifts(integer) to authenticated;
grant execute on function public.admin_set_gift_active(uuid, boolean) to authenticated;
grant execute on function public.admin_set_recharge_agency_active(uuid, boolean) to authenticated;
grant execute on function public.admin_set_recharge_agent_active(uuid, boolean) to authenticated;
grant execute on function public.admin_list_audit_logs(integer) to authenticated;
