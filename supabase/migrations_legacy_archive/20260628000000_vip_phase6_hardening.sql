-- =============================================================================
-- VIP Phase 6: Backend hardening and system closure
--
-- Changes:
--   1. Remove direct UPDATE path on user_vip_settings (use set_my_vip_setting)
--   2. Sync vip_levels.room_privileges with Flutter VipPrivilegeKey enum
--   3. Tighten vip_levels.level constraint from 1–10 to 1–9
--   4. Update grant_vip to reject level > 9
--   5. Document expiry automation options (pg_cron not enabled)
--
-- All changes are safe and additive. No tables dropped, no data deleted.
-- VIP 10 is permanently excluded. VIP system is closed after this migration.
-- =============================================================================

-- ── 1. Lock down user_vip_settings: remove direct UPDATE path ────────────────
--
-- set_my_vip_setting (SECURITY DEFINER RPC, Phase 4) is the enforced write path.
-- It validates VIP level before writing.  The direct authenticated UPDATE
-- policy allowed clients to bypass those checks via a table UPDATE call.
--
-- The SECURITY DEFINER RPC runs as the function owner (not as 'authenticated'),
-- so revoking UPDATE from the authenticated role does not break the RPC.
-- SELECT remains so clients can read their own settings.
-- INSERT remains because the RPC upserts via ON CONFLICT DO NOTHING followed
-- by a separate EXECUTE format() UPDATE — the INSERT path still needs INSERT.

DROP POLICY IF EXISTS "user_vip_settings_update_own" ON public.user_vip_settings;
REVOKE UPDATE ON public.user_vip_settings FROM authenticated;

-- ── 2. Sync vip_levels.room_privileges ───────────────────────────────────────
--
-- JSONB keys match Flutter VipPrivilegeKey enum identifiers exactly.
-- Prices, durations, and all other columns are preserved unchanged.
-- Each level's object contains only the privileges that are ACTIVE at that level.
-- The Flutter app uses this JSONB for informational display only; business logic
-- lives in VipPrivileges.dart.

UPDATE public.vip_levels SET
  room_privileges = '{
    "profileGlow": true,
    "vipBadge": true,
    "vipFrame": true,
    "micWave": true,
    "entranceEffect": true
  }',
  updated_at = now()
WHERE level = 1;

UPDATE public.vip_levels SET
  room_privileges = '{
    "profileGlow": true,
    "vipBadge": true,
    "vipFrame": true,
    "micWave": true,
    "entranceEffect": true
  }',
  updated_at = now()
WHERE level = 2;

UPDATE public.vip_levels SET
  room_privileges = '{
    "profileGlow": true,
    "vipBadge": true,
    "vipFrame": true,
    "micWave": true,
    "entranceEffect": true,
    "kickProtection": true
  }',
  updated_at = now()
WHERE level = 3;

UPDATE public.vip_levels SET
  room_privileges = '{
    "profileGlow": true,
    "vipBadge": true,
    "vipFrame": true,
    "micWave": true,
    "entranceEffect": true,
    "kickProtection": true,
    "kickConfirmation": true
  }',
  updated_at = now()
WHERE level = 4;

UPDATE public.vip_levels SET
  room_privileges = '{
    "profileGlow": true,
    "vipBadge": true,
    "vipFrame": true,
    "micWave": true,
    "entranceEffect": true,
    "kickProtection": true,
    "kickConfirmation": true,
    "strongAntiKick": true,
    "notBeingFollowed": true
  }',
  updated_at = now()
WHERE level = 5;

UPDATE public.vip_levels SET
  room_privileges = '{
    "profileGlow": true,
    "vipBadge": true,
    "vipFrame": true,
    "micWave": true,
    "entranceEffect": true,
    "silentEntry": true,
    "kickProtection": true,
    "kickConfirmation": true,
    "strongAntiKick": true,
    "notBeingFollowed": true,
    "antiEnteringRoom": true,
    "privateBrowsing": true
  }',
  updated_at = now()
WHERE level = 6;

UPDATE public.vip_levels SET
  room_privileges = '{
    "profileGlow": true,
    "vipBadge": true,
    "vipFrame": true,
    "micWave": true,
    "entranceEffect": true,
    "silentEntry": true,
    "kickProtection": true,
    "kickConfirmation": true,
    "strongAntiKick": true,
    "notBeingFollowed": true,
    "antiEnteringRoom": true,
    "privateBrowsing": true,
    "doNotDisturb": true
  }',
  updated_at = now()
WHERE level = 7;

UPDATE public.vip_levels SET
  room_privileges = '{
    "profileGlow": true,
    "vipBadge": true,
    "vipFrame": true,
    "micWave": true,
    "entranceEffect": true,
    "silentEntry": true,
    "kickProtection": true,
    "kickConfirmation": true,
    "strongAntiKick": true,
    "notBeingFollowed": true,
    "antiEnteringRoom": true,
    "privateBrowsing": true,
    "doNotDisturb": true,
    "antiKick": true,
    "invisibility": true
  }',
  updated_at = now()
WHERE level = 8;

