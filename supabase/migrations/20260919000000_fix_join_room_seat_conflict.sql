-- Fix duplicate seat constraint on room rejoin
--
-- ROOT CAUSE: join_room_with_password's ON CONFLICT DO UPDATE did not reset
-- seat_number to NULL. When a user rejoined a room where they previously held
-- a seat, their old seat_number was reactivated (left_at set back to NULL).
-- If another user had since claimed that seat, both rows ended up with the same
-- (room_id, seat_number, left_at=NULL), violating the unique partial index
-- room_members_unique_active_seat.
--
-- FIX: reset seat_number = NULL and force_muted = false on rejoin so the
-- returning user enters as a plain listener with no seat assignment.

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
  v_user_id      uuid;
  v_owner_id     uuid;
  v_is_locked    boolean;
  v_is_closed    boolean;
  v_password_hash text;
  v_role         text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select owner_id, is_locked, coalesce(is_closed, false), room_password_hash
  into   v_owner_id, v_is_locked, v_is_closed, v_password_hash
  from   public.rooms
  where  id = p_room_id;

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
    role        = excluded.role,
    is_muted    = true,
    force_muted = false,
    seat_number = null,
    left_at     = null,
    last_seen_at = now();
end;
$$;

grant execute on function public.join_room_with_password(uuid, text) to authenticated;
