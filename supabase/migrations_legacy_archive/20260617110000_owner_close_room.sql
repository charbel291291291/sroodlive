-- RPC: owner_close_room
-- Allows the room owner to force-close the room for all participants.
-- Unlike leave_room_and_maybe_close, this always closes the room regardless
-- of whether other members are still present.
CREATE OR REPLACE FUNCTION public.owner_close_room(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Only the owner can force-close
  IF NOT EXISTS (
    SELECT 1 FROM public.rooms
    WHERE id = p_room_id AND owner_id = v_user_id AND is_closed = false
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Mark all active members as left
  UPDATE public.room_members
  SET
    left_at      = now(),
    last_seen_at = now(),
    is_muted     = true
  WHERE room_id = p_room_id AND left_at IS NULL;

  -- Close the room
  UPDATE public.rooms
  SET
    is_closed     = true,
    closed_at     = now(),
    closed_by     = v_user_id,
    closed_reason = 'owner_closed'
  WHERE id = p_room_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.owner_close_room(uuid) TO authenticated;