UPDATE public.vip_levels SET
  room_privileges = '{
    "profileGlow": true,
    "vipBadge": true,
    "vipFrame": true,
    "micWave": true,
    "entranceEffect": true,
    "silentEntry": true,
    "kickProtection": true,
    "kickConfirmation": true,
    "strongAntiKick": true,
    "notBeingFollowed": true,
    "antiEnteringRoom": true,
    "privateBrowsing": true,
    "doNotDisturb": true,
    "antiKick": true,
    "invisibility": true
  }',
  updated_at = now()
WHERE level = 9;

-- ── 3. Tighten vip_levels.level constraint from 1–10 to 1–9 ─────────────────
--
-- standardize_vip_1_to_9 (20260615120000) tightened profiles, vip_packages,
-- vip_plans, entrance_banners, avatar_frames, badges — but NOT vip_levels.
-- Any rows with level = 10 were already deleted by the standardize migration;
-- this constraint update is safe.

ALTER TABLE public.vip_levels
  DROP CONSTRAINT IF EXISTS vip_levels_level_check;

ALTER TABLE public.vip_levels
  ADD CONSTRAINT vip_levels_level_check
  CHECK (level BETWEEN 1 AND 9);

-- ── 4. Update grant_vip to reject level > 9 ──────────────────────────────────
--
-- The previous implementation allowed 0–10.  Clamp to 0–9 to match all other
-- constraints.  admin_grant_vip (standardize migration) already clamps at 9;
-- this keeps the two functions consistent.

CREATE OR REPLACE FUNCTION public.grant_vip(
  p_user_id       uuid,
  p_vip_level     int,
  p_duration_days int DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller      uuid        := auth.uid();
  v_expires_at  timestamptz;
  v_now         timestamptz := now();
  v_sub_id      uuid;
BEGIN
  IF NOT public._vip_caller_is_admin() THEN
    RAISE EXCEPTION 'permission_denied: admin role required';
  END IF;

  IF p_vip_level < 0 OR p_vip_level > 9 THEN
    RAISE EXCEPTION 'invalid_vip_level: must be 0-9'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Level 0 = revoke
  IF p_vip_level = 0 THEN
    UPDATE public.user_vip_subscriptions
    SET is_active = false
    WHERE user_id = p_user_id AND is_active = true;

    UPDATE public.profiles
    SET vip_level = 0, vip_expires_at = NULL, vip_started_at = NULL
    WHERE id = p_user_id;

    RETURN jsonb_build_object('user_id', p_user_id, 'vip_level', 0, 'action', 'revoked');
  END IF;

  v_expires_at := v_now + (p_duration_days * interval '1 day');

  UPDATE public.user_vip_subscriptions
  SET is_active = false
  WHERE user_id = p_user_id AND is_active = true;

  INSERT INTO public.user_vip_subscriptions
    (user_id, vip_level, started_at, expires_at, is_active, payment_source, created_by_admin)
  VALUES
    (p_user_id, p_vip_level, v_now, v_expires_at, true, 'admin_grant', v_caller)
  RETURNING id INTO v_sub_id;

  UPDATE public.profiles
  SET
    vip_level      = p_vip_level,
    vip_started_at = v_now,
    vip_expires_at = v_expires_at
  WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'user_id',         p_user_id,
    'vip_level',       p_vip_level,
    'expires_at',      v_expires_at,
    'subscription_id', v_sub_id,
    'action',          'granted'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.grant_vip(uuid, int, int) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.grant_vip(uuid, int, int) FROM anon;

-- ── 5. Expiry automation — pg_cron is not enabled ────────────────────────────
--
-- expire_old_vips() exists (centralized_vip_system migration) and is correct.
-- pg_cron is not active on this project (no cron.schedule calls anywhere).
-- DO NOT add cron.schedule here — it breaks deployment when pg_cron is absent.
--
-- Choose ONE option to automate expiry:
--
-- Option A — Supabase Scheduled Edge Function (RECOMMENDED):
--   1. Deploy an Edge Function that calls: supabase.rpc('expire_old_vips')
--   2. Schedule it in: Supabase Dashboard > Edge Functions > Schedule
--   3. Suggested: daily at 03:00 UTC
--
-- Option B — pg_cron (only if verified active on your Supabase project):
--   SELECT cron.schedule(
--     'expire-old-vips-daily',
--     '0 3 * * *',
--     $$ SELECT public.expire_old_vips() $$
--   );
--
-- Option C — External cron (GitHub Actions, server cron, etc.):
--   curl -X POST https://<project-ref>.supabase.co/rest/v1/rpc/expire_old_vips \
--     -H "Authorization: Bearer <service-role-key>"
--   Suggested: daily at 03:00 UTC
--
-- =============================================================================
-- VIP SYSTEM CLOSED.  All phases 1–6 are complete.
--   Phase 1: VipSpecResolver — unified VIP visuals
--   Phase 2: Flutter consumer migration
--   Phase 3: VipPrivileges — centralized privilege rules
--   Phase 4: Backend enforcement (set_my_vip_setting, set_golden_id)
--   Phase 5: VIP Center UI polish + admin panel
--   Phase 6: (this file) backend hardening + constraint sync
-- =============================================================================
