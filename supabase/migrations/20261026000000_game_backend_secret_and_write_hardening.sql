-- ────────────────────────────────────────────────────────────────────────────
-- Game backend security hardening — close the critical/high findings from the
-- six-game read-only audit (Roulette/Fish Hunt/Treasure/Loto/Hungry Cat/Spin).
--
-- This is a NEW migration; it edits no prior migration file. It only tightens
-- table-level GRANTs, RLS policies, RPC bodies, and realtime publication
-- membership. It does NOT change any game's rules, payouts, RNG, or wallet
-- math — every settlement/payout path already runs inside SECURITY DEFINER
-- RPCs, which execute as the function owner and are therefore unaffected by
-- the table-level REVOKEs below. Clients keep working because they already
-- read exclusively through those RPCs (verified against the Flutter services).
--
-- Findings addressed (see audit):
--   P0-1 Treasure   — full prize layout directly queryable, bypassing the
--                     masking RPC.
--   P0-2 Fish Hunt  — hit_probability (the core hit/miss secret) and
--                     server_seed exposed via table SELECT, the get_state RPC,
--                     and the realtime publication.
--   P1-3 Hungry Cat — bets table had an INSERT policy and no explicit write
--                     REVOKE, so a client could fabricate bet rows directly.
--   P1-4 Loto       — no explicit write REVOKE on tickets/draws
--                     (defense-in-depth; RLS already blocks the insert path).
--
-- Roulette was already hardened (revoke-all + grant-select, own-row bets,
-- winner written only after betting closes, not in realtime) and needs no
-- change. spin_wheel is intentionally NOT touched here: its RPC is not present
-- in any migration (schema drift) and must be captured into version control
-- and audited separately before we can safely alter it.
--
-- REPLAY-SAFETY NOTE (post Fish Hunt/Roulette retirement): the P0-2 Fish Hunt
-- section that originally followed P0-1 below has been removed from this file.
-- Fish Hunt's creation migrations were retired out of supabase/migrations/ (see
-- retired_migrations_removed_games/), so a fresh local/CI replay never creates
-- fish_hunt_rounds/fish_hunt_fish/fish_hunt_shots and the original section's
-- `create or replace function` (which declares a `public.fish_hunt_rounds`
-- typed variable) fails to compile with "type ... does not exist". Production,
-- where this migration already ran against the live Fish Hunt tables, is
-- unaffected: Supabase tracks applied migrations by version in
-- supabase_migrations.schema_migrations and never re-executes this file there.
-- The original P0-2 text (hit_probability/server_seed hardening rationale and
-- SQL) remains available via `git log -- <this file>` prior to this edit.
-- ────────────────────────────────────────────────────────────────────────────


-- ── P0-1. Srood Treasure — hide the prize layout ────────────────────────────
--
-- treasure_get_current_game (SECURITY DEFINER) already masks prize_coins: it
-- reveals a box's prize only once it is opened, and the personal box only once
-- the game is completed. But the "treasure_boxes_own" RLS policy grants a
-- blanket column-unrestricted SELECT on every box of the caller's own game, so
-- a client could `select box_number, prize_coins from treasure_game_boxes
-- where game_id = <mine>` and read all 16 prizes (including the personal box
-- and the jackpot) before opening anything — total defeat of the game.
--
-- Fix: remove direct client SELECT on the boxes table. The Flutter client only
-- ever calls treasure_get_current_game / treasure_* RPCs (verified: no
-- `.from('treasure_game_boxes')` anywhere in lib/), and those RPCs are
-- SECURITY DEFINER so they keep reading the table as the owner. We drop the
-- policy (so no role matches for direct reads) and revoke any residual grant.
drop policy if exists "treasure_boxes_own" on public.treasure_game_boxes;
revoke all on public.treasure_game_boxes from anon, authenticated, public;

comment on table public.treasure_game_boxes is
  'Per-game box prizes. SECRET: never client-readable directly — prize_coins is '
  'the whole game. All access goes through the masking SECURITY DEFINER RPC '
  'treasure_get_current_game, which only reveals a prize once its box is opened '
  '(or the personal box once the game completes).';

-- treasure_game_events also references prize/offer internals; the client reads
-- it only via the RPCs too. Lock it down the same way for defense-in-depth.
drop policy if exists "treasure_events_own" on public.treasure_game_events;
revoke all on public.treasure_game_events from anon, authenticated, public;

-- treasure_games (status/offer/round metadata, no per-box secret) and
-- treasure_settings (public config) are left as-is: the settings table is
-- intentionally public-readable and the games row carries no exploitable
-- secret. Their SELECT policies remain untouched.


-- ── P0-2. Fish Hunt — hide hit_probability and server_seed ──────────────────
--
-- Removed for replay-safety (see REPLAY-SAFETY NOTE above). This section
-- originally hardened public.fish_hunt_rounds / fish_hunt_fish / fish_hunt_shots
-- (hit_probability + server_seed exposure via table SELECT, the get_state RPC,
-- and the realtime publication). Fish Hunt has since been retired; guard the
-- absence explicitly rather than compiling a function against a type that no
-- longer exists in any environment that replays this file from empty.
do $$
begin
  if to_regclass('public.fish_hunt_rounds') is null then
    return;
  end if;
  raise exception
    'fish_hunt_rounds exists but the P0-2 hardening body was removed from '
    '20261026000000_game_backend_secret_and_write_hardening.sql during the '
    'Fish Hunt retirement — restore it from git history before replaying '
    'against an environment where Fish Hunt is still live.';
end $$;


-- ── P1-3. Hungry Cat — block direct bet fabrication ─────────────────────────
--
-- hungry_cat_global_bets had an INSERT policy ("global_bets_insert") and no
-- explicit write REVOKE, so — depending on Supabase default privileges — a
-- client could INSERT bet rows directly with arbitrary bet_amount /
-- multiplier_at_bet, never debiting the wallet, then collect on settlement.
-- All legitimate bets go through place_hungry_cat_global_bet (SECURITY
-- DEFINER), which debits the wallet atomically. Remove the direct-write path.
drop policy if exists "global_bets_insert" on public.hungry_cat_global_bets;
revoke insert, update, delete on public.hungry_cat_global_bets from anon, authenticated;
revoke insert, update, delete on public.hungry_cat_global_bets from public;

-- Own-row SELECT ("global_bets_select") is intentionally kept so players can
-- still read their own bets; the SECURITY DEFINER RPCs retain full write access.
comment on table public.hungry_cat_global_bets is
  'Hungry Cat bets. Client access is read-own-rows only; all writes go through '
  'place_hungry_cat_global_bet / settle_hungry_cat_global_round (SECURITY '
  'DEFINER). Direct INSERT/UPDATE/DELETE is revoked so bets cannot be forged '
  'without a wallet debit.';


-- ── P1-4. Loto — explicit write REVOKE (defense-in-depth) ───────────────────
--
-- loto_tickets / loto_draws have only SELECT policies (own-row / public), so
-- RLS already denies client writes. We add explicit REVOKEs so the write
-- surface does not depend on Supabase default table privileges, matching the
-- hardened Roulette/Fish Hunt posture. All writes flow through the loto_*
-- SECURITY DEFINER RPCs, which are unaffected.
revoke insert, update, delete on public.loto_tickets from anon, authenticated, public;
revoke insert, update, delete on public.loto_draws   from anon, authenticated, public;

comment on table public.loto_tickets is
  'Loto tickets. Read-own-rows only; all writes via loto_buy_ticket / settle '
  'RPCs (SECURITY DEFINER). Direct writes revoked.';
