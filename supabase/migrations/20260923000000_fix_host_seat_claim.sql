-- Fix: host/owner cannot claim a seat (mic always muted, seat bounces back)
--
-- ROOT CAUSE: claim_speaker_seat contained an early-return for role='host'
-- with the comment "Hosts/owners are already speakers — nothing to do."
-- In practice the host always joins with seat_number=NULL (join_room_with_password
-- resets seat_number=NULL on every join). The early-return meant the owner
-- could never assign themselves a seat, so _isCurrentUserOnMic was always
-- false in Flutter → mic toggle was blocked and the seat UI bounced back.
--
-- FIX: For the 'host' role, perform the same seat_number update that
-- speakers receive, but preserve role='host' instead of writing 'speaker'.

create or replace function public.claim_speaker_seat(
  p_room_id     uuid,
  p_seat_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller      uuid    := auth.uid();
  v_max_seats   integer;
  v_is_closed   boolean;
  v_role        text;
  v_force_muted boolean;
  v_seat_user_id uuid;
  v_result      jsonb;
begin
  -- 1. Must be authenticated.
  if v_caller is null then
    raise exception 'not_authenticated';
  end if;

  -- 2. Room must exist and be open.
  select max_seats, is_closed
  into   v_max_seats, v_is_closed
  from   public.rooms
  where  id = p_room_id;

  if v_max_seats is null then
    raise exception 'room_not_found';
  end if;

  if v_is_closed then
    raise exception 'room_closed';
  end if;

  -- 3. Seat number must be within the room's capacity (seats are 1-indexed).
  if p_seat_number < 1 or p_seat_number > v_max_seats then
    raise exception 'invalid_seat_number';
  end if;

  -- 4. Caller must be an active member.
  select role, force_muted
  into   v_role, v_force_muted
  from   public.room_members
  where  room_id = p_room_id
    and  user_id = v_caller
    and  left_at is null;

  if v_role is null then
    raise exception 'not_in_room';
  end if;

  -- 5. Non-host: block if force-muted.
  if v_role != 'host' and v_force_muted then
    raise exception 'force_muted';
  end if;

  -- 6. Caller must not be banned from this room (non-host only).
  if v_role != 'host' and exists (
    select 1
    from   public.room_bans
    where  room_id    = p_room_id
      and  user_id    = v_caller
      and  (expires_at is null or expires_at > now())
  ) then
    raise exception 'banned_from_room';
  end if;

  -- 7. Seat must be empty or already held by the caller.
  select user_id
  into   v_seat_user_id
  from   public.room_members
  where  room_id     = p_room_id
    and  seat_number = p_seat_number
    and  left_at     is null;

  if v_seat_user_id is not null and v_seat_user_id != v_caller then
    raise exception 'seat_taken';
  end if;

  -- 8. Atomically claim the seat.
  --    Hosts keep role='host'; listeners are promoted to 'speaker'.
  --    The unique partial index on (room_id, seat_number) catches concurrent
  --    races at the DB level even if two callers pass check 7 simultaneously.
  begin
    update public.room_members
    set    role        = case when v_role = 'host' then 'host' else 'speaker' end,
           seat_number = p_seat_number,
           updated_at  = now()
    where  room_id = p_room_id
      and  user_id = v_caller
      and  left_at is null
    returning jsonb_build_object(
      'user_id',     user_id,
      'room_id',     room_id,
      'role',        role,
      'seat_number', seat_number
    ) into v_result;
  exception
    when unique_violation then
      raise exception 'seat_taken';
  end;

  if v_result is null then
    raise exception 'update_failed';
  end if;

  return v_result;
end;
$$;

-- Grant unchanged — already granted to authenticated in original migration.
grant execute on function public.claim_speaker_seat(uuid, integer) to authenticated;
