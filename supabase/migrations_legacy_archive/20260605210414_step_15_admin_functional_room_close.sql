alter table public.rooms
add column if not exists is_closed boolean not null default false,
add column if not exists closed_at timestamptz null,
add column if not exists closed_by uuid null references auth.users(id) on delete set null,
add column if not exists closed_reason text null;

create index if not exists rooms_is_closed_created_at_idx
on public.rooms (is_closed, created_at desc);

drop function if exists public.admin_list_rooms(integer);

create function public.admin_list_rooms(
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
  is_closed boolean,
  closed_at timestamptz,
  closed_reason text,
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
    coalesce(r.is_closed, false),
    r.closed_at,
    r.closed_reason,
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

create or replace function public.admin_close_room(
  p_room_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  if not public.has_room_admin_access() then
    raise exception 'not_authorized';
  end if;

  update public.rooms
  set is_closed = true,
      closed_at = v_now,
      closed_by = auth.uid(),
      closed_reason = nullif(trim(coalesce(p_reason, '')), '')
  where id = p_room_id;

  if not found then
    raise exception 'room_not_found';
  end if;

  update public.room_members
  set is_muted = true,
      seat_number = null,
      left_at = v_now,
      last_seen_at = v_now
  where room_id = p_room_id
    and left_at is null;

  perform public.admin_record_audit(
    'close_room',
    'rooms',
    p_room_id::text,
    null,
    jsonb_build_object('reason', p_reason)
  );
end;
$$;

create or replace function public.admin_reopen_room(
  p_room_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_room_admin_access() then
    raise exception 'not_authorized';
  end if;

  update public.rooms
  set is_closed = false,
      closed_at = null,
      closed_by = null,
      closed_reason = null
  where id = p_room_id;

  if not found then
    raise exception 'room_not_found';
  end if;

  perform public.admin_record_audit(
    'reopen_room',
    'rooms',
    p_room_id::text,
    null,
    '{}'::jsonb
  );
end;
$$;

create or replace function public.join_room_with_password(
  p_room_id uuid,
  p_password text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
  v_owner_id uuid;
  v_is_locked boolean;
  v_is_closed boolean;
  v_password_hash text;
  v_role text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select owner_id, is_locked, coalesce(is_closed, false), room_password_hash
  into v_owner_id, v_is_locked, v_is_closed, v_password_hash
  from public.rooms
  where id = p_room_id;

  if v_owner_id is null then
    raise exception 'room_not_found';
  end if;

  if v_is_closed then
    raise exception 'closed_room';
  end if;

  if v_owner_id = v_user_id then
    v_role := 'host';
  else
    v_role := 'listener';
  end if;

  if v_is_locked and v_role = 'listener' then
    if v_password_hash is null then
      raise exception 'locked_room';
    end if;

    if p_password is null or extensions.crypt(trim(p_password), v_password_hash) <> v_password_hash then
      raise exception 'wrong_room_password';
    end if;
  end if;

  insert into public.room_members (
    room_id,
    user_id,
    role,
    is_muted,
    left_at,
    last_seen_at
  )
  values (
    p_room_id,
    v_user_id,
    v_role,
    true,
    null,
    now()
  )
  on conflict (room_id, user_id)
  do update set
    role = excluded.role,
    is_muted = true,
    left_at = null,
    last_seen_at = now();
end;
$$;

grant execute on function public.admin_list_rooms(integer) to authenticated;
grant execute on function public.admin_close_room(uuid, text) to authenticated;
grant execute on function public.admin_reopen_room(uuid) to authenticated;
grant execute on function public.join_room_with_password(uuid, text) to authenticated;
