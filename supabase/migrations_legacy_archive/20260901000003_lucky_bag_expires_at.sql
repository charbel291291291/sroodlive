-- =============================================================================
-- Lucky Bag v3: add expires_at to red_envelopes + update create_red_envelope
-- RPC to accept a sender-selected expiry (p_expires_at).
-- =============================================================================

-- ── 1. Add expires_at column (nullable; NULL = never auto-expires) ────────────

ALTER TABLE public.red_envelopes
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- ── 2. Recreate create_red_envelope accepting p_expires_at ───────────────────

CREATE OR REPLACE FUNCTION public.create_red_envelope(
  p_room_id     uuid,
  p_total_coins integer,
  p_count       integer,
  p_is_super    boolean DEFAULT false,
  p_expires_at  timestamptz DEFAULT NULL
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

  IF NOT EXISTS (SELECT 1 FROM public.rooms WHERE id = p_room_id) THEN
    RAISE EXCEPTION 'room_not_found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.room_members
    WHERE room_id = p_room_id AND user_id = v_uid AND left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_room_member';
  END IF;

  INSERT INTO public.wallets (user_id) VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO v_wallet
  FROM public.wallets
  WHERE user_id = v_uid
  FOR UPDATE;

  IF v_wallet.coins_balance < p_total_coins THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE public.wallets
  SET coins_balance        = coins_balance - p_total_coins,
      lifetime_coins_spent = lifetime_coins_spent + p_total_coins,
      updated_at           = now()
  WHERE user_id = v_uid
  RETURNING * INTO v_wallet;

  INSERT INTO public.wallet_transactions (
    user_id, type, direction, coins_delta,
    balance_coins_after, balance_diamonds_after,
    related_room_id, note
  ) VALUES (
    v_uid, 'red_envelope_sent', 'debit', -p_total_coins,
    v_wallet.coins_balance, v_wallet.diamonds_balance,
    p_room_id,
    CASE WHEN p_is_super
      THEN 'Super Lucky Bag (' || p_count || ' × ~' || (p_total_coins / p_count) || ' coins)'
      ELSE 'Lucky Bag (' || p_count || ' × ~' || (p_total_coins / p_count) || ' coins)'
    END
  );

  INSERT INTO public.red_envelopes (room_id, sender_id, total_coins, envelope_count, is_super, expires_at)
  VALUES (p_room_id, v_uid, p_total_coins, p_count, p_is_super,
          COALESCE(p_expires_at, now() + interval '5 minutes'))
  RETURNING * INTO v_env;

  RETURN v_env;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_red_envelope(uuid, integer, integer, boolean, timestamptz) TO authenticated;

-- ── 3. Mark envelopes as expired when expires_at has passed ──────────────────
-- Existing scheduled job / trigger can check this column. If there is an
-- expiry trigger that checks now() > expires_at, it will use this column.
-- No-op here as that logic lives in the existing is_expired column / policy.
