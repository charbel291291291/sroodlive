-- =============================================================================
-- Fix red envelope RPCs: correct wallet column names and wallet_transactions
-- schema. The original migration used wallets.coins (doesn't exist) instead of
-- coins_balance, and wallet_transactions columns that don't match the schema.
-- =============================================================================

-- ── 1. Extend wallet_transactions type constraint ────────────────────────────

ALTER TABLE public.wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;

ALTER TABLE public.wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check CHECK (
    type IN (
      'recharge_request', 'admin_adjustment', 'gift_sent', 'gift_received',
      'agency_recharge', 'refund', 'system', 'withdrawal', 'withdrawal_refund',
      'agency_commission',
      'hungry_cat_bet', 'hungry_cat_reward', 'hungry_cat_refund',
      'gold_ladder_entry', 'gold_ladder_win', 'gold_ladder_safe_payout',
      'crash_rocket_bet', 'crash_rocket_win', 'crash_rocket_refund',
      'room_game_bet', 'room_game_win', 'room_game_refund',
      'srood_loto_ticket', 'srood_treasure_entry', 'srood_treasure_win',
      'red_envelope_sent', 'red_envelope_claimed'
    )
  );

-- ── 2. Recreate create_red_envelope with correct column names ────────────────

CREATE OR REPLACE FUNCTION public.create_red_envelope(
  p_room_id     uuid,
  p_total_coins integer,
  p_count       integer
)
RETURNS public.red_envelopes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_wallet public.wallets;
  v_env    public.red_envelopes;
BEGIN
  IF v_uid IS NULL        THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_total_coins < 10   THEN RAISE EXCEPTION 'min_coins_10'; END IF;
  IF p_count < 1          THEN RAISE EXCEPTION 'min_count_1'; END IF;
  IF p_count > p_total_coins THEN RAISE EXCEPTION 'count_exceeds_coins'; END IF;

  -- Validate room exists.
  IF NOT EXISTS (SELECT 1 FROM public.rooms WHERE id = p_room_id) THEN
    RAISE EXCEPTION 'room_not_found';
  END IF;

  -- Sender must be in the room.
  IF NOT EXISTS (
    SELECT 1 FROM public.room_members
    WHERE room_id = p_room_id AND user_id = v_uid AND left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_room_member';
  END IF;

  -- Ensure wallet row exists, then lock it.
  INSERT INTO public.wallets (user_id) VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO v_wallet
  FROM public.wallets
  WHERE user_id = v_uid
  FOR UPDATE;

  IF v_wallet.coins_balance < p_total_coins THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  -- Deduct coins.
  UPDATE public.wallets
  SET coins_balance        = coins_balance - p_total_coins,
      lifetime_coins_spent = lifetime_coins_spent + p_total_coins,
      updated_at           = now()
  WHERE user_id = v_uid
  RETURNING * INTO v_wallet;

  -- Record wallet transaction.
  INSERT INTO public.wallet_transactions (
    user_id, type, direction, coins_delta,
    balance_coins_after, balance_diamonds_after,
    related_room_id, note
  ) VALUES (
    v_uid, 'red_envelope_sent', 'debit', -p_total_coins,
    v_wallet.coins_balance, v_wallet.diamonds_balance,
    p_room_id,
    'Red envelope (' || p_count || ' × ~' || (p_total_coins / p_count) || ' coins)'
  );

  -- Create envelope.
  INSERT INTO public.red_envelopes (room_id, sender_id, total_coins, envelope_count)
  VALUES (p_room_id, v_uid, p_total_coins, p_count)
  RETURNING * INTO v_env;

  RETURN v_env;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_red_envelope(uuid, integer, integer) TO authenticated;

-- ── 3. Recreate claim_red_envelope with correct column names ─────────────────

CREATE OR REPLACE FUNCTION public.claim_red_envelope(
  p_envelope_id uuid
)
RETURNS integer   -- coins received
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_env        public.red_envelopes;
  v_remaining  integer;
  v_slots_left integer;
  v_coins      integer;
  v_wallet     public.wallets;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  -- Lock envelope row atomically.
  SELECT * INTO v_env
  FROM public.red_envelopes
  WHERE id = p_envelope_id
  FOR UPDATE;

  IF NOT FOUND                THEN RAISE EXCEPTION 'envelope_not_found'; END IF;
  IF v_env.is_expired         THEN RAISE EXCEPTION 'envelope_expired'; END IF;
  IF v_env.expires_at < now() THEN RAISE EXCEPTION 'envelope_expired'; END IF;
  IF v_env.claimed_count >= v_env.envelope_count THEN
    RAISE EXCEPTION 'envelope_full';
  END IF;

  -- Prevent duplicate claim.
  IF EXISTS (
    SELECT 1 FROM public.red_envelope_claims
    WHERE envelope_id = p_envelope_id AND claimer_id = v_uid
  ) THEN
    RAISE EXCEPTION 'already_claimed';
  END IF;

  -- Claimer must be in the room.
  IF NOT EXISTS (
    SELECT 1 FROM public.room_members
    WHERE room_id = v_env.room_id AND user_id = v_uid AND left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_room_member';
  END IF;

  -- Calculate coins: random share, at least 1, at most remaining-1 (unless last slot).
  v_remaining  := v_env.total_coins - (
    SELECT COALESCE(SUM(coins_received), 0)
    FROM public.red_envelope_claims WHERE envelope_id = p_envelope_id
  );
  v_slots_left := v_env.envelope_count - v_env.claimed_count;

  IF v_slots_left = 1 THEN
    v_coins := v_remaining;
  ELSE
    v_coins := GREATEST(1, LEAST(
      v_remaining - (v_slots_left - 1),
      1 + floor(random() * (2 * v_remaining / v_slots_left - 1))::integer
    ));
  END IF;

  -- Record claim.
  INSERT INTO public.red_envelope_claims (envelope_id, claimer_id, coins_received)
  VALUES (p_envelope_id, v_uid, v_coins);

  -- Update envelope claimed count / expiry flag.
  UPDATE public.red_envelopes
  SET claimed_count = claimed_count + 1,
      is_expired    = (claimed_count + 1 >= envelope_count)
  WHERE id = p_envelope_id;

  -- Ensure claimer wallet exists, then credit.
  INSERT INTO public.wallets (user_id) VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE public.wallets
  SET coins_balance = coins_balance + v_coins,
      updated_at    = now()
  WHERE user_id = v_uid
  RETURNING * INTO v_wallet;

  -- Record wallet transaction.
  INSERT INTO public.wallet_transactions (
    user_id, type, direction, coins_delta,
    balance_coins_after, balance_diamonds_after,
    related_room_id, note
  ) VALUES (
    v_uid, 'red_envelope_claimed', 'credit', v_coins,
    v_wallet.coins_balance, v_wallet.diamonds_balance,
    v_env.room_id,
    'Red envelope claim'
  );

  RETURN v_coins;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_red_envelope(uuid) TO authenticated;
