-- Forward-only correction for two high-severity privilege issues.

-- ---------------------------------------------------------------------------
-- 1. admin_audit_logs is append-only and writable only from trusted definer
--    functions. Table writes from API roles are forbidden.
-- ---------------------------------------------------------------------------

alter table public.admin_audit_logs enable row level security;

drop policy if exists admin_audit_logs_insert on public.admin_audit_logs;
drop policy if exists "Admins can insert audit logs" on public.admin_audit_logs;
drop policy if exists admin_audit_logs_update on public.admin_audit_logs;
drop policy if exists admin_audit_logs_delete on public.admin_audit_logs;

revoke insert, update, delete on table public.admin_audit_logs from public;
revoke insert, update, delete on table public.admin_audit_logs from anon;
revoke insert, update, delete on table public.admin_audit_logs from authenticated;

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
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_actor_role text;
  v_id uuid;
begin
  if v_actor is null or not public.has_admin_access() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  if p_action is null
     or length(trim(p_action)) not between 1 and 100 then
    raise exception 'invalid_audit_action' using errcode = '22023';
  end if;

  if p_entity_type is not null and length(p_entity_type) > 80 then
    raise exception 'invalid_entity_type' using errcode = '22023';
  end if;
  if p_entity_id is not null and length(p_entity_id) > 200 then
    raise exception 'invalid_entity_id' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(coalesce(p_metadata, '{}'::jsonb)) > 16384 then
    raise exception 'invalid_audit_metadata' using errcode = '22023';
  end if;

  v_actor_role := public.get_admin_role(v_actor);

  insert into public.admin_audit_logs (
    admin_user_id,
    actor_id,
    actor_role,
    target_user_id,
    action,
    entity_type,
    entity_id,
    target_type,
    target_id,
    metadata,
    created_at
  ) values (
    v_actor,
    v_actor,
    v_actor_role,
    p_target_user_id,
    trim(p_action),
    p_entity_type,
    p_entity_id,
    p_entity_type,
    p_entity_id,
    coalesce(p_metadata, '{}'::jsonb),
    statement_timestamp()
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.admin_record_audit(text,text,text,uuid,jsonb)
  from public, anon;
grant execute on function public.admin_record_audit(text,text,text,uuid,jsonb)
  to authenticated;

create or replace function public.admin_record_audit(
  p_action text,
  p_target_type text default null,
  p_target_id text default null,
  p_old_value jsonb default null,
  p_new_value jsonb default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not public.has_admin_access() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  if p_action is null or length(trim(p_action)) not between 1 and 100 then
    raise exception 'invalid_audit_action' using errcode = '22023';
  end if;
  if p_target_type is not null and length(p_target_type) > 80 then
    raise exception 'invalid_target_type' using errcode = '22023';
  end if;
  if p_target_id is not null and length(p_target_id) > 200 then
    raise exception 'invalid_target_id' using errcode = '22023';
  end if;
  if (p_old_value is not null and pg_column_size(p_old_value) > 16384)
     or (p_new_value is not null and pg_column_size(p_new_value) > 16384) then
    raise exception 'invalid_audit_value' using errcode = '22023';
  end if;

  insert into public.admin_audit_logs (
    admin_user_id,
    actor_id,
    actor_role,
    action,
    target_type,
    target_id,
    old_value,
    new_value,
    created_at
  ) values (
    v_actor,
    v_actor,
    public.get_admin_role(v_actor),
    trim(p_action),
    p_target_type,
    p_target_id,
    p_old_value,
    p_new_value,
    statement_timestamp()
  );
end;
$$;

revoke all on function public.admin_record_audit(text,text,text,jsonb,jsonb)
  from public, anon;
grant execute on function public.admin_record_audit(text,text,text,jsonb,jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Split private owner VIP state from minimal public presentation state.
-- ---------------------------------------------------------------------------

revoke all on function public.get_my_vip() from public, anon;
grant execute on function public.get_my_vip() to authenticated;

create or replace function public.get_public_user_vip(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when p.id is null then null else jsonb_build_object(
    'vip_level', case
      when coalesce(p.vip_level, 0) > 0
       and (p.vip_expires_at is null or p.vip_expires_at > statement_timestamp())
      then p.vip_level else 0 end,
    'vip_title', case
      when coalesce(p.vip_level, 0) > 0
       and (p.vip_expires_at is null or p.vip_expires_at > statement_timestamp())
      then p.vip_title else null end,
    'is_active', coalesce(p.vip_level, 0) > 0
      and (p.vip_expires_at is null or p.vip_expires_at > statement_timestamp()),
    'is_golden_id', coalesce(p.is_golden_id, false)
      and (p.golden_id_expires_at is null
        or p.golden_id_expires_at > statement_timestamp())
  ) end
  from (select 1) seed
  left join public.profiles p on p.id = p_user_id;
$$;

create or replace function public.get_public_users_vip(p_user_ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(
    p.id::text,
    jsonb_build_object(
      'vip_level', case
        when coalesce(p.vip_level, 0) > 0
         and (p.vip_expires_at is null or p.vip_expires_at > statement_timestamp())
        then p.vip_level else 0 end,
      'vip_title', case
        when coalesce(p.vip_level, 0) > 0
         and (p.vip_expires_at is null or p.vip_expires_at > statement_timestamp())
        then p.vip_title else null end,
      'is_active', coalesce(p.vip_level, 0) > 0
        and (p.vip_expires_at is null or p.vip_expires_at > statement_timestamp()),
      'is_golden_id', coalesce(p.is_golden_id, false)
        and (p.golden_id_expires_at is null
          or p.golden_id_expires_at > statement_timestamp())
    )
  ), '{}'::jsonb)
  from public.profiles p
  where p.id = any(coalesce(p_user_ids, array[]::uuid[]))
    and cardinality(coalesce(p_user_ids, array[]::uuid[])) <= 200;
$$;

revoke all on function public.get_public_user_vip(uuid) from public, anon;
revoke all on function public.get_public_users_vip(uuid[]) from public, anon;
grant execute on function public.get_public_user_vip(uuid) to authenticated;
grant execute on function public.get_public_users_vip(uuid[]) to authenticated;

revoke all on function public.get_user_vip(uuid)
  from public, anon, authenticated;
revoke all on function public.get_users_with_vip(uuid[])
  from public, anon, authenticated;

comment on function public.get_user_vip(uuid) is
  'Deprecated private VIP contract. Execution revoked; use get_my_vip or get_public_user_vip.';
comment on function public.get_users_with_vip(uuid[]) is
  'Deprecated private batch VIP contract. Execution revoked; use get_public_users_vip.';
