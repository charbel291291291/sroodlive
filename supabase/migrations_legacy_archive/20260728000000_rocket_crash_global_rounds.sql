-- ─────────────────────────────────────────────────────────────────────────────
-- Rocket Crash Global Rounds
-- Replaces per-user/local JS rounds with a single shared round visible to all
-- authenticated users simultaneously.  Old crash_rounds/crash_bets tables are
-- kept untouched (backward compat for any outstanding per-user bets).
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Sequence
create sequence if not exists public.rocket_crash_round_seq start 1;

-- 2. Global rounds table
create table if not exists public.rocket_crash_global_rounds (
  id                uuid        primary key default gen_random_uuid(),
  round_number      bigint      not null,
  status            text        not null default 'betting'
                      check (status in ('betting', 'flying', 'crashed')),
  betting_starts_at timestamptz not null default now(),
  betting_ends_at   timestamptz not null,
  flight_starts_at  timestamptz,
  crashed_at        timestamptz,
  crash_multiplier  numeric(10,2),   -- null until flight starts, then revealed
  created_at        timestamptz not null default now()
);

alter table public.rocket_crash_global_rounds enable row level security;

drop policy if exists "rcgr_select" on public.rocket_crash_global_rounds;
create policy "rcgr_select"
  on public.rocket_crash_global_rounds for select to authenticated
  using (true);

-- 3. Global bets table
create table if not exists public.rocket_crash_global_bets (
  id                      uuid        primary key default gen_random_uuid(),
  round_id                uuid        not null
                            references public.rocket_crash_global_rounds(id) on delete cascade,
  user_id                 uuid        not null references auth.users(id) on delete cascade,
  display_name            text,
  bet_amount              integer     not null check (bet_amount > 0),
  auto_cashout_multiplier numeric(10,2),
  cashout_multiplier      numeric(10,2),
  win_amount              integer     not null default 0,
  status                  text        not null default 'active'
                            check (status in ('active', 'cashed_out', 'lost')),
  cashed_out_at           timestamptz,
  created_at              timestamptz not null default now()
);

alter table public.rocket_crash_global_bets enable row level security;

-- All authenticated players can view the bet feed
drop policy if exists "rcgb_select" on public.rocket_crash_global_bets;
create policy "rcgb_select"
  on public.rocket_crash_global_bets for select to authenticated
  using (true);

drop policy if exists "rcgb_insert" on public.rocket_crash_global_bets;
create policy "rcgb_insert"
  on public.rocket_crash_global_bets for insert to authenticated
  with check (user_id = auth.uid());

-- 4. get_or_create_rocket_crash_round()
-- Returns the current active round (betting or flying, not stale), or creates
-- a new 8-second betting window.  Advisory lock prevents duplicate creation.
create or replace function public.get_or_create_rocket_crash_round()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round  public.rocket_crash_global_rounds;
  v_now    timestamptz := now();
  v_rnum   bigint;
  c_bet_s  constant int := 8;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  perform pg_advisory_xact_lock(hashtext('rocket_crash_global_round'));

  -- Current betting round (not expired)
  select * into v_round
  from public.rocket_crash_global_rounds
  where status = 'betting' and betting_ends_at > v_now
  order by created_at desc
  limit 1;

  if v_round.id is null then
    -- Current flying round (not stale — max flight ~95s for 200× crash)
    select * into v_round
    from public.rocket_crash_global_rounds
    where status = 'flying'
      and flight_starts_at > v_now - interval '120 seconds'
    order by created_at desc
    limit 1;
  end if;

  if v_round.id is not null then
    return json_build_object(
      'round_id',          v_round.id,
      'round_number',      v_round.round_number,
      'status',            v_round.status,
      'betting_ends_at',   extract(epoch from v_round.betting_ends_at) * 1000,
      'flight_starts_at',  case when v_round.flight_starts_at is not null
                               then extract(epoch from v_round.flight_starts_at) * 1000
                               else null end,
      'crash_multiplier',  v_round.crash_multiplier,
      'server_now',        extract(epoch from v_now) * 1000
    );
  end if;

  -- Create new betting round
  v_rnum := nextval('public.rocket_crash_round_seq');
  insert into public.rocket_crash_global_rounds
    (round_number, status, betting_starts_at, betting_ends_at)
  values
    (v_rnum, 'betting', v_now, v_now + (c_bet_s || ' seconds')::interval)
  returning * into v_round;

  return json_build_object(
    'round_id',         v_round.id,
    'round_number',     v_round.round_number,
    'status',           'betting',
    'betting_ends_at',  extract(epoch from v_round.betting_ends_at) * 1000,
    'flight_starts_at', null,
    'crash_multiplier', null,
    'server_now',       extract(epoch from v_now) * 1000
  );
