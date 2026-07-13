-- Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
-- Room-scoped server-authoritative game rounds
--
-- All users inside the same room see the same round, the same result, at the
-- same time.  The server is the ONLY source of truth.  Flutter clients:
--   Ã¢â‚¬Â¢ subscribe to room_game_rounds via Realtime
--   Ã¢â‚¬Â¢ display animations driven by backend timestamps (started_at, reveal_at)
--   Ã¢â‚¬Â¢ never generate the final result Ã¢â‚¬â€ they only display it
--
-- Security model
--   Ã¢â‚¬Â¢ result_json is NULL until status = 'revealed' (crash_multiplier hidden)
--   Ã¢â‚¬Â¢ crash_multiplier lives only in room_game_round_secrets (no client RLS)
--   Ã¢â‚¬Â¢ all state transitions happen inside SECURITY DEFINER functions
--   Ã¢â‚¬Â¢ clients can place bets and cashout, nothing else
-- Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

-- Ã¢â€â‚¬Ã¢â€â‚¬ 0. pgcrypto (needed for gen_random_bytes, digest) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
create extension if not exists pgcrypto;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 1. room_game_rounds Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

create table if not exists public.room_game_rounds (
  id                uuid        primary key default gen_random_uuid(),
  room_id           uuid        not null references public.rooms(id) on delete cascade,
  game_code         text        not null check (game_code in ('hungry_cat','crash_rocket')),
  round_number      bigint      not null default 1,
  status            text        not null default 'betting_open'
                                  check (status in (
                                    'waiting','betting_open','betting_closed',
                                    'running','revealed','finished','cancelled'
                                  )),
  -- Provably-fair: seed hidden until finished, hash shown from creation
  seed_hash         text        not null,
  seed              text,       -- revealed only after finished
  -- Result Ã¢â‚¬â€ NULL until status = 'revealed'
  result_json       jsonb,
  -- Timestamps that clients use to drive animations
  betting_opens_at  timestamptz,
  betting_closes_at timestamptz,
  started_at        timestamptz, -- crash: rocket launch time
  reveal_at         timestamptz, -- crash: pre-computed crash moment
  finished_at       timestamptz,
  created_by        uuid        references auth.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists rgr_room_game_idx
  on public.room_game_rounds (room_id, game_code, status);

create index if not exists rgr_active_idx
  on public.room_game_rounds (room_id, game_code)
  where status not in ('finished','cancelled');

alter table public.room_game_rounds enable row level security;

-- Active room members can read rounds (result_json is null until revealed Ã¢â‚¬â€ safe)
drop policy if exists "room_game_rounds_read" on public.room_game_rounds;
create policy "room_game_rounds_read"
  on public.room_game_rounds for select to authenticated
  using (
    exists (
      select 1 from public.room_members rm
      where rm.room_id = room_game_rounds.room_id
        and rm.user_id = auth.uid()
        and rm.left_at is null
    )
  );

-- No insert/update/delete policies Ã¢â‚¬â€ only SECURITY DEFINER RPCs modify this table

-- Ã¢â€â‚¬Ã¢â€â‚¬ 2. room_game_round_secrets Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
-- Crash multiplier lives here and is NEVER readable by clients (no RLS policy
-- = default deny; SECURITY DEFINER RPCs access it directly via Postgres).

create table if not exists public.room_game_round_secrets (
  round_id         uuid        primary key
                                 references public.room_game_rounds(id) on delete cascade,
  raw_seed         text        not null,
  crash_multiplier numeric(10,2),  -- for crash_rocket rounds
  winning_food_id  text            -- for hungry_cat rounds (pre-computed at creation)
);

-- No policies intentionally Ã¢â‚¬â€ SECURITY DEFINER functions bypass RLS anyway,
-- but this protects against accidental direct-read grants.
alter table public.room_game_round_secrets enable row level security;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 3. room_game_bets Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

create table if not exists public.room_game_bets (
  id                 uuid        primary key default gen_random_uuid(),
  round_id           uuid        not null references public.room_game_rounds(id) on delete cascade,
  room_id            uuid        not null references public.rooms(id) on delete cascade,
  user_id            uuid        not null references auth.users(id),
  bet_amount         bigint      not null check (bet_amount > 0),
  -- game-specific payload:
  --   hungry_cat:   {"food_id":"golden_fish","slot":"food_slot_1"}
  --   crash_rocket: {"auto_cashout_multiplier":2.5}  (optional)
  bet_json           jsonb       not null default '{}',
  status             text        not null default 'pending'
                                   check (status in (
                                     'pending','running','won','lost','refunded','cashed_out'
                                   )),
  payout_amount      bigint      not null default 0,
  cashout_multiplier numeric(10,2),
  created_at         timestamptz not null default now(),
  settled_at         timestamptz
);
create index if not exists room_game_bets_round_user_idx
on public.room_game_bets (round_id, user_id);

create index if not exists room_game_bets_room_user_idx
on public.room_game_bets (room_id, user_id);

create index if not exists room_game_bets_food_idx
on public.room_game_bets (
  round_id,
  user_id,
  ((bet_json ->> 'food_id'))
);

create index if not exists rgb_round_idx on public.room_game_bets (round_id);
create index if not exists rgb_user_round_idx on public.room_game_bets (user_id, round_id);

alter table public.room_game_bets enable row level security;

drop policy if exists "rgb_own" on public.room_game_bets;
create policy "rgb_own"
  on public.room_game_bets for all to authenticated
  using  (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Room members can read all bets in a round (leaderboard / social proof)
drop policy if exists "rgb_round_read" on public.room_game_bets;
create policy "rgb_round_read"
  on public.room_game_bets for select to authenticated
  using (
    exists (
      select 1
      from public.room_game_rounds r
      join public.room_members rm on rm.room_id = r.room_id
      where r.id = room_game_bets.round_id
        and rm.user_id = auth.uid()
        and rm.left_at is null
    )
  );

-- Ã¢â€â‚¬Ã¢â€â‚¬ 4. Extend wallet_transactions type constraint Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_type_check check (
    type in (
      'recharge_request','admin_adjustment','gift_sent','gift_received',
      'agency_recharge','refund','system','withdrawal','withdrawal_refund',
      'agency_commission',
      'red_envelope_sent','red_envelope_claimed',
      'hungry_cat_bet','hungry_cat_reward','hungry_cat_refund',
      'gold_ladder_entry','gold_ladder_win','gold_ladder_safe_payout',
      'crash_rocket_bet','crash_rocket_win','crash_rocket_refund',
      'room_game_bet','room_game_win','room_game_refund',
      'srood_loto_ticket','srood_treasure_entry','srood_treasure_win',
      'srood_loto_ticket','srood_treasure_entry','srood_treasure_win'
    )
  );

-- Ã¢â€â‚¬Ã¢â€â‚¬ 5. Realtime publication Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

do $$
begin
  -- Only add if not already in the publication
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'room_game_rounds'
  ) then
    alter publication supabase_realtime add table public.room_game_rounds;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'room_game_bets'
  ) then
    alter publication supabase_realtime add table public.room_game_bets;
  end if;
