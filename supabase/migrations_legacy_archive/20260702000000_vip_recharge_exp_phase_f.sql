-- =============================================================================
-- VIP Recharge EXP — Phase F: Schema foundation
--
-- Adds recharge-EXP tracking columns to profiles and threshold columns to
-- vip_levels.  All changes are additive (ADD COLUMN IF NOT EXISTS / DO UPDATE).
-- No existing columns, constraints, triggers, or RPCs are modified.
-- Migration is fully idempotent.
-- =============================================================================

-- ── 1. profiles — EXP tracking columns ──────────────────────────────────────
--
-- vip_recharge_exp    : total coins recharged by this user, ever (never resets).
--                       Used to determine lifetime tier eligibility.
-- vip_monthly_exp     : coins recharged in the current VIP cycle (month).
--                       Used to determine whether the current tier is maintained
--                       on renewal.  Reset to 0 when a new cycle starts.
-- vip_cycle_started_at: timestamp when the current monthly VIP cycle began.
--                       Populated when the user first reaches a VIP tier.
--                       Used by the renewal / expiry logic (Phase G+).
-- vip_last_recharge_at: timestamp of the most recent qualifying recharge.
--                       Informational; surfaced in VIP Center UI (Phase I).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS vip_recharge_exp     bigint      NOT NULL DEFAULT 0
                           CHECK (vip_recharge_exp >= 0),
  ADD COLUMN IF NOT EXISTS vip_monthly_exp      bigint      NOT NULL DEFAULT 0
                           CHECK (vip_monthly_exp >= 0),
  ADD COLUMN IF NOT EXISTS vip_cycle_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS vip_last_recharge_at timestamptz;

-- ── 2. profiles — indexes ────────────────────────────────────────────────────
--
-- vip_level      : used in leaderboard queries, room member VIP lookups, and
--                  admin reports that filter by active VIP tier.
-- vip_expires_at : used by expire_old_vips() and expiry-check reads.
-- vip_recharge_exp: will be used by Phase G hook to find the eligible tier
--                   and by admin reporting on top recharged users.

CREATE INDEX IF NOT EXISTS profiles_vip_level_idx
  ON public.profiles (vip_level)
  WHERE vip_level > 0;

CREATE INDEX IF NOT EXISTS profiles_vip_expires_at_idx
  ON public.profiles (vip_expires_at)
  WHERE vip_expires_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS profiles_vip_recharge_exp_idx
  ON public.profiles (vip_recharge_exp DESC)
  WHERE vip_recharge_exp > 0;

-- ── 3. vip_levels — threshold columns ───────────────────────────────────────
--
-- required_recharge_exp : cumulative lifetime coins recharged required to first
--                         reach (or upgrade to) this tier.
-- monthly_maintain_exp  : coins recharged in the current cycle required to
--                         keep this tier active for another month.
--                         Initially equal to required_recharge_exp; can be
--                         tuned independently later.

ALTER TABLE public.vip_levels
  ADD COLUMN IF NOT EXISTS required_recharge_exp bigint CHECK (required_recharge_exp >= 0),
  ADD COLUMN IF NOT EXISTS monthly_maintain_exp  bigint CHECK (monthly_maintain_exp  >= 0);

-- ── 4. vip_levels — seed / backfill thresholds ───────────────────────────────
--
-- Values use the business plan: 1 recharged coin = 1 VIP EXP.
-- The thresholds below are the confirmed starting plan.
-- monthly_maintain_exp = required_recharge_exp initially (can diverge later).

UPDATE public.vip_levels SET
  required_recharge_exp = 1000000,
  monthly_maintain_exp  = 1000000,
  updated_at            = now()
WHERE level = 1;

UPDATE public.vip_levels SET
  required_recharge_exp = 3000000,
  monthly_maintain_exp  = 3000000,
  updated_at            = now()
WHERE level = 2;

UPDATE public.vip_levels SET
  required_recharge_exp = 7000000,
  monthly_maintain_exp  = 7000000,
  updated_at            = now()
WHERE level = 3;

UPDATE public.vip_levels SET
  required_recharge_exp = 15000000,
  monthly_maintain_exp  = 15000000,
  updated_at            = now()
WHERE level = 4;

UPDATE public.vip_levels SET
  required_recharge_exp = 30000000,
  monthly_maintain_exp  = 30000000,
  updated_at            = now()
WHERE level = 5;

UPDATE public.vip_levels SET
  required_recharge_exp = 60000000,
  monthly_maintain_exp  = 60000000,
  updated_at            = now()
WHERE level = 6;

UPDATE public.vip_levels SET
  required_recharge_exp = 120000000,
  monthly_maintain_exp  = 120000000,
  updated_at            = now()
WHERE level = 7;

UPDATE public.vip_levels SET
  required_recharge_exp = 250000000,
  monthly_maintain_exp  = 250000000,
  updated_at            = now()
WHERE level = 8;

UPDATE public.vip_levels SET
  required_recharge_exp = 500000000,
  monthly_maintain_exp  = 500000000,
  updated_at            = now()
WHERE level = 9;

-- =============================================================================
-- Phase F complete.
--
-- Nothing changed:
--   - grant_vip()          → unchanged
--   - expire_old_vips()    → unchanged
--   - approve_recharge_request() → unchanged
--   - create_recharge_transaction() → unchanged
--   - set_my_vip_setting() → unchanged
--   - user_vip_subscriptions → unchanged
--   - wallets / wallet_transactions → unchanged
--
-- Next phases:
--   Phase G — update approve_recharge_request + create_recharge_transaction
--             to accumulate vip_recharge_exp / vip_monthly_exp and auto-assign
--             VIP tier when threshold is crossed.
--   Phase H — extend get_my_vip RPC to return exp fields; extend UserVip model.
--   Phase I — VIP Center EXP progress bar UI.
--   Phase J — monthly EXP reset + expiry renewal logic.
-- =============================================================================
