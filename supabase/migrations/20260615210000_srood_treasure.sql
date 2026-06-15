-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: srood_treasure
-- "Deal or No Deal"-style mini game with 16 treasure boxes.
-- Entry fee: 20,000 coins. Max prize: 1,000,000 coins.
-- All prize assignment, offer calculation, and wallet mutations happen here.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. TABLES ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.treasure_settings (
  id                  smallint    PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  is_enabled          boolean     NOT NULL DEFAULT true,
  entry_fee_coins     bigint      NOT NULL DEFAULT 20000,
  max_prize_coins     bigint      NOT NULL DEFAULT 1000000,
  -- 16 prize amounts shuffled into boxes each game
  prize_amounts       bigint[]    NOT NULL DEFAULT ARRAY[
    1000, 2000, 5000, 10000, 25000, 50000,
    75000, 100000, 150000, 200000, 250000, 300000,
    400000, 500000, 750000, 1000000
  ]::bigint[],
  -- offer_percentages[i] applied after round i (1-based, 3 rounds)
  offer_percentages   numeric[]   NOT NULL DEFAULT ARRAY[0.75, 0.82, 0.90]::numeric[],
  updated_at          timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.treasure_settings (id) VALUES (1) ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.treasure_games (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid        NOT NULL REFERENCES auth.users (id),
  -- selecting → playing → deal_offered → completed | abandoned
  status              text        NOT NULL DEFAULT 'selecting'
    CHECK (status IN ('selecting', 'playing', 'deal_offered', 'completed', 'abandoned')),
  personal_box_number int,
  personal_box_prize  bigint,
  current_offer_coins bigint,
  round_number        int         NOT NULL DEFAULT 0,
  boxes_opened        int         NOT NULL DEFAULT 0,
  entry_fee_coins     bigint      NOT NULL DEFAULT 20000,
  final_payout_coins  bigint,
  payout_type         text        CHECK (payout_type IN ('offer', 'box', 'none')),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  completed_at        timestamptz
);

CREATE INDEX IF NOT EXISTS treasure_games_user_status
  ON public.treasure_games (user_id, status);

-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.treasure_game_boxes (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id     uuid        NOT NULL REFERENCES public.treasure_games (id) ON DELETE CASCADE,
  box_number  int         NOT NULL CHECK (box_number BETWEEN 1 AND 16),
  prize_coins bigint      NOT NULL,
  is_personal boolean     NOT NULL DEFAULT false,
  is_opened   boolean     NOT NULL DEFAULT false,
  opened_at   timestamptz,
  UNIQUE (game_id, box_number)
);

CREATE INDEX IF NOT EXISTS treasure_game_boxes_game_id
  ON public.treasure_game_boxes (game_id);

-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.treasure_game_events (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id     uuid        NOT NULL REFERENCES public.treasure_games (id) ON DELETE CASCADE,
  event_type  text        NOT NULL,
  payload     jsonb       NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ── 2. WALLET TYPE CONSTRAINT ─────────────────────────────────────────────────

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
      'srood_loto_ticket', 'srood_loto_win', 'srood_loto_refund',
      'srood_treasure_entry', 'srood_treasure_win'
    )
  );

