-- =============================================================================
-- Migration: personal_rooms
-- Every user gets one permanent personal room linked to their account.
-- =============================================================================

-- 1. Add is_personal_room column (idempotent).
ALTER TABLE public.rooms
  ADD COLUMN IF NOT EXISTS is_personal_room boolean NOT NULL DEFAULT false;

-- 2. One personal room per owner — enforced globally (open AND closed).
--    The existing uniq_one_active_room_per_owner index already prevents two
--    open rooms at once; this new index prevents two personal rooms ever.
CREATE UNIQUE INDEX IF NOT EXISTS rooms_one_personal_room_per_owner
  ON public.rooms(owner_id)
  WHERE is_personal_room = true;

-- =============================================================================
-- 3. get_or_create_my_room() — no params variant for My Room button.
--    Returns the user's personal room (creating it on first call).
--    Does NOT reopen a closed personal room — caller checks isClosed and
--    calls reopen_my_room() if needed.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_or_create_my_room()
RETURNS public.rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_room      public.rooms;
  v_base_name text;
  v_lk_name   text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  -- Return existing personal room (may be open or closed — caller decides).
  SELECT * INTO v_room
  FROM public.rooms
  WHERE owner_id = v_uid AND is_personal_room = true
  LIMIT 1;

  IF FOUND THEN RETURN v_room; END IF;

  -- Build a default name: "<display_name>'s Room" or "My Room".
  SELECT COALESCE(
           NULLIF(TRIM(display_name), ''),
           NULLIF(TRIM(username), ''),
           'My'
         ) || '''s Room'
  INTO v_base_name
  FROM public.profiles
  WHERE id = v_uid
  LIMIT 1;

  IF v_base_name IS NULL THEN v_base_name := 'My Room'; END IF;

  v_lk_name := 'srood_' || extract(epoch from now())::bigint::text
            || '_' || left(v_uid::text, 8);

  BEGIN
    INSERT INTO public.rooms (
      owner_id, name, language, max_seats, livekit_room_name, is_personal_room
    ) VALUES (
      v_uid, v_base_name, 'ar', 12, v_lk_name, true
    )
    RETURNING * INTO v_room;

    RETURN v_room;
  EXCEPTION
    WHEN unique_violation THEN
      -- Race: another concurrent call already created it — just fetch it.
      SELECT * INTO v_room
      FROM public.rooms
      WHERE owner_id = v_uid AND is_personal_room = true
      LIMIT 1;
      RETURN v_room;
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_my_room() TO authenticated;

-- =============================================================================
-- 4. reopen_my_room() — un-closes the personal room so it appears in the list.
--    Closes any other active non-personal rooms first to avoid index conflict.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.reopen_my_room()
RETURNS public.rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_room public.rooms;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  -- Close any other active non-personal rooms owned by this user so the
  -- uniq_one_active_room_per_owner index doesn't conflict on the reopen.
  UPDATE public.rooms
  SET
    is_closed     = true,
    closed_at     = now(),
    closed_by     = v_uid,
    closed_reason = 'replaced_by_personal_room'
  WHERE owner_id = v_uid
    AND is_closed = false
    AND is_personal_room = false;

  UPDATE public.rooms
  SET
    is_closed     = false,
    closed_at     = NULL,
    closed_by     = NULL,
    closed_reason = NULL,
    updated_at    = now()
  WHERE owner_id = v_uid AND is_personal_room = true
  RETURNING * INTO v_room;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_personal_room';
  END IF;

  RETURN v_room;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reopen_my_room() TO authenticated;

-- =============================================================================
-- 5. Update leave_room_and_maybe_close — personal rooms do NOT auto-close
--    when the owner exits, even if they are the last one present.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.leave_room_and_maybe_close(
  p_room_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      uuid := auth.uid();
  v_owner_id     uuid;
  v_is_personal  boolean;
  v_active_count integer;
  v_was_closed   boolean := false;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  -- Soft-remove caller from room.
  UPDATE public.room_members
  SET left_at = now(), last_seen_at = now(), is_muted = true
  WHERE room_id = p_room_id AND user_id = v_user_id AND left_at IS NULL;

  -- Fetch room ownership and personal-room flag.
  SELECT owner_id, is_personal_room INTO v_owner_id, v_is_personal
  FROM public.rooms
  WHERE id = p_room_id AND is_closed = false;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('closed', false, 'was_owner', false);
  END IF;

  -- Auto-close only for non-personal rooms when the owner is the last to leave.
  IF v_owner_id = v_user_id AND NOT v_is_personal THEN
    SELECT count(*) INTO v_active_count
    FROM public.room_members
    WHERE room_id = p_room_id AND left_at IS NULL;

    IF v_active_count = 0 THEN
      UPDATE public.rooms
      SET
        is_closed     = true,
        closed_at     = now(),
        closed_by     = v_user_id,
        closed_reason = 'owner_left_empty'
      WHERE id = p_room_id;
      v_was_closed := true;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'closed',    v_was_closed,
    'was_owner', (v_owner_id = v_user_id)
  );
END;
$$;

-- =============================================================================
-- 6. Update close_empty_rooms — personal rooms are never auto-closed.
-- =============================================================================
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
    WHERE r.is_closed       = false
      AND r.is_personal_room = false   -- personal rooms are never auto-closed
      AND NOT EXISTS (
        SELECT 1 FROM public.room_members m
        WHERE m.room_id = r.id AND m.left_at IS NULL
      )
  )
  UPDATE public.rooms
  SET
    is_closed     = true,
    closed_at     = now(),
    closed_reason = 'auto-closed: no active members'
  WHERE id IN (SELECT id FROM empty_rooms);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
