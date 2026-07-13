-- =============================================================================
-- Centralized VIP System
-- Creates vip_levels + user_vip_subscriptions tables alongside existing tables.
-- Existing data in profiles is preserved. All changes are idempotent.
-- =============================================================================

-- ── 1. vip_levels — canonical metadata table ────────────────────────────────

CREATE TABLE IF NOT EXISTS public.vip_levels (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  level            int         NOT NULL UNIQUE CHECK (level BETWEEN 1 AND 10),
  name             text        NOT NULL,
  price_coins      int         ,
  price_usd        numeric(10,2),
  duration_days    int         NOT NULL DEFAULT 30,
  badge_url        text        ,
  profile_frame_url text       ,
  mic_frame_url    text        ,
  entrance_effect_key text     ,
  chat_bubble_style text       ,
  room_privileges  jsonb       NOT NULL DEFAULT '{}',
  priority_rank    int         NOT NULL DEFAULT 0,
  is_active        boolean     NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS vip_levels_level_idx      ON public.vip_levels (level);
CREATE INDEX IF NOT EXISTS vip_levels_is_active_idx  ON public.vip_levels (is_active);

-- Seed canonical VIP levels (upsert so re-running is safe)
INSERT INTO public.vip_levels
  (level, name, price_coins, duration_days, entrance_effect_key, room_privileges, priority_rank, is_active)
VALUES
  (1, 'VIP 1', 500,   30, 'sparkle',   '{"kick_protection": false, "silent_entry": false}', 100, true),
  (2, 'VIP 2', 1000,  30, 'sparkle',   '{"kick_protection": false, "silent_entry": false}', 200, true),
  (3, 'VIP 3', 2000,  30, 'glow',      '{"kick_protection": true,  "silent_entry": false}', 300, true),
  (4, 'VIP 4', 4000,  30, 'premium',   '{"kick_protection": true,  "silent_entry": false, "kick_confirm": true}', 400, true),
  (5, 'VIP 5', 8000,  30, 'luxury',    '{"kick_protection": true,  "strong_kick": true,   "silent_entry": false}', 500, true),
  (6, 'VIP 6', 15000, 30, 'luxury',    '{"kick_protection": true,  "strong_kick": true,   "silent_entry": true}',  600, true),
  (7, 'VIP 7', 25000, 30, 'royal',     '{"kick_protection": true,  "strong_kick": true,   "silent_entry": true}',  700, true),
  (8, 'VIP 8', 40000, 30, 'royal',     '{"kick_protection": true,  "strong_kick": true,   "silent_entry": true,  "anti_kick": true}', 800, true),
  (9, 'VIP 9', 60000, 30, 'legendary', '{"kick_protection": true,  "strong_kick": true,   "silent_entry": true,  "anti_kick": true}', 900, true)
ON CONFLICT (level) DO UPDATE SET
  name                = EXCLUDED.name,
  price_coins         = EXCLUDED.price_coins,
  duration_days       = EXCLUDED.duration_days,
  entrance_effect_key = EXCLUDED.entrance_effect_key,
  room_privileges     = EXCLUDED.room_privileges,
  priority_rank       = EXCLUDED.priority_rank,
  updated_at          = now();

-- RLS
ALTER TABLE public.vip_levels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "VIP levels are public" ON public.vip_levels;
CREATE POLICY "VIP levels are public"
  ON public.vip_levels FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admins manage vip_levels" ON public.vip_levels;
CREATE POLICY "Admins manage vip_levels"
  ON public.vip_levels FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users ar
      WHERE ar.user_id = auth.uid()
        AND ar.role IN ('super_admin', 'content_admin')
        AND ar.is_active = true
    )
  );

-- ── 2. user_vip_subscriptions — history / audit trail ───────────────────────
-- Table already exists with columns: vip_plan_id, starts_at, ends_at, is_active.
-- Add missing columns needed by centralized system.

ALTER TABLE public.user_vip_subscriptions
  ADD COLUMN IF NOT EXISTS vip_level         int,
  ADD COLUMN IF NOT EXISTS started_at        timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at        timestamptz,
  ADD COLUMN IF NOT EXISTS payment_source    text,
  ADD COLUMN IF NOT EXISTS created_by_admin  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS auto_renew        boolean NOT NULL DEFAULT false;

