-- =============================================================================
-- User Level System — Phase L3: Gift XP Hook
--
-- Goal:
--   Award user level XP to the gift sender every time a gift send succeeds.
--   Increment total_gifts_sent (sender) and total_gifts_received (receiver).
--
-- Strategy:
--   Replace send_gift_with_wallet with an identical copy plus one new
--   side-effect block appended after the existing PK scoring block.
--   Wallet logic is UNCHANGED. Return type is UNCHANGED (uuid).
--   Flutter GiftsService.sendGift() requires no changes.
--
-- XP formula:
--   sender XP = v_total_cost  (= gift.price_coins * quantity)
--   1 coin spent = 1 XP awarded.
--
-- Safety:
--   The level XP block runs inside BEGIN...EXCEPTION WHEN OTHERS THEN NULL.
--   Any failure in the XP block is silently swallowed — the gift transaction
--   and wallet debit are already committed and are NOT rolled back.
--
-- auth.uid() inside add_user_xp:
--   send_gift_with_wallet is SECURITY DEFINER, so auth.uid() = the RPC caller
--   (the gift sender). add_user_xp checks p_user_id = auth.uid() for callers
--   without admin rights. Calling it with v_sender_id satisfies that check.
--   For the receiver we skip add_user_xp and update the counter directly via
--   INSERT ... ON CONFLICT so no auth check is triggered.
--
-- Idempotency:
--   CREATE OR REPLACE — safe to re-run.
--   INSERT ... ON CONFLICT on user_levels — safe if row is missing.
--
-- Unchanged:
--   Wallet debit / credit logic    VIP system    charm_score    noble_level
--   PK scoring block               gift_transactions schema
--   Flutter GiftsService           add_user_xp signature
-- =============================================================================

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
  -- Identical to prior version. Failure here is swallowed.
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
  -- Runs after all wallet/gift writes succeed.
  -- XP formula: 1 coin spent = 1 XP (v_total_cost = price_coins * quantity).
  -- Receiver counter is updated via direct UPSERT (no auth check needed).
  -- Any failure here is swallowed — must never roll back the gift.
  BEGIN
    -- Award XP to sender (stamps last_xp_at, recalculates level)
    PERFORM public.add_user_xp(
      v_sender_id,
      v_total_cost::bigint,
      'gift_sent'
    );

    -- Increment sender gift-sent counter.
    -- add_user_xp already ensured the row exists via INSERT ON CONFLICT.
    UPDATE public.user_levels
    SET    total_gifts_sent = total_gifts_sent + v_quantity,
           updated_at       = now()
    WHERE  user_id = v_sender_id;

    -- Increment receiver gift-received counter (no XP to receiver in Phase L3).
    -- Use UPSERT in case this is receiver's first user_levels row.
    INSERT INTO public.user_levels (user_id, total_gifts_received)
    VALUES (p_receiver_id, v_quantity)
    ON CONFLICT (user_id) DO UPDATE
      SET total_gifts_received = public.user_levels.total_gifts_received + v_quantity,
          updated_at           = now();

  EXCEPTION WHEN OTHERS THEN
    NULL; -- Level XP error must never break the gift flow
  END;

  RETURN v_gift_transaction_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_gift_with_wallet(uuid, uuid, uuid, integer) TO authenticated;

-- =============================================================================
-- Phase L3 complete.
--
-- Function updated:
--   send_gift_with_wallet(uuid, uuid, uuid, integer) → uuid
--     ← same signature, same return type, same wallet/gift logic
--     ← new Level XP block appended after PK scoring block
--
-- XP formula:
--   sender XP = gift.price_coins * quantity  (v_total_cost)
--   source label = 'gift_sent'
--
-- user_levels mutations per successful gift:
--   sender   → xp += v_total_cost, level recalculated, last_xp_at = now()
--              total_gifts_sent += quantity
--   receiver → total_gifts_received += quantity  (no XP in Phase L3)
--
-- Flutter changes: NONE — GiftsService.sendGift() signature unchanged.
-- VIP changes: NONE.  charm_score: NONE.  noble_level: NONE.
--
-- Next:
--   Phase L4 — LevelService.getMyLevel() → get_my_level() RPC; LevelBadge
--               widget; wire MyLevelScreen into profile navigation.
-- =============================================================================
