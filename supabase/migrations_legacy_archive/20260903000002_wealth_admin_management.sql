-- Wealth XP admin management: audit table + two o_super_admin-only RPCs.
-- Only accounts with role = 'o_super_admin' may call these functions.

-- ── Audit table ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.wealth_admin_adjustments (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id   uuid        NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  target_user_id  uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action          text        NOT NULL CHECK (action IN ('add', 'remove', 'set')),
  amount          bigint      NOT NULL,
  xp_before       bigint      NOT NULL DEFAULT 0,
  xp_after        bigint      NOT NULL DEFAULT 0,
  reason          text        NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.wealth_admin_adjustments ENABLE ROW LEVEL SECURITY;

-- Only o_super_admin can read the audit log.
CREATE POLICY "o_super_admin_read_wealth_audit"
  ON public.wealth_admin_adjustments
  FOR SELECT
  USING (public.is_o_super_admin());

-- No direct INSERT/UPDATE/DELETE from clients; only via SECURITY DEFINER RPCs.

-- ── Helper: resolve current wealth XP for a user ─────────────────────────────

-- (user_wealth may not have a row yet; treat missing as 0)

-- ── RPC: super_admin_adjust_wealth_xp ────────────────────────────────────────
-- action: 'add' adds p_amount XP; 'remove' subtracts p_amount XP (floor 0).

CREATE OR REPLACE FUNCTION public.super_admin_adjust_wealth_xp(
  p_target_user_id  uuid,
  p_action          text,    -- 'add' | 'remove'
  p_amount          bigint,
  p_reason          text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id  uuid := auth.uid();
  v_xp_before bigint;
  v_xp_after  bigint;
BEGIN
  -- Permission gate: o_super_admin only.
  IF NOT public.is_o_super_admin() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF p_action NOT IN ('add', 'remove') THEN
    RAISE EXCEPTION 'invalid_action: must be add or remove';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount: must be positive';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  -- Read current XP (0 if no row yet).
  SELECT COALESCE(wealth_xp, 0)
    INTO v_xp_before
    FROM public.user_wealth
   WHERE user_id = p_target_user_id;

  v_xp_before := COALESCE(v_xp_before, 0);

  IF p_action = 'add' THEN
    v_xp_after := v_xp_before + p_amount;
  ELSE
    v_xp_after := GREATEST(0, v_xp_before - p_amount);
  END IF;

  -- Upsert user_wealth with recalculated level.
  INSERT INTO public.user_wealth (user_id, wealth_xp, wealth_level, tier_number, updated_at)
  VALUES (
    p_target_user_id,
    v_xp_after,
    COALESCE((
      SELECT level FROM public.wealth_level_rules
       WHERE required_xp <= v_xp_after AND is_active = true
       ORDER BY required_xp DESC LIMIT 1
    ), 1),
    COALESCE((
      SELECT tier_number FROM public.wealth_level_rules
       WHERE required_xp <= v_xp_after AND is_active = true
       ORDER BY required_xp DESC LIMIT 1
    ), 1),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
    SET wealth_xp    = EXCLUDED.wealth_xp,
        wealth_level = EXCLUDED.wealth_level,
        tier_number  = EXCLUDED.tier_number,
        updated_at   = now();

  -- Write audit row.
  INSERT INTO public.wealth_admin_adjustments
    (admin_user_id, target_user_id, action, amount, xp_before, xp_after, reason)
  VALUES
    (v_admin_id, p_target_user_id, p_action, p_amount, v_xp_before, v_xp_after, trim(p_reason));
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_adjust_wealth_xp(uuid, text, bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_adjust_wealth_xp(uuid, text, bigint, text) TO authenticated;

-- ── RPC: super_admin_set_wealth_xp ───────────────────────────────────────────
-- Sets exact XP (must be >= 0).

CREATE OR REPLACE FUNCTION public.super_admin_set_wealth_xp(
  p_target_user_id  uuid,
  p_xp              bigint,
  p_reason          text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id  uuid := auth.uid();
  v_xp_before bigint;
  v_xp_after  bigint;
BEGIN
  IF NOT public.is_o_super_admin() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF p_xp < 0 THEN
    RAISE EXCEPTION 'invalid_amount: xp cannot be negative';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  SELECT COALESCE(wealth_xp, 0)
    INTO v_xp_before
    FROM public.user_wealth
   WHERE user_id = p_target_user_id;

  v_xp_before := COALESCE(v_xp_before, 0);
  v_xp_after  := p_xp;

  INSERT INTO public.user_wealth (user_id, wealth_xp, wealth_level, tier_number, updated_at)
  VALUES (
    p_target_user_id,
    v_xp_after,
    COALESCE((
      SELECT level FROM public.wealth_level_rules
       WHERE required_xp <= v_xp_after AND is_active = true
       ORDER BY required_xp DESC LIMIT 1
    ), 1),
    COALESCE((
      SELECT tier_number FROM public.wealth_level_rules
       WHERE required_xp <= v_xp_after AND is_active = true
       ORDER BY required_xp DESC LIMIT 1
    ), 1),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
    SET wealth_xp    = EXCLUDED.wealth_xp,
        wealth_level = EXCLUDED.wealth_level,
        tier_number  = EXCLUDED.tier_number,
        updated_at   = now();

  INSERT INTO public.wealth_admin_adjustments
    (admin_user_id, target_user_id, action, amount, xp_before, xp_after, reason)
  VALUES
    (v_admin_id, p_target_user_id, 'set', v_xp_after, v_xp_before, v_xp_after, trim(p_reason));
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_set_wealth_xp(uuid, bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_set_wealth_xp(uuid, bigint, text) TO authenticated;
