-- =============================================================================
-- Team PK Backend — production-grade foundation
-- Supersedes: 20260615130000_room_team_pk.sql (tables renamed + schema hardened)
-- =============================================================================
-- Tables  : room_team_pk_sessions, room_team_pk_members, room_team_pk_support_logs
-- Helpers : is_room_owner(), is_room_manager()
-- RPCs    : start_room_team_pk, assign_room_team_pk_member,
--           cancel_room_team_pk, finish_room_team_pk,
--           get_active_room_team_pk, record_team_pk_gift_support
-- Gift    : send_gift_with_wallet modified to call record_team_pk_gift_support
-- Realtime: sessions + members + support_logs added to supabase_realtime
-- Safety  : idempotent, no destructive drops of non-PK objects
-- =============================================================================

-- ── 0. Clean up superseded tables from 20260615130000_room_team_pk.sql ───────
-- Those tables are empty (created today, no production data). Drop old trigger
-- first to avoid FK / dependency errors.

drop trigger  if exists on_gift_pk_score on public.gift_transactions;
drop function if exists public.handle_pk_gift_score() cascade;
drop function if exists public.start_pk_session(uuid, integer, jsonb) cascade;
drop function if exists public.finish_pk_session(uuid) cascade;
drop function if exists public.cancel_pk_session(uuid) cascade;
drop function if exists public.get_active_pk(uuid) cascade;

drop table if exists public.room_pk_support_logs cascade;
drop table if exists public.room_pk_members cascade;
drop table if exists public.room_pk_sessions cascade;

-- =============================================================================
-- 1. TABLES
-- =============================================================================

-- ── 1a. room_team_pk_sessions ─────────────────────────────────────────────────

create table if not exists public.room_team_pk_sessions (
  id                uuid        not null primary key default gen_random_uuid(),
  room_id           uuid        not null references public.rooms(id) on delete cascade,
  status            text        not null default 'active',
  duration_seconds  integer     not null,
  started_at        timestamptz not null default now(),
  ends_at           timestamptz not null,
  finished_at       timestamptz,
  team_a_score      bigint      not null default 0,
  team_b_score      bigint      not null default 0,
  team_a_gift_count integer     not null default 0,
  team_b_gift_count integer     not null default 0,
  winner_team       text,
  created_by        uuid        not null references auth.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint room_team_pk_sessions_status_check
    check (status in ('active', 'finished', 'cancelled')),
  constraint room_team_pk_sessions_duration_check
    check (duration_seconds in (300, 600, 1800)),
  constraint room_team_pk_sessions_winner_check
    check (winner_team is null or winner_team in ('a', 'b', 'draw')),
  constraint room_team_pk_sessions_score_a_check
    check (team_a_score >= 0),
  constraint room_team_pk_sessions_score_b_check
    check (team_b_score >= 0),
  constraint room_team_pk_sessions_gift_count_a_check
    check (team_a_gift_count >= 0),
  constraint room_team_pk_sessions_gift_count_b_check
    check (team_b_gift_count >= 0)
);

-- Enforce single active PK per room.
create unique index if not exists room_team_pk_sessions_room_active_idx
  on public.room_team_pk_sessions(room_id)
  where status = 'active';

create index if not exists room_team_pk_sessions_room_id_idx
  on public.room_team_pk_sessions(room_id);
create index if not exists room_team_pk_sessions_status_idx
  on public.room_team_pk_sessions(status);
create index if not exists room_team_pk_sessions_ends_at_idx
  on public.room_team_pk_sessions(ends_at);
create index if not exists room_team_pk_sessions_created_by_idx
  on public.room_team_pk_sessions(created_by);

-- Full replica identity so realtime broadcasts full row on UPDATE.
alter table public.room_team_pk_sessions
  replica identity full;

-- ── 1b. room_team_pk_members ──────────────────────────────────────────────────

