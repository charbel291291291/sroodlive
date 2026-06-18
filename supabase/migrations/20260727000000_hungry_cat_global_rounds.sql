-- ─────────────────────────────────────────────────────────────────────────────
-- Hungry Cat Global Rounds
-- Replaces per-session spins with a single shared round that all authenticated
-- users participate in simultaneously.  Per-user tables are untouched.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Sequence for round numbers ────────────────────────────────────────────
create sequence if not exists public.hungry_cat_round_seq start 1;

-- ── 2. Global rounds table ───────────────────────────────────────────────────

create table if not exists public.hungry_cat_global_rounds (
  id                 uuid        primary key default gen_random_uuid(),
  round_number       bigint      not null,
  status             text        not null default 'betting'
                       check (status in ('betting', 'settled')),
  betting_starts_at  timestamptz not null default now(),
  betting_ends_at    timestamptz not null,
  result_reveals_at  timestamptz,
  winning_food_id    text,
  winning_food_icon  text,
  winning_food_name  text,
  winning_multiplier numeric(8,2),
  created_at         timestamptz not null default now()
);

alter table public.hungry_cat_global_rounds enable row level security;

drop policy if exists "global_rounds_select" on public.hungry_cat_global_rounds;
create policy "global_rounds_select"
  on public.hungry_cat_global_rounds for select to authenticated
  using (true);

-- ── 3. Global bets table ─────────────────────────────────────────────────────

create table if not exists public.hungry_cat_global_bets (
  id                uuid        primary key default gen_random_uuid(),
  round_id          uuid        not null
                      references public.hungry_cat_global_rounds(id) on delete cascade,
  user_id           uuid        not null references auth.users(id) on delete cascade,
  food_id           text        not null,
  food_name         text        not null default '',
  food_icon         text        not null default '🍽️',
  multiplier_at_bet numeric(8,2) not null,
  bet_amount        integer     not null check (bet_amount > 0),
  status            text        not null default 'pending'
                      check (status in ('pending','won','lost')),
  win_amount        integer     not null default 0,
  created_at        timestamptz not null default now()
);

alter table public.hungry_cat_global_bets enable row level security;

-- Users may read and insert only their own bets
drop policy if exists "global_bets_select" on public.hungry_cat_global_bets;
create policy "global_bets_select"
  on public.hungry_cat_global_bets for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "global_bets_insert" on public.hungry_cat_global_bets;
create policy "global_bets_insert"
  on public.hungry_cat_global_bets for insert to authenticated
  with check (user_id = auth.uid());

-- ── 4. get_or_create_hungry_cat_round() ──────────────────────────────────────
-- Returns the current active (betting) global round, or creates a new one.
-- Advisory lock prevents two clients from creating duplicate rounds.

create or replace function public.get_or_create_hungry_cat_round()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round  public.hungry_cat_global_rounds;
  v_now    timestamptz := now();
  v_rnum   bigint;
  c_dur    constant int := 12; -- seconds per betting window
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  perform pg_advisory_xact_lock(hashtext('hungry_cat_global_round'));

  -- Return existing active round if it still has time
  select * into v_round
  from public.hungry_cat_global_rounds
  where status = 'betting'
  order by created_at desc
  limit 1;

  if v_round.id is not null and v_round.betting_ends_at > v_now then
    return json_build_object(
      'round_id',           v_round.id,
      'round_number',       v_round.round_number,
      'status',             v_round.status,
      'betting_starts_at',  v_round.betting_starts_at,
      'betting_ends_at',    v_round.betting_ends_at,
      'winning_food_id',    v_round.winning_food_id,
      'winning_food_icon',  v_round.winning_food_icon,
      'winning_food_name',  v_round.winning_food_name,
      'winning_multiplier', v_round.winning_multiplier,
      'server_now',         v_now
    );
  end if;

  -- Create a new round
  v_rnum := nextval('public.hungry_cat_round_seq');

  insert into public.hungry_cat_global_rounds
    (round_number, status, betting_starts_at, betting_ends_at)
  values
    (v_rnum, 'betting', v_now, v_now + (c_dur || ' seconds')::interval)
  returning * into v_round;

  return json_build_object(
    'round_id',           v_round.id,
    'round_number',       v_round.round_number,
    'status',             v_round.status,
    'betting_starts_at',  v_round.betting_starts_at,
    'betting_ends_at',    v_round.betting_ends_at,
    'winning_food_id',    null,
    'winning_food_icon',  null,
    'winning_food_name',  null,
    'winning_multiplier', null,
    'server_now',         v_now
  );
