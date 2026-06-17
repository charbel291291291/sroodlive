-- =============================================================================
-- VIP Recharge EXP — Phase G: Recharge hook + automatic tier assignment
--
-- What this migration does:
--   1. Makes user_vip_subscriptions.vip_plan_id nullable (idempotent guard).
--      grant_vip() already inserts without vip_plan_id; this formalises that.
--   2. Creates public.apply_vip_recharge_exp(p_user_id, p_recharged_coins).
--      A reusable SECURITY DEFINER function called by both approval RPCs.
--   3. Replaces approve_recharge_request with a version that calls the hook
--      immediately after coin credit — preserving all existing behaviour.
--   4. Replaces approve_recharge_transaction with a version that calls the
--      hook immediately after coin credit — preserving all existing behaviour.
--
-- Nothing removed.  No coin balance logic changed.  No Flutter changes needed.
-- Migration is fully idempotent (CREATE OR REPLACE / ALTER … IF NOT EXISTS /
-- status guards inside both approval functions prevent double application).
-- =============================================================================

-- ── 0. Guard: make vip_plan_id nullable ──────────────────────────────────────
--
-- user_vip_subscriptions was created with vip_plan_id NOT NULL, but
-- grant_vip() (centralized_vip_system migration, 20260624) already inserts
-- without it.  The apply_vip_recharge_exp function will also insert without a
-- plan id (recharge-earned VIP has no plan).  Making the column nullable is
-- a safe, additive change.

ALTER TABLE public.user_vip_subscriptions
  ALTER COLUMN vip_plan_id DROP NOT NULL;

-- ── 1. apply_vip_recharge_exp ────────────────────────────────────────────────
--
-- Called after coins are credited on any approved recharge.
-- Accumulates EXP, computes the earned VIP tier, and upgrades / renews.
--
-- Parameters:
--   p_user_id        — the user whose EXP to update
--   p_recharged_coins — coins that were just credited (must be > 0)
--
-- Behaviour:
--   a) Add p_recharged_coins to vip_recharge_exp + vip_monthly_exp.
--   b) Set vip_last_recharge_at = now().
--   c) If vip_cycle_started_at IS NULL, set it to now() (first-ever recharge).
--   d) Find the highest VIP tier where required_recharge_exp <= new lifetime EXP.
--   e) Upgrade: if earned_tier > current vip_level
--        → set vip_level, vip_started_at, vip_expires_at = now()+30d
--        → insert user_vip_subscriptions row (payment_source = 'recharge_exp')
--   f) Renew: if earned_tier = current vip_level AND vip_monthly_exp >= monthly_maintain_exp
--        → extend vip_expires_at = GREATEST(vip_expires_at, now()) + 30d
--        → insert user_vip_subscriptions row (payment_source = 'recharge_exp')
--   g) Never downgrades.  A user above their earned tier keeps their current
--      tier until it expires naturally (expire_old_vips handles that).
--
-- Double-apply safety:
--   The callers (approve_recharge_request, approve_recharge_transaction) both
--   check status = 'pending' and set status = 'approved' before returning.
--   A second approval call raises an exception before reaching this function,
--   so EXP is never applied twice for the same approval.