-- ── 3. RPC: treasure_get_current_game ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.treasure_get_current_game()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_game     public.treasure_games;
  v_wallet   public.wallets;
  v_settings public.treasure_settings;
  v_boxes    jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_settings FROM public.treasure_settings LIMIT 1;
  SELECT * INTO v_wallet   FROM public.wallets WHERE user_id = v_user_id;

  SELECT * INTO v_game
  FROM   public.treasure_games
  WHERE  user_id = v_user_id
    AND  status NOT IN ('completed', 'abandoned')
  ORDER  BY created_at DESC
  LIMIT  1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'current_game',  null,
      'user_balance',  COALESCE(v_wallet.coins_balance, 0),
      'settings',      row_to_json(v_settings)::jsonb
    );
  END IF;

  -- Box list: hide prize for unopened non-personal boxes
  SELECT jsonb_agg(
    jsonb_build_object(
      'box_number',  b.box_number,
      'is_personal', b.is_personal,
      'is_opened',   b.is_opened,
      'prize_coins', CASE
        WHEN b.is_opened                               THEN b.prize_coins
        WHEN b.is_personal AND v_game.status = 'completed' THEN b.prize_coins
        ELSE null
      END
    ) ORDER BY b.box_number
  ) INTO v_boxes
  FROM public.treasure_game_boxes b
  WHERE b.game_id = v_game.id;

  RETURN jsonb_build_object(
    'current_game', jsonb_build_object(
      'id',                  v_game.id,
      'status',              v_game.status,
      'personal_box_number', v_game.personal_box_number,
      'personal_box_prize',
        CASE WHEN v_game.status = 'completed' THEN v_game.personal_box_prize ELSE null END,
      'current_offer_coins', v_game.current_offer_coins,
      'round_number',        v_game.round_number,
      'boxes_opened',        v_game.boxes_opened,
      'entry_fee_coins',     v_game.entry_fee_coins,
      'final_payout_coins',  v_game.final_payout_coins,
      'payout_type',         v_game.payout_type,
      'boxes',               COALESCE(v_boxes, '[]'::jsonb),
      'created_at',          v_game.created_at
    ),
    'user_balance', COALESCE(v_wallet.coins_balance, 0),
    'settings',     row_to_json(v_settings)::jsonb
  );
END;
$$;

-- ── 4. RPC: treasure_start_game ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.treasure_start_game()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_settings public.treasure_settings;
  v_wallet   public.wallets;
  v_existing public.treasure_games;
  v_game_id  uuid;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_settings FROM public.treasure_settings WHERE id = 1;
  IF NOT FOUND        THEN RAISE EXCEPTION 'game_not_configured'; END IF;
  IF NOT v_settings.is_enabled THEN RAISE EXCEPTION 'game_disabled'; END IF;

  -- Reject if an active game already exists
  SELECT * INTO v_existing
  FROM public.treasure_games
  WHERE user_id = v_user_id AND status NOT IN ('completed', 'abandoned')
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'active_game_exists: %', v_existing.id;
  END IF;

  -- Lock wallet and check balance
  SELECT * INTO v_wallet
  FROM public.wallets WHERE user_id = v_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;
  IF v_wallet.coins_balance < v_settings.entry_fee_coins THEN
    RAISE EXCEPTION 'insufficient_balance: need % coins', v_settings.entry_fee_coins;
  END IF;

  -- Deduct entry fee
  UPDATE public.wallets
  SET coins_balance = coins_balance - v_settings.entry_fee_coins,
      updated_at    = now()
  WHERE user_id = v_user_id;

  INSERT INTO public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  VALUES
    (v_user_id, 'srood_treasure_entry', 'debit',
     -v_settings.entry_fee_coins, 0,
     'Srood Treasure – entry fee',
     jsonb_build_object('entry_fee', v_settings.entry_fee_coins));

  -- Create game record
  INSERT INTO public.treasure_games (user_id, entry_fee_coins)
  VALUES (v_user_id, v_settings.entry_fee_coins)
  RETURNING id INTO v_game_id;

  -- Assign shuffled prizes to boxes 1-16
  WITH shuffled AS (
    SELECT
      row_number() OVER (ORDER BY random()) AS box_number,
      prize_coins
    FROM unnest(v_settings.prize_amounts) AS prize_coins
  )
  INSERT INTO public.treasure_game_boxes (game_id, box_number, prize_coins)
  SELECT v_game_id, box_number, prize_coins FROM shuffled;

  INSERT INTO public.treasure_game_events (game_id, event_type, payload)
  VALUES (v_game_id, 'game_started',
          jsonb_build_object('entry_fee', v_settings.entry_fee_coins));

  RETURN jsonb_build_object(
    'game_id',        v_game_id,
    'status',         'selecting',
    'entry_fee_coins', v_settings.entry_fee_coins,
    'user_balance',   v_wallet.coins_balance - v_settings.entry_fee_coins
  );