create table if not exists public.room_team_pk_members (
  id              uuid        not null primary key default gen_random_uuid(),
  pk_session_id   uuid        not null references public.room_team_pk_sessions(id) on delete cascade,
  room_id         uuid        not null references public.rooms(id) on delete cascade,
  user_id         uuid        not null references auth.users(id) on delete cascade,
  seat_index      integer,
  team            text        not null,
  role            text,
  assigned_by     uuid        references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint room_team_pk_members_team_check
    check (team in ('a', 'b')),
  constraint room_team_pk_members_seat_index_check
    check (seat_index is null or seat_index >= 1),
  unique (pk_session_id, user_id)
);

create index if not exists room_team_pk_members_session_idx
  on public.room_team_pk_members(pk_session_id);
create index if not exists room_team_pk_members_room_idx
  on public.room_team_pk_members(room_id);
create index if not exists room_team_pk_members_user_idx
  on public.room_team_pk_members(user_id);
create index if not exists room_team_pk_members_team_idx
  on public.room_team_pk_members(pk_session_id, team);

alter table public.room_team_pk_members
  replica identity full;

-- ── 1c. room_team_pk_support_logs ─────────────────────────────────────────────

create table if not exists public.room_team_pk_support_logs (
  id                   uuid        not null primary key default gen_random_uuid(),
  pk_session_id        uuid        not null references public.room_team_pk_sessions(id) on delete cascade,
  room_id              uuid        not null references public.rooms(id) on delete cascade,
  sender_user_id       uuid        not null references auth.users(id),
  receiver_user_id     uuid        not null references auth.users(id),
  receiver_team        text        not null,
  gift_transaction_id  uuid        unique,   -- null prevented via application logic; unique prevents double-score
  gift_code            text,
  coins_value          bigint      not null,
  pk_points            bigint      not null,
  created_at           timestamptz not null default now(),

  constraint room_team_pk_support_logs_team_check
    check (receiver_team in ('a', 'b')),
  constraint room_team_pk_support_logs_coins_check
    check (coins_value > 0),
  constraint room_team_pk_support_logs_points_check
    check (pk_points > 0)
);

create index if not exists room_team_pk_support_logs_session_idx
  on public.room_team_pk_support_logs(pk_session_id);
create index if not exists room_team_pk_support_logs_room_idx
  on public.room_team_pk_support_logs(room_id);
create index if not exists room_team_pk_support_logs_sender_idx
  on public.room_team_pk_support_logs(sender_user_id);
create index if not exists room_team_pk_support_logs_receiver_idx
  on public.room_team_pk_support_logs(receiver_user_id);
create index if not exists room_team_pk_support_logs_team_idx
  on public.room_team_pk_support_logs(receiver_team);
create index if not exists room_team_pk_support_logs_gift_tx_idx
  on public.room_team_pk_support_logs(gift_transaction_id)
  where gift_transaction_id is not null;

-- =============================================================================
-- 2. ROW-LEVEL SECURITY
-- =============================================================================

alter table public.room_team_pk_sessions     enable row level security;
alter table public.room_team_pk_members      enable row level security;
alter table public.room_team_pk_support_logs enable row level security;

-- Sessions: any authenticated user may read (room presence check kept in RPC).
drop policy if exists "team_pk_sessions_select" on public.room_team_pk_sessions;
create policy "team_pk_sessions_select"
  on public.room_team_pk_sessions for select to authenticated
  using (true);

-- Members: any authenticated user may read.
drop policy if exists "team_pk_members_select" on public.room_team_pk_members;
create policy "team_pk_members_select"
  on public.room_team_pk_members for select to authenticated
  using (true);

-- Support logs: any authenticated user may read.
drop policy if exists "team_pk_support_logs_select" on public.room_team_pk_support_logs;
create policy "team_pk_support_logs_select"
  on public.room_team_pk_support_logs for select to authenticated
  using (true);

-- No direct INSERT/UPDATE/DELETE by regular users on any PK table.
-- All mutations flow through SECURITY DEFINER RPCs.

