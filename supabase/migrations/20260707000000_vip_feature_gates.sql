-- =============================================================================
-- VIP Feature Gates — Phase V1
--
-- Adds a centralized VIP permission query layer.
--
-- New RPCs:
--   get_user_vip_permissions(p_user_id uuid) → jsonb
--     Full permissions matrix for any user. Authenticated callers only.
--     Safe to call for other users — returns only the permission flags,
--     not financial or private VIP data.
--
--   can_user_send_chat_image(p_user_id uuid) → boolean
--     Focused helper for the single most-common gate check.
--
-- Permission rules (all derived from effective VIP level, expiry-aware):
--   VIP 1+ : can_use_profile_frame    = true
--   VIP 3+ : can_use_premium_entrance = true
--   VIP 5+ : can_use_premium_bubble   = true
--   VIP 7+ : can_send_chat_image      = true
--   VIP 8+ : can_use_animated_frame   = true
--
-- Media limits:
--   max_chat_image_mb  : 0 (non-VIP), 5 (VIP 7–9), 10 (VIP 10+)
--   max_room_upload_mb : 0 (non-VIP), 20 (VIP 5–9), 50 (VIP 10+)
--
-- Source of truth for VIP level:
--   public.profiles.vip_level + vip_expires_at
--   (no new VIP table; existing economy untouched)
--
-- Unchanged:
--   VIP purchase / recharge logic    wallet    user_levels
--   send_room_image_message          room_chat_images bucket
--   send_gift_with_wallet
--
-- Idempotent: CREATE OR REPLACE throughout.
-- =============================================================================

-- ── 1. get_user_vip_permissions ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_user_vip_permissions(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw_level  int;
  v_expires_at timestamptz;
  v_level      int;  -- effective (0 when expired)
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT vip_level, vip_expires_at
  INTO   v_raw_level, v_expires_at
  FROM   public.profiles
  WHERE  id = p_user_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Compute effective level (0 when expired).
  v_level := COALESCE(v_raw_level, 0);
  IF v_level > 0 AND v_expires_at IS NOT NULL AND v_expires_at <= now() THEN
    v_level := 0;
  END IF;

  RETURN jsonb_build_object(
    'user_id',                p_user_id,
    'vip_level',              v_level,

    -- ── Feature flags ────────────────────────────────────────────────────────
    'can_use_profile_frame',    v_level >= 1,
    'can_use_premium_entrance', v_level >= 3,
    'can_use_premium_bubble',   v_level >= 5,
    'can_send_chat_image',      v_level >= 7,
    'can_use_animated_frame',   v_level >= 8,

    -- ── Media limits (MB) ─────────────────────────────────────────────────
    'max_chat_image_mb',   CASE
                             WHEN v_level >= 10 THEN 10
                             WHEN v_level >=  7 THEN  5
                             ELSE 0
                           END,
    'max_room_upload_mb',  CASE
                             WHEN v_level >= 10 THEN 50
                             WHEN v_level >=  5 THEN 20
                             ELSE 0
                           END
  );
END;
$$;

GRANT  EXECUTE ON FUNCTION public.get_user_vip_permissions(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_user_vip_permissions(uuid) FROM anon;

-- ── 2. can_user_send_chat_image ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.can_user_send_chat_image(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_perms jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  v_perms := public.get_user_vip_permissions(p_user_id);
  RETURN COALESCE((v_perms ->> 'can_send_chat_image')::boolean, false);
END;
$$;

GRANT  EXECUTE ON FUNCTION public.can_user_send_chat_image(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.can_user_send_chat_image(uuid) FROM anon;

-- =============================================================================
-- Phase V1 complete.
--
-- RPCs added:
--   get_user_vip_permissions(uuid) → jsonb
--   can_user_send_chat_image(uuid) → boolean
--
-- Permission matrix (effective VIP level, expiry-aware):
--   1+ can_use_profile_frame
--   3+ can_use_premium_entrance
--   5+ can_use_premium_bubble    | max_room_upload_mb = 20
--   7+ can_send_chat_image       | max_chat_image_mb = 5
--   8+ can_use_animated_frame
--   10+ (reserved)               | max_chat_image_mb = 10, max_room_upload_mb = 50
--
-- Flutter: VipPermissions model + VipPermissionsService added.
--         Room chat input updated: image button always visible, locked when < VIP7.
--
-- Next:
--   Phase V2 — private message image attachments (if desired)
--   Phase L4 — level badge wiring into profile / room UI
-- =============================================================================