CREATE OR REPLACE FUNCTION public.apply_vip_recharge_exp(
  p_user_id        uuid,
  p_recharged_coins bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now            timestamptz := now();
  v_new_lifetime   bigint;
  v_new_monthly    bigint;
  v_current_level  int;
  v_current_exp    timestamptz;
  v_earned_tier    int := 0;
  v_maintain_exp   bigint;
  v_new_expires    timestamptz;
BEGIN
  -- Guard: nothing to do for zero or negative coins
  IF p_recharged_coins <= 0 THEN
    RETURN;
  END IF;

  -- ── a+b+c  Accumulate EXP ─────────────────────────────────────────────────
  UPDATE public.profiles
  SET
    vip_recharge_exp     = vip_recharge_exp + p_recharged_coins,
    vip_monthly_exp      = vip_monthly_exp  + p_recharged_coins,
    vip_last_recharge_at = v_now,
    vip_cycle_started_at = COALESCE(vip_cycle_started_at, v_now)
  WHERE id = p_user_id
  RETURNING vip_recharge_exp, vip_monthly_exp, vip_level, vip_expires_at
  INTO v_new_lifetime, v_new_monthly, v_current_level, v_current_exp;

  -- User row must exist; if not, silently exit (no profile = no VIP to grant)
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- ── d  Find highest earned tier ───────────────────────────────────────────
  SELECT COALESCE(MAX(level), 0)
  INTO   v_earned_tier
  FROM   public.vip_levels
  WHERE  is_active = true
    AND  required_recharge_exp IS NOT NULL
    AND  required_recharge_exp <= v_new_lifetime;

  -- No tier earned yet — nothing more to do
  IF v_earned_tier = 0 THEN
    RETURN;
  END IF;

  -- ── e  Upgrade path (earned_tier > current level) ─────────────────────────
  IF v_earned_tier > COALESCE(v_current_level, 0) THEN

    v_new_expires := v_now + interval '30 days';

    -- Deactivate any current recharge-exp subscriptions (not admin grants)
    UPDATE public.user_vip_subscriptions
    SET    is_active = false
    WHERE  user_id = p_user_id
      AND  is_active = true
      AND  payment_source = 'recharge_exp';

    -- Update profile
    UPDATE public.profiles
    SET
      vip_level      = v_earned_tier,
      vip_started_at = v_now,
      vip_expires_at = v_new_expires
    WHERE id = p_user_id;

    -- Subscription audit row
    INSERT INTO public.user_vip_subscriptions
      (user_id, vip_level, started_at, expires_at, is_active, payment_source)
    VALUES
      (p_user_id, v_earned_tier, v_now, v_new_expires, true, 'recharge_exp');

    RETURN;
  END IF;

  -- ── f  Renewal path (earned_tier = current level, monthly EXP sufficient) ─
  IF v_earned_tier = COALESCE(v_current_level, 0) THEN

    -- Look up the maintain threshold for this tier
    SELECT COALESCE(monthly_maintain_exp, required_recharge_exp, 0)
    INTO   v_maintain_exp
    FROM   public.vip_levels
    WHERE  level = v_earned_tier
      AND  is_active = true
    LIMIT  1;

    IF v_new_monthly >= v_maintain_exp THEN

      -- Extend from max(current expiry, now) to avoid shrinking a long-running grant
      v_new_expires := GREATEST(COALESCE(v_current_exp, v_now), v_now)
                       + interval '30 days';

      UPDATE public.profiles
      SET    vip_expires_at = v_new_expires
      WHERE  id = p_user_id;

      -- Deactivate old recharge-exp subscription for this tier (if any)
      UPDATE public.user_vip_subscriptions
      SET    is_active = false
      WHERE  user_id = p_user_id
        AND  is_active = true
        AND  payment_source = 'recharge_exp'
        AND  vip_level = v_earned_tier;

      -- Subscription audit row
      INSERT INTO public.user_vip_subscriptions
        (user_id, vip_level, started_at, expires_at, is_active, payment_source)
      VALUES
        (p_user_id, v_earned_tier, v_now, v_new_expires, true, 'recharge_exp');

    END IF;
  END IF;

  -- ── g  No downgrade — tiers above earned are left untouched ───────────────
  -- (expire_old_vips handles expiry for admin-granted levels the user no longer earns)
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_vip_recharge_exp(uuid, bigint) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.apply_vip_recharge_exp(uuid, bigint) FROM anon;

-- ── 2. approve_recharge_request — add EXP hook ───────────────────────────────
--
-- Legacy recharge path (recharge_requests table → wallets table).
-- All existing coin credit / wallet_transactions insert logic is preserved
-- verbatim.  The single addition is the call to apply_vip_recharge_exp
-- after the wallet UPDATE commits, using v_request.requested_coins.
--
-- Double-apply guard: the existing check `v_request.status <> 'pending'`
-- raises an exception before any wallet or EXP update, making the function
-- safe to call idempotently with no risk of applying EXP twice.

CREATE OR REPLACE FUNCTION public.approve_recharge_request(
  p_request_id uuid,
  p_admin_note text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_request  public.recharge_requests;
  v_wallet   public.wallets;
BEGIN
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT public.has_finance_access() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT *
  INTO   v_request
  FROM   public.recharge_requests rr
  WHERE  rr.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'recharge_request_not_found';
  END IF;

  -- Double-apply guard: only pending requests can be approved
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'recharge_request_not_pending';
  END IF;

  -- ── Coin credit (unchanged) ───────────────────────────────────────────────

  INSERT INTO public.wallets (user_id)
  VALUES (v_request.user_id)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE public.wallets
  SET    coins_balance         = coins_balance         + v_request.requested_coins,
         lifetime_coins_charged = lifetime_coins_charged + v_request.requested_coins,
         updated_at            = now()
  WHERE  user_id = v_request.user_id
  RETURNING * INTO v_wallet;

  UPDATE public.recharge_requests
  SET    status        = 'approved',
         admin_user_id = v_admin_id,
         admin_note    = NULLIF(TRIM(COALESCE(p_admin_note, '')), ''),
         approved_at   = now(),
         updated_at    = now()
  WHERE  id = v_request.id;

  INSERT INTO public.wallet_transactions (
    user_id,
    type,
    direction,
    coins_delta,
    balance_coins_after,
    balance_diamonds_after,
    related_recharge_request_id,
    agency_id,
    agent_id,
    note
  )
  VALUES (
    v_request.user_id,
    CASE WHEN v_request.agent_id IS NULL THEN 'recharge_request' ELSE 'agency_recharge' END,
    'credit',
    v_request.requested_coins,
    v_wallet.coins_balance,
    v_wallet.diamonds_balance,
    v_request.id,
    v_request.agency_id,
    v_request.agent_id,
    p_admin_note
  );

  -- ── VIP EXP hook (new) ────────────────────────────────────────────────────
  -- Called after the coin credit transaction is committed to the wallet.
  -- Uses requested_coins (the coins actually credited), not amount_usd.

  PERFORM public.apply_vip_recharge_exp(
    v_request.user_id,
    v_request.requested_coins::bigint
  );

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_recharge_request(uuid, text) TO authenticated;

-- ── 3. approve_recharge_transaction — add EXP hook ───────────────────────────
--
-- Newer recharge path (recharge_transactions table → user_wallets table).
-- All existing coin credit / coin_transactions insert / wallet sync logic is
-- preserved verbatim.  The single addition is the call to apply_vip_recharge_exp
-- after the user_wallets UPDATE commits, using v_tx.total_coins.
--
-- Double-apply guard: the existing check `v_tx.status <> 'pending'` raises an
-- exception before any wallet or EXP update.

CREATE OR REPLACE FUNCTION public.approve_recharge_transaction(
  p_transaction_id   uuid,
  p_payment_reference text DEFAULT NULL,
  p_admin_note        text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_tx       public.recharge_transactions;
  v_wallet   public.user_wallets;
  v_before   bigint;
BEGIN
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT public.has_finance_access() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT *
  INTO   v_tx
  FROM   public.recharge_transactions
  WHERE  id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'recharge_transaction_not_found';
  END IF;

  -- Double-apply guard: only pending transactions can be approved
  IF v_tx.status <> 'pending' THEN
    RAISE EXCEPTION 'recharge_transaction_not_pending';
  END IF;

  -- ── Coin credit (unchanged) ───────────────────────────────────────────────

  PERFORM public.ensure_user_wallet(v_tx.user_id);

  SELECT *
  INTO   v_wallet
  FROM   public.user_wallets
  WHERE  user_id = v_tx.user_id
  FOR UPDATE;

  v_before := v_wallet.coin_balance;

  UPDATE public.user_wallets
  SET    coin_balance          = coin_balance          + v_tx.total_coins,
         total_recharged_usd   = total_recharged_usd   + v_tx.price_usd,
         total_recharged_coins = total_recharged_coins + v_tx.total_coins,
         updated_at            = now()
  WHERE  user_id = v_tx.user_id
  RETURNING * INTO v_wallet;

  -- Sync legacy wallets table (unchanged)
  INSERT INTO public.wallets (user_id)
  VALUES (v_tx.user_id)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE public.wallets
  SET    coins_balance          = v_wallet.coin_balance::integer,
         diamonds_balance       = v_wallet.diamond_balance::integer,
         lifetime_coins_charged = v_wallet.total_recharged_coins::integer,
         updated_at             = now()
  WHERE  user_id = v_tx.user_id;

  UPDATE public.recharge_transactions
  SET    status            = 'approved',
         payment_reference = COALESCE(
           NULLIF(TRIM(COALESCE(p_payment_reference, '')), ''),
           payment_reference
         ),
         admin_note        = NULLIF(TRIM(COALESCE(p_admin_note, '')), ''),
         approved_at       = now(),
         approved_by       = v_admin_id
  WHERE  id = v_tx.id;

  INSERT INTO public.coin_transactions (
    user_id,
    transaction_type,
    amount,
    balance_before,
    balance_after,
    source_type,
    source_id,
    description,
    created_by
  )
  VALUES (
    v_tx.user_id,
    'recharge',
    v_tx.total_coins,
    v_before,
    v_wallet.coin_balance,
    'recharge_transactions',
    v_tx.id,
    'Recharge approved',
    v_admin_id
  );

  -- ── VIP EXP hook (new) ────────────────────────────────────────────────────
  -- Uses total_coins (coins_amount + bonus_coins) — the full credited amount.
  -- This mirrors how lifetime_coins_charged / total_recharged_coins are updated
  -- above, so EXP accounting stays consistent with the wallet.

  PERFORM public.apply_vip_recharge_exp(
    v_tx.user_id,
    v_tx.total_coins
  );

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_recharge_transaction(uuid, text, text) TO authenticated;

-- =============================================================================
-- Phase G complete.
--
-- Functions created / replaced:
--   public.apply_vip_recharge_exp(uuid, bigint)   ← NEW
--   public.approve_recharge_request(uuid, text)   ← UPDATED (EXP hook added)
--   public.approve_recharge_transaction(uuid, text, text) ← UPDATED (EXP hook added)
--
-- Recharge paths hooked:
--   ✓ approve_recharge_request  (legacy: recharge_requests → wallets)
--   ✓ approve_recharge_transaction (newer: recharge_transactions → user_wallets)
--
-- Recharge paths deferred (not approval paths — no coins credited):
--   – create_recharge_transaction  (creates pending row only; no coin credit)
--   – request_recharge             (creates pending request only; no coin credit)
--
-- Nothing changed:
--   – grant_vip()          Admin grant path is unaffected.
--   – expire_old_vips()    Expiry sweep is unaffected.
--   – set_my_vip_setting() VIP settings RPC is unaffected.
--   – Coin balance logic   Identical to before in both approval RPCs.
--   – wallet_transactions / coin_transactions inserts  Identical to before.
-- =============================================================================
