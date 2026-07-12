-- ─────────────────────────────────────────────────────────────────────────────
-- Team PK battle system.
-- Tables: room_pk_sessions, room_pk_members, room_pk_support_logs
-- Trigger: gift_transactions → auto-score for active PK sessions
-- RPCs: start_pk_session, finish_pk_session, cancel_pk_session, get_active_pk
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Tables ───────────────────────────────────────────────────────────────────

create table if not exists public.room_pk_sessions (
  id               uuid        primary key default gen_random_uuid(),
  room_id          uuid        not null references public.rooms(id) on delete cascade,
  created_by       uuid        not null references auth.users(id),
  status           text        not null default 'active'
                               check (status in ('active', 'finished', 'cancelled')),
  duration_seconds integer     not null check (duration_seconds > 0),
  started_at       timestamptz not null default now(),
  ends_at          timestamptz not null,
  finished_at      timestamptz,
  team_a_score     integer     not null default 0 check (team_a_score >= 0),
  team_b_score     integer     not null default 0 check (team_b_score >= 0),
  winner_team      text        check (winner_team in ('a', 'b', 'draw')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- Enforce one active PK per room.
create unique index if not exists room_pk_sessions_room_active
  on public.room_pk_sessions(room_id)
  where status = 'active';

create index if not exists room_pk_sessions_room_id_idx
  on public.room_pk_sessions(room_id);

create table if not exists public.room_pk_members (
  id              uuid        primary key default gen_random_uuid(),
  pk_session_id   uuid        not null references public.room_pk_sessions(id) on delete cascade,
  user_id         uuid        not null references auth.users(id),
  seat_number     integer     not null check (seat_number >= 1),
  team            text        not null check (team in ('a', 'b')),
  display_name    text,
  avatar_url      text,
  pk_score        integer     not null default 0 check (pk_score >= 0),
  created_at      timestamptz not null default now(),
  unique (pk_session_id, user_id)
);

create index if not exists room_pk_members_session_idx
  on public.room_pk_members(pk_session_id);

create table if not exists public.room_pk_support_logs (
  id                   uuid        primary key default gen_random_uuid(),
  pk_session_id        uuid        not null references public.room_pk_sessions(id) on delete cascade,
  gift_transaction_id  uuid        references public.gift_transactions(id),
  sender_user_id       uuid        not null references auth.users(id),
  receiver_user_id     uuid        not null references auth.users(id),
  receiver_team        text        not null check (receiver_team in ('a', 'b')),
  coins_value          integer     not null default 0 check (coins_value >= 0),
  created_at           timestamptz not null default now()
);

create index if not exists room_pk_support_logs_session_idx
  on public.room_pk_support_logs(pk_session_id);

-- ── RLS ──────────────────────────────────────────────────────────────────────

alter table public.room_pk_sessions    enable row level security;
alter table public.room_pk_members     enable row level security;
alter table public.room_pk_support_logs enable row level security;

-- Sessions: all authenticated users can read; write via RPCs only.
drop policy if exists "pk_sessions_read" on public.room_pk_sessions;
create policy "pk_sessions_read" on public.room_pk_sessions
  for select to authenticated using (true);

-- Members: all authenticated users can read.
drop policy if exists "pk_members_read" on public.room_pk_members;
create policy "pk_members_read" on public.room_pk_members
  for select to authenticated using (true);

-- Support logs: all authenticated users can read.
drop policy if exists "pk_support_read" on public.room_pk_support_logs;
create policy "pk_support_read" on public.room_pk_support_logs
  for select to authenticated using (true);

-- ── Realtime ─────────────────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and tablename = 'room_pk_sessions'
  ) then
    alter publication supabase_realtime add table public.room_pk_sessions;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and tablename = 'room_pk_members'
  ) then
    alter publication supabase_realtime add table public.room_pk_members;
  end if;
end$$;

-- ── Gift scoring trigger ──────────────────────────────────────────────────────

create or replace function public.handle_pk_gift_score()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id  uuid;
  v_team        text;
  v_coins       integer;
begin
  v_coins := coalesce(NEW.gift_price_coins, 0);
  if v_coins <= 0 then return NEW; end if;

  -- Find active PK in this room that hasn't expired yet.
  select id into v_session_id
  from public.room_pk_sessions
  where room_id = NEW.room_id
    and status   = 'active'
    and ends_at  > now()
  limit 1;

  if v_session_id is null then return NEW; end if;

  -- Check if the gift receiver is a registered PK member.
  select team into v_team
  from public.room_pk_members
  where pk_session_id = v_session_id
    and user_id       = NEW.receiver_id;

  if v_team is null then return NEW; end if;

  -- Log the support action.
  insert into public.room_pk_support_logs (
    pk_session_id, gift_transaction_id,
    sender_user_id, receiver_user_id, receiver_team, coins_value
  ) values (
    v_session_id, NEW.id,
    NEW.sender_id, NEW.receiver_id, v_team, v_coins
  )
  on conflict do nothing;

  -- Increment member personal score.
  update public.room_pk_members
  set pk_score = pk_score + v_coins
  where pk_session_id = v_session_id
    and user_id       = NEW.receiver_id;

  -- Increment session team total.
  if v_team = 'a' then
    update public.room_pk_sessions
    set team_a_score = team_a_score + v_coins,
        updated_at   = now()
    where id = v_session_id;
  else
    update public.room_pk_sessions
    set team_b_score = team_b_score + v_coins,
        updated_at   = now()
    where id = v_session_id;
  end if;

  return NEW;
