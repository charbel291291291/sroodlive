-- Add PIN columns to rooms
ALTER TABLE public.rooms
  ADD COLUMN IF NOT EXISTS room_pin_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS room_pin_hash    text;

-- RPC: verify_room_pin
CREATE OR REPLACE FUNCTION public.verify_room_pin(p_room_id uuid, p_pin text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled boolean;
  v_hash    text;
BEGIN
  SELECT room_pin_enabled, room_pin_hash
  INTO   v_enabled, v_hash
  FROM   public.rooms
  WHERE  id = p_room_id;

  IF NOT FOUND OR NOT v_enabled OR v_hash IS NULL THEN
    RETURN true;
  END IF;

  RETURN v_hash = encode(sha256(convert_to(p_pin, 'UTF8')), 'hex');
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_room_pin(uuid, text) TO authenticated;

-- RPC: set_room_pin (owner only)
CREATE OR REPLACE FUNCTION public.set_room_pin(p_room_id uuid, p_pin text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.rooms WHERE id = p_room_id AND owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
  UPDATE public.rooms
  SET room_pin_enabled = (p_pin IS NOT NULL AND p_pin <> ''),
      room_pin_hash    = CASE
                           WHEN p_pin IS NOT NULL AND p_pin <> ''
                           THEN encode(sha256(convert_to(p_pin, 'UTF8')), 'hex')
                           ELSE NULL
                         END
  WHERE id = p_room_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_room_pin(uuid, text) TO authenticated;

-- RPC: owner_close_room_with_pin
CREATE OR REPLACE FUNCTION public.owner_close_room_with_pin(
  p_room_id uuid,
  p_pin     text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner   uuid;
  v_enabled boolean;
  v_hash    text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT owner_id, room_pin_enabled, room_pin_hash
  INTO   v_owner, v_enabled, v_hash
  FROM   public.rooms
  WHERE  id = p_room_id AND is_closed = false;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_owner <> auth.uid() THEN RAISE EXCEPTION 'not_authorized'; END IF;
  IF v_enabled AND v_hash IS NOT NULL THEN
    IF p_pin IS NULL OR
       encode(sha256(convert_to(p_pin, 'UTF8')), 'hex') <> v_hash
    THEN
      RAISE EXCEPTION 'wrong_pin';
    END IF;
  END IF;
  UPDATE public.room_members
  SET left_at = now(), last_seen_at = now(), is_muted = true
  WHERE room_id = p_room_id AND left_at IS NULL;
  UPDATE public.rooms
  SET is_closed = true, closed_at = now(), closed_by = auth.uid(),
      closed_reason = 'owner_closed'
  WHERE id = p_room_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.owner_close_room_with_pin(uuid, text) TO authenticated;
