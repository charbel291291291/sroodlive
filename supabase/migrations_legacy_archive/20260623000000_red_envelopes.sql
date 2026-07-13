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

-- NOTE: RPCs and type constraint extension are in 20260625000000_fix_red_envelope_rpcs.sql
-- (kept separate so the fix applies to existing deployments as well).
