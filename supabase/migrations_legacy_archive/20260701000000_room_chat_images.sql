-- =============================================================================
-- Room chat image messages
-- Adds image_url / image_path columns to room_messages, creates the
-- room_chat_images storage bucket, restricts direct inserts of image-type
-- messages to the SECURITY DEFINER RPC, and enforces VIP7+ on the backend.
-- =============================================================================

-- ── 1. Extend room_messages ───────────────────────────────────────────────────

ALTER TABLE public.room_messages
  ADD COLUMN IF NOT EXISTS image_url  text,
  ADD COLUMN IF NOT EXISTS image_path text;

-- ── 2. Tighten the direct-insert policy so clients cannot bypass the RPC ─────
--   Text / system messages continue to work via the existing direct insert.
--   Image messages must go through send_room_image_message() (SECURITY DEFINER).

DROP POLICY IF EXISTS "room_messages_insert_own" ON public.room_messages;
CREATE POLICY "room_messages_insert_own"
  ON public.room_messages FOR INSERT
  WITH CHECK (
    auth.uid() = sender_id
    AND message_type IN ('text', 'system')
  );

-- ── 3. Storage bucket ─────────────────────────────────────────────────────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'room_chat_images',
  'room_chat_images',
  true,              -- public read so Image.network() works without signed URLs
  5242880,           -- 5 MB hard cap enforced by storage layer
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/jpg']
)
ON CONFLICT (id) DO NOTHING;

-- ── 4. Storage policies ───────────────────────────────────────────────────────

-- Only VIP 7+ may upload; path must start with their own user-id folder
-- so users cannot overwrite each other's files.
DROP POLICY IF EXISTS "room_chat_images_upload_vip7" ON storage.objects;
CREATE POLICY "room_chat_images_upload_vip7"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'room_chat_images'
    AND (SELECT vip_level FROM public.profiles WHERE id = auth.uid()) >= 7
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Authenticated users can delete their own files (for future cleanup)
DROP POLICY IF EXISTS "room_chat_images_delete_own" ON storage.objects;
CREATE POLICY "room_chat_images_delete_own"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'room_chat_images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── 5. RPC: send_room_image_message ──────────────────────────────────────────
--
-- SECURITY DEFINER → bypasses RLS so it can insert message_type = 'image'.
-- Validates VIP level from the server-side profiles row — never trusts the
-- client's claimed VIP level.

CREATE OR REPLACE FUNCTION public.send_room_image_message(
  p_room_id     uuid,
  p_image_url   text,
  p_image_path  text,
  p_sender_role text DEFAULT 'listener'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller    uuid := auth.uid();
  v_vip_level int;
  v_msg_id    uuid;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  -- Validate VIP level from the canonical server-side source.
  SELECT vip_level INTO v_vip_level
  FROM public.profiles
  WHERE id = v_caller;

  IF COALESCE(v_vip_level, 0) < 7 THEN
    RAISE EXCEPTION 'vip7_required: image sending requires VIP 7 or higher';
  END IF;

  IF p_image_url IS NULL OR trim(p_image_url) = '' THEN
    RAISE EXCEPTION 'image_url_required';
  END IF;

  -- Verify the room exists (also catches deleted rooms gracefully).
  IF NOT EXISTS (SELECT 1 FROM public.rooms WHERE id = p_room_id) THEN
    RAISE EXCEPTION 'room_not_found';
  END IF;

  INSERT INTO public.room_messages
    (room_id, sender_id, message, message_type, image_url, image_path, metadata)
  VALUES
    (p_room_id, v_caller, '', 'image', p_image_url, p_image_path,
     jsonb_build_object('role', p_sender_role))
  RETURNING id INTO v_msg_id;

  RETURN v_msg_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_room_image_message(uuid, text, text, text)
  TO authenticated;

-- =============================================================================
-- End of room_chat_images.sql
-- =============================================================================