end $$;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 6. Helper: derive crash multiplier from seed (provably-fair) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
-- Used at creation (to compute reveal_at) and at reveal (for result_json).

create or replace function public._derive_crash_multiplier(p_seed text, p_round_id uuid)
returns numeric(10,2)
language plpgsql
immutable
security definer
set search_path = public
as $$
declare
  v_hash  bytea;
  v_int   bigint;
  v_rand  float8;
  v_crash numeric(10,2);
begin
  v_hash := digest(p_seed || p_round_id::text, 'sha256');
  -- Treat first 8 bytes as an unsigned 64-bit int (positive range only)
  v_int  := abs(('x' || encode(substring(v_hash from 1 for 8), 'hex'))::bit(64)::bigint);
  v_rand := v_int::float8 / 9223372036854775807::float8; -- 0..1

  if v_rand < 0.01 then
    v_crash := 1.00;
  else
    v_crash := round((0.99 / (1.0 - v_rand))::numeric, 2);
    v_crash := greatest(1.00::numeric(10,2), least(1000.00::numeric(10,2), v_crash));
  end if;
  return v_crash;
end;
$$;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 7. RPC: create_room_game_round Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
-- Only the room owner/host can start a round.
-- For crash_rocket: pre-commits crash_multiplier into secrets table.
-- For hungry_cat:   pre-commits winning_food_id into secrets table.
-- Returns timestamps clients use to drive animations (no secret values).