END;
$$;

-- ── 5. RPC: treasure_select_personal_box ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.treasure_select_personal_box(
  p_game_id    uuid,
  p_box_number int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_game    public.treasure_games;
  v_prize   bigint;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_box_number < 1 OR p_box_number > 16 THEN RAISE EXCEPTION 'invalid_box_number'; END IF;

  SELECT * INTO v_game
  FROM public.treasure_games
  WHERE id = p_game_id AND user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game_not_found'; END IF;
  IF v_game.status != 'selecting' THEN
    RAISE EXCEPTION 'invalid_game_status: %', v_game.status;
  END IF;

  SELECT prize_coins INTO v_prize
  FROM public.treasure_game_boxes
  WHERE game_id = p_game_id AND box_number = p_box_number;

  UPDATE public.treasure_game_boxes
  SET is_personal = true
  WHERE game_id = p_game_id AND box_number = p_box_number;

  UPDATE public.treasure_games
  SET status              = 'playing',
      personal_box_number = p_box_number,
      personal_box_prize  = v_prize,
      updated_at          = now()
  WHERE id = p_game_id;

  INSERT INTO public.treasure_game_events (game_id, event_type, payload)
  VALUES (p_game_id, 'personal_box_selected',
          jsonb_build_object('box_number', p_box_number));

  RETURN jsonb_build_object(
    'game_id',             p_game_id,
    'status',              'playing',
    'personal_box_number', p_box_number
  );
END;
$$;

-- ── 6. RPC: treasure_open_box ────────────────────────────────────────────────
-- Round thresholds (boxes_opened reaching): 6 → round 1, 11 → round 2, 15 → round 3 (final).

CREATE OR REPLACE FUNCTION public.treasure_open_box(
  p_game_id    uuid,
  p_box_number int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        uuid := auth.uid();
  v_game           public.treasure_games;
  v_box            public.treasure_game_boxes;
  v_settings       public.treasure_settings;
  v_new_opened     int;
  v_round_complete boolean := false;
  v_new_round      int;
  v_offer_pct      numeric;
  v_new_offer      bigint;
  v_new_status     text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_settings FROM public.treasure_settings WHERE id = 1;

  SELECT * INTO v_game
  FROM public.treasure_games
  WHERE id = p_game_id AND user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game_not_found'; END IF;
  IF v_game.status != 'playing' THEN
    RAISE EXCEPTION 'invalid_game_status: %', v_game.status;
  END IF;

  SELECT * INTO v_box
  FROM public.treasure_game_boxes
  WHERE game_id = p_game_id AND box_number = p_box_number;
  IF NOT FOUND     THEN RAISE EXCEPTION 'box_not_found'; END IF;
  IF v_box.is_opened  THEN RAISE EXCEPTION 'box_already_opened'; END IF;
  IF v_box.is_personal THEN RAISE EXCEPTION 'cannot_open_personal_box'; END IF;

  -- Open the box
  UPDATE public.treasure_game_boxes
  SET is_opened = true, opened_at = now()
  WHERE game_id = p_game_id AND box_number = p_box_number;

  v_new_opened := v_game.boxes_opened + 1;

  -- Check round threshold
  IF v_new_opened IN (6, 11, 15) THEN
    v_round_complete := true;
    v_new_round      := v_game.round_number + 1;
    v_offer_pct      := v_settings.offer_percentages[v_new_round];

    IF v_new_opened = 15 THEN
      -- Final round: offer is a percentage of the personal box value
      v_new_offer := round(v_game.personal_box_prize::numeric * v_offer_pct);
    ELSE
      -- Standard: average of remaining non-personal, unopened boxes
      SELECT round(AVG(prize_coins)::numeric * v_offer_pct) INTO v_new_offer
      FROM public.treasure_game_boxes
      WHERE game_id = p_game_id AND is_personal = false AND is_opened = false;
    END IF;

    v_new_status := 'deal_offered';
    UPDATE public.treasure_games
    SET boxes_opened        = v_new_opened,
        round_number        = v_new_round,
        current_offer_coins = v_new_offer,
        status              = 'deal_offered',
        updated_at          = now()
    WHERE id = p_game_id;
  ELSE
    v_new_status := 'playing';
    UPDATE public.treasure_games
    SET boxes_opened = v_new_opened,
        updated_at   = now()
    WHERE id = p_game_id;
  END IF;

  INSERT INTO public.treasure_game_events (game_id, event_type, payload)
  VALUES (p_game_id, 'box_opened',
          jsonb_build_object(
            'box_number',   p_box_number,
            'prize_coins',  v_box.prize_coins,
            'boxes_opened', v_new_opened
          ));

  RETURN jsonb_build_object(
    'opened_box_number',  p_box_number,
    'opened_prize_coins', v_box.prize_coins,
    'new_offer_coins',    v_new_offer,
    'round_complete',     v_round_complete,
    'game_status',        v_new_status
  );
END;
$$;

-- ── 7. RPC: treasure_accept_offer ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.treasure_accept_offer(p_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_game    public.treasure_games;
  v_wallet  public.wallets;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_game
  FROM public.treasure_games
  WHERE id = p_game_id AND user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game_not_found'; END IF;
  IF v_game.status != 'deal_offered' OR v_game.current_offer_coins IS NULL THEN
    RAISE EXCEPTION 'no_active_offer';
  END IF;

  UPDATE public.wallets
  SET coins_balance = coins_balance + v_game.current_offer_coins,
      updated_at    = now()
  WHERE user_id = v_user_id
  RETURNING * INTO v_wallet;

  INSERT INTO public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  VALUES
    (v_user_id, 'srood_treasure_win', 'credit',
     v_game.current_offer_coins, 0,
     'Srood Treasure – accepted offer',
     jsonb_build_object(
       'game_id',     p_game_id,
       'offer_coins', v_game.current_offer_coins,
       'round',       v_game.round_number
     ));

  UPDATE public.treasure_games
  SET status             = 'completed',
      final_payout_coins = v_game.current_offer_coins,
      payout_type        = 'offer',
      completed_at       = now(),
      updated_at         = now()
  WHERE id = p_game_id;

  INSERT INTO public.treasure_game_events (game_id, event_type, payload)
  VALUES (p_game_id, 'offer_accepted',
          jsonb_build_object('offer_coins', v_game.current_offer_coins));

  RETURN jsonb_build_object(
    'payout_coins',       v_game.current_offer_coins,
    'personal_box_prize', v_game.personal_box_prize,
    'payout_type',        'offer',
    'new_balance',        v_wallet.coins_balance
  );
END;
$$;

-- ── 8. RPC: treasure_take_box ────────────────────────────────────────────────
-- Only available in the final round (boxes_opened = 15).

CREATE OR REPLACE FUNCTION public.treasure_take_box(p_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_game    public.treasure_games;
  v_wallet  public.wallets;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_game
  FROM public.treasure_games
  WHERE id = p_game_id AND user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game_not_found'; END IF;
  IF v_game.status != 'deal_offered' THEN
    RAISE EXCEPTION 'invalid_game_status: %', v_game.status;
  END IF;
  IF v_game.boxes_opened < 15 THEN
    RAISE EXCEPTION 'not_final_round: open all other boxes first';
  END IF;

  UPDATE public.wallets
  SET coins_balance = coins_balance + v_game.personal_box_prize,
      updated_at    = now()
  WHERE user_id = v_user_id
  RETURNING * INTO v_wallet;

  INSERT INTO public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  VALUES
    (v_user_id, 'srood_treasure_win', 'credit',
     v_game.personal_box_prize, 0,
     'Srood Treasure – took personal box',
     jsonb_build_object('game_id', p_game_id, 'box_prize', v_game.personal_box_prize));

  UPDATE public.treasure_games
  SET status             = 'completed',
      final_payout_coins = v_game.personal_box_prize,
      payout_type        = 'box',
      completed_at       = now(),
      updated_at         = now()
  WHERE id = p_game_id;

  INSERT INTO public.treasure_game_events (game_id, event_type, payload)
  VALUES (p_game_id, 'box_taken',
          jsonb_build_object('box_prize', v_game.personal_box_prize));

  RETURN jsonb_build_object(
    'payout_coins',       v_game.personal_box_prize,
    'personal_box_prize', v_game.personal_box_prize,
    'payout_type',        'box',
    'new_balance',        v_wallet.coins_balance
  );
END;
$$;

-- ── 9. RPC: treasure_continue_game ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.treasure_continue_game(p_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_game    public.treasure_games;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_game
  FROM public.treasure_games
  WHERE id = p_game_id AND user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game_not_found'; END IF;
  IF v_game.status != 'deal_offered' THEN RAISE EXCEPTION 'no_active_offer'; END IF;
  IF v_game.boxes_opened >= 15 THEN
    RAISE EXCEPTION 'must_decide_final_round: accept offer or take box';
  END IF;

  UPDATE public.treasure_games
  SET status              = 'playing',
      current_offer_coins = null,
      updated_at          = now()
  WHERE id = p_game_id;

  INSERT INTO public.treasure_game_events (game_id, event_type, payload)
  VALUES (p_game_id, 'offer_declined',
          jsonb_build_object('declined_offer', v_game.current_offer_coins));

  RETURN jsonb_build_object('game_id', p_game_id, 'status', 'playing');
END;
$$;

-- ── 10. RPC: treasure_abandon_game ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.treasure_abandon_game(p_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_game    public.treasure_games;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_game
  FROM public.treasure_games
  WHERE id = p_game_id AND user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game_not_found'; END IF;

  IF v_game.status IN ('completed', 'abandoned') THEN
    RETURN jsonb_build_object('game_id', p_game_id, 'status', v_game.status);
  END IF;

  UPDATE public.treasure_games
  SET status       = 'abandoned',
      payout_type  = 'none',
      completed_at = now(),
      updated_at   = now()
  WHERE id = p_game_id;

  INSERT INTO public.treasure_game_events (game_id, event_type, payload)
  VALUES (p_game_id, 'game_abandoned', '{}'::jsonb);

  RETURN jsonb_build_object('game_id', p_game_id, 'status', 'abandoned');
END;
$$;

-- ── 11. RLS ──────────────────────────────────────────────────────────────────

ALTER TABLE public.treasure_settings    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasure_games       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasure_game_boxes  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasure_game_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "treasure_settings_public_read" ON public.treasure_settings
  FOR SELECT USING (true);

CREATE POLICY "treasure_games_own" ON public.treasure_games
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "treasure_boxes_own" ON public.treasure_game_boxes
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.treasure_games
      WHERE id = game_id AND user_id = auth.uid()
    )
  );

CREATE POLICY "treasure_events_own" ON public.treasure_game_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.treasure_games
      WHERE id = game_id AND user_id = auth.uid()
    )
  );

-- ── 12. GRANTS ───────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION public.treasure_get_current_game()               TO authenticated;
GRANT EXECUTE ON FUNCTION public.treasure_start_game()                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.treasure_select_personal_box(uuid, int)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.treasure_open_box(uuid, int)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.treasure_accept_offer(uuid)                TO authenticated;
GRANT EXECUTE ON FUNCTION public.treasure_take_box(uuid)                    TO authenticated;
GRANT EXECUTE ON FUNCTION public.treasure_continue_game(uuid)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.treasure_abandon_game(uuid)                TO authenticated;
