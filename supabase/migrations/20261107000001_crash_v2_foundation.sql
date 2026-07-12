-- =============================================================================
-- Crash Rocket v2 — foundation: tables, RLS, grants, config, feature flag,
-- realtime publication membership.
--
-- Design principles (see docs/CRASH_ROCKET_V2.md):
--   * All client access goes through SECURITY DEFINER RPCs; API roles get NO
--     table write privileges anywhere and NO read on secrets/config/audit.
--   * Provably fair: each round pre-commits sha256(server_seed) as
--     server_seed_hash at open; the seed itself lives in crash_v2_round_secrets
--     (definer-only) and is copied into crash_v2_rounds.server_seed ONLY when
--     the round completes. Verification: recompute
--     sha256(server_seed || ':' || client_seed || ':' || nonce) -> first 52
--     bits -> u -> floor((house_edge_factor / (1-u)) * 100) / 100, clamped to
--     [1.00, max_multiplier].
--   * Mechanics preserved from the retired generation: 0.97 house-edge factor,
--     52-bit roll, exp(growth_rate * t) flight curve (growth_rate 0.09),
--     8s betting, bets 100..1,000,000 coins, slots 1..2, auto-cashout
--     1.01..1000, shared wallets + immutable wallet_transactions ledger.
--   * Feature flag: game_settings row 'crash_rocket_v2' seeded is_enabled=false
--     (server-controlled kill switch; the game ships DISABLED).
-- =============================================================================

-- ── Rounds (public state; realtime-published) ────────────────────────────────
create sequence if not exists public.crash_v2_round_number_seq;

create table if not exists public.crash_v2_rounds (
  id                uuid primary key default gen_random_uuid(),
  room_id           uuid references public.rooms(id) on delete cascade,
  public_round_number bigint not null default nextval('public.crash_v2_round_number_seq'),
  status            text not null default 'waiting'
                    check (status in ('waiting','betting_open','betting_locked',
                                      'flying','crashed','settling','completed')),
  betting_open_at   timestamptz not null,
  betting_close_at  timestamptz not null,
  started_at        timestamptz,          -- flight start
  crashed_at        timestamptz,
  completed_at      timestamptz,
  crash_multiplier  numeric(12,2) check (crash_multiplier is null or crash_multiplier >= 1.00),
  server_seed_hash  text not null,
  server_seed       text,                 -- revealed ONLY at completion
  client_seed       text not null default '',
  nonce             bigint not null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (betting_close_at > betting_open_at)
);

comment on table public.crash_v2_rounds is
  'Crash Rocket v2 rounds. server_seed is NULL until the round completes (provably fair reveal).';

create index if not exists crash_v2_rounds_scope_active_idx
  on public.crash_v2_rounds (room_id, public_round_number desc);
create index if not exists crash_v2_rounds_status_idx
  on public.crash_v2_rounds (status)
  where status <> 'completed';

-- ── Round secrets (definer-only; never granted, never published) ─────────────
create table if not exists public.crash_v2_round_secrets (
  round_id          uuid primary key references public.crash_v2_rounds(id) on delete cascade,
  server_seed       text not null,
  target_multiplier numeric(12,2) not null check (target_multiplier >= 1.00),
  target_crashed_at timestamptz,           -- set when flight starts
  created_at        timestamptz not null default now()
);

comment on table public.crash_v2_round_secrets is
  'Crash Rocket v2 pre-committed seed + derived crash target. Definer-only; no API role has any privilege.';

-- ── Bets (one row per user/slot/round; cashout recorded on the bet) ──────────
create table if not exists public.crash_v2_bets (
  id                      uuid primary key default gen_random_uuid(),
  round_id                uuid not null references public.crash_v2_rounds(id) on delete cascade,
  user_id                 uuid not null references public.profiles(id) on delete cascade,
  bet_slot                integer not null check (bet_slot in (1,2)),
  amount                  integer not null check (amount > 0),
  auto_cashout_multiplier numeric(12,2)
                          check (auto_cashout_multiplier is null
                                 or (auto_cashout_multiplier >= 1.01
                                     and auto_cashout_multiplier <= 1000.00)),
  status                  text not null default 'placed'
                          check (status in ('placed','cashed_out','lost','canceled','refunded')),
  cashout_multiplier      numeric(12,2),
  payout                  integer check (payout is null or payout >= 0),
  idempotency_key         text not null,
  cashout_idempotency_key text,
  created_at              timestamptz not null default now(),
  cashed_out_at           timestamptz,
  settled_at              timestamptz,
  unique (user_id, idempotency_key),
  unique (round_id, user_id, bet_slot)
);

create index if not exists crash_v2_bets_round_status_idx
  on public.crash_v2_bets (round_id, status);
create index if not exists crash_v2_bets_user_created_idx
  on public.crash_v2_bets (user_id, created_at desc);
create unique index if not exists crash_v2_bets_cashout_idem_idx
  on public.crash_v2_bets (user_id, cashout_idempotency_key)
  where cashout_idempotency_key is not null;

