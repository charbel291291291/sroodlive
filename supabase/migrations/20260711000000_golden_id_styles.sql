-- =============================================================================
-- Golden ID Styles & Frames — Phase V2
--
-- Adds visual styling metadata to the Golden ID system:
--   golden_id_style  — colour theme  (gold | diamond | royal | neon | fire | purple)
--   golden_id_frame  — frame variant (classic | crown | wings | glow | shield | luxury)
--
-- New RPC: set_custom_golden_id(p_user_id, p_public_user_id, p_enabled,
--           p_duration_days, p_style, p_frame)  → jsonb
--   Replaces the older set_golden_id for admin use.  The old RPC is kept.
--
-- Updated RPC: admin_find_user_for_grants — now returns is_golden_id,
--   golden_id_expires_at, golden_id_style, golden_id_frame.
--
-- Auth guard: public._vip_caller_is_admin()
-- Idempotent: ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE FUNCTION.
-- =============================================================================

-- ── 1. Schema ─────────────────────────────────────────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS golden_id_style text NOT NULL DEFAULT 'gold',
  ADD COLUMN IF NOT EXISTS golden_id_frame  text NOT NULL DEFAULT 'classic';

-- ── 2. Validation sets (constant expressions — avoids duplication) ────────────

-- Allowed styles  : gold | diamond | royal | neon | fire | purple
-- Allowed frames  : classic | crown | wings | glow | shield | luxury

-- ── 3. RPC: set_custom_golden_id ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_custom_golden_id(
  p_user_id        uuid,
  p_public_user_id text,
  p_enabled        boolean  DEFAULT true,
  p_duration_days  integer  DEFAULT NULL,
  p_style          text     DEFAULT 'gold',
  p_frame          text     DEFAULT 'classic'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_public_user_id text;
  v_style          text;
  v_frame          text;
  v_expires_at     timestamptz;
  v_result         jsonb;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
  IF NOT public._vip_caller_is_admin() THEN
    RAISE EXCEPTION 'permission_denied: admin role required';
  END IF;

  -- ── Normalise ─────────────────────────────────────────────────────────────
  v_public_user_id := trim(coalesce(p_public_user_id, ''));
  v_style          := trim(lower(coalesce(p_style, 'gold')));
  v_frame          := trim(lower(coalesce(p_frame, 'classic')));

  -- ── Disable path ─────────────────────────────────────────────────────────
  IF NOT coalesce(p_enabled, true) THEN
    UPDATE public.profiles
    SET
      is_golden_id          = false,
      golden_id_expires_at  = NULL,
      golden_id_style       = 'gold',
      golden_id_frame       = 'classic',
      updated_at            = now()
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
      'user_id',              p_user_id,
      'public_user_id',       (SELECT public_user_id FROM public.profiles WHERE id = p_user_id),
      'is_golden_id',         false,
      'golden_id_expires_at', NULL,
      'golden_id_style',      'gold',
      'golden_id_frame',      'classic'
    );
  END IF;

  -- ── Enable path — validate ────────────────────────────────────────────────

  -- ID format
  IF v_public_user_id !~ '^[A-Za-z0-9_-]{2,20}$' THEN
    RAISE EXCEPTION 'invalid_golden_id: must be 2–20 alphanumeric/dash/underscore characters';
  END IF;

  -- Uniqueness (exclude target user)
  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE public_user_id = v_public_user_id
      AND id <> p_user_id
  ) THEN
    RAISE EXCEPTION 'golden_id_taken';
  END IF;

  -- Style
  IF v_style NOT IN ('gold', 'diamond', 'royal', 'neon', 'fire', 'purple') THEN
    RAISE EXCEPTION 'invalid_golden_id_style: allowed values are gold, diamond, royal, neon, fire, purple';
  END IF;

  -- Frame
  IF v_frame NOT IN ('classic', 'crown', 'wings', 'glow', 'shield', 'luxury') THEN
    RAISE EXCEPTION 'invalid_golden_id_frame: allowed values are classic, crown, wings, glow, shield, luxury';
  END IF;

  -- Expiry
  v_expires_at := CASE
    WHEN p_duration_days IS NULL OR p_duration_days <= 0 THEN NULL
    ELSE now() + (p_duration_days || ' days')::interval
  END;

  -- ── Update ────────────────────────────────────────────────────────────────
  UPDATE public.profiles
  SET
    public_user_id       = v_public_user_id,
    is_golden_id         = true,
    golden_id_expires_at = v_expires_at,
    golden_id_style      = v_style,
    golden_id_frame      = v_frame,
    updated_at           = now()
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_not_found';
  END IF;

  -- ── Return ────────────────────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'user_id',              p_user_id,
    'public_user_id',       v_public_user_id,
    'is_golden_id',         true,
    'golden_id_expires_at', v_expires_at,
    'golden_id_style',      v_style,
    'golden_id_frame',      v_frame
  );
END;
$$;

GRANT  EXECUTE ON FUNCTION public.set_custom_golden_id(uuid, text, boolean, integer, text, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.set_custom_golden_id(uuid, text, boolean, integer, text, text) FROM anon;

-- ── 4. Updated: admin_find_user_for_grants ───────────────────────────────────
-- Returns the same columns as before plus golden ID metadata.

CREATE OR REPLACE FUNCTION public.admin_find_user_for_grants(
  p_query  text,
  p_limit  integer DEFAULT 10
)
RETURNS TABLE (
  user_id              uuid,
  username             text,
  display_name         text,
  golden_id            text,
  avatar_url           text,
  vip_level            integer,
  vip_until            timestamptz,
  is_golden_id         boolean,
  golden_id_expires_at timestamptz,
  golden_id_style      text,
  golden_id_frame      text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_query   text    := trim(coalesce(p_query, ''));
  v_limit   int     := greatest(1, least(coalesce(p_limit, 10), 50));
  v_is_uuid boolean;
BEGIN
  IF NOT public.has_admin_access() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF v_query = '' THEN
    RETURN;
  END IF;

  v_is_uuid := v_query ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.display_name,
    p.public_user_id,
    p.avatar_url,
    COALESCE(p.vip_level, 0),
    p.vip_expires_at,
    COALESCE(p.is_golden_id, false),
    p.golden_id_expires_at,
    COALESCE(p.golden_id_style, 'gold'),
    COALESCE(p.golden_id_frame, 'classic')
  FROM public.profiles p
  WHERE
    CASE
      WHEN v_is_uuid THEN
        p.id = v_query::uuid
      WHEN p.public_user_id = v_query THEN
        true
      ELSE
        p.public_user_id ilike '%' || v_query || '%'
        OR p.username     ilike '%' || v_query || '%'
        OR p.display_name ilike '%' || v_query || '%'
        OR p.id::text     ilike '%' || v_query || '%'
    END
  ORDER BY
    (p.public_user_id = v_query) DESC,
    (v_is_uuid AND p.id = v_query::uuid) DESC,
    p.created_at DESC
  LIMIT v_limit;
END;
$$;

GRANT  EXECUTE ON FUNCTION public.admin_find_user_for_grants(text, integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_find_user_for_grants(text, integer) FROM anon;

-- =============================================================================
-- End.
-- =============================================================================
