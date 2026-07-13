-- ============================================================
-- Room reads — per-user per-room last-read tracking
-- ============================================================
-- Enables the unread badge on the Rooms nav tab.
-- When a user enters a room the app calls mark_room_read() to
-- clear that room from their unread set.
-- The client subscribes to Realtime INSERT events on
-- room_messages to detect new activity, and to this table to
-- know when a room has been cleared on another device.
-- ============================================================

-- ── 1. Table ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.room_reads (
  user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  room_id      uuid        NOT NULL REFERENCES public.rooms(id)  ON DELETE CASCADE,
  last_read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, room_id)
);

-- ── 2. RLS ───────────────────────────────────────────────────────────────────

ALTER TABLE public.room_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "room_reads_own" ON public.room_reads;
CREATE POLICY "room_reads_own"
  ON public.room_reads
  FOR ALL
  TO authenticated
  USING  (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── 3. Realtime (cross-device badge sync) ────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'room_reads'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.room_reads;
  END IF;
END;
$$;

-- ── 4. mark_room_read RPC ────────────────────────────────────────────────────
-- Upserts last_read_at = now() for the calling user + given room.
-- Called by the client when the user opens a room.

CREATE OR REPLACE FUNCTION public.mark_room_read(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  INSERT INTO public.room_reads (user_id, room_id, last_read_at)
  VALUES (auth.uid(), p_room_id, now())
  ON CONFLICT (user_id, room_id)
  DO UPDATE SET last_read_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.mark_room_read(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_room_read(uuid) TO authenticated;
