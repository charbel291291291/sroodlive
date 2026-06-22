-- Phase R4-A: secure self-promotion to speaker seat
--
-- Problem: moveMeToSpeakerSeat used a direct client UPDATE, meaning a user
-- could forge any role/seat value. Two users could also race and claim the
-- same seat simultaneously because no unique constraint existed.
--
-- Fix:
--   1. Unique partial index on (room_id, seat_number) where left_at IS NULL
--      so that the DB rejects duplicate seat claims atomically.
--   2. claim_speaker_seat SECURITY DEFINER RPC that verifies every condition
--      server-side before writing. The client no longer sends a role value.

-- ── 1. Unique partial index — prevents two active members holding the same seat ──
create unique index if not exists room_members_unique_active_seat
  on public.room_members (room_id, seat_number)
  where (left_at is null and seat_number is not null);

-- ── 2. RPC: claim_speaker_seat ────────────────────────────────────────────────
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
  v_caller   uuid    := auth.uid();
  v_max_seats integer;
  v_is_closed boolean;
  v_role      text;
  v_force_muted boolean;
  v_seat_user_id uuid;
  v_result   jsonb;
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

  -- 5. Owner claims seats differently (managed by update_room_member_role).
  --    This RPC is for listeners promoting themselves only.
  --    Hosts/owners are already speakers — nothing to do, return early.
  if v_role in ('host', 'owner') then
    select jsonb_build_object(
      'user_id',     user_id,
      'room_id',     room_id,
      'role',        role,
      'seat_number', seat_number
    )
    into v_result
    from public.room_members
    where room_id = p_room_id and user_id = v_caller and left_at is null;
    return v_result;
  end if;

  -- 6. Caller must not be force-muted from speaking by the owner.
  if v_force_muted then
    raise exception 'force_muted';
  end if;

  -- 7. Caller must not be banned from this room.
  if exists (
    select 1
    from   public.room_bans
    where  room_id    = p_room_id
      and  user_id    = v_caller
      and  (expires_at is null or expires_at > now())
  ) then
    raise exception 'banned_from_room';
  end if;

  -- 8. Seat must be empty or already held by the caller.
  select user_id
  into   v_seat_user_id
  from   public.room_members
  where  room_id     = p_room_id
    and  seat_number = p_seat_number
    and  left_at     is null;

  if v_seat_user_id is not null and v_seat_user_id != v_caller then
    raise exception 'seat_taken';
  end if;

  -- 9. Atomically claim the seat.
  --    The unique partial index on (room_id, seat_number) ensures a concurrent
  --    race is caught at the DB level even if two callers pass check 8 at the
  --    same time — the second UPDATE will violate the index and raise 23505.
  begin
    update public.room_members
    set    role        = 'speaker',
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

grant execute on function public.claim_speaker_seat(uuid, integer) to authenticated;

comment on function public.claim_speaker_seat(uuid, integer) is
  'Allows a listener to self-promote to speaker and claim a seat. '
  'Verifies membership, bans, force-mute, seat availability, and seat capacity '
  'entirely server-side. Never trusts a client-provided role value.';
