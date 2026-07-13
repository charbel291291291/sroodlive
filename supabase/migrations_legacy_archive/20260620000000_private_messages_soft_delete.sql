-- Add soft-delete support to private_messages
ALTER TABLE public.private_messages
  ADD COLUMN IF NOT EXISTS deleted_at  timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by  uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- Policy: sender can soft-delete (update deleted_at / deleted_by) their own messages only.
-- Only allow setting deleted_by to their own uid.
DROP POLICY IF EXISTS "Sender can soft-delete own messages" ON public.private_messages;
CREATE POLICY "Sender can soft-delete own messages"
  ON public.private_messages
  FOR UPDATE
  USING  (sender_id = auth.uid())
  WITH CHECK (
    deleted_by = auth.uid()
    AND deleted_at IS NOT NULL
  );
