-- ────────────────────────────────────────────────────────────────────────────
-- Rocket Crash – local WebView betting RPCs
--
-- The local game drives its own round loop in JS. Flutter handles wallet
-- operations through these four atomic RPC functions only.
-- No coin movement ever happens client-side.
-- ────────────────────────────────────────────────────────────────────────────

-- Allow round_id to be nullable so local bets don't require a server round.
ALTER TABLE public.crash_bets
  ALTER COLUMN round_id DROP NOT NULL;

-- Expand status to include pending and refunded.
ALTER TABLE public.crash_bets
  DROP CONSTRAINT IF EXISTS crash_bets_status_check;
ALTER TABLE public.crash_bets
  ADD CONSTRAINT crash_bets_status_check
  CHECK (status IN ('pending','running','cashed_out','lost','refunded'));

-- ─── arm_crash_bet ───────────────────────────────────────────────────────────
-- Deducts p_amount from wallet, inserts a pending bet, returns
-- { bet_id, new_balance }.  Called when the user arms a bet slot.
CREATE OR REPLACE FUNCTION public.arm_crash_bet(
  p_amount      integer,
  p_slot_index  integer DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid         uuid    := auth.uid();
  v_balance     integer;
  v_bet_id      uuid;
  v_new_balance integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_amount <= 0    THEN RAISE EXCEPTION 'invalid_amount';  END IF;

  SELECT coins_balance INTO v_balance
  FROM wallets WHERE user_id = v_uid FOR UPDATE;

  IF NOT FOUND             THEN RAISE EXCEPTION 'wallet_not_found';    END IF;
  IF v_balance < p_amount  THEN RAISE EXCEPTION 'insufficient_coins';  END IF;

  UPDATE wallets
  SET    coins_balance = coins_balance - p_amount
  WHERE  user_id = v_uid;

  v_new_balance := v_balance - p_amount;

  INSERT INTO crash_bets (user_id, bet_amount, mode, status)
  VALUES (v_uid, p_amount, 'manual', 'pending')
  RETURNING id INTO v_bet_id;

  RETURN json_build_object(
    'bet_id',      v_bet_id,
    'new_balance', v_new_balance
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.arm_crash_bet(integer, integer) TO authenticated;

-- ─── cashout_crash_bet_local ─────────────────────────────────────────────────
-- Credits floor(bet_amount × p_multiplier) to wallet and marks bet cashed_out.
-- Called when the player manually or auto cashes out during flight.
CREATE OR REPLACE FUNCTION public.cashout_crash_bet_local(
  p_bet_id     uuid,
  p_multiplier numeric
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_bet         crash_bets;
  v_win_amount  integer;
  v_new_balance integer;
BEGIN
  IF v_uid IS NULL       THEN RAISE EXCEPTION 'not_authenticated';  END IF;
  IF p_multiplier < 1.0  THEN RAISE EXCEPTION 'invalid_multiplier'; END IF;

  SELECT * INTO v_bet
  FROM crash_bets
  WHERE id = p_bet_id AND user_id = v_uid
  FOR UPDATE;

  IF NOT FOUND                            THEN RAISE EXCEPTION 'bet_not_found';       END IF;
  IF v_bet.status NOT IN ('pending','running')
                                          THEN RAISE EXCEPTION 'bet_already_settled'; END IF;

  v_win_amount := floor(v_bet.bet_amount::numeric * p_multiplier)::integer;

  UPDATE wallets
  SET    coins_balance = coins_balance + v_win_amount
  WHERE  user_id = v_uid
  RETURNING coins_balance INTO v_new_balance;

  UPDATE crash_bets
  SET    status             = 'cashed_out',
         cashout_multiplier = p_multiplier,
         win_amount         = v_win_amount
  WHERE  id = p_bet_id;

  RETURN json_build_object(
    'win_amount',  v_win_amount,
    'new_balance', v_new_balance,
    'multiplier',  p_multiplier
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.cashout_crash_bet_local(uuid, numeric) TO authenticated;

-- ─── refund_crash_bet ────────────────────────────────────────────────────────
-- Refunds the full bet_amount back to wallet.
-- Called when the player cancels before flight starts.
CREATE OR REPLACE FUNCTION public.refund_crash_bet(
  p_bet_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_bet         crash_bets;
  v_new_balance integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_bet
  FROM crash_bets
  WHERE id = p_bet_id AND user_id = v_uid
  FOR UPDATE;

  IF NOT FOUND                             THEN RAISE EXCEPTION 'bet_not_found';  END IF;
  IF v_bet.status NOT IN ('pending','running')
                                           THEN RAISE EXCEPTION 'not_refundable'; END IF;

  UPDATE wallets
  SET    coins_balance = coins_balance + v_bet.bet_amount
  WHERE  user_id = v_uid
  RETURNING coins_balance INTO v_new_balance;

  UPDATE crash_bets SET status = 'refunded' WHERE id = p_bet_id;

  RETURN json_build_object(
    'refunded_amount', v_bet.bet_amount,
    'new_balance',     v_new_balance
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.refund_crash_bet(uuid) TO authenticated;

-- ─── mark_crash_bet_lost ─────────────────────────────────────────────────────
-- Marks a pending/running bet as lost (no coin movement — already deducted).
-- Called when the rocket crashes before the player cashed out.
CREATE OR REPLACE FUNCTION public.mark_crash_bet_lost(
  p_bet_id           uuid,
  p_crash_multiplier numeric DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  UPDATE crash_bets
  SET    status             = 'lost',
         cashout_multiplier = p_crash_multiplier
  WHERE  id       = p_bet_id
    AND  user_id  = v_uid
    AND  status   IN ('pending','running');
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_crash_bet_lost(uuid, numeric) TO authenticated;
