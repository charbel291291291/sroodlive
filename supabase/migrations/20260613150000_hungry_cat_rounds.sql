-- ────────────────────────────────────────────────────────────────────────────
-- Hungry Cat Wheel — automatic betting rounds
--   Each Flutter session creates its own round. Users bet on multiple foods
--   during the 10-second betting window. When the window closes, the server
--   picks a weighted-random winning food and pays out bets placed on it.
--   All coin logic lives here — the WebView only animates results.
-- ────────────────────────────────────────────────────────────────────────────

-- ── 1. hungry_cat_rounds ─────────────────────────────────────────────────────

create table if not exists public.hungry_cat_rounds (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  status              text not null default 'betting'
                        check (status in ('betting','locked','completed')),
  winning_food_id     text,
  winning_food_icon   text,
  winning_food_name   text,
  winning_food_rarity text,
  winning_multiplier  numeric(8,2),
  betting_ends_at     timestamptz not null,
  completed_at        timestamptz,
  created_at          timestamptz not null default now()
);

alter table public.hungry_cat_rounds enable row level security;

drop policy if exists "hungry_cat_rounds_own" on public.hungry_cat_rounds;
create policy "hungry_cat_rounds_own"
  on public.hungry_cat_rounds for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ── 2. hungry_cat_bets ───────────────────────────────────────────────────────

