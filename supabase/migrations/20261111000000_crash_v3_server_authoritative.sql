-- Crash Rocket V3: isolated server-authoritative storage and security boundary.
-- The client has no direct write access. Secret seed material is never exposed
-- through a client-readable table or realtime publication.

create extension if not exists pgcrypto with schema extensions;

create sequence public.crash_v3_public_round_id_seq as bigint start 100000;
create sequence public.crash_v3_nonce_seq as bigint start 1;

create table public.crash_v3_settings (
  singleton boolean primary key default true check (singleton),
  game_enabled boolean not null default false,
  maintenance_mode boolean not null default false,
  emergency_stop boolean not null default false,
  minimum_bet bigint not null default 100 check (minimum_bet > 0),
  maximum_bet bigint not null default 100000 check (maximum_bet >= minimum_bet and maximum_bet <= 2000000000),
  maximum_payout_per_bet bigint not null default 1000000 check (maximum_payout_per_bet > 0 and maximum_payout_per_bet <= 2000000000),
  maximum_total_round_exposure bigint not null default 10000000 check (maximum_total_round_exposure > 0),
  betting_duration_ms integer not null default 8000 check (betting_duration_ms between 3000 and 60000),
  locked_duration_ms integer not null default 2000 check (locked_duration_ms between 500 and 10000),
  waiting_duration_ms integer not null default 4000 check (waiting_duration_ms between 1000 and 30000),
  settlement_timeout_ms integer not null default 3000 check (settlement_timeout_ms between 1000 and 30000),
  inter_round_delay_ms integer not null default 2000 check (inter_round_delay_ms between 500 and 30000),
  house_edge_bps integer not null default 300 check (house_edge_bps between 0 and 2500),
  maximum_multiplier numeric(12,2) not null default 1000.00 check (maximum_multiplier between 1.01 and 100000.00),
  default_growth_rate numeric(12,8) not null default 0.065 check (default_growth_rate > 0 and default_growth_rate <= 1),
  auto_refund_on_engine_failure boolean not null default true,
  daily_user_loss_limit bigint not null default 1000000 check (daily_user_loss_limit > 0),
  daily_user_wager_limit bigint not null default 2000000 check (daily_user_wager_limit > 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp()
);

insert into public.crash_v3_settings (singleton) values (true);

create table public.crash_v3_rounds (
  id uuid primary key default extensions.gen_random_uuid(),
  public_round_id bigint not null unique default nextval('public.crash_v3_public_round_id_seq'),
  nonce bigint not null unique default nextval('public.crash_v3_nonce_seq'),
  status text not null check (status in ('waiting','betting','locked','flying','crashed','settling','settled','cancelled')),
  starts_at timestamptz not null,
  betting_opens_at timestamptz,
  betting_closes_at timestamptz,
  flight_started_at timestamptz,
  crashed_at timestamptz,
  settlement_started_at timestamptz,
  settled_at timestamptz,
  cancelled_at timestamptz,
  crash_multiplier numeric(12,2) check (crash_multiplier is null or crash_multiplier >= 1.00),
  server_seed_hash text not null check (server_seed_hash ~ '^[0-9a-f]{64}$'),
  encrypted_server_seed text not null,
  revealed_server_seed text,
  client_seed text not null check (length(client_seed) between 1 and 256),
  result_hash text check (result_hash is null or result_hash ~ '^[0-9a-f]{64}$'),
  growth_rate numeric(12,8) not null check (growth_rate > 0 and growth_rate <= 1),
  house_edge_bps integer not null check (house_edge_bps between 0 and 2500),
  maximum_multiplier numeric(12,2) not null check (maximum_multiplier between 1.01 and 100000.00),
  total_wagered bigint not null default 0 check (total_wagered >= 0),
  total_paid bigint not null default 0 check (total_paid >= 0),
  total_refunded bigint not null default 0 check (total_refunded >= 0),
  bet_count integer not null default 0 check (bet_count >= 0),
  cashout_count integer not null default 0 check (cashout_count >= 0),
  engine_instance_id text,
  failure_reason text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (betting_closes_at is null or betting_opens_at is not null),
  check (flight_started_at is null or betting_closes_at is not null),
  check (revealed_server_seed is null or status in ('settled','cancelled'))
);

create table public.crash_v3_bets (
  id uuid primary key default extensions.gen_random_uuid(),
  round_id uuid not null references public.crash_v3_rounds(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  slot_number integer not null check (slot_number in (1,2)),
  bet_amount bigint not null check (bet_amount > 0 and bet_amount <= 2000000000),
  auto_cashout_multiplier numeric(12,2) check (auto_cashout_multiplier is null or auto_cashout_multiplier >= 1.01),
  status text not null default 'pending' check (status in ('pending','accepted','won','lost','refunded','rejected','cancelled')),
  placed_at timestamptz not null default clock_timestamp(),
  accepted_at timestamptz,
  cashout_requested_at timestamptz,
  cashed_out_at timestamptz,
  cashout_multiplier numeric(12,2) check (cashout_multiplier is null or cashout_multiplier >= 1.00),
  payout_amount bigint not null default 0 check (payout_amount >= 0 and payout_amount <= 2000000000),
  refunded_at timestamptz,
  idempotency_key text not null check (length(idempotency_key) between 16 and 128),
  cashout_idempotency_key text check (cashout_idempotency_key is null or length(cashout_idempotency_key) between 16 and 128),
  client_request_id text,
  wallet_transaction_id uuid references public.wallet_transactions(id) on delete restrict,
  payout_transaction_id uuid references public.wallet_transactions(id) on delete restrict,
  failure_reason text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (round_id, user_id, slot_number),
  unique (user_id, idempotency_key),
  unique (user_id, cashout_idempotency_key)
);

create table public.crash_v3_round_events (
  id bigint generated always as identity primary key,
  round_id uuid not null references public.crash_v3_rounds(id) on delete cascade,
  event_type text not null check (event_type in ('round_created','betting_opened','betting_locked','flight_started','bet_accepted','cashout_confirmed','auto_cashout_confirmed','round_crashed','round_settling','round_settled','round_cancelled','settings_changed','emergency_stop')),
  event_sequence bigint not null check (event_sequence > 0),
  event_payload jsonb not null default '{}'::jsonb,
  server_timestamp timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  engine_instance_id text,
  unique (round_id, event_sequence)
);

create table public.crash_v3_engine_leases (
  lease_key text primary key,
  engine_instance_id text not null,
  acquired_at timestamptz not null,
  heartbeat_at timestamptz not null,
  expires_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb,
  check (expires_at > heartbeat_at)
);

create table public.crash_v3_audit_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_role text not null,
  action text not null,
  round_id uuid references public.crash_v3_rounds(id) on delete set null,
  bet_id uuid references public.crash_v3_bets(id) on delete set null,
  before_data jsonb,
  after_data jsonb,
  request_id text,
  ip_hash text,
  user_agent_hash text,
  created_at timestamptz not null default clock_timestamp()
);

create table public.crash_v3_daily_user_limits (
  user_id uuid not null references auth.users(id) on delete restrict,
  limit_date date not null,
  wagered_amount bigint not null default 0 check (wagered_amount >= 0),
  lost_amount bigint not null default 0 check (lost_amount >= 0),
  paid_amount bigint not null default 0 check (paid_amount >= 0),
  bet_count integer not null default 0 check (bet_count >= 0),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, limit_date)
);

