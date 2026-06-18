-- Fix send_room_image_message RPC
--
-- Root cause: the 20260713 version tried to INSERT into sender_name,
-- sender_avatar_url, sender_vip_level, sender_role — columns that do not
-- exist in room_messages.  The table only has:
--   id, room_id, sender_id, message, message_type, metadata, created_at,
--   image_url, image_path
-- Sender display data is always resolved via a profiles JOIN in Flutter.
-- sender_role goes into metadata just like text messages.

DROP FUNCTION IF EXISTS public.send_room_image_message(uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.send_room_image_message(
  p_room_id     uuid,
  p_image_url   text,
  p_image_path  text,
  p_sender_role text DEFAULT 'listener'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    uuid := auth.uid();
  v_message_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT public.can_user_send_chat_image(v_user_id) THEN
    RAISE EXCEPTION 'image_messages_unlock_at_vip_7';
  END IF;

  IF p_room_id IS NULL THEN
    RAISE EXCEPTION 'missing_room_id';
  END IF;

  IF coalesce(trim(p_image_url), '') = '' THEN
    RAISE EXCEPTION 'missing_image_url';
  END IF;

  -- path owner check: first segment must be the caller's user_id
  IF split_part(coalesce(p_image_path, ''), '/', 1) <> v_user_id::text THEN
    RAISE EXCEPTION 'invalid_image_path_owner';
  END IF;

  -- room existence guard
  IF NOT EXISTS (SELECT 1 FROM public.rooms WHERE id = p_room_id) THEN
    RAISE EXCEPTION 'room_not_found';
  END IF;

  INSERT INTO public.room_messages
    (room_id, sender_id, message, message_type, image_url, image_path, metadata)
  VALUES
    (p_room_id, v_user_id, '', 'image', p_image_url, p_image_path,
     jsonb_build_object('role', coalesce(nullif(p_sender_role, ''), 'listener')))
  RETURNING id INTO v_message_id;

  RETURN jsonb_build_object(
    'id',         v_message_id,
    'room_id',    p_room_id,
    'image_url',  p_image_url,
    'image_path', p_image_path
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_room_image_message(uuid, text, text, text)
  TO authenticated;

-- Also ensure the insert RLS allows the SECURITY DEFINER path for image type.
-- (The direct-client insert policy already limits to 'text'/'system'; SECURITY
--  DEFINER bypasses RLS so no change needed there, but re-state the read policy
--  to be safe.)
DROP POLICY IF EXISTS "room_messages_read" ON public.room_messages;
CREATE POLICY "room_messages_read"
  ON public.room_messages FOR SELECT
  USING (auth.uid() IS NOT NULL);