create table if not exists public.hungry_cat_bets (
  id               uuid primary key default gen_random_uuid(),
  round_id         uuid not null references public.hungry_cat_rounds(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  food_id          text not null,
  food_name        text not null,
  food_icon        text not null default '🍽️',
  multiplier_at_bet numeric(8,2) not null,
  bet_amount       integer not null check (bet_amount > 0),
  status           text not null default 'pending'
                     check (status in ('pending','won','lost','refunded')),
  win_amount       integer not null default 0,
  created_at       timestamptz not null default now()
);

alter table public.hungry_cat_bets enable row level security;

drop policy if exists "hungry_cat_bets_own" on public.hungry_cat_bets;
create policy "hungry_cat_bets_own"
  on public.hungry_cat_bets for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ── 3. start_hungry_cat_round ────────────────────────────────────────────────

create or replace function public.start_hungry_cat_round()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_round_id uuid := gen_random_uuid();
  v_ends_at  timestamptz := now() + interval '12 seconds';
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Check game is enabled
  if exists (
    select 1 from public.game_settings
    where game_key = 'hungry_cat' and is_enabled = false
  ) then
    raise exception 'game_disabled';
  end if;

  insert into public.hungry_cat_rounds
    (id, user_id, status, betting_ends_at)
  values
    (v_round_id, v_user_id, 'betting', v_ends_at);

  return jsonb_build_object(
    'round_id',       v_round_id,
    'betting_ends_at', v_ends_at
  );
end;
$$;

grant execute on function public.start_hungry_cat_round() to authenticated;

-- ── 4. place_hungry_cat_bet ──────────────────────────────────────────────────

create or replace function public.place_hungry_cat_bet(
  p_round_id  uuid,
  p_food_id   text,
  p_amount    integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_round      public.hungry_cat_rounds;
  v_food       public.hungry_cat_config;
  v_new_balance integer;
  v_bet_id     uuid := gen_random_uuid();
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_amount <= 0 then raise exception 'invalid_bet_amount'; end if;

  -- Validate round
  select * into v_round
  from public.hungry_cat_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found then raise exception 'round_not_found'; end if;
  if v_round.status != 'betting' then raise exception 'betting_closed'; end if;
  if now() > v_round.betting_ends_at then raise exception 'betting_closed'; end if;

  -- Validate food exists
  select * into v_food
  from public.hungry_cat_config
  where food_id = p_food_id and is_active = true;

  if not found then raise exception 'invalid_food'; end if;

  -- Deduct bet from wallet
  update public.wallets
  set    coins_balance        = coins_balance - p_amount,
         lifetime_coins_spent = lifetime_coins_spent + p_amount,
         updated_at           = now()
  where  user_id = v_user_id
  and    coins_balance >= p_amount
  returning coins_balance into v_new_balance;

  if not found then raise exception 'insufficient_coins'; end if;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_user_id, 'hungry_cat_bet', 'debit', -p_amount, 0,
     'Hungry Cat bet on ' || v_food.name,
     jsonb_build_object('round_id', p_round_id, 'food_id', p_food_id, 'bet_id', v_bet_id));

  insert into public.hungry_cat_bets
    (id, round_id, user_id, food_id, food_name, food_icon, multiplier_at_bet, bet_amount, status)
  values
    (v_bet_id, p_round_id, v_user_id,
     p_food_id, v_food.name, v_food.icon, v_food.multiplier, p_amount, 'pending');

  return jsonb_build_object(
    'bet_id',      v_bet_id,
    'food_id',     p_food_id,
    'amount',      p_amount,
    'new_balance', v_new_balance
  );
end;
$$;

grant execute on function public.place_hungry_cat_bet(uuid, text, integer) to authenticated;

-- ── 5. refund_hungry_cat_round_bets ─────────────────────────────────────────

create or replace function public.refund_hungry_cat_round_bets(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id       uuid := auth.uid();
  v_round         public.hungry_cat_rounds;
  v_refund_total  integer := 0;
  v_new_balance   integer;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select * into v_round
  from public.hungry_cat_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found then raise exception 'round_not_found'; end if;
  if v_round.status != 'betting' then raise exception 'betting_closed'; end if;

  select coalesce(sum(bet_amount), 0) into v_refund_total
  from public.hungry_cat_bets
  where round_id = p_round_id and user_id = v_user_id and status = 'pending';

  if v_refund_total > 0 then
    update public.wallets
    set coins_balance = coins_balance + v_refund_total, updated_at = now()
    where user_id = v_user_id
    returning coins_balance into v_new_balance;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
    values
      (v_user_id, 'hungry_cat_refund', 'credit', v_refund_total, 0,
       'Hungry Cat bets cleared',
       jsonb_build_object('round_id', p_round_id));

    update public.hungry_cat_bets
    set status = 'refunded'
    where round_id = p_round_id and user_id = v_user_id and status = 'pending';
  else
    select coins_balance into v_new_balance
    from public.wallets where user_id = v_user_id;
  end if;

  return jsonb_build_object(
    'refunded_amount', v_refund_total,
    'new_balance',     v_new_balance
  );
end;
$$;

grant execute on function public.refund_hungry_cat_round_bets(uuid) to authenticated;

-- ── 6. settle_hungry_cat_round ───────────────────────────────────────────────

create or replace function public.settle_hungry_cat_round(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id        uuid := auth.uid();
  v_round          public.hungry_cat_rounds;
  v_food           public.hungry_cat_config;
  v_total_weight   numeric;
  v_roll           numeric;
  v_cumulative     numeric := 0;
  v_found          boolean := false;
  v_user_total_bet integer;
  v_user_win       integer := 0;
  v_new_balance    integer;
  v_round_win_amt  integer;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select * into v_round
  from public.hungry_cat_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found then raise exception 'round_not_found'; end if;

  -- Idempotent: already settled
  if v_round.status = 'completed' then
    select coalesce(sum(case when status='won' then bet_amount else 0 end), 0)
    into v_user_total_bet
    from public.hungry_cat_bets
    where round_id = p_round_id and user_id = v_user_id;

    select coins_balance into v_new_balance from public.wallets where user_id = v_user_id;

    return jsonb_build_object(
      'winning_food_id',     v_round.winning_food_id,
      'winning_food_icon',   v_round.winning_food_icon,
      'winning_food_name',   v_round.winning_food_name,
      'winning_multiplier',  v_round.winning_multiplier,
      'rarity',              v_round.winning_food_rarity,
      'user_total_bet',      v_user_total_bet,
      'user_win_amount',     0,
      'new_balance',         v_new_balance
    );
  end if;

  -- Lock round
  update public.hungry_cat_rounds set status = 'locked' where id = p_round_id;

  -- Weighted random food selection
  select sum(weight) into v_total_weight from public.hungry_cat_config where is_active = true;
  if v_total_weight is null or v_total_weight <= 0 then
    raise exception 'no_active_foods';
  end if;
  v_roll := random() * v_total_weight;

  for v_food in (
    select * from public.hungry_cat_config
    where is_active = true
    order by sort_order
  ) loop
    v_cumulative := v_cumulative + v_food.weight;
    if v_roll <= v_cumulative then
      v_found := true;
      exit;
    end if;
  end loop;

  if not v_found then
    select * into v_food from public.hungry_cat_config
    where is_active = true order by sort_order limit 1;
  end if;

  -- Sum user bets on winning food
  select coalesce(sum(bet_amount), 0) into v_user_total_bet
  from public.hungry_cat_bets
  where round_id = p_round_id and user_id = v_user_id;

  -- Compute win for bets on the winning food
  select coalesce(sum(bet_amount), 0) into v_round_win_amt
  from public.hungry_cat_bets
  where round_id = p_round_id
    and user_id = v_user_id
    and food_id = v_food.food_id
    and status = 'pending';

  v_user_win := (v_round_win_amt * v_food.multiplier)::integer;

  -- Settle all bets
  update public.hungry_cat_bets
  set status   = case when food_id = v_food.food_id then 'won' else 'lost' end,
      win_amount = case when food_id = v_food.food_id
                        then (bet_amount * v_food.multiplier)::integer else 0 end
  where round_id = p_round_id and user_id = v_user_id and status = 'pending';

  -- Credit winnings if any
  if v_user_win > 0 then
    update public.wallets
    set coins_balance = coins_balance + v_user_win, updated_at = now()
    where user_id = v_user_id
    returning coins_balance into v_new_balance;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
    values
      (v_user_id, 'hungry_cat_reward', 'credit', v_user_win, 0,
       'Hungry Cat win — ' || v_food.name || ' ×' || v_food.multiplier,
       jsonb_build_object('round_id', p_round_id, 'food_id', v_food.food_id));
  else
    select coins_balance into v_new_balance from public.wallets where user_id = v_user_id;
  end if;

  -- Complete round
  update public.hungry_cat_rounds
  set status              = 'completed',
      winning_food_id     = v_food.food_id,
      winning_food_icon   = v_food.icon,
      winning_food_name   = v_food.name,
      winning_food_rarity = v_food.rarity,
      winning_multiplier  = v_food.multiplier,
      completed_at        = now()
  where id = p_round_id;

  return jsonb_build_object(
    'winning_food_id',     v_food.food_id,
    'winning_food_icon',   v_food.icon,
    'winning_food_name',   v_food.name,
    'winning_multiplier',  v_food.multiplier,
    'rarity',              v_food.rarity,
    'user_total_bet',      v_user_total_bet,
    'user_win_amount',     v_user_win,
    'new_balance',         v_new_balance
  );
end;
$$;

grant execute on function public.settle_hungry_cat_round(uuid) to authenticated;

-- ── 7. get_hungry_cat_recent_rounds ─────────────────────────────────────────

create or replace function public.get_hungry_cat_recent_rounds(
  p_limit integer default 20
)
returns table (
  food_icon    text,
  food_name    text,
  multiplier   numeric,
  rarity       text,
  reward_amount integer,
  bet_amount    integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query
  select
    r.winning_food_icon  as food_icon,
    r.winning_food_name  as food_name,
    r.winning_multiplier as multiplier,
    coalesce(r.winning_food_rarity, 'common') as rarity,
    0::integer           as reward_amount,
    0::integer           as bet_amount
  from public.hungry_cat_rounds r
  where r.status = 'completed'
    and r.winning_food_id is not null
  order by r.completed_at desc
  limit p_limit;
end;
$$;

grant execute on function public.get_hungry_cat_recent_rounds(integer) to authenticated;
