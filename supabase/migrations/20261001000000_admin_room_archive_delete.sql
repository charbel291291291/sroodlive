-- Admin: soft-archive and soft-delete controls for rooms.
--
-- Adds nullable tracking columns, two admin RPCs, and rebuilds
-- admin_list_rooms to surface archived/deleted status.
-- No rows are ever hard-deleted.

-- ── 1. New columns on public.rooms ───────────────────────────────────────────

alter table public.rooms
  add column if not exists archived_at    timestamptz,
  add column if not exists archived_by    uuid references auth.users(id) on delete set null,
  add column if not exists archive_reason text,
  add column if not exists deleted_at     timestamptz,
  add column if not exists deleted_by     uuid references auth.users(id) on delete set null,
  add column if not exists delete_reason  text;

-- ── 2. admin_archive_room ─────────────────────────────────────────────────────

create or replace function public.admin_archive_room(
  p_room_id uuid,
  p_reason  text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  -- Any recognised admin who has room-management rights can archive.
  if not (
    public.has_admin_access()
    or public.has_room_admin_access()
    or public.has_app_role('o_super_admin')
    or public.has_app_role('p_super_admin')
    or public.has_app_role('support_admin')
  ) then
    raise exception 'not_authorized';
  end if;

  update public.rooms
  set
    archived_at    = v_now,
    archived_by    = auth.uid(),
    archive_reason = nullif(trim(coalesce(p_reason, '')), ''),
    -- Archiving also closes the room so no one can join.
    is_closed      = true,
    closed_at      = coalesce(closed_at, v_now),
    closed_reason  = coalesce(closed_reason, 'archived'),
    updated_at     = v_now
  where id = p_room_id;

  if not found then
    raise exception 'room_not_found';
  end if;

  perform public.admin_record_audit(
    'archive_room'::text,
    'rooms'::text,
    p_room_id::text,
    auth.uid()::uuid,
    jsonb_build_object('reason', p_reason)::jsonb
  );
end;
$$;

grant execute on function public.admin_archive_room(uuid, text) to authenticated;

-- ── 3. admin_soft_delete_room ─────────────────────────────────────────────────

create or replace function public.admin_soft_delete_room(
  p_room_id uuid,
  p_reason  text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  -- Soft-delete is restricted to the highest admin tiers only.
  if not (
    public.has_app_role('super_admin')
    or public.has_app_role('o_super_admin')
  ) then
    raise exception 'not_authorized';
  end if;

  update public.rooms
  set
    deleted_at    = v_now,
    deleted_by    = auth.uid(),
    delete_reason = nullif(trim(coalesce(p_reason, '')), ''),
    is_closed     = true,
    closed_at     = coalesce(closed_at, v_now),
    closed_reason = 'deleted',
    updated_at    = v_now
  where id = p_room_id;

  if not found then
    raise exception 'room_not_found';
  end if;

  perform public.admin_record_audit(
    'soft_delete_room'::text,
    'rooms'::text,
    p_room_id::text,
    auth.uid()::uuid,
    jsonb_build_object('reason', p_reason)::jsonb
  );
end;
$$;

grant execute on function public.admin_soft_delete_room(uuid, text) to authenticated;

-- ── 4. Rebuild admin_list_rooms with archived/deleted columns ─────────────────

drop function if exists public.admin_list_rooms(integer);

create function public.admin_list_rooms(
  p_limit integer default 50
)
returns table (
  id                   uuid,
  name                 text,
  description          text,
  owner_id             uuid,
  owner_public_user_id text,
  owner_name           text,
  language             text,
  max_seats            integer,
  is_private           boolean,
  is_locked            boolean,
  is_closed            boolean,
  closed_at            timestamptz,
  closed_reason        text,
  active_members       bigint,
  public_room_code     text,
  archived_at          timestamptz,
  deleted_at           timestamptz,
  created_at           timestamptz
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
    coalesce(r.max_seats, r.max_members, 12),
    coalesce(r.is_private, false),
    coalesce(r.is_locked, false),
    coalesce(r.is_closed, false),
    r.closed_at,
    r.closed_reason,
    (
      select count(*)
      from public.room_members rm
      where rm.room_id = r.id
        and rm.left_at is null
        and rm.last_seen_at >= now() - interval '60 seconds'
    )::bigint,
    r.public_room_code,
    r.archived_at,
    r.deleted_at,
    r.created_at
  from public.rooms r
  left join public.profiles p on p.id = r.owner_id
  where public.has_admin_access()
  order by r.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

grant execute on function public.admin_list_rooms(integer) to authenticated;
