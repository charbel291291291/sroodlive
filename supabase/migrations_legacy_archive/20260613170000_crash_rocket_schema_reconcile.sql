-- ────────────────────────────────────────────────────────────────────────────
-- Crash Rocket — schema reconciliation
--
--   The 20260613160000 migration defined NEW per-user-round tables and RPCs,
--   but `create table if not exists` was a no-op because crash_rounds/crash_bets
--   already existed from an earlier (per-bet) design that was applied OUTSIDE the
--   migration system. That old schema is incompatible with the new RPCs:
--     • crash_rounds.bet_amount was NOT NULL  → start_crash_round INSERT failed
--       ("null value in column bet_amount …") → surfaced as "Network error".
--     • crash_rounds had no crashed_at column  → settlement UPDATE would fail.
--     • status checks lacked 'flying' (rounds) and 'lost' (bets).
--
--   Only the four crash RPCs reference these tables. The rows held were ephemeral
--   round records from the broken design (no wallet/user content). This migration
--   drops and recreates both tables to exactly match the RPC contract, restoring
--   a coherent schema once and for all. The RPCs themselves are unchanged.
-- ────────────────────────────────────────────────────────────────────────────

drop table if exists public.crash_bets   cascade;
drop table if exists public.crash_rounds cascade;

-- ── crash_rounds (per-user round; crash_multiplier is the pre-committed secret) ─
create table public.crash_rounds (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  status           text not null default 'flying'
                     check (status in ('flying', 'crashed')),
  crash_multiplier numeric(10,2) not null,
  started_at       timestamptz not null default now(),
  crashed_at       timestamptz,
  created_at       timestamptz not null default now()
);

alter table public.crash_rounds enable row level security;

drop policy if exists "crash_rounds_own" on public.crash_rounds;
create policy "crash_rounds_own"
  on public.crash_rounds for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists crash_rounds_recent_idx
  on public.crash_rounds (crashed_at desc)
  where status = 'crashed';

-- ── crash_bets ────────────────────────────────────────────────────────────────
create table public.crash_bets (
  id                      uuid primary key default gen_random_uuid(),
  round_id                uuid not null references public.crash_rounds(id) on delete cascade,
  user_id                 uuid not null references auth.users(id) on delete cascade,
  bet_amount              integer not null check (bet_amount > 0),
  mode                    text not null default 'manual'
                            check (mode in ('manual', 'auto')),
  auto_cashout_multiplier numeric(10,2),
  cashout_multiplier      numeric(10,2),
  win_amount              integer not null default 0,
  status                  text not null default 'running'
                            check (status in ('running', 'cashed_out', 'lost')),
  created_at              timestamptz not null default now()
);

alter table public.crash_bets enable row level security;

drop policy if exists "crash_bets_own" on public.crash_bets;
create policy "crash_bets_own"
  on public.crash_bets for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists crash_bets_round_idx on public.crash_bets (round_id);
