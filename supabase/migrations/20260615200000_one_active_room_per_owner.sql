-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: one_active_room_per_owner
-- Each user may have at most one room where is_closed = false at any time.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Clean up existing duplicate active rooms (keep the newest per owner).
--    This must run BEFORE the unique index is created.
UPDATE public.rooms
SET
  is_closed  = true,
  closed_at  = now(),
  closed_by  = owner_id,
  closed_reason = 'auto-closed: duplicate active room cleanup'
WHERE id IN (
  SELECT id
  FROM (
    SELECT
      id,
      ROW_NUMBER() OVER (
        PARTITION BY owner_id
        ORDER BY created_at DESC
      ) AS rn
    FROM public.rooms
    WHERE is_closed = false
  ) ranked
  WHERE rn > 1
);

-- 2. Partial unique index: one open room per owner.
--    Concurrent inserts or updates that would create a second open room will
--    get a unique-constraint violation that we catch in the RPC below.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_one_active_room_per_owner
  ON public.rooms (owner_id)
  WHERE (is_closed = false);

-- 3. RPC: get_or_create_my_room
--    Returns the caller's existing open room, or creates a new one.
--    Handles race conditions via the unique index: if two concurrent calls
--    both see no existing room, one insert wins and the other catches the
--    duplicate-key error, then re-fetches.
CREATE OR REPLACE FUNCTION public.get_or_create_my_room(
  p_name        text,
  p_description text    DEFAULT NULL,
  p_language    text    DEFAULT 'ar',
  p_max_seats   integer DEFAULT 12
)
RETURNS SETOF public.rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   uuid := auth.uid();
  v_room_name text;
  v_room      public.rooms;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Check for an existing open room first.
  SELECT * INTO v_room
  FROM public.rooms
  WHERE owner_id = v_user_id
    AND is_closed = false
  LIMIT 1;

  IF FOUND THEN
    RETURN NEXT v_room;
    RETURN;
  END IF;

  -- Generate a unique livekit room name.
  v_room_name := 'srood_' || extract(epoch from now())::bigint::text
              || '_' || left(v_user_id::text, 8);

  -- Attempt to create. If another concurrent call already created one
  -- (unique-constraint violation), fall through to the SELECT below.
  BEGIN
    INSERT INTO public.rooms (
      owner_id, name, description, language, max_seats, livekit_room_name
    ) VALUES (
      v_user_id, p_name, p_description, p_language, p_max_seats, v_room_name
    )
    RETURNING * INTO v_room;

    RETURN NEXT v_room;
    RETURN;
  EXCEPTION
    WHEN unique_violation THEN
      -- Another request won the race; return the existing room.
      SELECT * INTO v_room
      FROM public.rooms
      WHERE owner_id = v_user_id
        AND is_closed = false
      LIMIT 1;

      IF FOUND THEN
        RETURN NEXT v_room;
      END IF;
      RETURN;
  END;
END;
$$;

-- 4. RPC: leave_room_and_maybe_close
--    Soft-removes the caller from a room.
--    If the caller is the owner AND no other members remain, closes the room.
CREATE OR REPLACE FUNCTION public.leave_room_and_maybe_close(
  p_room_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id       uuid := auth.uid();
  v_owner_id      uuid;
  v_active_count  integer;
  v_was_closed    boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Mark this member as left.
  UPDATE public.room_members
  SET
    left_at      = now(),
    last_seen_at = now(),
    is_muted     = true
  WHERE room_id = p_room_id
    AND user_id = v_user_id
    AND left_at IS NULL;

  -- Check room ownership.
  SELECT owner_id INTO v_owner_id
  FROM public.rooms
  WHERE id = p_room_id AND is_closed = false;

  IF NOT FOUND THEN
    -- Room already closed or does not exist.
    RETURN jsonb_build_object('closed', false, 'was_owner', false);
  END IF;

  IF v_owner_id = v_user_id THEN
    -- Count remaining active members (joined but not yet left).
    SELECT count(*) INTO v_active_count
    FROM public.room_members
    WHERE room_id = p_room_id
      AND left_at IS NULL;

    IF v_active_count = 0 THEN
      UPDATE public.rooms
      SET
        is_closed    = true,
        closed_at    = now(),
        closed_by    = v_user_id,
        closed_reason = 'owner_left_empty'
      WHERE id = p_room_id;

      v_was_closed := true;
    END IF;

    RETURN jsonb_build_object(
      'closed',    v_was_closed,
      'was_owner', true
    );
  END IF;

  RETURN jsonb_build_object('closed', false, 'was_owner', false);
END;
$$;

-- 5. RPC: close_empty_rooms
--    Closes active rooms that have zero members still present.
--    Call on: room-list load, after leave, or on app resume.
CREATE OR REPLACE FUNCTION public.close_empty_rooms()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH empty_rooms AS (
    SELECT r.id
    FROM public.rooms r
    WHERE r.is_closed = false
      AND NOT EXISTS (
        SELECT 1
        FROM public.room_members m
        WHERE m.room_id = r.id
          AND m.left_at IS NULL
      )
  )
  UPDATE public.rooms
  SET
    is_closed    = true,
    closed_at    = now(),
    closed_reason = 'auto-closed: no active members'
  WHERE id IN (SELECT id FROM empty_rooms);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- Grant execute rights to authenticated users.
GRANT EXECUTE ON FUNCTION public.get_or_create_my_room(text, text, text, integer)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_room_and_maybe_close(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_empty_rooms()
  TO authenticated;