create or replace function public.create_room_game_round(
  p_room_id        uuid,
  p_game_code      text,
  p_betting_seconds integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid              uuid    := auth.uid();
  v_room             record;
  v_round_id         uuid    := gen_random_uuid();
  v_round_number     bigint;
  v_seed             text;
  v_seed_hash        text;
  v_betting_opens    timestamptz := now();
  v_betting_closes   timestamptz;
  v_started_at       timestamptz; -- when running begins
  v_reveal_at        timestamptz;
  -- crash
  v_crash_m          numeric(10,2);
  v_forced_crash_m   numeric(10,2);
  v_time_to_crash    float8;
  -- hungry cat
  v_total_weight     numeric;
  v_roll             numeric;
  v_cumulative       numeric := 0;
  v_food             record;
  v_winning_food_id  text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  if p_game_code not in ('hungry_cat','crash_rocket') then
    raise exception 'invalid_game_code';
  end if;

  -- Verify caller is room owner
  select * into v_room from public.rooms where id = p_room_id;
  if not found then raise exception 'room_not_found'; end if;

  if v_room.owner_id != v_uid then
    raise exception 'not_room_host';
  end if;

  -- Ensure no active round already exists for this game in this room
  if exists (
    select 1 from public.room_game_rounds
    where room_id  = p_room_id
      and game_code = p_game_code
      and status   not in ('finished','cancelled')
  ) then
    raise exception 'round_already_active';
  end if;

  -- Next round number
  select coalesce(max(round_number), 0) + 1 into v_round_number
  from public.room_game_rounds
  where room_id = p_room_id and game_code = p_game_code;

  -- Generate provably-fair seed
  v_seed      := encode(gen_random_bytes(32), 'hex');
  v_seed_hash := encode(digest(v_seed, 'sha256'), 'hex');

  v_betting_closes := v_betting_opens + (p_betting_seconds || ' seconds')::interval;

  -- Ã¢â€â‚¬Ã¢â€â‚¬ Game-specific secret pre-commitment Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  if p_game_code = 'crash_rocket' then
    -- Check for forced multiplier (test / owner override)
    select gs.forced_crash_multiplier into v_forced_crash_m
    from public.game_settings gs
    where gs.game_key = 'crash_rocket'
      and gs.forced_crash_multiplier is not null
      and gs.forced_crash_multiplier_expires_at > now();

    if v_forced_crash_m is not null then
      v_crash_m := v_forced_crash_m;
    else
      v_crash_m := public._derive_crash_multiplier(v_seed, v_round_id);
    end if;

    -- Rocket launches when betting closes; reveal = launch + time_to_crash
    v_started_at    := v_betting_closes;
    v_time_to_crash := ln(v_crash_m::float8) / 0.15;  -- seconds
    v_reveal_at     := v_started_at + (v_time_to_crash || ' seconds')::interval;

    insert into public.room_game_round_secrets (round_id, raw_seed, crash_multiplier)
    values (v_round_id, v_seed, v_crash_m);

  elsif p_game_code = 'hungry_cat' then
    -- Pre-select winning food server-side using weighted random
    select sum(weight) into v_total_weight
    from public.hungry_cat_config where is_active = true;

    if coalesce(v_total_weight, 0) <= 0 then
      raise exception 'no_active_foods';
    end if;

    -- Use seed to get a deterministic roll (provably fair)
    v_roll := (('x' || encode(substring(digest(v_seed, 'sha256') from 1 for 8), 'hex'))::bit(64)::bigint::float8
              / 9223372036854775807::float8) * v_total_weight;
    v_roll := abs(v_roll);

    for v_food in (
      select * from public.hungry_cat_config
      where is_active = true
      order by sort_order
    ) loop
      v_cumulative := v_cumulative + v_food.weight;
      if v_roll <= v_cumulative and v_winning_food_id is null then
        v_winning_food_id := v_food.food_id;
      end if;
    end loop;

    if v_winning_food_id is null then
      select food_id into v_winning_food_id
      from public.hungry_cat_config
      where is_active = true order by sort_order limit 1;
    end if;

    -- No "started_at" needed for hungry_cat (settle immediately on lock)
    v_reveal_at := v_betting_closes + interval '2 seconds'; -- brief spin time

    insert into public.room_game_round_secrets (round_id, raw_seed, winning_food_id)
    values (v_round_id, v_seed, v_winning_food_id);
  end if;

  -- Create the round record (result_json is null Ã¢â‚¬â€ hidden from clients)
  insert into public.room_game_rounds (
    id, room_id, game_code, round_number, status,
    seed_hash, seed,
    betting_opens_at, betting_closes_at, started_at, reveal_at,
    created_by
  ) values (
    v_round_id, p_room_id, p_game_code, v_round_number, 'betting_open',
    v_seed_hash, null,  -- seed revealed only after finished
    v_betting_opens, v_betting_closes, v_started_at, v_reveal_at,
    v_uid
  );

  return jsonb_build_object(
    'round_id',          v_round_id,
    'round_number',      v_round_number,
    'seed_hash',         v_seed_hash,
    'betting_opens_at',  v_betting_opens,
    'betting_closes_at', v_betting_closes,
    'started_at',        v_started_at,
    'reveal_at',         v_reveal_at
  );
end;
$$;

grant execute on function public.create_room_game_round(uuid, text, integer) to authenticated;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 8. RPC: place_room_game_bet Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
-- Any active room member may place a bet while status = 'betting_open'.
-- Deducts coins atomically; idempotent on (round_id, user_id, food_id).

create or replace function public.place_room_game_bet(
  p_round_id   uuid,
  p_bet_amount bigint,
  p_bet_json   jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_round       record;
  v_bet_id      uuid := gen_random_uuid();
  v_new_balance bigint;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_bet_amount <= 0 then raise exception 'invalid_bet_amount'; end if;

  -- Validate round
  select r.* into v_round
  from public.room_game_rounds r
  where r.id = p_round_id
  for update;

  if not found then raise exception 'round_not_found'; end if;

  -- Verify caller is an active room member
  if not exists (
    select 1 from public.room_members rm
    where rm.room_id = v_round.room_id
      and rm.user_id = v_uid
      and rm.left_at is null
  ) then
    raise exception 'not_room_member';
  end if;

  if v_round.status != 'betting_open' then raise exception 'betting_closed'; end if;
  if now() > v_round.betting_closes_at then raise exception 'betting_closed'; end if;

  -- Deduct from wallet
  update public.wallets
  set    coins_balance        = coins_balance - p_bet_amount,
         lifetime_coins_spent = lifetime_coins_spent + p_bet_amount,
         updated_at           = now()
  where  user_id = v_uid
    and  coins_balance >= p_bet_amount
  returning coins_balance into v_new_balance;

  if not found then raise exception 'insufficient_coins'; end if;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_uid, 'room_game_bet', 'debit', -p_bet_amount, 0,
     'Room game bet Ã¢â‚¬â€ ' || v_round.game_code,
     jsonb_build_object('round_id', p_round_id, 'bet_id', v_bet_id,
                        'room_id', v_round.room_id, 'bet_json', p_bet_json));

  insert into public.room_game_bets
    (id, round_id, room_id, user_id, bet_amount, bet_json, status)
  values
    (v_bet_id, p_round_id, v_round.room_id, v_uid, p_bet_amount, p_bet_json, 'pending');

  return jsonb_build_object(
    'bet_id',      v_bet_id,
    'new_balance', v_new_balance
  );
end;
$$;

grant execute on function public.place_room_game_bet(uuid, bigint, jsonb) to authenticated;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 9. RPC: lock_room_game_round Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
-- Host calls this when betting_closes_at has passed.
-- Hungry cat Ã¢â€ â€™ immediately reveals + settles.
-- Crash rocket Ã¢â€ â€™ transitions to 'running' (rocket launches).

create or replace function public.lock_room_game_round(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_round  record;
  v_secret record;
  v_food   record;
  v_result jsonb;
  -- settle variables
  v_bet    record;
  v_win    bigint;
  v_new_bal bigint;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select r.* into v_round
  from public.room_game_rounds r
  where r.id = p_round_id
  for update;

  if not found then raise exception 'round_not_found'; end if;

  -- Only host can lock
  if not exists (
    select 1 from public.rooms where id = v_round.room_id and owner_id = v_uid
  ) then
    raise exception 'not_room_host';
  end if;

  if v_round.status != 'betting_open' then
    raise exception 'round_not_in_betting';
  end if;

  -- Read pre-committed secret
  select * into v_secret from public.room_game_round_secrets
  where round_id = p_round_id;

  if not found then raise exception 'secret_not_found'; end if;

  -- Ã¢â€â‚¬Ã¢â€â‚¬ Hungry Cat: reveal + settle immediately Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  if v_round.game_code = 'hungry_cat' then
    select * into v_food
    from public.hungry_cat_config
    where food_id = v_secret.winning_food_id;

    if not found then raise exception 'winning_food_not_found'; end if;

    v_result := jsonb_build_object(
      'winning_food_id',    v_food.food_id,
      'winning_food_icon',  v_food.icon,
      'winning_food_name',  v_food.name,
      'winning_multiplier', v_food.multiplier,
      'rarity',             v_food.rarity
    );

    -- Settle all bets
    for v_bet in
      select * from public.room_game_bets
      where round_id = p_round_id and status = 'pending'
    loop
      if (v_bet.bet_json->>'food_id') = v_food.food_id then
        v_win := floor(v_bet.bet_amount::float * v_food.multiplier::float)::bigint;
        update public.room_game_bets
        set status = 'won', payout_amount = v_win, settled_at = now()
        where id = v_bet.id;

        update public.wallets
        set coins_balance = coins_balance + v_win, updated_at = now()
        where user_id = v_bet.user_id
        returning coins_balance into v_new_bal;

        insert into public.wallet_transactions
          (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
        values
          (v_bet.user_id, 'room_game_win', 'credit', v_win, 0,
           'Room Hungry Cat win Ã¢â‚¬â€ ' || v_food.name || ' Ãƒâ€”' || v_food.multiplier,
           jsonb_build_object('round_id', p_round_id, 'bet_id', v_bet.id,
                              'food_id', v_food.food_id, 'multiplier', v_food.multiplier));
      else
        update public.room_game_bets
        set status = 'lost', payout_amount = 0, settled_at = now()
        where id = v_bet.id;
      end if;
    end loop;

    -- Reveal seed for provably-fair audit
    update public.room_game_rounds
    set status      = 'finished',
        result_json = v_result,
        seed        = v_secret.raw_seed, -- now revealed
        started_at  = now(),
        finished_at = now(),
        updated_at  = now()
    where id = p_round_id;

    return jsonb_build_object('status', 'finished', 'result', v_result);
  end if;

  -- Ã¢â€â‚¬Ã¢â€â‚¬ Crash Rocket: transition to 'running' (rocket launches) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  if v_round.game_code = 'crash_rocket' then
    -- Mark all pending bets as running
    update public.room_game_bets
    set status = 'running'
    where round_id = p_round_id and status = 'pending';

    update public.room_game_rounds
    set status     = 'running',
        started_at = now(),
        updated_at = now()
    where id = p_round_id;

    return jsonb_build_object('status', 'running', 'started_at', now());
  end if;

  raise exception 'unsupported_game_code';
end;
$$;

grant execute on function public.lock_room_game_round(uuid) to authenticated;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 10. RPC: reveal_room_crash_round Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
-- Called when the crash moment arrives (host Flutter timer fires at reveal_at).
-- Reads crash_multiplier from secrets, settles all bets, reveals result_json.

create or replace function public.reveal_room_crash_round(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_round     record;
  v_secret    record;
  v_crash_m   numeric(10,2);
  v_bet       record;
  v_auto_win  bigint;
  v_new_bal   bigint;
  v_result    jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select r.* into v_round
  from public.room_game_rounds r
  where r.id = p_round_id
  for update;

  if not found then raise exception 'round_not_found'; end if;
  if v_round.game_code != 'crash_rocket' then raise exception 'wrong_game'; end if;
  if v_round.status != 'running' then
    -- Idempotent
    if v_round.status in ('revealed','finished') then
      return jsonb_build_object('status', v_round.status, 'result', v_round.result_json);
    end if;
    raise exception 'round_not_running';
  end if;

  -- Only host can reveal
  if not exists (
    select 1 from public.rooms where id = v_round.room_id and owner_id = v_uid
  ) then
    raise exception 'not_room_host';
  end if;

  -- Server must agree time has passed (prevent premature reveal)
  if v_round.reveal_at is not null and now() < v_round.reveal_at - interval '500 milliseconds' then
    raise exception 'too_early_to_reveal';
  end if;

  select * into v_secret from public.room_game_round_secrets where round_id = p_round_id;
  if not found then raise exception 'secret_not_found'; end if;

  v_crash_m := v_secret.crash_multiplier;

  -- Process bets: auto-cashouts that beat the crash, remainder lost
  for v_bet in
    select * from public.room_game_bets
    where round_id = p_round_id and status = 'running'
    for update
  loop
    declare
      v_auto_m numeric(10,2);
    begin
      v_auto_m := (v_bet.bet_json->>'auto_cashout_multiplier')::numeric(10,2);

      if v_auto_m is not null and v_auto_m < v_crash_m then
        -- Auto-cashout triggers
        v_auto_win := floor(v_bet.bet_amount::float * v_auto_m::float)::bigint;
        update public.room_game_bets
        set status             = 'cashed_out',
            cashout_multiplier = v_auto_m,
            payout_amount      = v_auto_win,
            settled_at         = now()
        where id = v_bet.id;

        update public.wallets
        set coins_balance = coins_balance + v_auto_win, updated_at = now()
        where user_id = v_bet.user_id;

        insert into public.wallet_transactions
          (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
        values
          (v_bet.user_id, 'room_game_win', 'credit', v_auto_win, 0,
           'Room Crash auto-cashout at ' || v_auto_m || 'Ãƒâ€”',
           jsonb_build_object('round_id', p_round_id, 'bet_id', v_bet.id,
                              'auto_multiplier', v_auto_m, 'crash_at', v_crash_m));
      else
        -- Lost
        update public.room_game_bets
        set status = 'lost', payout_amount = 0, settled_at = now()
        where id = v_bet.id;
      end if;
    end;
  end loop;

  v_result := jsonb_build_object('crash_multiplier', v_crash_m);

  update public.room_game_rounds
  set status      = 'finished',
      result_json = v_result,
      seed        = v_secret.raw_seed, -- reveal for fairness audit
      finished_at = now(),
      updated_at  = now()
  where id = p_round_id;

  return jsonb_build_object(
    'status',           'finished',
    'crash_multiplier', v_crash_m,
    'result',           v_result
  );
end;
$$;

grant execute on function public.reveal_room_crash_round(uuid) to authenticated;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 11. RPC: cashout_room_crash_bet Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
-- Player manually cashes out during 'running' state.
-- Server validates: round is still running, multiplier hasn't exceeded crash.

create or replace function public.cashout_room_crash_bet(
  p_bet_id     uuid,
  p_multiplier numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_bet       record;
  v_round     record;
  v_secret    record;
  v_current_m numeric(10,2);
  v_elapsed   float8;
  v_win       bigint;
  v_new_bal   bigint;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_multiplier < 1.0 then raise exception 'invalid_multiplier'; end if;

  select * into v_bet
  from public.room_game_bets
  where id = p_bet_id and user_id = v_uid
  for update;

  if not found then raise exception 'bet_not_found'; end if;
  if v_bet.status = 'cashed_out' then
    return jsonb_build_object('status', 'cashed_out', 'already_settled', true,
                              'payout_amount', v_bet.payout_amount);
  end if;
  if v_bet.status != 'running' then raise exception 'bet_not_cashable'; end if;

  select r.* into v_round
  from public.room_game_rounds r
  where r.id = v_bet.round_id;

  if v_round.status != 'running' then raise exception 'round_not_running'; end if;

  -- Compute server-authoritative current multiplier
  v_elapsed   := greatest(0, extract(epoch from (now() - v_round.started_at)));
  v_current_m := round(exp(0.15 * v_elapsed)::numeric, 2);

  -- Check pre-committed crash point
  select crash_multiplier into v_secret.crash_multiplier
  from public.room_game_round_secrets where round_id = v_bet.round_id;

  if v_current_m >= v_secret.crash_multiplier then
    -- Already crashed Ã¢â‚¬â€ mark as lost
    update public.room_game_bets
    set status = 'lost', payout_amount = 0, settled_at = now()
    where id = p_bet_id;
    return jsonb_build_object('status', 'lost', 'crash_multiplier', v_secret.crash_multiplier);
  end if;

  -- Client-submitted multiplier must not exceed server's current value (prevent cheating)
  declare v_safe_m numeric(10,2);
  begin
    v_safe_m := least(p_multiplier::numeric(10,2), v_current_m);
    v_win    := floor(v_bet.bet_amount::float * v_safe_m::float)::bigint;
  end;

  update public.room_game_bets
  set status             = 'cashed_out',
      cashout_multiplier = v_safe_m,
      payout_amount      = v_win,
      settled_at         = now()
  where id = p_bet_id;

  update public.wallets
  set coins_balance = coins_balance + v_win, updated_at = now()
  where user_id = v_uid
  returning coins_balance into v_new_bal;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_uid, 'room_game_win', 'credit', v_win, 0,
     'Room Crash cashout at ' || v_safe_m || 'Ãƒâ€”',
     jsonb_build_object('round_id', v_bet.round_id, 'bet_id', p_bet_id,
                        'multiplier', v_safe_m));

  return jsonb_build_object(
    'status',             'cashed_out',
    'cashout_multiplier', v_safe_m,
    'payout_amount',      v_win,
    'new_balance',        v_new_bal
  );
end;
$$;

grant execute on function public.cashout_room_crash_bet(uuid, numeric) to authenticated;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 12. RPC: cancel_room_game_round Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
-- Host cancels round and refunds all placed bets.

create or replace function public.cancel_room_game_round(
  p_round_id uuid,
  p_reason   text default 'cancelled_by_host'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid           uuid := auth.uid();
  v_round         record;
  v_bet           record;
  v_refunded_bets int     := 0;
  v_total_refund  bigint  := 0;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select r.* into v_round
  from public.room_game_rounds r
  where r.id = p_round_id
  for update;

  if not found then raise exception 'round_not_found'; end if;

  if not exists (
    select 1 from public.rooms where id = v_round.room_id and owner_id = v_uid
  ) then
    raise exception 'not_room_host';
  end if;

  if v_round.status in ('finished','cancelled') then
    raise exception 'round_already_ended';
  end if;

  -- Refund all non-settled bets
  for v_bet in
    select * from public.room_game_bets
    where round_id = p_round_id
      and status in ('pending','running')
    for update
  loop
    update public.room_game_bets
    set status = 'refunded', settled_at = now()
    where id = v_bet.id;

    update public.wallets
    set coins_balance = coins_balance + v_bet.bet_amount, updated_at = now()
    where user_id = v_bet.user_id;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
    values
      (v_bet.user_id, 'room_game_refund', 'credit', v_bet.bet_amount, 0,
       'Room game refund Ã¢â‚¬â€ ' || p_reason,
       jsonb_build_object('round_id', p_round_id, 'bet_id', v_bet.id));

    v_refunded_bets  := v_refunded_bets + 1;
    v_total_refund   := v_total_refund + v_bet.bet_amount;
  end loop;

  update public.room_game_rounds
  set status      = 'cancelled',
      finished_at = now(),
      updated_at  = now(),
      result_json = jsonb_build_object('cancelled', true, 'reason', p_reason)
  where id = p_round_id;

  return jsonb_build_object(
    'ok',             true,
    'refunded_bets',  v_refunded_bets,
    'total_refund',   v_total_refund
  );
end;
$$;

grant execute on function public.cancel_room_game_round(uuid, text) to authenticated;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 13. RPC: get_active_room_game_round Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
-- Late joiners call this to sync to the current round state.
-- Returns the round + calling user's own bets. result_json only if revealed.

create or replace function public.get_active_room_game_round(
  p_room_id   uuid,
  p_game_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_round record;
  v_bets  jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- Verify room membership
  if not exists (
    select 1 from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = v_uid
      and rm.left_at is null
  ) then
    raise exception 'not_room_member';
  end if;

  select r.* into v_round
  from public.room_game_rounds r
  where r.room_id  = p_room_id
    and r.game_code = p_game_code
    and r.status   not in ('finished','cancelled')
  order by r.created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('active_round', null);
  end if;

  -- User's own bets for this round
  select coalesce(jsonb_agg(to_jsonb(b.*) order by b.created_at), '[]'::jsonb)
  into v_bets
  from public.room_game_bets b
  where b.round_id = v_round.id and b.user_id = v_uid;

  return jsonb_build_object(
    'active_round', jsonb_build_object(
      'id',                 v_round.id,
      'room_id',            v_round.room_id,
      'game_code',          v_round.game_code,
      'round_number',       v_round.round_number,
      'status',             v_round.status,
      'seed_hash',          v_round.seed_hash,
      'result_json',        case
                              when v_round.status in ('revealed','finished')
                              then v_round.result_json
                              else null
                            end,
      'betting_opens_at',   v_round.betting_opens_at,
      'betting_closes_at',  v_round.betting_closes_at,
      'started_at',         v_round.started_at,
      'reveal_at',          v_round.reveal_at,
      'finished_at',        v_round.finished_at,
      'created_at',         v_round.created_at
    ),
    'my_bets', v_bets
  );
end;
$$;

grant execute on function public.get_active_room_game_round(uuid, text) to authenticated;

-- Ã¢â€â‚¬Ã¢â€â‚¬ 14. auto-updated_at trigger Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

create or replace function public._set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end; $$;

drop trigger if exists room_game_rounds_updated_at on public.room_game_rounds;
create trigger room_game_rounds_updated_at
  before update on public.room_game_rounds
  for each row execute function public._set_updated_at();





