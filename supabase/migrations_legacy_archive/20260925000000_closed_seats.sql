-- Feature: close/lock individual mic seats
--
-- Room owners and moderators can lock seats so no participant can claim them.
-- A locked seat appears with a lock icon; only the owner/mod who locked it
-- (or any other owner/mod) can re-open it.
--
-- Design: store locked seat numbers as an integer array on the rooms row.
-- This keeps it simple (no extra table) and fires the existing rooms realtime
-- UPDATE event so all connected clients update instantly.

-- 1. Add column to rooms table.
alter table public.rooms
  add column if not exists closed_seats integer[] not null default '{}';

-- 2. RPC: toggle_room_seat_closed
--    Requires caller to be the room owner or an active moderator.
--    If the seat is currently open  → adds it to closed_seats.
--    If the seat is currently closed → removes it from closed_seats.
--    If the seat is occupied when closing → evicts the occupant first
--    (sets them to listener with no seat assignment).
--    Returns the new closed_seats array so the client can update state.

create or replace function public.toggle_room_seat_closed(
  p_room_id     uuid,
  p_seat_number integer
)
returns integer[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller      uuid := auth.uid();
  v_owner_id    uuid;
  v_max_seats   integer;
  v_is_closed   boolean;
  v_closed_arr  integer[];
  v_is_mod      boolean;
  v_currently_closed boolean;
begin
  if v_caller is null then
    raise exception 'not_authenticated';
  end if;

  select owner_id, max_seats, is_closed
  into   v_owner_id, v_max_seats, v_is_closed
  from   public.rooms
  where  id = p_room_id;

  if v_owner_id is null then
    raise exception 'room_not_found';
  end if;

  if v_is_closed then
    raise exception 'room_closed';
  end if;

  if p_seat_number < 1 or p_seat_number > v_max_seats then
    raise exception 'invalid_seat_number';
  end if;

  -- Permission check: owner or active moderator.
  if v_caller != v_owner_id then
    select exists(
      select 1 from public.room_moderators
      where  room_id = p_room_id
        and  user_id = v_caller
    ) into v_is_mod;

    if not v_is_mod then
      raise exception 'not_authorized';
    end if;
  end if;

  -- Determine whether seat is currently in the closed list.
  select closed_seats
  into   v_closed_arr
  from   public.rooms
  where  id = p_room_id;

  v_closed_arr := coalesce(v_closed_arr, '{}');
  v_currently_closed := p_seat_number = any(v_closed_arr);

  if v_currently_closed then
    -- Re-open: remove from array.
    v_closed_arr := array_remove(v_closed_arr, p_seat_number);
  else
    -- Close: add to array, evict any current occupant of this seat.
    update public.room_members
    set    role        = 'listener',
           seat_number = null,
           updated_at  = now()
    where  room_id     = p_room_id
      and  seat_number = p_seat_number
      and  left_at     is null;

    v_closed_arr := array_append(v_closed_arr, p_seat_number);
  end if;

  -- Persist updated array.
  update public.rooms
  set    closed_seats = v_closed_arr,
         updated_at   = now()
  where  id = p_room_id
  returning closed_seats into v_closed_arr;

  return v_closed_arr;
end;
$$;

revoke all on function public.toggle_room_seat_closed(uuid, integer) from public;
grant execute on function public.toggle_room_seat_closed(uuid, integer) to authenticated;