-- Backfill vip_level from vip_plan_id join if vip_levels exists (no-op here, just safe)
-- starts_at / ends_at already exist as the canonical dates; alias via view if needed.

CREATE INDEX IF NOT EXISTS uvs_user_active_idx
  ON public.user_vip_subscriptions (user_id, is_active, ends_at DESC);
CREATE INDEX IF NOT EXISTS uvs_vip_level_idx
  ON public.user_vip_subscriptions (vip_level)
  WHERE vip_level IS NOT NULL;
CREATE INDEX IF NOT EXISTS uvs_expires_at_idx
  ON public.user_vip_subscriptions (ends_at)
  WHERE is_active = true;

ALTER TABLE public.user_vip_subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own subscriptions" ON public.user_vip_subscriptions;
CREATE POLICY "Users read own subscriptions"
  ON public.user_vip_subscriptions FOR SELECT
  USING (user_id = auth.uid());
DROP POLICY IF EXISTS "Admins manage subscriptions" ON public.user_vip_subscriptions;
CREATE POLICY "Admins manage subscriptions"
  ON public.user_vip_subscriptions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users ar
      WHERE ar.user_id = auth.uid()
        AND ar.role IN ('super_admin', 'support_admin')
        AND ar.is_active = true
    )
  );

-- ── 3. Helper: is_admin ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._vip_caller_is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users ar
    WHERE ar.user_id = auth.uid()
      AND ar.role IN ('super_admin', 'support_admin')
      AND ar.is_active = true
  );
$$;