end;
$$;

grant execute on function public.get_or_create_hungry_cat_round() to authenticated;

-- ── 5. place_hungry_cat_global_bet(round_id, food_id, amount) ────────────────

create or replace function public.place_hungry_cat_global_bet(
  p_round_id uuid,
  p_food_id  text,
  p_amount   integer
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid := auth.uid();
  v_round       public.hungry_cat_global_rounds;
  v_food        public.hungry_cat_config;
  v_wallet      public.wallets;
  v_bet_id      uuid;
  v_new_balance integer;
  c_min constant integer := 100;
  c_max constant integer := 100000;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  if not exists (
    select 1 from public.game_settings
    where game_key = 'hungry_cat' and is_enabled
  ) then
    raise exception 'game_disabled';
  end if;

  if p_amount is null or p_amount < c_min or p_amount > c_max then
    raise exception 'invalid_bet_amount';
  end if;

  select * into v_round
  from public.hungry_cat_global_rounds
  where id = p_round_id;

  if v_round.id is null then raise exception 'round_not_found'; end if;

  if v_round.status <> 'betting' or v_round.betting_ends_at <= now() then
    raise exception 'betting_closed';
  end if;

  select * into v_food
  from public.hungry_cat_config
  where food_id = p_food_id and is_active;

  if v_food.id is null then raise exception 'invalid_food'; end if;

  select * into v_wallet
  from public.wallets
  where user_id = v_user_id
  for update;

  if v_wallet is null or v_wallet.coins_balance < p_amount then
    raise exception 'insufficient_coins';
  end if;

  update public.wallets
  set coins_balance        = coins_balance - p_amount,
      lifetime_coins_spent = lifetime_coins_spent + p_amount,
      updated_at           = now()
  where user_id = v_user_id
  returning coins_balance into v_new_balance;

  insert into public.hungry_cat_global_bets
    (round_id, user_id, food_id, food_name, food_icon, multiplier_at_bet, bet_amount, status)
  values
    (p_round_id, v_user_id, p_food_id,
     v_food.name, v_food.icon, v_food.multiplier, p_amount, 'pending')
  returning id into v_bet_id;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_user_id, 'hungry_cat_bet', 'debit', -p_amount, 0,
     'Hungry Cat bet on ' || v_food.name,
     jsonb_build_object('bet_id', v_bet_id, 'round_id', p_round_id, 'food_id', p_food_id));

  return json_build_object(
    'bet_id',      v_bet_id,
    'new_balance', v_new_balance
  );
end;
$$;

grant execute on function public.place_hungry_cat_global_bet(uuid, text, integer) to authenticated;

-- ── 6. settle_hungry_cat_global_round(round_id) ──────────────────────────────
-- Idempotent; safe to call from multiple clients simultaneously.
-- Uses FOR UPDATE to ensure exactly one settlement per round.

