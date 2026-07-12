-- Fix: empty-looking mic shows "seat taken" because ghost rows block claims
--
-- ROOT CAUSE:
--   getActiveRoomMembers filters members by last_seen_at >= now() - 45s.
--   When a user crashes or force-quits, their room_members row stays with
--   left_at = NULL and seat_number = N (never cleaned up). After 45 seconds
--   the Flutter UI stops rendering them (seat appears empty), but the unique
--   partial index room_members_unique_active_seat still sees the row as active
--   (left_at IS NULL) and raises 'seat_taken' for anyone who taps the seat.
--
-- ALSO FIXES (from 20260923000000_fix_host_seat_claim.sql):
--   claim_speaker_seat early-returned for role='host' without updating
--   seat_number, so the room owner could never claim/move a seat.
--
-- FIX:
--   1. Before checking seat availability, evict any ghost occupant of the
--      target seat: a row with left_at IS NULL whose last_seen_at is older
--      than 45 seconds (three missed heartbeats, matching Flutter threshold).
--   2. Hosts keep role='host' when claiming a seat (not promoted to 'speaker').
--   3. All other guards (force-mute, ban, capacity) unchanged.
--
-- This migration supersedes 20260923000000_fix_host_seat_claim.sql.
-- Apply only this one if 20260923 has not yet been applied.

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
  v_caller        uuid    := auth.uid();
  v_max_seats     integer;
  v_is_closed     boolean;
  v_role          text;
  v_force_muted   boolean;
  v_seat_user_id  uuid;
  v_seat_last_seen timestamptz;
  v_result        jsonb;
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

  -- 3. Seat number must be within the room's capacity (1-indexed).
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

  -- 6. Non-host: block if banned.
  if v_role != 'host' and exists (
    select 1
    from   public.room_bans
    where  room_id    = p_room_id
      and  user_id    = v_caller
      and  (expires_at is null or expires_at > now())
  ) then
    raise exception 'banned_from_room';
  end if;

  -- 7. Resolve seat occupancy: check who holds the target seat right now.
  select user_id, last_seen_at
  into   v_seat_user_id, v_seat_last_seen
  from   public.room_members
  where  room_id     = p_room_id
    and  seat_number = p_seat_number
    and  left_at     is null;

  if v_seat_user_id is not null and v_seat_user_id != v_caller then
    -- Ghost check: same 45-second threshold as Flutter's getActiveRoomMembers.
    -- A member who hasn't heartbeated in >45s is considered disconnected and
    -- their seat can be safely reclaimed.
    if v_seat_last_seen < now() - interval '45 seconds' then
      -- Evict the ghost row so the unique partial index stops blocking.
      update public.room_members
      set    left_at      = now(),
             seat_number  = null,
             is_muted     = true,
             last_seen_at = now(),
             updated_at   = now()
      where  room_id  = p_room_id
        and  user_id  = v_seat_user_id
        and  left_at  is null;
    else
      -- Seat is actively occupied by a live user.
      raise exception 'seat_taken';
    end if;
  end if;

  -- 8. Atomically claim the seat.
  --    Hosts keep role='host'; listeners/speakers get role='speaker'.
  --    The unique partial index on (room_id, seat_number) WHERE left_at IS NULL
  --    catches concurrent races: the second UPDATE hits a unique_violation which
  --    we surface as seat_taken.
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
