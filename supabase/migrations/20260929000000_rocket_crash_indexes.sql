-- Rocket Crash performance: add missing indexes
--
-- These indexes cover every query shape used by:
--   advance_rocket_crash_rounds (cron, every 15 s)
--   get_or_create_rocket_crash_round / get_rocket_crash_current_round
--   get_rocket_crash_recent_results
--   get_rocket_crash_round_bets
--   cash_out_rocket_crash_bet (settlement inner loop)
--
-- Without them the rounds table grows ~3 rows/min and every cron tick
-- performs 4 full-table scans. All indexes are additive and idempotent.

-- ── rocket_crash_global_rounds ───────────────────────────────────────────────

-- Active betting round lookup (get_or_create, advance step 2 & 3)
create index if not exists idx_rcgr_betting_active
  on public.rocket_crash_global_rounds (betting_ends_at)
  where status = 'betting';

-- Active flying round lookup (get_or_create, advance step 1 & 3)
create index if not exists idx_rcgr_flying_active
  on public.rocket_crash_global_rounds (flight_starts_at)
  where status = 'flying';

-- Due-for-settlement flying rounds (advance step 1: needs crash_multiplier)
create index if not exists idx_rcgr_flying_settle
  on public.rocket_crash_global_rounds (flight_starts_at, crash_multiplier)
  where status = 'flying' and crash_multiplier is not null;

-- Recent crash history (get_rocket_crash_recent_results ORDER BY crashed_at DESC)
create index if not exists idx_rcgr_crashed_history
  on public.rocket_crash_global_rounds (crashed_at desc)
  where status = 'crashed' and crash_multiplier is not null;

-- ── rocket_crash_global_bets ─────────────────────────────────────────────────

-- All bets for a round ordered by created_at (get_rocket_crash_round_bets)
create index if not exists idx_rcgb_round_created
  on public.rocket_crash_global_bets (round_id, created_at desc);

-- Active bets for a round (settlement inner loop, cashout check)
create index if not exists idx_rcgb_round_active
  on public.rocket_crash_global_bets (round_id)
  where status = 'active';

-- User bets for a round (mid-round rejoin: own active bets)
create index if not exists idx_rcgb_user_round
  on public.rocket_crash_global_bets (user_id, round_id);