create or replace function public.settle_hungry_cat_global_round(
  p_round_id uuid
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_round        public.hungry_cat_global_rounds;
  v_food         public.hungry_cat_config;
  v_total_weight numeric;
  v_roll         numeric;
  v_bet          record;
  v_win_amount   integer;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select * into v_round
  from public.hungry_cat_global_rounds
  where id = p_round_id
  for update;

  if v_round.id is null then raise exception 'round_not_found'; end if;

  -- Idempotent: already settled
  if v_round.status = 'settled' then
    return json_build_object(
      'round_id',           v_round.id,
      'status',             'settled',
      'winning_food_id',    v_round.winning_food_id,
      'winning_food_icon',  v_round.winning_food_icon,
      'winning_food_name',  v_round.winning_food_name,
      'winning_multiplier', v_round.winning_multiplier,
      'server_now',         now()
    );
  end if;

  if v_round.betting_ends_at > now() then
    raise exception 'betting_still_open';
  end if;

  -- Weighted-random food selection (same algorithm as single-spin RPC)
  select coalesce(sum(weight), 0) into v_total_weight
  from public.hungry_cat_config
  where is_active and weight > 0;

  if v_total_weight <= 0 then raise exception 'invalid_food_config'; end if;

  v_roll := random() * v_total_weight;

  select * into v_food
  from (
    select c.*,
           sum(c.weight) over (order by c.sort_order, c.food_id) as cum_weight
    from public.hungry_cat_config c
    where c.is_active and c.weight > 0
  ) ranked
  where ranked.cum_weight >= v_roll
  order by ranked.cum_weight
  limit 1;

  if v_food.id is null then
    select c.* into v_food
    from public.hungry_cat_config c
    where c.is_active and c.weight > 0
    order by c.sort_order desc
    limit 1;
  end if;

  -- Pay out all winning bets; mark losers
  for v_bet in
    select b.id, b.user_id, b.bet_amount, b.food_id
    from public.hungry_cat_global_bets b
    where b.round_id = p_round_id and b.status = 'pending'
  loop
    if v_bet.food_id = v_food.food_id then
      v_win_amount := floor(v_bet.bet_amount * v_food.multiplier)::integer;

      update public.wallets
      set coins_balance = coins_balance + v_win_amount,
          updated_at    = now()
      where user_id = v_bet.user_id;

      update public.hungry_cat_global_bets
      set status = 'won', win_amount = v_win_amount
      where id = v_bet.id;

      insert into public.wallet_transactions
        (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
      values
        (v_bet.user_id, 'hungry_cat_reward', 'credit', v_win_amount, 0,
         'Hungry Cat win: ' || v_food.name || ' x' || v_food.multiplier,
         jsonb_build_object('bet_id', v_bet.id, 'round_id', p_round_id,
                            'food_id', v_food.food_id,
                            'multiplier', v_food.multiplier));
    else
      update public.hungry_cat_global_bets
      set status = 'lost'
      where id = v_bet.id;
    end if;
  end loop;

  update public.hungry_cat_global_rounds
  set status             = 'settled',
      result_reveals_at  = now(),
      winning_food_id    = v_food.food_id,
      winning_food_icon  = v_food.icon,
      winning_food_name  = v_food.name,
      winning_multiplier = v_food.multiplier
  where id = p_round_id;

  return json_build_object(
    'round_id',           p_round_id,
    'status',             'settled',
    'winning_food_id',    v_food.food_id,
    'winning_food_icon',  v_food.icon,
    'winning_food_name',  v_food.name,
    'winning_multiplier', v_food.multiplier,
    'server_now',         now()
  );
end;
$$;

grant execute on function public.settle_hungry_cat_global_round(uuid) to authenticated;

-- ── 7. get_hungry_cat_global_history(limit) ──────────────────────────────────

create or replace function public.get_hungry_cat_global_history(
  p_limit integer default 20
)
returns table (
  food_icon     text,
  food_name     text,
  multiplier    numeric,
  rarity        text,
  reward_amount integer,
  bet_amount    integer,
  created_at    timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  return query
  select
    r.winning_food_icon  as food_icon,
    r.winning_food_name  as food_name,
    r.winning_multiplier as multiplier,
    'common'::text       as rarity,
    0                    as reward_amount,
    0                    as bet_amount,
    r.created_at
  from public.hungry_cat_global_rounds r
  where r.status = 'settled'
    and r.winning_food_id is not null
  order by r.created_at desc
  limit p_limit;
end;
$$;

grant execute on function public.get_hungry_cat_global_history(integer) to authenticated;

-- ── 8. Enable Realtime ───────────────────────────────────────────────────────
alter publication supabase_realtime add table public.hungry_cat_global_rounds;