-- ── Round events (public activity feed; realtime-published) ──────────────────
create table if not exists public.crash_v2_round_events (
  id          bigint generated always as identity primary key,
  round_id    uuid not null references public.crash_v2_rounds(id) on delete cascade,
  event_type  text not null
              check (event_type in ('round_opened','betting_locked','flight_started',
                                    'bet_placed','bet_canceled','bet_cashed_out',
                                    'round_crashed','round_completed','round_voided',
                                    'game_paused','game_resumed')),
  payload     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists crash_v2_round_events_round_idx
  on public.crash_v2_round_events (round_id, id desc);

-- ── Game config (single row per scope; read via RPC only) ────────────────────
create table if not exists public.crash_v2_config (
  singleton              boolean primary key default true check (singleton),
  is_paused              boolean not null default false,
  maintenance_message    text,
  waiting_seconds        integer not null default 3  check (waiting_seconds between 1 and 60),
  betting_seconds        integer not null default 8  check (betting_seconds between 3 and 60),
  lock_seconds           integer not null default 1  check (lock_seconds between 0 and 10),
  crash_display_seconds  integer not null default 4  check (crash_display_seconds between 1 and 30),
  growth_rate            numeric(6,4) not null default 0.0900
                         check (growth_rate > 0 and growth_rate <= 1),
  house_edge_factor      numeric(6,4) not null default 0.9700
                         check (house_edge_factor > 0.5 and house_edge_factor < 1),
  max_multiplier         numeric(12,2) not null default 1000.00
                         check (max_multiplier between 2 and 10000),
  min_bet                integer not null default 100     check (min_bet > 0),
  max_bet                integer not null default 1000000 check (max_bet > 0),
  max_payout             integer not null default 1000000000 check (max_payout > 0),
  min_auto_cashout       numeric(12,2) not null default 1.01,
  max_auto_cashout       numeric(12,2) not null default 1000.00,
  updated_at             timestamptz not null default now(),
  updated_by             uuid,
  check (max_bet >= min_bet),
  check (max_auto_cashout >= min_auto_cashout)
);

insert into public.crash_v2_config (singleton) values (true)
on conflict (singleton) do nothing;

-- ── Admin audit trail (append-only; read via admin RPC only) ─────────────────
create table if not exists public.crash_v2_admin_actions (
  id          bigint generated always as identity primary key,
  admin_id    uuid not null,
  action      text not null,
  detail      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create or replace function public._crash_v2_admin_actions_immutable()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'crash_v2_admin_actions is append-only';
end;
$$;
revoke all on function public._crash_v2_admin_actions_immutable() from public, anon, authenticated;

drop trigger if exists crash_v2_admin_actions_immutable on public.crash_v2_admin_actions;
create trigger crash_v2_admin_actions_immutable
  before update or delete on public.crash_v2_admin_actions
  for each row execute function public._crash_v2_admin_actions_immutable();

-- ── RLS: fail-closed everywhere; reads only where safe ───────────────────────
alter table public.crash_v2_rounds         enable row level security;
alter table public.crash_v2_round_secrets  enable row level security;
alter table public.crash_v2_bets           enable row level security;
alter table public.crash_v2_round_events   enable row level security;
alter table public.crash_v2_config         enable row level security;
alter table public.crash_v2_admin_actions  enable row level security;

-- Rounds: public state, readable by signed-in users (needed for realtime).
drop policy if exists crash_v2_rounds_read on public.crash_v2_rounds;
create policy crash_v2_rounds_read on public.crash_v2_rounds
  for select to authenticated using (true);

-- Events: aggregated public activity, readable by signed-in users (realtime).
drop policy if exists crash_v2_events_read on public.crash_v2_round_events;
create policy crash_v2_events_read on public.crash_v2_round_events
  for select to authenticated using (true);

-- Bets: each user can read ONLY their own bets. No insert/update/delete.
drop policy if exists crash_v2_bets_read_own on public.crash_v2_bets;
create policy crash_v2_bets_read_own on public.crash_v2_bets
  for select to authenticated using (user_id = (select auth.uid()));

-- Secrets, config, admin actions: NO policies -> no API-role access at all.

-- ── Grants: fail-closed. SELECT only where RLS allows; zero writes ────────────
revoke all on table public.crash_v2_rounds         from public, anon, authenticated;
revoke all on table public.crash_v2_round_secrets  from public, anon, authenticated;
revoke all on table public.crash_v2_bets           from public, anon, authenticated;
revoke all on table public.crash_v2_round_events   from public, anon, authenticated;
revoke all on table public.crash_v2_config         from public, anon, authenticated;
revoke all on table public.crash_v2_admin_actions  from public, anon, authenticated;
revoke all on sequence public.crash_v2_round_number_seq from public, anon, authenticated;

grant select on table public.crash_v2_rounds       to authenticated;
grant select on table public.crash_v2_round_events to authenticated;
grant select on table public.crash_v2_bets         to authenticated;

-- ── Feature flag: ships DISABLED (server-controlled kill switch) ─────────────
insert into public.game_settings (game_key, is_enabled)
values ('crash_rocket_v2', false)
on conflict (game_key) do nothing;

-- ── Realtime publication membership (rounds + events only; never bets,
--    secrets, config, or audit) ────────────────────────────────────────────────
do $$
declare
  v_tbl text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return; -- platform provides it; nothing to do in bare validation containers
  end if;
  foreach v_tbl in array array['crash_v2_rounds','crash_v2_round_events'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = v_tbl
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_tbl);
    end if;
  end loop;
end $$;

-- Full row images so realtime UPDATE payloads carry all round fields.
alter table public.crash_v2_rounds replica identity full;
