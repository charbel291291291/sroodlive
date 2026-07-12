-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: charisma_challenge
-- Free daily charisma competition. Users join, perform on mic, audience votes.
-- Winner receives 100,000 coins + special avatar frame.
-- Two scopes: 'official' (Srood admin) and 'agency' (agency admin/owner).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. TABLES ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.charisma_challenges (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  title           text        NOT NULL,
  title_ar        text,
  scope           text        NOT NULL CHECK (scope IN ('agency', 'official')),
  agency_id       uuid,
  created_by      uuid        NOT NULL REFERENCES auth.users (id),
  -- state machine: scheduled → active → ended → crowned | cancelled
  status          text        NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'active', 'ended', 'crowned', 'cancelled')),
  starts_at       timestamptz NOT NULL,
  ends_at         timestamptz NOT NULL,
  reward_coins    int         NOT NULL DEFAULT 100000,
  reward_frame_id uuid,
  winner_user_id  uuid,
  crowned_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_charisma_challenges_status
  ON public.charisma_challenges (status, starts_at DESC);

-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.charisma_entries (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id  uuid        NOT NULL
    REFERENCES public.charisma_challenges (id) ON DELETE CASCADE,
  user_id       uuid        NOT NULL REFERENCES auth.users (id),
  room_id       uuid,
  agency_id     uuid,
  status        text        NOT NULL DEFAULT 'joined'
    CHECK (status IN ('joined', 'performed', 'disqualified', 'winner')),
  vote_count    int         NOT NULL DEFAULT 0,
  joined_at     timestamptz NOT NULL DEFAULT now(),
  performed_at  timestamptz,
  UNIQUE (challenge_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_charisma_entries_challenge
  ON public.charisma_entries (challenge_id, vote_count DESC);

-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.charisma_votes (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id         uuid        NOT NULL
    REFERENCES public.charisma_challenges (id) ON DELETE CASCADE,
  entry_id             uuid        NOT NULL
    REFERENCES public.charisma_entries (id) ON DELETE CASCADE,
  voter_id             uuid        NOT NULL REFERENCES auth.users (id),
  participant_user_id  uuid        NOT NULL,
  vote_weight          int         NOT NULL DEFAULT 1,
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (challenge_id, entry_id, voter_id)
);

CREATE INDEX IF NOT EXISTS idx_charisma_votes_entry
  ON public.charisma_votes (entry_id, voter_id);

-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.charisma_rewards (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id    uuid        NOT NULL
    REFERENCES public.charisma_challenges (id),
  user_id         uuid        NOT NULL REFERENCES auth.users (id),
  reward_coins    int         NOT NULL DEFAULT 100000,
  reward_frame_id uuid,
  reward_status   text        NOT NULL DEFAULT 'pending'
    CHECK (reward_status IN ('pending', 'granted', 'failed')),
  granted_at      timestamptz,
  metadata        jsonb       NOT NULL DEFAULT '{}',
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.charisma_admin_audit_logs (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id      uuid        NOT NULL REFERENCES auth.users (id),
  challenge_id  uuid,
  action        text        NOT NULL,
  old_value     jsonb,
  new_value     jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
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
      'srood_treasure_entry', 'srood_treasure_win',
      'charisma_reward'
    )
  );

-- ── 3. RPC: charisma_get_active_challenges ────────────────────────────────────
-- Auto-advances challenge status based on time, then returns visible challenges.

CREATE OR REPLACE FUNCTION public.charisma_get_active_challenges(
  p_scope     text DEFAULT NULL,
  p_agency_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_result  jsonb;
BEGIN
  -- Auto-activate scheduled challenges whose window has started
  UPDATE charisma_challenges
  SET status = 'active', updated_at = now()
  WHERE status = 'scheduled' AND starts_at <= now() AND ends_at > now();

  -- Auto-end active challenges whose window has closed
  UPDATE charisma_challenges
  SET status = 'ended', updated_at = now()
  WHERE status = 'active' AND ends_at < now();

  SELECT jsonb_agg(
    jsonb_build_object(
      'challenge', jsonb_build_object(
        'id',               c.id,
        'title',            c.title,
        'title_ar',         c.title_ar,
        'scope',            c.scope,
        'agency_id',        c.agency_id,
        'status',           c.status,
        'starts_at',        c.starts_at,
        'ends_at',          c.ends_at,
        'reward_coins',     c.reward_coins,
        'reward_frame_id',  c.reward_frame_id,
        'winner_user_id',   c.winner_user_id,
        'crowned_at',       c.crowned_at,
        'created_at',       c.created_at,
        'created_by',       c.created_by
      ),
      'participant_count', (
        SELECT COUNT(*)
        FROM   charisma_entries e
        WHERE  e.challenge_id = c.id AND e.status != 'disqualified'
      ),
      'my_entry', (
        SELECT jsonb_build_object(
          'id',           e.id,
          'challenge_id', e.challenge_id,
          'user_id',      e.user_id,
          'status',       e.status,
          'vote_count',   e.vote_count,
          'joined_at',    e.joined_at,
          'performed_at', e.performed_at
        )
        FROM charisma_entries e
        WHERE e.challenge_id = c.id AND e.user_id = v_user_id
        LIMIT 1
      )
    ) ORDER BY c.starts_at DESC
  ) INTO v_result
  FROM charisma_challenges c
  WHERE c.status IN ('active', 'ended', 'crowned')
    AND (p_scope IS NULL OR c.scope = p_scope)
    AND (
      p_agency_id IS NULL
      OR c.agency_id = p_agency_id
      OR c.scope = 'official'
    )
    -- Show crowned only if crowned within last 48 hours
    AND (c.status != 'crowned' OR c.crowned_at > now() - interval '48 hours')
  ;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- ── 4. RPC: charisma_join_challenge ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.charisma_join_challenge(
  p_challenge_id uuid,
  p_room_id      uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_challenge charisma_challenges;
  v_entry_id  uuid;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_challenge
  FROM charisma_challenges
  WHERE id = p_challenge_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'challenge_not_found'; END IF;
  IF v_challenge.status != 'active' THEN
    RAISE EXCEPTION 'challenge_not_active: %', v_challenge.status;
  END IF;

  -- unique constraint catches race conditions; give a nicer error first
  IF EXISTS (
    SELECT 1 FROM charisma_entries
    WHERE challenge_id = p_challenge_id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'already_joined';
  END IF;

  INSERT INTO charisma_entries (challenge_id, user_id, room_id, agency_id)
  VALUES (p_challenge_id, v_user_id, p_room_id, v_challenge.agency_id)
  RETURNING id INTO v_entry_id;

  RETURN jsonb_build_object(
    'entry_id',    v_entry_id,
    'challenge_id', p_challenge_id,
    'user_id',     v_user_id,
    'status',      'joined'
  );
END;
$$;

-- ── 5. RPC: charisma_vote ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.charisma_vote(p_entry_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_voter_id uuid := auth.uid();
  v_entry    charisma_entries;
  v_challenge charisma_challenges;
  v_new_count int;
BEGIN
  IF v_voter_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_entry FROM charisma_entries WHERE id = p_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'entry_not_found'; END IF;
  IF v_entry.user_id = v_voter_id THEN RAISE EXCEPTION 'self_vote'; END IF;

  SELECT * INTO v_challenge
  FROM   charisma_challenges
  WHERE  id = v_entry.challenge_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'challenge_not_found'; END IF;
  IF v_challenge.status != 'active' THEN RAISE EXCEPTION 'challenge_not_active'; END IF;

  -- Use unique constraint to prevent duplicate votes atomically
  BEGIN
    INSERT INTO charisma_votes
      (challenge_id, entry_id, voter_id, participant_user_id)
    VALUES
      (v_entry.challenge_id, p_entry_id, v_voter_id, v_entry.user_id);
  EXCEPTION
    WHEN unique_violation THEN RAISE EXCEPTION 'already_voted';
  END;

  UPDATE charisma_entries
  SET    vote_count = vote_count + 1
  WHERE  id = p_entry_id
  RETURNING vote_count INTO v_new_count;

  RETURN jsonb_build_object(
    'entry_id',      p_entry_id,
    'new_vote_count', v_new_count,
    'voter_id',      v_voter_id
  );
END;
$$;

-- ── 6. RPC: charisma_get_leaderboard ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.charisma_get_leaderboard(p_challenge_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_result  jsonb;
BEGIN
  WITH ranked AS (
    SELECT
      e.*,
      ROW_NUMBER() OVER (ORDER BY e.vote_count DESC, e.joined_at ASC) AS rank
    FROM charisma_entries e
    WHERE e.challenge_id = p_challenge_id
      AND e.status != 'disqualified'
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'rank',         r.rank,
      'entry_id',     r.id,
      'user_id',      r.user_id,
      'status',       r.status,
      'vote_count',   r.vote_count,
      'joined_at',    r.joined_at,
      'performed_at', r.performed_at,
      'has_voted', EXISTS (
        SELECT 1 FROM charisma_votes v
        WHERE  v.entry_id = r.id AND v.voter_id = v_user_id
      ),
      'is_me', r.user_id = v_user_id,
      'profile', jsonb_build_object(
        'display_name',              p.display_name,
        'username',                  p.username,
        'avatar_url',                p.avatar_url,
        'selected_avatar_frame_key', p.selected_avatar_frame_key,
        'public_user_id',            p.public_user_id,
        'vip_level',                 p.vip_level
      )
    ) ORDER BY r.rank
  ) INTO v_result
  FROM ranked r
  JOIN profiles p ON p.id = r.user_id;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- ── 7. RPC: admin_charisma_create_challenge ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_charisma_create_challenge(
  p_title           text,
  p_title_ar        text        DEFAULT NULL,
  p_scope           text        DEFAULT 'official',
  p_agency_id       uuid        DEFAULT NULL,
  p_starts_at       timestamptz DEFAULT now(),
  p_ends_at         timestamptz DEFAULT (now() + interval '24 hours'),
  p_reward_coins    int         DEFAULT 100000,
  p_reward_frame_id uuid        DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   uuid := auth.uid();
  v_is_admin  boolean;
  v_challenge charisma_challenges;
  v_status    text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.app_user_roles
    WHERE user_id = v_user_id AND role IN ('super_admin', 'admin')
  ) INTO v_is_admin;

  IF p_scope = 'official' AND NOT v_is_admin THEN
    RAISE EXCEPTION 'insufficient_permissions: official challenges require admin role';
  END IF;
  IF p_scope NOT IN ('agency', 'official') THEN
    RAISE EXCEPTION 'invalid_scope: %', p_scope;
  END IF;
  IF p_scope = 'agency' AND p_agency_id IS NULL THEN
    RAISE EXCEPTION 'agency_id_required_for_agency_scope';
  END IF;
  IF p_ends_at <= p_starts_at THEN
    RAISE EXCEPTION 'ends_at_must_be_after_starts_at';
  END IF;

  v_status := CASE
    WHEN p_starts_at <= now() AND p_ends_at > now() THEN 'active'
    WHEN p_starts_at > now()                         THEN 'scheduled'
    ELSE 'ended'
  END;

  INSERT INTO charisma_challenges (
    title, title_ar, scope, agency_id, created_by,
    starts_at, ends_at, reward_coins, reward_frame_id, status
  ) VALUES (
    p_title, p_title_ar, p_scope, p_agency_id, v_user_id,
    p_starts_at, p_ends_at, p_reward_coins, p_reward_frame_id, v_status
  )
  RETURNING * INTO v_challenge;

  INSERT INTO charisma_admin_audit_logs (admin_id, challenge_id, action, new_value)
  VALUES (v_user_id, v_challenge.id, 'create_challenge',
          jsonb_build_object('title', p_title, 'scope', p_scope, 'status', v_status));

  RETURN jsonb_build_object(
    'id',           v_challenge.id,
    'title',        v_challenge.title,
    'scope',        v_challenge.scope,
    'status',       v_challenge.status,
    'starts_at',    v_challenge.starts_at,
    'ends_at',      v_challenge.ends_at,
    'reward_coins', v_challenge.reward_coins
  );
END;
$$;

-- ── 8. RPC: admin_charisma_crown_winner ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_charisma_crown_winner(p_challenge_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   uuid := auth.uid();
  v_challenge charisma_challenges;
  v_winner    charisma_entries;
  v_has_admin boolean;
  v_is_creator boolean;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.app_user_roles
    WHERE user_id = v_user_id AND role IN ('super_admin', 'admin')
  ) INTO v_has_admin;

  SELECT EXISTS (
    SELECT 1 FROM charisma_challenges
    WHERE id = p_challenge_id AND created_by = v_user_id
  ) INTO v_is_creator;

  IF NOT v_has_admin AND NOT v_is_creator THEN
    RAISE EXCEPTION 'insufficient_permissions';
  END IF;

  SELECT * INTO v_challenge
  FROM charisma_challenges
  WHERE id = p_challenge_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'challenge_not_found'; END IF;
  IF v_challenge.status NOT IN ('active', 'ended') THEN
    RAISE EXCEPTION 'challenge_cannot_be_crowned: status is %', v_challenge.status;
  END IF;

  -- Top participant by votes, earliest join breaks ties
  SELECT * INTO v_winner
  FROM charisma_entries
  WHERE challenge_id = p_challenge_id AND status != 'disqualified'
  ORDER BY vote_count DESC, joined_at ASC
  LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'no_participants'; END IF;

  -- Mark winner
  UPDATE charisma_entries SET status = 'winner' WHERE id = v_winner.id;

  -- Crown the challenge
  UPDATE charisma_challenges
  SET winner_user_id = v_winner.user_id,
      status         = 'crowned',
      crowned_at     = now(),
      updated_at     = now()
  WHERE id = p_challenge_id;

  -- Credit coins — upsert wallet to be safe
  INSERT INTO wallets (user_id, coins_balance)
  VALUES (v_winner.user_id, v_challenge.reward_coins)
  ON CONFLICT (user_id) DO UPDATE
    SET coins_balance = wallets.coins_balance + v_challenge.reward_coins,
        updated_at    = now();

  -- Wallet transaction record
  INSERT INTO wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  VALUES (
    v_winner.user_id, 'charisma_reward', 'credit',
    v_challenge.reward_coins, 0,
    'Charisma Challenge winner – ' || v_challenge.title,
    jsonb_build_object(
      'challenge_id', p_challenge_id,
      'scope',        v_challenge.scope,
      'vote_count',   v_winner.vote_count
    )
  );

  -- Reward record (coins granted; frame remains pending until frame system grants it)
  INSERT INTO charisma_rewards
    (challenge_id, user_id, reward_coins, reward_frame_id,
     reward_status, granted_at, metadata)
  VALUES (
    p_challenge_id, v_winner.user_id,
    v_challenge.reward_coins, v_challenge.reward_frame_id,
    'granted', now(),
    jsonb_build_object(
      'coins_granted', true,
      'frame_status', CASE
        WHEN v_challenge.reward_frame_id IS NOT NULL THEN 'pending'
        ELSE 'none'
      END
    )
  );

  -- Audit
  INSERT INTO charisma_admin_audit_logs (admin_id, challenge_id, action, new_value)
  VALUES (v_user_id, p_challenge_id, 'crown_winner',
          jsonb_build_object(
            'winner_user_id', v_winner.user_id,
            'vote_count',     v_winner.vote_count,
            'reward_coins',   v_challenge.reward_coins
          ));

  RETURN jsonb_build_object(
    'winner_user_id',  v_winner.user_id,
    'vote_count',      v_winner.vote_count,
    'reward_coins',    v_challenge.reward_coins,
    'challenge_status', 'crowned'
  );
END;
$$;

-- ── 9. RPC: admin_charisma_cancel_challenge ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_charisma_cancel_challenge(p_challenge_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    uuid := auth.uid();
  v_challenge  charisma_challenges;
  v_has_admin  boolean;
  v_is_creator boolean;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.app_user_roles
    WHERE user_id = v_user_id AND role IN ('super_admin', 'admin')
  ) INTO v_has_admin;

  SELECT EXISTS (
    SELECT 1 FROM charisma_challenges
    WHERE id = p_challenge_id AND created_by = v_user_id
  ) INTO v_is_creator;

  IF NOT v_has_admin AND NOT v_is_creator THEN
    RAISE EXCEPTION 'insufficient_permissions';
  END IF;

  SELECT * INTO v_challenge FROM charisma_challenges
  WHERE id = p_challenge_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'challenge_not_found'; END IF;
  IF v_challenge.status IN ('crowned', 'cancelled') THEN
    RAISE EXCEPTION 'challenge_already_finalized: %', v_challenge.status;
  END IF;

  UPDATE charisma_challenges
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_challenge_id;

  INSERT INTO charisma_admin_audit_logs (admin_id, challenge_id, action)
  VALUES (v_user_id, p_challenge_id, 'cancel_challenge');

  RETURN jsonb_build_object('challenge_id', p_challenge_id, 'status', 'cancelled');
END;
$$;

-- ── 10. RPC: admin_charisma_get_challenges ────────────────────────────────────
-- Returns all (non-cancelled) challenges for admin management view.

CREATE OR REPLACE FUNCTION public.admin_charisma_get_challenges(
  p_scope     text DEFAULT NULL,
  p_agency_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_result  jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  -- Auto-advance scheduled/ended statuses before reporting
  UPDATE charisma_challenges
  SET status = 'active', updated_at = now()
  WHERE status = 'scheduled' AND starts_at <= now() AND ends_at > now();

  UPDATE charisma_challenges
  SET status = 'ended', updated_at = now()
  WHERE status = 'active' AND ends_at < now();

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',               c.id,
      'title',            c.title,
      'title_ar',         c.title_ar,
      'scope',            c.scope,
      'agency_id',        c.agency_id,
      'created_by',       c.created_by,
      'status',           c.status,
      'starts_at',        c.starts_at,
      'ends_at',          c.ends_at,
      'reward_coins',     c.reward_coins,
      'reward_frame_id',  c.reward_frame_id,
      'winner_user_id',   c.winner_user_id,
      'crowned_at',       c.crowned_at,
      'created_at',       c.created_at,
      'updated_at',       c.updated_at,
      'participant_count', (
        SELECT COUNT(*) FROM charisma_entries e
        WHERE e.challenge_id = c.id AND e.status != 'disqualified'
      )
    ) ORDER BY c.created_at DESC
  ) INTO v_result
  FROM charisma_challenges c
  WHERE c.status != 'cancelled'
    AND (p_scope IS NULL OR c.scope = p_scope)
    AND (p_agency_id IS NULL OR c.agency_id = p_agency_id)
  ;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- ── 11. RLS ──────────────────────────────────────────────────────────────────

ALTER TABLE public.charisma_challenges       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.charisma_entries          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.charisma_votes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.charisma_rewards          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.charisma_admin_audit_logs ENABLE ROW LEVEL SECURITY;

-- Challenges: anyone can read non-cancelled challenges
CREATE POLICY "charisma_challenges_public_read" ON public.charisma_challenges
  FOR SELECT USING (status != 'cancelled');

-- Entries: authenticated users can read entries of any challenge
CREATE POLICY "charisma_entries_read" ON public.charisma_entries
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Votes: users can read their own votes
CREATE POLICY "charisma_votes_own_read" ON public.charisma_votes
  FOR SELECT USING (voter_id = auth.uid());

-- Rewards: users see only their own rewards
CREATE POLICY "charisma_rewards_own_read" ON public.charisma_rewards
  FOR SELECT USING (user_id = auth.uid());

-- Audit logs: no direct client access (admin only via service role)
CREATE POLICY "charisma_audit_no_read" ON public.charisma_admin_audit_logs
  FOR SELECT USING (false);

-- ── 12. GRANTS ───────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION public.charisma_get_active_challenges(text, uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.charisma_join_challenge(uuid, uuid)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.charisma_vote(uuid)                          TO authenticated;
GRANT EXECUTE ON FUNCTION public.charisma_get_leaderboard(uuid)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_charisma_create_challenge(text, text, text, uuid, timestamptz, timestamptz, int, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_charisma_crown_winner(uuid)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_charisma_cancel_challenge(uuid)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_charisma_get_challenges(text, uuid)    TO authenticated;
