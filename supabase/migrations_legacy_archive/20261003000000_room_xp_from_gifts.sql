-- Grant room XP whenever a gift is sent inside a room.
--
-- Root cause: send_gift_with_wallet (last defined in 20260903000001) calls
-- add_user_xp and add_wealth_xp but never grant_room_xp(), so room_level
-- never increases from gifts.
--
-- Fix: add a swallowed side-effect block after the Wealth XP block, matching
-- the exact pattern used for User Level XP and Wealth XP side-effects.
--
-- XP formula: total coins spent × bonus multiplier
--   > 2000 coins → 1.5×
--   > 500  coins → 1.2×
--   else         → 1.0×

CREATE OR REPLACE FUNCTION public.send_gift_with_wallet(
  p_room_id     uuid,
  p_receiver_id uuid,
  p_gift_id     uuid,
  p_quantity    integer DEFAULT 1
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_id           uuid    := auth.uid();
  v_quantity            integer := GREATEST(COALESCE(p_quantity, 1), 1);
  v_gift                record;
  v_total_cost          integer;
  v_diamonds_earned     integer;
  v_sender_wallet       public.wallets;
  v_receiver_wallet     public.wallets;
  v_gift_transaction_id uuid;
BEGIN
  -- ── Auth & validation ─────────────────────────────────────────────────────
  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_receiver_id IS NULL OR p_receiver_id = v_sender_id THEN
    RAISE EXCEPTION 'invalid_receiver';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.room_members rm
    WHERE rm.room_id = p_room_id
      AND rm.user_id = v_sender_id
      AND rm.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'sender_not_in_room';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.room_members rm
    WHERE rm.room_id = p_room_id
      AND rm.user_id = p_receiver_id
      AND rm.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'receiver_not_in_room';
  END IF;

  -- ── Gift lookup ───────────────────────────────────────────────────────────
  SELECT g.id, g.code, g.name, g.price_coins
  INTO   v_gift
  FROM   public.gifts g
  WHERE  g.id = p_gift_id
    AND  COALESCE(g.is_active, true)
  LIMIT  1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'gift_not_found';
  END IF;

  v_total_cost      := v_gift.price_coins::integer * v_quantity;
  v_diamonds_earned := v_total_cost;

  IF v_total_cost <= 0 THEN
    RAISE EXCEPTION 'invalid_gift_price';
  END IF;

  -- ── Ensure wallets exist ──────────────────────────────────────────────────
  INSERT INTO public.wallets (user_id) VALUES (v_sender_id)
    ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.wallets (user_id) VALUES (p_receiver_id)
    ON CONFLICT (user_id) DO NOTHING;

  -- ── Lock sender wallet and check balance ──────────────────────────────────
  SELECT * INTO v_sender_wallet
  FROM   public.wallets
  WHERE  user_id = v_sender_id
  FOR UPDATE;

  IF v_sender_wallet.coins_balance < v_total_cost THEN
    RAISE EXCEPTION 'insufficient_coins';
  END IF;

  -- ── Debit sender / credit receiver ───────────────────────────────────────
  UPDATE public.wallets
  SET    coins_balance        = coins_balance        - v_total_cost,
         lifetime_coins_spent = lifetime_coins_spent + v_total_cost,
         updated_at           = now()
  WHERE  user_id = v_sender_id
  RETURNING * INTO v_sender_wallet;

  UPDATE public.wallets
  SET    diamonds_balance         = diamonds_balance         + v_diamonds_earned,
         lifetime_diamonds_earned = lifetime_diamonds_earned + v_diamonds_earned,
         updated_at               = now()
  WHERE  user_id = p_receiver_id
  RETURNING * INTO v_receiver_wallet;

  -- ── Record gift transaction ───────────────────────────────────────────────
  INSERT INTO public.gift_transactions (
    room_id, sender_id, receiver_id,
    gift_id, gift_code, gift_name, gift_price_coins
  ) VALUES (
    p_room_id, v_sender_id, p_receiver_id,
    v_gift.id, v_gift.code, v_gift.name, v_total_cost
  )
  RETURNING id INTO v_gift_transaction_id;

  -- ── Wallet transaction ledger — sender ────────────────────────────────────
  INSERT INTO public.wallet_transactions (
    user_id, type, direction, coins_delta,
    balance_coins_after, balance_diamonds_after,
    related_user_id, related_room_id, related_gift_id,
    related_gift_transaction_id, note, metadata
  ) VALUES (
    v_sender_id, 'gift_sent', 'debit', -v_total_cost,
    v_sender_wallet.coins_balance, v_sender_wallet.diamonds_balance,
    p_receiver_id, p_room_id, v_gift.id,
    v_gift_transaction_id, 'Gift sent',
    jsonb_build_object('quantity', v_quantity, 'gift_code', v_gift.code)
  );

  -- ── Wallet transaction ledger — receiver ──────────────────────────────────
  INSERT INTO public.wallet_transactions (
    user_id, type, direction, diamonds_delta,
    balance_coins_after, balance_diamonds_after,
    related_user_id, related_room_id, related_gift_id,
    related_gift_transaction_id, note, metadata
  ) VALUES (
    p_receiver_id, 'gift_received', 'credit', v_diamonds_earned,
    v_receiver_wallet.coins_balance, v_receiver_wallet.diamonds_balance,
    v_sender_id, p_room_id, v_gift.id,
    v_gift_transaction_id, 'Gift received',
    jsonb_build_object('quantity', v_quantity, 'gift_code', v_gift.code)
  );

  -- ── Team PK scoring side-effect ───────────────────────────────────────────
  BEGIN
    PERFORM public.record_team_pk_gift_support(
      p_room_id,
      v_sender_id,
      p_receiver_id,
      v_gift_transaction_id,
      v_gift.code,
      v_total_cost::bigint
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- ── User Level XP side-effect (Phase L3) ─────────────────────────────────
  BEGIN
    PERFORM public.add_user_xp(
      v_sender_id,
      v_total_cost::bigint,
      'gift_sent'
    );

    UPDATE public.user_levels
    SET    total_gifts_sent = total_gifts_sent + v_quantity,
           updated_at       = now()
    WHERE  user_id = v_sender_id;

    INSERT INTO public.user_levels (user_id, total_gifts_received)
    VALUES (p_receiver_id, v_quantity)
    ON CONFLICT (user_id) DO UPDATE
      SET total_gifts_received = public.user_levels.total_gifts_received + v_quantity,
          updated_at           = now();

  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- ── Wealth XP side-effect ─────────────────────────────────────────────────
  BEGIN
    PERFORM public.add_wealth_xp(
      v_sender_id,
      v_total_cost::bigint,
      'gift_sent'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- ── Room XP side-effect ───────────────────────────────────────────────────
  -- Coins spent in the room grant XP to the room itself, enabling level-up.
  -- Bonus multiplier rewards high-value gifts.
  -- Swallowed so it can never break the gift flow.
  BEGIN
    PERFORM public.grant_room_xp(
      p_room_id,
      (v_total_cost * (CASE
        WHEN v_total_cost > 2000 THEN 1.5
        WHEN v_total_cost > 500  THEN 1.2
        ELSE 1.0
      END))::bigint,
      'gift'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN v_gift_transaction_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_gift_with_wallet(uuid, uuid, uuid, integer) TO authenticated;