create table public.crash_v3_financial_reconciliation (
  id uuid primary key default extensions.gen_random_uuid(),
  round_id uuid not null unique references public.crash_v3_rounds(id) on delete restrict,
  expected_total_wagered bigint not null,
  actual_total_debited bigint not null,
  expected_total_paid bigint not null,
  actual_total_credited bigint not null,
  expected_total_refunded bigint not null,
  actual_total_refunded bigint not null,
  reconciliation_status text not null check (reconciliation_status in ('matched','mismatch','resolved')),
  mismatch_details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null
);

create index crash_v3_rounds_status_created_idx on public.crash_v3_rounds(status, created_at desc);
create index crash_v3_bets_round_idx on public.crash_v3_bets(round_id);
create index crash_v3_bets_user_created_idx on public.crash_v3_bets(user_id, created_at desc);
create index crash_v3_bets_round_status_idx on public.crash_v3_bets(round_id, status);
create index crash_v3_bets_idempotency_idx on public.crash_v3_bets(user_id, idempotency_key);
create index crash_v3_events_round_sequence_idx on public.crash_v3_round_events(round_id, event_sequence);
create index crash_v3_audit_created_idx on public.crash_v3_audit_logs(created_at desc);
create index crash_v3_audit_user_idx on public.crash_v3_audit_logs(actor_user_id, created_at desc);
create index crash_v3_reconciliation_status_idx on public.crash_v3_financial_reconciliation(reconciliation_status, created_at desc);
create index crash_v3_lease_expiry_idx on public.crash_v3_engine_leases(expires_at);

alter table public.crash_v3_settings enable row level security;
alter table public.crash_v3_rounds enable row level security;
alter table public.crash_v3_bets enable row level security;
alter table public.crash_v3_round_events enable row level security;
alter table public.crash_v3_engine_leases enable row level security;
alter table public.crash_v3_audit_logs enable row level security;
alter table public.crash_v3_daily_user_limits enable row level security;
alter table public.crash_v3_financial_reconciliation enable row level security;

create policy crash_v3_bets_read_own on public.crash_v3_bets for select to authenticated using (user_id = (select auth.uid()));
create policy crash_v3_events_read_authenticated on public.crash_v3_round_events for select to authenticated using (true);

revoke all on public.crash_v3_settings, public.crash_v3_rounds,
  public.crash_v3_bets, public.crash_v3_round_events,
  public.crash_v3_engine_leases, public.crash_v3_audit_logs,
  public.crash_v3_daily_user_limits,
  public.crash_v3_financial_reconciliation from public, anon, authenticated;
grant select on public.crash_v3_bets, public.crash_v3_round_events to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.crash_v3_bets;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.crash_v3_round_events;
exception when duplicate_object then null; end $$;
alter table public.crash_v3_bets replica identity full;
alter table public.crash_v3_round_events replica identity full;

comment on table public.crash_v3_rounds is 'Crash V3 authoritative rounds. RPC-only reads prevent encrypted seed exposure.';
comment on column public.crash_v3_rounds.encrypted_server_seed is 'Ciphertext supplied and recoverable only by the trusted engine; never client-readable.';
comment on table public.crash_v3_bets is 'Two-slot player bets. Direct writes are revoked; wallet-safe RPCs are mandatory.';
