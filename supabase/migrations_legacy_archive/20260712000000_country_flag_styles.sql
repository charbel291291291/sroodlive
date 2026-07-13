-- =============================================================================
-- Country Flag Styles & Frames
--
-- Adds premium visual styling for country flags (does NOT change the country
-- itself — the flag emoji is always the real one for the stored country).
--
-- New columns on public.profiles:
--   country_code           text nullable         — ISO 3166-1 alpha-2 (e.g. "AO")
--   country_flag_style     text NOT NULL default 'normal'
--   country_flag_frame     text NOT NULL default 'classic'
--   country_flag_expires_at timestamptz nullable
--
-- New RPC: set_user_country_flag_style(...)  → jsonb
-- Updated: admin_find_user_for_grants — adds country, country_code, flag style cols.
--
-- Auth guard: public._vip_caller_is_admin()
-- Idempotent: ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE FUNCTION.
-- =============================================================================

-- ── 1. Schema ─────────────────────────────────────────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS country_code             text,
  ADD COLUMN IF NOT EXISTS country_flag_style       text NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS country_flag_frame       text NOT NULL DEFAULT 'classic',
  ADD COLUMN IF NOT EXISTS country_flag_expires_at  timestamptz;

-- ── 2. RPC: set_user_country_flag_style ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_user_country_flag_style(
  p_user_id      uuid,
  p_country_code text     DEFAULT NULL,
  p_country_name text     DEFAULT NULL,
  p_style        text     DEFAULT 'normal',
  p_frame        text     DEFAULT 'classic',
  p_duration_days integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_style    text := trim(lower(coalesce(p_style, 'normal')));
  v_frame    text := trim(lower(coalesce(p_frame, 'classic')));
  v_code     text;
  v_name     text;
  v_expires  timestamptz;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
  IF NOT public._vip_caller_is_admin() THEN
    RAISE EXCEPTION 'permission_denied: admin role required';
  END IF;

  -- ── Validate style ────────────────────────────────────────────────────────
  IF v_style NOT IN ('normal', 'gold', 'diamond', 'royal', 'neon', 'fire', 'purple') THEN
    RAISE EXCEPTION 'invalid_country_flag_style: allowed values are normal, gold, diamond, royal, neon, fire, purple';
  END IF;

  -- ── Validate frame ────────────────────────────────────────────────────────
  IF v_frame NOT IN ('classic', 'crown', 'glow', 'shield', 'luxury') THEN
    RAISE EXCEPTION 'invalid_country_flag_frame: allowed values are classic, crown, glow, shield, luxury';
  END IF;

  -- ── country_code: trim + uppercase + format check ─────────────────────────
  IF p_country_code IS NOT NULL AND trim(p_country_code) <> '' THEN
    v_code := upper(trim(p_country_code));
    IF v_code !~ '^[A-Z]{2}$' THEN
      RAISE EXCEPTION 'invalid_country_code: must be two uppercase letters like LB, AO, AE';
    END IF;
  END IF;

  -- ── country name: only overwrite if explicitly provided ───────────────────
  IF p_country_name IS NOT NULL AND trim(p_country_name) <> '' THEN
    v_name := trim(p_country_name);
  END IF;

  -- ── Expiry ────────────────────────────────────────────────────────────────
  v_expires := CASE
    WHEN p_duration_days IS NULL OR p_duration_days <= 0 THEN NULL
    ELSE now() + (p_duration_days || ' days')::interval
  END;

  -- ── Update ────────────────────────────────────────────────────────────────
  UPDATE public.profiles
  SET
    country_code            = COALESCE(v_code,  country_code),
    country                 = COALESCE(v_name,  country),
    country_flag_style      = v_style,
    country_flag_frame      = v_frame,
    country_flag_expires_at = v_expires,
    updated_at              = now()
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_not_found';
  END IF;

  -- ── Return ────────────────────────────────────────────────────────────────
  RETURN (
    SELECT jsonb_build_object(
      'user_id',                p_user_id,
      'country',                p.country,
      'country_code',           p.country_code,
      'country_flag_style',     p.country_flag_style,
      'country_flag_frame',     p.country_flag_frame,
      'country_flag_expires_at', p.country_flag_expires_at
    )
    FROM public.profiles p
    WHERE p.id = p_user_id
  );
END;
$$;

GRANT  EXECUTE ON FUNCTION public.set_user_country_flag_style(uuid, text, text, text, text, integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.set_user_country_flag_style(uuid, text, text, text, text, integer) FROM anon;

-- ── 3. Updated: admin_find_user_for_grants ───────────────────────────────────
-- Adds country, country_code, and flag style columns to the result.

DROP FUNCTION IF EXISTS public.admin_find_user_for_grants(text, integer);

CREATE OR REPLACE FUNCTION public.admin_find_user_for_grants(
  p_query  text,
  p_limit  integer DEFAULT 10
)
RETURNS TABLE (
  user_id               uuid,
  username              text,
  display_name          text,
  golden_id             text,
  avatar_url            text,
  vip_level             integer,
  vip_until             timestamptz,
  is_golden_id          boolean,
  golden_id_expires_at  timestamptz,
  golden_id_style       text,
  golden_id_frame       text,
  country               text,
  country_code          text,
  country_flag_style    text,
  country_flag_frame    text,
  country_flag_expires_at timestamptz
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
    COALESCE(p.golden_id_frame, 'classic'),
    p.country,
    p.country_code,
    COALESCE(p.country_flag_style, 'normal'),
    COALESCE(p.country_flag_frame, 'classic'),
    p.country_flag_expires_at
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