end;
$$;
grant execute on function public.get_or_create_rocket_crash_round() to authenticated;

-- 5. place_rocket_crash_bet(round_id, amount, auto_cashout_multiplier)
create or replace function public.place_rocket_crash_bet(
  p_round_id    uuid,
  p_amount      integer,
  p_auto_cashout numeric default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_round       public.rocket_crash_global_rounds;
  v_bet_id      uuid;
  v_new_balance integer;
  v_dname       text;
  c_min constant integer := 100;
  c_max constant integer := 100000;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  if not exists (select 1 from public.game_settings where game_key = 'crash_rocket' and is_enabled) then
    raise exception 'game_disabled';
  end if;

  if p_amount is null or p_amount < c_min or p_amount > c_max then
    raise exception 'invalid_bet_amount';
  end if;

  if p_auto_cashout is not null and p_auto_cashout < 1.01 then
    raise exception 'invalid_auto_cashout';
  end if;

  select * into v_round from public.rocket_crash_global_rounds where id = p_round_id;
  if v_round.id is null then raise exception 'round_not_found'; end if;
  if v_round.status <> 'betting' or v_round.betting_ends_at <= now() then
    raise exception 'betting_closed';
  end if;

  update public.wallets
  set coins_balance        = coins_balance - p_amount,
      lifetime_coins_spent = lifetime_coins_spent + p_amount,
      updated_at           = now()
  where user_id = v_uid
    and coins_balance >= p_amount
  returning coins_balance into v_new_balance;

  if not found then raise exception 'insufficient_coins'; end if;

  select coalesce(display_name, username, 'Player') into v_dname
  from public.profiles where id = v_uid;

  insert into public.rocket_crash_global_bets
    (round_id, user_id, display_name, bet_amount, auto_cashout_multiplier, status)
  values
    (p_round_id, v_uid, v_dname, p_amount, p_auto_cashout, 'active')
  returning id into v_bet_id;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_uid, 'crash_rocket_bet', 'debit', -p_amount, 0,
     'Rocket Crash bet',
     jsonb_build_object('round_id', p_round_id, 'bet_id', v_bet_id));

  return json_build_object(
    'bet_id',      v_bet_id,
    'new_balance', v_new_balance
  );
end;
$$;
grant execute on function public.place_rocket_crash_bet(uuid, integer, numeric) to authenticated;

