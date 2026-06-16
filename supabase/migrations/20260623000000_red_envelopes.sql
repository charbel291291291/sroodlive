-- =============================================================================
-- Migration: red_envelopes
-- Host/owner drops a red envelope in the room; members race to claim coins.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.red_envelopes (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id         uuid        NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  sender_id       uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  total_coins     integer     NOT NULL CHECK (total_coins >= 10),
  envelope_count  integer     NOT NULL CHECK (envelope_count >= 1),
  claimed_count   integer     NOT NULL DEFAULT 0,
  is_expired      boolean     NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL DEFAULT (now() + interval '5 minutes')
);

CREATE TABLE IF NOT EXISTS public.red_envelope_claims (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  envelope_id     uuid        NOT NULL REFERENCES public.red_envelopes(id) ON DELETE CASCADE,
  claimer_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  coins_received  integer     NOT NULL,
  claimed_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (envelope_id, claimer_id)
);

-- RLS
ALTER TABLE public.red_envelopes        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.red_envelope_claims  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view red envelopes"
  ON public.red_envelopes FOR SELECT USING (true);

CREATE POLICY "Anyone can view claims"
  ON public.red_envelope_claims FOR SELECT USING (true);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.red_envelopes;
ALTER PUBLICATION supabase_realtime ADD TABLE public.red_envelope_claims;

-- =============================================================================
-- create_red_envelope — deduct coins from sender's wallet and create envelope.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_red_envelope(
  p_room_id       uuid,
  p_total_coins   integer,
  p_count         integer
)
RETURNS public.red_envelopes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_bal  integer;
  v_env  public.red_envelopes;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_total_coins < 10  THEN RAISE EXCEPTION 'min_coins_10'; END IF;
  IF p_count < 1         THEN RAISE EXCEPTION 'min_count_1'; END IF;
  IF p_count > p_total_coins THEN RAISE EXCEPTION 'count_exceeds_coins'; END IF;

  -- Check balance.
  SELECT coins INTO v_bal FROM public.wallets WHERE user_id = v_uid FOR UPDATE;
  IF v_bal IS NULL OR v_bal < p_total_coins THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  -- Deduct.
  UPDATE public.wallets SET coins = coins - p_total_coins WHERE user_id = v_uid;

  -- Record transaction.
  INSERT INTO public.wallet_transactions (user_id, amount, type, description)
  VALUES (v_uid, -p_total_coins, 'red_envelope_send',
          'Red envelope (' || p_count || ' × ~' || (p_total_coins / p_count) || ' coins)');

  -- Create envelope.
  INSERT INTO public.red_envelopes (room_id, sender_id, total_coins, envelope_count)
  VALUES (p_room_id, v_uid, p_total_coins, p_count)
  RETURNING * INTO v_env;

  RETURN v_env;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_red_envelope(uuid, integer, integer) TO authenticated;

-- =============================================================================
-- claim_red_envelope — atomically claim one slot; distribute random coins.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.claim_red_envelope(
  p_envelope_id uuid
)
RETURNS integer   -- coins received
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_env         public.red_envelopes;
  v_remaining   integer;
  v_slots_left  integer;
  v_coins       integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  -- Lock envelope row.
  SELECT * INTO v_env
  FROM public.red_envelopes
  WHERE id = p_envelope_id
  FOR UPDATE;

  IF NOT FOUND                  THEN RAISE EXCEPTION 'envelope_not_found'; END IF;
  IF v_env.is_expired           THEN RAISE EXCEPTION 'envelope_expired'; END IF;
  IF v_env.expires_at < now()   THEN RAISE EXCEPTION 'envelope_expired'; END IF;
  IF v_env.claimed_count >= v_env.envelope_count THEN
    RAISE EXCEPTION 'envelope_full';
  END IF;

  -- Already claimed by this user?
  IF EXISTS (
    SELECT 1 FROM public.red_envelope_claims
    WHERE envelope_id = p_envelope_id AND claimer_id = v_uid
  ) THEN
    RAISE EXCEPTION 'already_claimed';
  END IF;

  -- Calculate coins: random share of remaining coins, but at least 1.
  v_remaining  := v_env.total_coins - (
    SELECT COALESCE(SUM(coins_received), 0)
    FROM public.red_envelope_claims WHERE envelope_id = p_envelope_id
  );
  v_slots_left := v_env.envelope_count - v_env.claimed_count;

  IF v_slots_left = 1 THEN
    v_coins := v_remaining;
  ELSE
    -- Random in [1 .. 2×(remaining/slots_left)-1], capped to remaining-1.
    v_coins := GREATEST(1, LEAST(
      v_remaining - (v_slots_left - 1),
      1 + floor(random() * (2 * v_remaining / v_slots_left - 1))::integer
    ));
  END IF;

  -- Record claim.
  INSERT INTO public.red_envelope_claims (envelope_id, claimer_id, coins_received)
  VALUES (p_envelope_id, v_uid, v_coins);

  -- Update envelope.
  UPDATE public.red_envelopes
  SET claimed_count = claimed_count + 1,
      is_expired    = (claimed_count + 1 >= envelope_count)
  WHERE id = p_envelope_id;

  -- Credit claimer's wallet.
  INSERT INTO public.wallets (user_id, coins)
  VALUES (v_uid, v_coins)
  ON CONFLICT (user_id) DO UPDATE SET coins = wallets.coins + v_coins;

  INSERT INTO public.wallet_transactions (user_id, amount, type, description)
  VALUES (v_uid, v_coins, 'red_envelope_claim', 'Red envelope claim');

  RETURN v_coins;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_red_envelope(uuid) TO authenticated;
