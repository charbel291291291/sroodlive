create extension if not exists pgcrypto;

alter table public.rooms
add column if not exists room_password_hash text;

create or replace function public.set_room_lock(
  p_room_id uuid,
  p_is_locked boolean,
  p_password text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_owner_id uuid;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select owner_id
  into v_owner_id
  from public.rooms
  where id = p_room_id;

  if v_owner_id is null then
    raise exception 'room_not_found';
  end if;

  if v_owner_id <> v_user_id then
    raise exception 'only_host_can_lock_room';
  end if;

  if p_is_locked then
    if p_password is null or length(trim(p_password)) < 3 then
      raise exception 'room_password_required';
    end if;

    update public.rooms
    set
      is_locked = true,
      room_password_hash = crypt(trim(p_password), gen_salt('bf'))
    where id = p_room_id;
  else
    update public.rooms
    set
      is_locked = false,
      room_password_hash = null
    where id = p_room_id;
  end if;
end;
$$;

create or replace function public.join_room_with_password(
  p_room_id uuid,
  p_password text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_owner_id uuid;
  v_is_locked boolean;
  v_password_hash text;
  v_role text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select owner_id, is_locked, room_password_hash
  into v_owner_id, v_is_locked, v_password_hash
  from public.rooms
  where id = p_room_id;

  if v_owner_id is null then
    raise exception 'room_not_found';
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

    if p_password is null or crypt(trim(p_password), v_password_hash) <> v_password_hash then
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

grant execute on function public.set_room_lock(uuid, boolean, text) to authenticated;
grant execute on function public.join_room_with_password(uuid, text) to authenticated;