-- 6. start_rocket_crash_flight(round_id)
-- Idempotent.  Transitions betting → flying, commits the server crash point.
-- Multiplier formula: exp(0.055 * elapsed_seconds) — matches the JS client.
create or replace function public.start_rocket_crash_flight(p_round_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round  public.rocket_crash_global_rounds;
  v_rand   numeric;
  v_crash  numeric;
  v_now    timestamptz := now();
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  select * into v_round
  from public.rocket_crash_global_rounds
  where id = p_round_id for update;

  if v_round.id is null then raise exception 'round_not_found'; end if;

  -- Idempotent: already flying
  if v_round.status = 'flying' then
    return json_build_object(
      'flight_starts_at', extract(epoch from v_round.flight_starts_at) * 1000,
      'crash_multiplier', v_round.crash_multiplier,
      'server_now',       extract(epoch from v_now) * 1000
    );
  end if;

  if v_round.status = 'crashed' then raise exception 'round_already_crashed'; end if;

  -- Generate crash multiplier (same distribution as JS genCrash)
  v_rand := random();
  if v_rand < 0.04 then
    v_crash := 1.00;
  elsif v_rand < 0.08 then
    v_crash := round((1.00 + random() * 0.04)::numeric, 2);
  else
    v_crash := round(greatest(1.01, least(200.00, 0.96 / (1 - v_rand)))::numeric, 2);
  end if;

  update public.rocket_crash_global_rounds
  set status           = 'flying',
      flight_starts_at = v_now,
      crash_multiplier = v_crash
  where id = p_round_id;

  return json_build_object(
    'flight_starts_at', extract(epoch from v_now) * 1000,
    'crash_multiplier', v_crash,
    'server_now',       extract(epoch from v_now) * 1000
  );
end;
$$;
grant execute on function public.start_rocket_crash_flight(uuid) to authenticated;

-- 7. cash_out_rocket_crash_bet(bet_id)
-- Server-calculated multiplier.  Locks round first, then bet, to avoid deadlock
-- with settle_rocket_crash_round which also locks the round row.
create or replace function public.cash_out_rocket_crash_bet(p_bet_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_bet         public.rocket_crash_global_bets;
  v_round       public.rocket_crash_global_rounds;
  v_elapsed     numeric;
  v_current_m   numeric;
  v_win         integer;
  v_new_balance integer;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- Fetch bet (not locked yet — just to get round_id)
  select * into v_bet
  from public.rocket_crash_global_bets
  where id = p_bet_id and user_id = v_uid;

  if not found then raise exception 'bet_not_found'; end if;

  -- Lock round first to prevent deadlock with settle (settle also locks round)
  select * into v_round
  from public.rocket_crash_global_rounds
  where id = v_bet.round_id for update;

  if v_round.id is null then raise exception 'round_not_found'; end if;

  -- Now lock the bet row
  select * into v_bet
  from public.rocket_crash_global_bets
  where id = p_bet_id and user_id = v_uid for update;

  -- Idempotent: already settled
  if v_bet.status <> 'active' then
    return json_build_object(
      'status',             v_bet.status,
      'cashout_multiplier', v_bet.cashout_multiplier,
      'win_amount',         v_bet.win_amount
    );
  end if;

  -- Round crashed before cashout arrived
  if v_round.status = 'crashed' then
    update public.rocket_crash_global_bets set status = 'lost' where id = p_bet_id;
    return json_build_object('status', 'lost', 'cashout_multiplier', null, 'win_amount', 0);
  end if;

  if v_round.status <> 'flying' then raise exception 'round_not_flying'; end if;

  -- Server-calculated multiplier: exp(0.055 * elapsed_seconds)
  v_elapsed   := greatest(0, extract(epoch from (now() - v_round.flight_starts_at)));
  v_current_m := round(exp(0.055 * v_elapsed)::numeric, 2);

  -- Cashout arrived after crash point (race with settle)
  if v_current_m >= v_round.crash_multiplier then
    update public.rocket_crash_global_bets set status = 'lost' where id = p_bet_id;
    return json_build_object('status', 'lost', 'cashout_multiplier', null, 'win_amount', 0);
  end if;

  v_win := floor(v_bet.bet_amount * v_current_m)::integer;

  update public.rocket_crash_global_bets
  set status             = 'cashed_out',
      cashout_multiplier = v_current_m,
      win_amount         = v_win,
      cashed_out_at      = now()
  where id = p_bet_id;

  update public.wallets
  set coins_balance = coins_balance + v_win, updated_at = now()
  where user_id = v_uid
  returning coins_balance into v_new_balance;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_uid, 'crash_rocket_win', 'credit', v_win, 0,
     'Rocket Crash cashout at ' || v_current_m || '×',
     jsonb_build_object('bet_id', p_bet_id, 'round_id', v_bet.round_id, 'multiplier', v_current_m));

  return json_build_object(
    'status',             'cashed_out',
    'cashout_multiplier', v_current_m,
    'win_amount',         v_win,
    'new_balance',        v_new_balance
  );
end;
$$;
grant execute on function public.cash_out_rocket_crash_bet(uuid) to authenticated;

-- 8. settle_rocket_crash_round(round_id)
-- Idempotent.  Processes auto-cashouts for qualifying bets, marks rest lost,
-- transitions round to 'crashed', triggering Realtime update for all clients.
create or replace function public.settle_rocket_crash_round(p_round_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round  public.rocket_crash_global_rounds;
  v_bet    record;
  v_win    integer;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  select * into v_round
  from public.rocket_crash_global_rounds
  where id = p_round_id for update;

  if v_round.id is null then raise exception 'round_not_found'; end if;

  -- Idempotent
  if v_round.status = 'crashed' then
    return json_build_object('status', 'crashed', 'crash_multiplier', v_round.crash_multiplier);
  end if;

  if v_round.status <> 'flying' then raise exception 'round_not_flying'; end if;

  -- Pay auto-cashout bets whose target is at or below the crash multiplier
  for v_bet in
    select b.* from public.rocket_crash_global_bets b
    where b.round_id = p_round_id
      and b.status = 'active'
      and b.auto_cashout_multiplier is not null
      and b.auto_cashout_multiplier <= v_round.crash_multiplier
  loop
    v_win := floor(v_bet.bet_amount * v_bet.auto_cashout_multiplier)::integer;

    update public.rocket_crash_global_bets
    set status             = 'cashed_out',
        cashout_multiplier = v_bet.auto_cashout_multiplier,
        win_amount         = v_win,
        cashed_out_at      = now()
    where id = v_bet.id;

    update public.wallets
    set coins_balance = coins_balance + v_win, updated_at = now()
    where user_id = v_bet.user_id;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
    values
      (v_bet.user_id, 'crash_rocket_win', 'credit', v_win, 0,
       'Rocket Crash auto-cashout at ' || v_bet.auto_cashout_multiplier || '×',
       jsonb_build_object('bet_id', v_bet.id, 'round_id', p_round_id,
                          'multiplier', v_bet.auto_cashout_multiplier, 'auto', true));
  end loop;

  -- Mark remaining active bets as lost
  update public.rocket_crash_global_bets
  set status = 'lost'
  where round_id = p_round_id and status = 'active';

  update public.rocket_crash_global_rounds
  set status     = 'crashed',
      crashed_at = now()
  where id = p_round_id;

  return json_build_object('status', 'crashed', 'crash_multiplier', v_round.crash_multiplier);
end;
$$;
grant execute on function public.settle_rocket_crash_round(uuid) to authenticated;

-- 9. get_rocket_crash_recent_results(limit)
create or replace function public.get_rocket_crash_recent_results(p_limit integer default 20)
returns table (
  crash_multiplier numeric,
  crashed_at       timestamptz
)
language plpgsql stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
  select r.crash_multiplier, r.crashed_at
  from public.rocket_crash_global_rounds r
  where r.status = 'crashed' and r.crash_multiplier is not null
  order by r.crashed_at desc
  limit p_limit;
end;
$$;
grant execute on function public.get_rocket_crash_recent_results(integer) to authenticated;

-- 10. get_rocket_crash_round_bets(round_id)
-- Returns the bet feed for a round (display_name sanitised, no private info).
create or replace function public.get_rocket_crash_round_bets(p_round_id uuid)
returns table (
  bet_id                  uuid,
  display_name            text,
  bet_amount              integer,
  auto_cashout_multiplier numeric,
  cashout_multiplier      numeric,
  win_amount              integer,
  status                  text,
  is_own                  boolean
)
language plpgsql stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  return query
  select b.id,
         b.display_name,
         b.bet_amount,
         b.auto_cashout_multiplier,
         b.cashout_multiplier,
         b.win_amount,
         b.status,
         (b.user_id = v_uid)
  from public.rocket_crash_global_bets b
  where b.round_id = p_round_id
  order by b.created_at desc
  limit 50;
end;
$$;
grant execute on function public.get_rocket_crash_round_bets(uuid) to authenticated;

-- 11. Enable Realtime (Flutter subscribes to this table for round phase changes)
alter publication supabase_realtime add table public.rocket_crash_global_rounds;