-- ── 4. RPC: get_my_vip ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_my_vip()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_row   record;
  v_now   timestamptz := now();
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;

  SELECT
    p.id,
    p.vip_level,
    p.vip_started_at,
    p.vip_expires_at,
    p.vip_title,
    p.is_golden_id,
    p.golden_id_expires_at
  INTO v_row
  FROM public.profiles p
  WHERE p.id = v_uid;

  IF NOT FOUND THEN RETURN NULL; END IF;

  RETURN json_build_object(
    'user_id',              v_row.id,
    'vip_level',            COALESCE(v_row.vip_level, 0),
    'vip_started_at',       v_row.vip_started_at,
    'vip_expires_at',       v_row.vip_expires_at,
    'vip_title',            v_row.vip_title,
    'is_active',            (
      COALESCE(v_row.vip_level, 0) > 0
      AND (v_row.vip_expires_at IS NULL OR v_row.vip_expires_at > v_now)
    ),
    'is_golden_id',         COALESCE(v_row.is_golden_id, false),
    'golden_id_expires_at', v_row.golden_id_expires_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_vip() TO authenticated;

-- ── 5. RPC: get_user_vip ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_user_vip(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_row  record;
  v_now  timestamptz := now();
BEGIN
  SELECT
    p.id,
    p.vip_level,
    p.vip_started_at,
    p.vip_expires_at,
    p.vip_title,
    p.is_golden_id,
    p.golden_id_expires_at
  INTO v_row
  FROM public.profiles p
  WHERE p.id = p_user_id;

  IF NOT FOUND THEN RETURN NULL; END IF;

  RETURN json_build_object(
    'user_id',              v_row.id,
    'vip_level',            COALESCE(v_row.vip_level, 0),
    'vip_started_at',       v_row.vip_started_at,
    'vip_expires_at',       v_row.vip_expires_at,
    'vip_title',            v_row.vip_title,
    'is_active',            (
      COALESCE(v_row.vip_level, 0) > 0
      AND (v_row.vip_expires_at IS NULL OR v_row.vip_expires_at > v_now)
    ),
    'is_golden_id',         COALESCE(v_row.is_golden_id, false),
    'golden_id_expires_at', v_row.golden_id_expires_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_vip(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_vip(uuid) TO anon;

-- ── 6. RPC: get_users_with_vip ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_users_with_vip(p_user_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_now timestamptz := now();
  v_result jsonb;
BEGIN
  SELECT jsonb_object_agg(
    p.id::text,
    json_build_object(
      'user_id',              p.id,
      'vip_level',            COALESCE(p.vip_level, 0),
      'vip_started_at',       p.vip_started_at,
      'vip_expires_at',       p.vip_expires_at,
      'vip_title',            p.vip_title,
      'is_active',            (
        COALESCE(p.vip_level, 0) > 0
        AND (p.vip_expires_at IS NULL OR p.vip_expires_at > v_now)
      ),
      'is_golden_id',         COALESCE(p.is_golden_id, false),
      'golden_id_expires_at', p.golden_id_expires_at
    )
  )
  INTO v_result
  FROM public.profiles p
  WHERE p.id = ANY(p_user_ids);

  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_users_with_vip(uuid[]) TO authenticated;

-- ── 7. RPC: grant_vip ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.grant_vip(
  p_user_id      uuid,
  p_vip_level    int,
  p_duration_days int DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller      uuid := auth.uid();
  v_expires_at  timestamptz;
  v_now         timestamptz := now();
  v_sub_id      uuid;
BEGIN
  -- Admin check
  IF NOT public._vip_caller_is_admin() THEN
    RAISE EXCEPTION 'permission_denied: admin role required';
  END IF;

  IF p_vip_level < 0 OR p_vip_level > 10 THEN
    RAISE EXCEPTION 'invalid_vip_level: must be 0-10';
  END IF;

  -- Level 0 = revoke
  IF p_vip_level = 0 THEN
    -- Deactivate all current subscriptions
    UPDATE public.user_vip_subscriptions
    SET is_active = false
    WHERE user_id = p_user_id AND is_active = true;

    -- Clear profiles
    UPDATE public.profiles
    SET vip_level = 0, vip_expires_at = NULL, vip_started_at = NULL
    WHERE id = p_user_id;

    RETURN json_build_object('user_id', p_user_id, 'vip_level', 0, 'action', 'revoked');
  END IF;

  v_expires_at := v_now + (p_duration_days * interval '1 day');

  -- Deactivate old subscriptions
  UPDATE public.user_vip_subscriptions
  SET is_active = false
  WHERE user_id = p_user_id AND is_active = true;

  -- Insert new subscription
  INSERT INTO public.user_vip_subscriptions
    (user_id, vip_level, started_at, expires_at, is_active, payment_source, created_by_admin)
  VALUES
    (p_user_id, p_vip_level, v_now, v_expires_at, true, 'admin_grant', v_caller)
  RETURNING id INTO v_sub_id;

  -- Sync to profiles (source of truth for fast reads)
  UPDATE public.profiles
  SET
    vip_level       = p_vip_level,
    vip_started_at  = v_now,
    vip_expires_at  = v_expires_at
  WHERE id = p_user_id;

  RETURN json_build_object(
    'user_id',       p_user_id,
    'vip_level',     p_vip_level,
    'expires_at',    v_expires_at,
    'subscription_id', v_sub_id,
    'action',        'granted'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.grant_vip(uuid, int, int) TO authenticated;

-- ── 8. RPC: expire_old_vips ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.expire_old_vips()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int;
BEGIN
  -- Mark subscriptions inactive
  UPDATE public.user_vip_subscriptions
  SET is_active = false
  WHERE is_active = true AND expires_at < now();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- Sync profiles: clear VIP for users whose subscription expired
  UPDATE public.profiles p
  SET vip_level = 0, vip_expires_at = NULL, vip_started_at = NULL
  WHERE p.vip_level > 0
    AND p.vip_expires_at IS NOT NULL
    AND p.vip_expires_at < now()
    AND NOT EXISTS (
      SELECT 1 FROM public.user_vip_subscriptions s
      WHERE s.user_id = p.id AND s.is_active = true
    );

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.expire_old_vips() TO authenticated;

-- ── 9. auto-updated_at trigger for vip_levels ───────────────────────────────

CREATE OR REPLACE FUNCTION public._vip_levels_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS trg_vip_levels_updated_at ON public.vip_levels;
CREATE TRIGGER trg_vip_levels_updated_at
  BEFORE UPDATE ON public.vip_levels
  FOR EACH ROW EXECUTE FUNCTION public._vip_levels_updated_at();
