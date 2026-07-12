-- =============================================================================
-- Phase 1 moderation: message removal + moderation_keywords table
-- =============================================================================

-- ── 1. Add removal columns to room_messages ───────────────────────────────────

ALTER TABLE public.room_messages
  ADD COLUMN IF NOT EXISTS is_removed   BOOLEAN       NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS removed_by   UUID          REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS removed_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS remove_reason TEXT;

-- Index for fast is_removed queries (fetching only active messages)
CREATE INDEX IF NOT EXISTS idx_room_messages_not_removed
  ON public.room_messages (room_id, created_at DESC)
  WHERE is_removed = false;

-- ── 2. RPC: remove_room_message ───────────────────────────────────────────────
-- Callable by: admin (has_admin_access), room owner, or room moderator.
-- Sets is_removed=true + records who removed it and why.
-- SECURITY DEFINER so the write bypasses RLS.

CREATE OR REPLACE FUNCTION public.remove_room_message(
  p_message_id UUID,
  p_reason     TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id  UUID := auth.uid();
  v_room_id    UUID;
  v_is_owner   BOOLEAN := false;
  v_is_mod     BOOLEAN := false;
  v_is_admin   BOOLEAN := false;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Look up the message to get its room_id
  SELECT room_id INTO v_room_id
  FROM public.room_messages
  WHERE id = p_message_id;

  IF v_room_id IS NULL THEN
    RAISE EXCEPTION 'message_not_found';
  END IF;

  -- Admin check
  SELECT public.has_admin_access() INTO v_is_admin;

  IF NOT v_is_admin THEN
    -- Room owner check
    SELECT EXISTS (
      SELECT 1 FROM public.rooms
      WHERE id = v_room_id AND owner_id = v_caller_id
    ) INTO v_is_owner;

    IF NOT v_is_owner THEN
      -- Room moderator check
      SELECT EXISTS (
        SELECT 1 FROM public.room_moderators
        WHERE room_id = v_room_id AND user_id = v_caller_id
      ) INTO v_is_mod;
    END IF;
  END IF;

  IF NOT (v_is_admin OR v_is_owner OR v_is_mod) THEN
    RAISE EXCEPTION 'insufficient_permissions';
  END IF;

  -- Mark as removed
  UPDATE public.room_messages
  SET is_removed    = true,
      removed_by    = v_caller_id,
      removed_at    = now(),
      remove_reason = p_reason
  WHERE id = p_message_id
    AND is_removed = false;  -- idempotent

  -- Log moderation event
  PERFORM public.log_moderation_event(
    p_room_id        := v_room_id,
    p_source         := 'admin',
    p_violation_type := 'message_removed',
    p_severity       := 2,
    p_original_text  := p_reason,
    p_normalized_text:= NULL,
    p_matched_rule   := NULL,
    p_action_taken   := 'message_removed'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_room_message(UUID, TEXT) TO authenticated;

-- ── 3. moderation_keywords table ─────────────────────────────────────────────
-- Admin-managed banned words/phrases. Phase 2 will load these into the app
-- instead of relying on hardcoded Flutter rules.

CREATE TABLE IF NOT EXISTS public.moderation_keywords (
  id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  pattern        TEXT          NOT NULL,
  language       TEXT          NOT NULL DEFAULT 'any'
                               CHECK (language IN ('ar', 'en', 'fr', 'any')),
  severity       INT           NOT NULL DEFAULT 2
                               CHECK (severity BETWEEN 1 AND 4),
  violation_type TEXT          NOT NULL DEFAULT 'insult'
                               CHECK (violation_type IN (
                                 'insult', 'hate_speech', 'sexual_content',
                                 'threat', 'spam', 'scam_fraud', 'illegal_content'
                               )),
  action         TEXT          NOT NULL DEFAULT 'block_message'
                               CHECK (action IN (
                                 'block_message', 'warn', 'mute',
                                 'temp_ban', 'report_to_admin'
                               )),
  is_enabled     BOOLEAN       NOT NULL DEFAULT true,
  created_by     UUID          REFERENCES auth.users(id),
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

ALTER TABLE public.moderation_keywords ENABLE ROW LEVEL SECURITY;

-- Only admins can read/write keywords
CREATE POLICY "keywords_admin_all"
  ON public.moderation_keywords
  FOR ALL
  USING (public.has_admin_access());

-- ── 4. Seed: migrate existing hardcoded Flutter rules into DB ────────────────
-- This seeds the same rules as in moderation_service.dart so they are
-- visible/editable in the admin panel. Flutter still uses client-side rules
-- until Phase 2 switches to DB-loaded rules.

INSERT INTO public.moderation_keywords (pattern, language, severity, violation_type, action) VALUES
  ('كلب',          'ar', 2, 'insult',         'block_message'),
  ('حمار',         'ar', 2, 'insult',         'block_message'),
  ('غبي',          'ar', 1, 'insult',         'warn'),
  ('احمق',         'ar', 1, 'insult',         'warn'),
  ('تف',           'ar', 1, 'insult',         'warn'),
  ('يلعن',         'ar', 2, 'insult',         'block_message'),
  ('ابن الحرام',   'ar', 3, 'insult',         'block_message'),
  ('ابن الكلب',    'ar', 3, 'insult',         'block_message'),
  ('شرموطه',       'ar', 3, 'hate_speech',    'block_message'),
  ('شرموطة',       'ar', 3, 'hate_speech',    'block_message'),
  ('عاهره',        'ar', 3, 'hate_speech',    'block_message'),
  ('عاهرة',        'ar', 3, 'hate_speech',    'block_message'),
  ('قحبه',         'ar', 3, 'hate_speech',    'block_message'),
  ('قحبة',         'ar', 3, 'hate_speech',    'block_message'),
  ('زبالة',        'ar', 2, 'insult',         'block_message'),
  ('منافق',        'ar', 1, 'insult',         'warn'),
  ('خنزير',        'ar', 2, 'insult',         'block_message'),
  ('روح تنيك',     'ar', 4, 'sexual_content', 'block_message'),
  ('كس امك',       'ar', 4, 'hate_speech',    'block_message'),
  ('كس اختك',      'ar', 4, 'hate_speech',    'block_message'),
  ('نيك',          'ar', 3, 'sexual_content', 'block_message'),
  ('اللعن ابوك',   'ar', 3, 'insult',         'block_message'),
  ('اقتلك',        'ar', 4, 'threat',         'report_to_admin'),
  ('هقتلك',        'ar', 4, 'threat',         'report_to_admin'),
  ('سوي بيك',      'ar', 3, 'threat',         'block_message'),
  ('ايدي عليك',    'ar', 3, 'threat',         'block_message'),
  ('fuck',         'en', 2, 'insult',         'block_message'),
  ('fucking',      'en', 2, 'insult',         'block_message'),
  ('bitch',        'en', 2, 'insult',         'block_message'),
  ('asshole',      'en', 2, 'insult',         'block_message'),
  ('bastard',      'en', 2, 'insult',         'block_message'),
  ('idiot',        'en', 1, 'insult',         'warn'),
  ('stupid',       'en', 1, 'insult',         'warn'),
  ('moron',        'en', 1, 'insult',         'warn'),
  ('loser',        'en', 1, 'insult',         'warn'),
  ('trash',        'en', 1, 'insult',         'warn'),
  ('retard',       'en', 3, 'hate_speech',    'block_message'),
  ('nigger',       'en', 4, 'hate_speech',    'report_to_admin'),
  ('faggot',       'en', 3, 'hate_speech',    'block_message'),
  ('whore',        'en', 3, 'sexual_content', 'block_message'),
  ('slut',         'en', 3, 'sexual_content', 'block_message'),
  ('kill yourself','en', 4, 'threat',         'report_to_admin'),
  ('i will kill',  'en', 4, 'threat',         'report_to_admin'),
  ('ill kill you', 'en', 4, 'threat',         'report_to_admin'),
  ('send nudes',   'en', 3, 'sexual_content', 'block_message'),
  ('rape',         'en', 4, 'sexual_content', 'report_to_admin'),
  ('bomb',         'en', 3, 'illegal_content','block_message'),
  ('terrorist',    'en', 3, 'illegal_content','block_message'),
  ('scam',         'en', 2, 'scam_fraud',     'block_message'),
  ('give me money','en', 2, 'scam_fraud',     'block_message'),
  ('western union','en', 3, 'scam_fraud',     'block_message'),
  ('click this link','en',2,'scam_fraud',     'block_message'),
  ('putain',       'fr', 1, 'insult',         'warn'),
  ('merde',        'fr', 1, 'insult',         'warn'),
  ('connard',      'fr', 2, 'insult',         'block_message'),
  ('salope',       'fr', 3, 'hate_speech',    'block_message'),
  ('pute',         'fr', 3, 'hate_speech',    'block_message'),
  ('va te faire',  'fr', 2, 'insult',         'block_message'),
  ('je vais te tuer','fr',4,'threat',         'report_to_admin'),
  ('whatsapp',     'any',1, 'spam',           'warn'),
  ('telegram',     'any',1, 'spam',           'warn'),
  ('instagram',    'any',1, 'spam',           'warn')
ON CONFLICT DO NOTHING;
