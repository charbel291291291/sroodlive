-- =============================================================================
-- VIP Recharge EXP — Phase H: Expose EXP progress in VIP RPCs
--
-- Changes:
--   1. get_my_vip()          — add EXP progress fields (private, own user only)
--   2. get_user_vip(uuid)    — no change (EXP is private; tier/expiry is enough)
--   3. get_users_with_vip()  — no change (batch call for display, tier only)
--
-- All new fields are additive.  Existing field names and types are unchanged,
-- so existing Flutter VipService / UserVip parsing continues to work without
-- modification.  Migration is fully idempotent (CREATE OR REPLACE).
-- =============================================================================

-- ── 1. get_my_vip — extended with EXP progress ───────────────────────────────
--
-- New return fields (all null-safe):
--   vip_recharge_exp         bigint  — lifetime EXP accumulated (1 coin = 1 EXP)
--   vip_monthly_exp          bigint  — EXP in the current cycle (resets Phase J)
--   vip_cycle_started_at     text    — ISO timestamp when current cycle began
--   vip_last_recharge_at     text    — ISO timestamp of most recent recharge
--   current_tier_required_exp bigint — EXP required to hold current tier (NULL if no VIP)
--   next_tier_required_exp   bigint  — EXP required for next tier (NULL at VIP 9)
--   monthly_maintain_exp     bigint  — monthly EXP to keep current tier (NULL if no VIP)
--   exp_to_next_tier         bigint  — remaining EXP to reach next tier (0 when already there)
--   exp_to_maintain          bigint  — remaining monthly EXP to maintain tier (0 when met)
--
-- Existing fields preserved verbatim:
--   user_id, vip_level, vip_started_at, vip_expires_at, vip_title,
--   is_active, is_golden_id, golden_id_expires_at
--
-- Note: STABLE removed — the function now joins vip_levels which can be
-- updated by admins; VOLATILE is safer for correctness.

CREATE OR REPLACE FUNCTION public.get_my_vip()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid             uuid        := auth.uid();
  v_now             timestamptz := now();
  v_profile         record;
  v_cur_tier        record;   -- vip_levels row for current tier
  v_next_tier_exp   bigint;   -- required_recharge_exp for next tier
  v_exp_to_next     bigint;
  v_exp_to_maintain bigint;
  v_level           int;
  v_lifetime_exp    bigint;
  v_monthly_exp     bigint;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;

  SELECT
    p.id,
    p.vip_level,
    p.vip_started_at,
    p.vip_expires_at,
    p.vip_title,
    p.is_golden_id,
    p.golden_id_expires_at,
    COALESCE(p.vip_recharge_exp, 0)  AS vip_recharge_exp,
    COALESCE(p.vip_monthly_exp,  0)  AS vip_monthly_exp,
    p.vip_cycle_started_at,
    p.vip_last_recharge_at
  INTO v_profile
  FROM public.profiles p
  WHERE p.id = v_uid;

  IF NOT FOUND THEN RETURN NULL; END IF;

  v_level        := COALESCE(v_profile.vip_level, 0);
  v_lifetime_exp := v_profile.vip_recharge_exp;
  v_monthly_exp  := v_profile.vip_monthly_exp;

  -- ── Look up current tier thresholds ──────────────────────────────────────
  -- NULL when user has no active VIP tier (level = 0).
  IF v_level > 0 THEN
    SELECT
      vl.required_recharge_exp,
      COALESCE(vl.monthly_maintain_exp, vl.required_recharge_exp) AS monthly_maintain_exp
    INTO v_cur_tier
    FROM public.vip_levels vl
    WHERE vl.level = v_level
      AND vl.is_active = true
    LIMIT 1;
  END IF;

  -- ── Look up next tier threshold ───────────────────────────────────────────
  -- NULL at VIP 9 (max tier) or when no tier is defined above current.
  SELECT vl.required_recharge_exp
  INTO   v_next_tier_exp
  FROM   public.vip_levels vl
  WHERE  vl.level > v_level
    AND  vl.is_active = true
    AND  vl.required_recharge_exp IS NOT NULL
  ORDER  BY vl.level ASC
  LIMIT  1;

  -- ── Compute progress values ───────────────────────────────────────────────
  -- exp_to_next_tier: how many more lifetime EXP to reach the next tier.
  --   0 if already at or past the threshold, NULL if no next tier.
  IF v_next_tier_exp IS NOT NULL THEN
    v_exp_to_next := GREATEST(0, v_next_tier_exp - v_lifetime_exp);
  END IF;

  -- exp_to_maintain: how many more monthly EXP to secure current-tier renewal.
  --   0 if already met, NULL if no current tier or no maintain threshold.
  IF v_level > 0 AND v_cur_tier IS NOT NULL AND v_cur_tier.monthly_maintain_exp IS NOT NULL THEN
    v_exp_to_maintain := GREATEST(0, v_cur_tier.monthly_maintain_exp - v_monthly_exp);
  END IF;

  RETURN jsonb_build_object(
    -- ── Existing fields (unchanged) ─────────────────────────────────────────
    'user_id',               v_profile.id,
    'vip_level',             v_level,
    'vip_started_at',        v_profile.vip_started_at,
    'vip_expires_at',        v_profile.vip_expires_at,
    'vip_title',             v_profile.vip_title,
    'is_active',             (
      v_level > 0
      AND (v_profile.vip_expires_at IS NULL OR v_profile.vip_expires_at > v_now)
    ),
    'is_golden_id',          COALESCE(v_profile.is_golden_id, false),
    'golden_id_expires_at',  v_profile.golden_id_expires_at,
    -- ── New EXP progress fields ─────────────────────────────────────────────
    'vip_recharge_exp',          v_lifetime_exp,
    'vip_monthly_exp',           v_monthly_exp,
    'vip_cycle_started_at',      v_profile.vip_cycle_started_at,
    'vip_last_recharge_at',      v_profile.vip_last_recharge_at,
    'current_tier_required_exp', CASE WHEN v_level > 0 THEN v_cur_tier.required_recharge_exp ELSE NULL END,
    'next_tier_required_exp',    v_next_tier_exp,
    'monthly_maintain_exp',      CASE WHEN v_level > 0 THEN v_cur_tier.monthly_maintain_exp  ELSE NULL END,
    'exp_to_next_tier',          v_exp_to_next,
    'exp_to_maintain',           v_exp_to_maintain
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_vip() TO authenticated;

-- ── 2. get_user_vip / get_users_with_vip — unchanged ─────────────────────────
--
-- EXP data is private (recharge history is personal financial information).
-- Public consumers (other users' profiles, room member lists, leaderboard)
-- only need tier + expiry + golden-id, which is already returned.
-- No changes needed.

-- =============================================================================
-- Phase H complete.
--
-- RPCs updated:
--   get_my_vip()              ← extended with 9 new EXP progress fields
--   get_user_vip(uuid)        ← unchanged (EXP is private)
--   get_users_with_vip(uuid[]) ← unchanged (batch display, tier only)
--
-- Backward compatibility:
--   All existing field names and types in get_my_vip are preserved.
--   Flutter UserVip.fromJson ignores unknown keys, so old app versions
--   receiving new fields will not crash.
--   New app versions receiving old responses (before db push) will parse
--   all new fields as null/0 due to null-safe fromJson defaults.
-- =============================================================================