end;
$$;

drop trigger if exists on_gift_pk_score on public.gift_transactions;
create trigger on_gift_pk_score
  after insert on public.gift_transactions
  for each row execute function public.handle_pk_gift_score();

-- ── RPCs ──────────────────────────────────────────────────────────────────────

-- start_pk_session: host/owner creates a new PK session with team assignments.
-- p_assignments: [{"user_id":"...","seat_number":1,"team":"a",...}, ...]
create or replace function public.start_pk_session(
  p_room_id         uuid,
  p_duration_seconds integer,
  p_assignments     jsonb   -- array of {user_id, seat_number, team, display_name?, avatar_url?}
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_session_id uuid;
  v_member     jsonb;
begin
  -- Must be authenticated.
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- Must be room host or owner.
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id
      and user_id = v_uid
      and role    in ('host', 'owner')
      and left_at is null
  ) and not exists (
    select 1 from public.rooms
    where id = p_room_id and owner_id = v_uid
  ) then
    raise exception 'not_authorized';
  end if;

  -- Only one active PK per room.
  if exists (
    select 1 from public.room_pk_sessions
    where room_id = p_room_id and status = 'active'
  ) then
    raise exception 'pk_already_active';
  end if;

  -- At least one assignment required.
  if p_assignments is null or jsonb_array_length(p_assignments) = 0 then
    raise exception 'no_members_assigned';
  end if;

  -- Create the session.
  insert into public.room_pk_sessions (
    room_id, created_by, duration_seconds,
    started_at, ends_at
  ) values (
    p_room_id, v_uid, p_duration_seconds,
    now(), now() + make_interval(secs => p_duration_seconds)
  )
  returning id into v_session_id;

  -- Insert member assignments.
  for v_member in select * from jsonb_array_elements(p_assignments)
  loop
    insert into public.room_pk_members (
      pk_session_id, user_id, seat_number, team, display_name, avatar_url
    ) values (
      v_session_id,
      (v_member->>'user_id')::uuid,
      (v_member->>'seat_number')::integer,
      v_member->>'team',
      v_member->>'display_name',
      v_member->>'avatar_url'
    )
    on conflict (pk_session_id, user_id) do nothing;
  end loop;

  return v_session_id;
end;
$$;

-- finish_pk_session: host or server-side auto-finish when time expires.
create or replace function public.finish_pk_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_session public.room_pk_sessions;
  v_winner  text;
begin
  select * into v_session
  from public.room_pk_sessions
  where id = p_session_id;

  if v_session is null then return; end if;
  if v_session.status != 'active' then return; end if;

  -- Only creator, room owner, or expired session can be finished by any member.
  if v_uid is not null and v_uid != v_session.created_by then
    if not exists (
      select 1 from public.rooms
      where id = v_session.room_id and owner_id = v_uid
    ) then
      -- Allow finish if time has expired (any authenticated user can close expired PK).
      if v_session.ends_at > now() then
        raise exception 'not_authorized';
      end if;
    end if;
  end if;

  -- Compute winner.
  v_winner := case
    when v_session.team_a_score > v_session.team_b_score then 'a'
    when v_session.team_b_score > v_session.team_a_score then 'b'
    else 'draw'
  end;

  update public.room_pk_sessions
  set status      = 'finished',
      finished_at = now(),
      winner_team = v_winner,
      updated_at  = now()
  where id = p_session_id
    and status = 'active';
end;
$$;

-- cancel_pk_session: host/owner cancels PK early without announcing a winner.
create or replace function public.cancel_pk_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_session public.room_pk_sessions;
begin
  select * into v_session
  from public.room_pk_sessions
  where id = p_session_id;

  if v_session is null then return; end if;
  if v_session.status != 'active' then return; end if;

  if v_uid != v_session.created_by and not exists (
    select 1 from public.rooms
    where id = v_session.room_id and owner_id = v_uid
  ) then
    raise exception 'not_authorized';
  end if;

  update public.room_pk_sessions
  set status     = 'cancelled',
      updated_at = now()
  where id = p_session_id
    and status = 'active';
end;
$$;

-- get_active_pk: returns full session + members for a room in a single call.
create or replace function public.get_active_pk(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.room_pk_sessions;
  v_members jsonb;
begin
  select * into v_session
  from public.room_pk_sessions
  where room_id = p_room_id
    and status  = 'active'
  limit 1;

  if v_session is null then return null; end if;

  select jsonb_agg(row_to_json(m)) into v_members
  from public.room_pk_members m
  where m.pk_session_id = v_session.id;

  return jsonb_build_object(
    'session', row_to_json(v_session),
    'members', coalesce(v_members, '[]'::jsonb)
  );
end;
$$;