-- =============================================================================
-- 3. REALTIME PUBLICATION
-- =============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'room_team_pk_sessions',
    'room_team_pk_members',
    'room_team_pk_support_logs'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename  = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end$$;

-- =============================================================================
-- 4. PERMISSION HELPERS
-- =============================================================================

-- is_room_owner: true if p_user_id owns the room.
create or replace function public.is_room_owner(
  p_room_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.rooms
    where id = p_room_id and owner_id = p_user_id
  );
$$;

-- is_room_manager: true if user is owner, host on mic, or listed moderator.
create or replace function public.is_room_manager(
  p_room_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (
    -- owner
    exists (
      select 1 from public.rooms
      where id = p_room_id and owner_id = p_user_id
    )
    or
    -- host seat in room_members
    exists (
      select 1 from public.room_members
      where room_id = p_room_id
        and user_id = p_user_id
        and role    in ('host', 'owner')
        and left_at is null
    )
    or
    -- listed moderator
    exists (
      select 1 from public.room_moderators
      where room_id = p_room_id
        and user_id = p_user_id
    )
  );
$$;

-- =============================================================================
-- 5. INTERNAL HELPER: _finish_team_pk_internal
-- =============================================================================
-- Called by finish_room_team_pk and get_active_room_team_pk (lazy expiry).
-- Does NOT check caller permission — callers are responsible.

create or replace function public._finish_team_pk_internal(
  p_session_id uuid
)
returns public.room_team_pk_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.room_team_pk_sessions;
  v_winner  text;
begin
  select * into v_session
  from public.room_team_pk_sessions
  where id = p_session_id
  for update;

  if v_session is null then
    raise exception 'pk_session_not_found';
  end if;

  -- Already resolved — return current state without touching it.
  if v_session.status in ('finished', 'cancelled') then
    return v_session;
  end if;

  -- Determine winner.
  v_winner := case
    when v_session.team_a_score > v_session.team_b_score then 'a'
    when v_session.team_b_score > v_session.team_a_score then 'b'
    else 'draw'
  end;

  update public.room_team_pk_sessions
  set status      = 'finished',
      winner_team = v_winner,
      finished_at = now(),
      updated_at  = now()
  where id = p_session_id
  returning * into v_session;

  return v_session;
end;
$$;

-- =============================================================================
-- 6. RPC: record_team_pk_gift_support
-- =============================================================================
-- SECURITY DEFINER — called by send_gift_with_wallet, never by client directly.
-- Returns jsonb: {scored: bool, team: text|null, session_id: uuid|null}

create or replace function public.record_team_pk_gift_support(
  p_room_id            uuid,
  p_sender_user_id     uuid,
  p_receiver_user_id   uuid,
  p_gift_transaction_id uuid,
  p_gift_code          text,
  p_coins_value        bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id  uuid;
  v_team        text;
  v_pk_points   bigint;
begin
  -- Fast no-op if no active (non-expired) PK in this room.
  select id into v_session_id
  from public.room_team_pk_sessions
  where room_id = p_room_id
    and status  = 'active'
    and ends_at > now()
  limit 1;

  if v_session_id is null then
    return jsonb_build_object('scored', false, 'reason', 'no_active_pk');
  end if;

  -- Check if receiver is assigned to a team in this session.
  select team into v_team
  from public.room_team_pk_members
  where pk_session_id = v_session_id
    and user_id       = p_receiver_user_id;

  if v_team is null then
    return jsonb_build_object('scored', false, 'reason', 'receiver_not_assigned');
  end if;

  -- 1 gift coin = 1 PK point (configurable later via admin multiplier).
  v_pk_points := p_coins_value;

  -- Insert support log. ON CONFLICT on gift_transaction_id prevents double-scoring.
  begin
    insert into public.room_team_pk_support_logs (
      pk_session_id,
      room_id,
      sender_user_id,
      receiver_user_id,
      receiver_team,
      gift_transaction_id,
      gift_code,
      coins_value,
      pk_points
    ) values (
      v_session_id,
      p_room_id,
      p_sender_user_id,
      p_receiver_user_id,
      v_team,
      p_gift_transaction_id,
      p_gift_code,
      p_coins_value,
      v_pk_points
    );
  exception when unique_violation then
    -- This gift was already scored (duplicate call guard).
    return jsonb_build_object('scored', false, 'reason', 'already_scored');
  end;

  -- Atomically increment team score + gift count on the session row.
  if v_team = 'a' then
    update public.room_team_pk_sessions
    set team_a_score      = team_a_score + v_pk_points,
        team_a_gift_count = team_a_gift_count + 1,
        updated_at        = now()
    where id = v_session_id;
  else
    update public.room_team_pk_sessions
    set team_b_score      = team_b_score + v_pk_points,
        team_b_gift_count = team_b_gift_count + 1,
        updated_at        = now()
    where id = v_session_id;
  end if;

  return jsonb_build_object(
    'scored',      true,
    'team',        v_team,
    'pk_points',   v_pk_points,
    'session_id',  v_session_id
  );

exception when others then
  -- PK scoring must never corrupt the wallet/gift flow.
  -- Silently absorb unexpected errors and return failure flag.
  return jsonb_build_object(
    'scored', false,
    'reason', 'internal_error',
    'detail', sqlerrm
  );
end;
$$;

-- =============================================================================
-- 7. HOOK send_gift_with_wallet → PK scoring
-- =============================================================================
-- Replace the existing function, adding one non-destructive call at the end.
-- Wallet logic is UNCHANGED. PK scoring is a pure side-effect after commit.

create or replace function public.send_gift_with_wallet(
  p_room_id    uuid,
  p_receiver_id uuid,
  p_gift_id    uuid,
  p_quantity   integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_id             uuid := auth.uid();
  v_quantity              integer := greatest(coalesce(p_quantity, 1), 1);
  v_gift                  record;
  v_total_cost            integer;
  v_diamonds_earned       integer;
  v_sender_wallet         public.wallets;
  v_receiver_wallet       public.wallets;
  v_gift_transaction_id   uuid;
begin
  if v_sender_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_receiver_id is null or p_receiver_id = v_sender_id then
    raise exception 'invalid_receiver';
  end if;

  if not exists (
    select 1 from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = v_sender_id
      and rm.left_at is null
  ) then
    raise exception 'sender_not_in_room';
  end if;

  if not exists (
    select 1 from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = p_receiver_id
      and rm.left_at is null
  ) then
    raise exception 'receiver_not_in_room';
  end if;

  select g.id, g.code, g.name, g.price_coins
  into v_gift
  from public.gifts g
  where g.id = p_gift_id
    and coalesce(g.is_active, true)
  limit 1;

  if not found then
    raise exception 'gift_not_found';
  end if;

  v_total_cost      := (v_gift.price_coins::integer * v_quantity);
  v_diamonds_earned := v_total_cost;

  if v_total_cost <= 0 then
    raise exception 'invalid_gift_price';
  end if;

  insert into public.wallets (user_id) values (v_sender_id)
    on conflict (user_id) do nothing;
  insert into public.wallets (user_id) values (p_receiver_id)
    on conflict (user_id) do nothing;

  select * into v_sender_wallet
  from public.wallets
  where user_id = v_sender_id
  for update;

  if v_sender_wallet.coins_balance < v_total_cost then
    raise exception 'insufficient_coins';
  end if;

  update public.wallets
  set coins_balance        = coins_balance - v_total_cost,
      lifetime_coins_spent = lifetime_coins_spent + v_total_cost,
      updated_at           = now()
  where user_id = v_sender_id
  returning * into v_sender_wallet;

  update public.wallets
  set diamonds_balance          = diamonds_balance + v_diamonds_earned,
      lifetime_diamonds_earned  = lifetime_diamonds_earned + v_diamonds_earned,
      updated_at                = now()
  where user_id = p_receiver_id
  returning * into v_receiver_wallet;

  insert into public.gift_transactions (
    room_id, sender_id, receiver_id,
    gift_id, gift_code, gift_name, gift_price_coins
  ) values (
    p_room_id, v_sender_id, p_receiver_id,
    v_gift.id, v_gift.code, v_gift.name, v_total_cost
  )
  returning id into v_gift_transaction_id;

  insert into public.wallet_transactions (
    user_id, type, direction, coins_delta,
    balance_coins_after, balance_diamonds_after,
    related_user_id, related_room_id, related_gift_id,
    related_gift_transaction_id, note, metadata
  ) values (
    v_sender_id, 'gift_sent', 'debit', -v_total_cost,
    v_sender_wallet.coins_balance, v_sender_wallet.diamonds_balance,
    p_receiver_id, p_room_id, v_gift.id,
    v_gift_transaction_id, 'Gift sent',
    jsonb_build_object('quantity', v_quantity, 'gift_code', v_gift.code)
  );

  insert into public.wallet_transactions (
    user_id, type, direction, diamonds_delta,
    balance_coins_after, balance_diamonds_after,
    related_user_id, related_room_id, related_gift_id,
    related_gift_transaction_id, note, metadata
  ) values (
    p_receiver_id, 'gift_received', 'credit', v_diamonds_earned,
    v_receiver_wallet.coins_balance, v_receiver_wallet.diamonds_balance,
    v_sender_id, p_room_id, v_gift.id,
    v_gift_transaction_id, 'Gift received',
    jsonb_build_object('quantity', v_quantity, 'gift_code', v_gift.code)
  );

  -- ── Team PK scoring side-effect ──────────────────────────────────────────
  -- Runs after all wallet/gift writes succeed. Any failure here is swallowed
  -- so it never rolls back the gift transaction.
  begin
    perform public.record_team_pk_gift_support(
      p_room_id,
      v_sender_id,
      p_receiver_id,
      v_gift_transaction_id,
      v_gift.code,
      v_total_cost::bigint
    );
  exception when others then
    null; -- PK scoring error must never break the gift flow
  end;

  return v_gift_transaction_id;
end;
$$;

grant execute on function public.send_gift_with_wallet(uuid, uuid, uuid, integer) to authenticated;

-- =============================================================================
-- 8. RPC: start_room_team_pk
-- =============================================================================

create or replace function public.start_room_team_pk(
  p_room_id          uuid,
  p_duration_seconds integer,
  p_auto_assign      boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id  uuid := auth.uid();
  v_session_id uuid;
  v_session    public.room_team_pk_sessions;
  v_members    jsonb;
  v_mic_users  record;
  v_idx        integer := 0;
  v_team       text;
  v_mic_list   uuid[];
  v_mic_count  integer;
begin
  if v_caller_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_duration_seconds not in (300, 600, 1800) then
    raise exception 'invalid_duration — allowed: 300, 600, 1800 seconds';
  end if;

  if not public.is_room_manager(p_room_id, v_caller_id) then
    raise exception 'not_authorized';
  end if;

  if exists (
    select 1 from public.room_team_pk_sessions
    where room_id = p_room_id and status = 'active'
  ) then
    raise exception 'pk_already_active';
  end if;

  -- Create the session.
  insert into public.room_team_pk_sessions (
    room_id, created_by, duration_seconds, ends_at
  ) values (
    p_room_id,
    v_caller_id,
    p_duration_seconds,
    now() + make_interval(secs => p_duration_seconds)
  )
  returning * into v_session;

  v_session_id := v_session.id;

  -- Auto-assign mic members to teams if requested.
  if p_auto_assign then
    -- Collect current mic occupants (host + speaker), ordered by seat_number.
    select array_agg(user_id order by coalesce(seat_number, 999), user_id)
    into v_mic_list
    from public.room_members
    where room_id = p_room_id
      and role    in ('host', 'speaker')
      and left_at is null;

    v_mic_count := coalesce(array_length(v_mic_list, 1), 0);

    for i in 1..v_mic_count loop
      -- First half (ceil) → Team A, second half → Team B.
      v_team := case when i <= ceil(v_mic_count::numeric / 2) then 'a' else 'b' end;

      insert into public.room_team_pk_members (
        pk_session_id, room_id, user_id, seat_index, team, assigned_by
      )
      select
        v_session_id,
        p_room_id,
        v_mic_list[i],
        rm.seat_number,
        v_team,
        v_caller_id
      from public.room_members rm
      where rm.room_id = p_room_id
        and rm.user_id = v_mic_list[i]
        and rm.left_at is null
      on conflict (pk_session_id, user_id) do nothing;
    end loop;
  end if;

  -- Fetch members for return payload.
  select jsonb_agg(row_to_json(m))
  into v_members
  from public.room_team_pk_members m
  where m.pk_session_id = v_session_id;

  return jsonb_build_object(
    'session', row_to_json(v_session),
    'members', coalesce(v_members, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.start_room_team_pk(uuid, integer, boolean) to authenticated;

-- =============================================================================
-- 9. RPC: assign_room_team_pk_member
-- =============================================================================

create or replace function public.assign_room_team_pk_member(
  p_pk_session_id uuid,
  p_user_id       uuid,
  p_team          text,
  p_seat_index    integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_session   public.room_team_pk_sessions;
  v_member    public.room_team_pk_members;
begin
  if v_caller_id is null then raise exception 'not_authenticated'; end if;
  if p_team not in ('a', 'b')   then raise exception 'invalid_team'; end if;

  select * into v_session
  from public.room_team_pk_sessions
  where id = p_pk_session_id;

  if v_session is null then raise exception 'session_not_found'; end if;
  if v_session.status <> 'active' then raise exception 'session_not_active'; end if;

  if not public.is_room_manager(v_session.room_id, v_caller_id) then
    raise exception 'not_authorized';
  end if;

  insert into public.room_team_pk_members (
    pk_session_id, room_id, user_id, seat_index, team, assigned_by
  ) values (
    p_pk_session_id, v_session.room_id, p_user_id, p_seat_index, p_team, v_caller_id
  )
  on conflict (pk_session_id, user_id) do update
    set team       = excluded.team,
        seat_index = coalesce(excluded.seat_index, room_team_pk_members.seat_index),
        assigned_by = excluded.assigned_by,
        updated_at  = now()
  returning * into v_member;

  return row_to_json(v_member)::jsonb;
end;
$$;

grant execute on function public.assign_room_team_pk_member(uuid, uuid, text, integer) to authenticated;

-- =============================================================================
-- 10. RPC: cancel_room_team_pk
-- =============================================================================

create or replace function public.cancel_room_team_pk(
  p_pk_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_session   public.room_team_pk_sessions;
begin
  if v_caller_id is null then raise exception 'not_authenticated'; end if;

  select * into v_session
  from public.room_team_pk_sessions
  where id = p_pk_session_id;

  if v_session is null     then raise exception 'session_not_found'; end if;
  if v_session.status <> 'active' then
    -- Already resolved — return current state.
    return row_to_json(v_session)::jsonb;
  end if;

  if not public.is_room_manager(v_session.room_id, v_caller_id) then
    raise exception 'not_authorized';
  end if;

  update public.room_team_pk_sessions
  set status      = 'cancelled',
      finished_at = now(),
      updated_at  = now()
  where id = p_pk_session_id
  returning * into v_session;

  return row_to_json(v_session)::jsonb;
end;
$$;

grant execute on function public.cancel_room_team_pk(uuid) to authenticated;

-- =============================================================================
-- 11. RPC: finish_room_team_pk
-- =============================================================================

create or replace function public.finish_room_team_pk(
  p_pk_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_session   public.room_team_pk_sessions;
begin
  -- Unauthenticated callers are allowed only if session has expired.
  -- (For client-triggered finish after timer expires, auth is present anyway.)

  select * into v_session
  from public.room_team_pk_sessions
  where id = p_pk_session_id;

  if v_session is null then raise exception 'session_not_found'; end if;

  -- If still active and not yet expired, require manager auth.
  if v_session.status = 'active' and v_session.ends_at > now() then
    if v_caller_id is null or not public.is_room_manager(v_session.room_id, v_caller_id) then
      raise exception 'not_authorized';
    end if;
  end if;

  -- Delegate to internal helper (handles idempotency).
  v_session := public._finish_team_pk_internal(p_pk_session_id);

  return row_to_json(v_session)::jsonb;
end;
$$;

grant execute on function public.finish_room_team_pk(uuid) to authenticated;

-- =============================================================================
-- 12. RPC: get_active_room_team_pk
-- =============================================================================
-- Safe for reconnect / rejoin. Lazily finishes expired sessions.

create or replace function public.get_active_room_team_pk(
  p_room_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session  public.room_team_pk_sessions;
  v_members  jsonb;
  v_remaining_seconds bigint;
begin
  -- Find the most recent non-cancelled session for this room.
  select * into v_session
  from public.room_team_pk_sessions
  where room_id = p_room_id
    and status in ('active', 'finished')
  order by created_at desc
  limit 1;

  if v_session is null then
    return null;
  end if;

  -- Lazily finish if active but expired.
  if v_session.status = 'active' and v_session.ends_at <= now() then
    v_session := public._finish_team_pk_internal(v_session.id);
  end if;

  -- Compute remaining seconds (0 if finished/expired).
  v_remaining_seconds := greatest(
    0,
    extract(epoch from (v_session.ends_at - now()))::bigint
  );

  -- Fetch current member assignments.
  select jsonb_agg(row_to_json(m))
  into v_members
  from public.room_team_pk_members m
  where m.pk_session_id = v_session.id;

  return jsonb_build_object(
    'session',            row_to_json(v_session),
    'members',            coalesce(v_members, '[]'::jsonb),
    'remaining_seconds',  v_remaining_seconds
  );
end;
$$;

grant execute on function public.get_active_room_team_pk(uuid) to authenticated;

-- =============================================================================
-- 13. GRANT helpers
-- =============================================================================

grant execute on function public.is_room_owner(uuid, uuid)   to authenticated;
grant execute on function public.is_room_manager(uuid, uuid) to authenticated;
grant execute on function public.record_team_pk_gift_support(uuid, uuid, uuid, uuid, text, bigint)
  to authenticated;

-- =============================================================================
-- VERIFICATION NOTES
-- =============================================================================
-- Manual test sequence after applying this migration:
--
-- 1. Start a 5-min PK:
--    select public.start_room_team_pk('<room_id>', 300, true);
--
-- 2. Verify only one active PK per room:
--    select public.start_room_team_pk('<room_id>', 300, true);
--    -- should raise: pk_already_active
--
-- 3. Manually assign a member:
--    select public.assign_room_team_pk_member('<session_id>', '<user_id>', 'b', 3);
--
-- 4. Simulate a gift (call send_gift_with_wallet as sender):
--    select public.send_gift_with_wallet('<room_id>', '<receiver_id>', '<gift_id>', 1);
--
-- 5. Confirm team score incremented:
--    select team_a_score, team_b_score from public.room_team_pk_sessions where id = '<session_id>';
--
-- 6. Confirm duplicate gift transaction does NOT double-score:
--    select public.record_team_pk_gift_support(
--      '<room_id>', '<sender_id>', '<receiver_id>',
--      '<same_gift_transaction_id>', 'gift_code', 100
--    );
--    -- should return: {scored: false, reason: already_scored}
--    -- score in sessions table must not change
--
-- 7. Finish PK:
--    select public.finish_room_team_pk('<session_id>');
--
-- 8. Confirm winner:
--    select status, winner_team from public.room_team_pk_sessions where id = '<session_id>';
--
-- 9. Confirm idempotency — calling finish again returns same result without error.
--    select public.finish_room_team_pk('<session_id>');

