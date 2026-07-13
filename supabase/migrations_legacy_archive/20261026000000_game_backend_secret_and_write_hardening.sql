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
-- hit_probability is the server secret that decides every shot
-- (`if random() < v_fish.hit_probability`); server_seed is a per-round secret.
-- Both were readable three ways: the table SELECT policies, the get_state RPC
-- payload, and the realtime publication. A modified client could read each
-- fish's true hit chance and only fire at high-probability fish.
--
-- The Flutter client reads Fish Hunt state ONLY through fish_hunt_get_state
-- (verified: no `.from('fish_hunt_*')` and no realtime channel in lib/), and
-- it parses but never uses hit_probability (the UI derives rarity from
-- reward_multiplier). So we can safely (a) stop returning hit_probability from
-- the RPC, (b) revoke direct table SELECT on the two secret-bearing tables,
-- and (c) drop them from the realtime publication — all without any UI change.

-- (a) Redefine get_state to omit hit_probability. Body is byte-for-byte the
--     original except the single 'hit_probability' line is removed from the
--     fish JSON. Everything else (round, balance, shots, ordering) is identical.
create or replace function public.fish_hunt_get_state(
  p_room_id uuid default null
)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id  uuid := auth.uid();
  v_round    public.fish_hunt_rounds;
  v_balance  integer;
  v_fish     json;
  v_shots    json;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into v_round
  from public.fish_hunt_rounds
  where status = 'active'
    and (p_room_id is null or room_id = p_room_id)
  order by started_at desc
  limit 1;

  select coalesce(json_agg(
           json_build_object(
             'fish_id', f.id,
             'fish_type', f.fish_type,
             'reward_multiplier', f.reward_multiplier,
             -- hit_probability intentionally NOT exposed: it is the server-side
             -- hit/miss secret. The client never uses it.
             'spawned_at', f.spawned_at,
             'expires_at', f.expires_at
           )
           order by f.spawned_at
         ), '[]'::json)
  into v_fish
  from public.fish_hunt_fish f
  where v_round.id is not null
    and f.round_id = v_round.id
    and f.status = 'alive'
    and f.expires_at > now();

  select coins_balance
  into v_balance
  from public.wallets
  where user_id = v_user_id;

  select coalesce(json_agg(
           json_build_object(
             'shot_id', s.id,
             'fish_id', s.fish_id,
             'bet_amount', s.bet_amount,
             'result', s.result,
             'payout_amount', s.payout_amount,
             'created_at', s.created_at
           )
           order by s.created_at desc
         ), '[]'::json)
  into v_shots
  from (
    select *
    from public.fish_hunt_shots
    where user_id = v_user_id
    order by created_at desc
    limit 20
  ) s;

  return json_build_object(
    'round_id', v_round.id,
    'room_id', v_round.room_id,
    'round_status', v_round.status,
    'fish', v_fish,
    'balance', coalesce(v_balance, 0),
    'recent_shots', v_shots,
    'server_now', now()
  );
end;
$$;

-- Re-assert the original grant posture on the redefined function.
revoke all on function public.fish_hunt_get_state(uuid) from public, anon;
grant execute on function public.fish_hunt_get_state(uuid) to authenticated;

-- (b) Remove direct client SELECT on the secret-bearing tables. The get_state
--     / place_shot / leaderboard RPCs are SECURITY DEFINER and keep reading
--     these as the owner, so gameplay is unchanged.
revoke select on public.fish_hunt_fish   from authenticated;
revoke select on public.fish_hunt_rounds from authenticated;

comment on column public.fish_hunt_fish.hit_probability is
  'SECRET: per-fish hit chance used only inside fish_hunt_place_shot. Never '
  'exposed to clients (no direct table SELECT, not in get_state, not in the '
  'realtime publication).';
comment on column public.fish_hunt_rounds.server_seed is
  'SECRET: per-round seed. Never client-readable.';

-- fish_hunt_shots keeps its own-row SELECT so players still see their own
-- shot history through the RPC-backed state (grant retained).

-- (c) Drop the secret-bearing tables from realtime so their full rows (with
--     hit_probability / server_seed) are no longer broadcast. No client
--     subscribes to these channels — state comes from the 3s get_state poll.
do $$
begin
  if exists (select 1 from pg_publication_tables
             where pubname = 'supabase_realtime'
               and schemaname = 'public' and tablename = 'fish_hunt_fish') then
    alter publication supabase_realtime drop table public.fish_hunt_fish;
  end if;
  if exists (select 1 from pg_publication_tables
             where pubname = 'supabase_realtime'
               and schemaname = 'public' and tablename = 'fish_hunt_rounds') then
    alter publication supabase_realtime drop table public.fish_hunt_rounds;
  end if;
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
