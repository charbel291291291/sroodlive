-- ────────────────────────────────────────────────────────────────────────────
-- Hungry Cat history: add food_icon + rarity to spin records, update RPC,
-- add history query function for the live lobby banner.
-- ────────────────────────────────────────────────────────────────────────────

-- ── 1. Add display columns to hungry_cat_spins ───────────────────────────────

alter table public.hungry_cat_spins
  add column if not exists food_icon text not null default '🍽️',
  add column if not exists rarity    text not null default 'common'
    check (rarity in ('common', 'uncommon', 'rare', 'epic', 'legendary'));

-- ── 2. Replace play_hungry_cat_spin — now stores food_icon and rarity ────────
-- This is an in-place replacement; only the INSERT statement changes.

create or replace function public.play_hungry_cat_spin(
  p_bet_amount integer,
  p_client_spin_id uuid,
  p_room_id uuid default null
)
returns table (
  spin_id uuid,
  food_id text,
  food_name text,
  food_icon text,
  multiplier numeric,
  rarity text,
  bet_amount integer,
  reward_amount integer,
  new_balance integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet public.wallets;
  v_existing public.hungry_cat_spins;
  v_food public.hungry_cat_config;
  v_total_weight numeric;
  v_roll numeric;
  v_reward integer;
  v_spin_id uuid;
  v_new_balance integer;
  c_min_bet constant integer := 100;
  c_max_bet constant integer := 100000;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_client_spin_id is null then
    raise exception 'missing_client_spin_id';
  end if;

  if not exists (
    select 1 from public.game_settings
    where game_key = 'hungry_cat' and is_enabled
  ) then
    raise exception 'game_disabled';
  end if;

  if p_bet_amount is null
     or p_bet_amount < c_min_bet
     or p_bet_amount > c_max_bet then
    raise exception 'invalid_bet_amount';
  end if;

  -- Idempotency: if this client_spin_id was already settled, return the
  -- original result without charging twice.
  select * into v_existing
  from public.hungry_cat_spins s
  where s.client_spin_id = p_client_spin_id;

  if v_existing.id is not null then
    select w.coins_balance into v_new_balance
    from public.wallets w where w.user_id = v_user_id;

    select * into v_food
    from public.hungry_cat_config c
    where c.food_id = v_existing.food_id;

    return query select
      v_existing.id, v_existing.food_id, v_existing.food_name,
      coalesce(v_existing.food_icon, coalesce(v_food.icon, '🍽️')),
      v_existing.multiplier,
      coalesce(v_existing.rarity, coalesce(v_food.rarity, 'common')),
      v_existing.bet_amount, v_existing.reward_amount,
      coalesce(v_new_balance, 0);
    return;
  end if;

  -- Lock wallet row, verify balance
  select * into v_wallet
  from public.wallets
  where user_id = v_user_id
  for update;

  if v_wallet is null or v_wallet.coins_balance < p_bet_amount then
    raise exception 'insufficient_coins';
  end if;

  -- Weighted random food selection (server decides — never the client)
  select coalesce(sum(weight), 0) into v_total_weight
  from public.hungry_cat_config
  where is_active and weight > 0;

  if v_total_weight <= 0 then
    raise exception 'invalid_food_config';
  end if;

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
    order by c.sort_order desc, c.food_id desc
    limit 1;
  end if;

  v_reward := floor(p_bet_amount * v_food.multiplier)::integer;

  update public.wallets
  set coins_balance = coins_balance - p_bet_amount + v_reward,
      lifetime_coins_spent = lifetime_coins_spent + p_bet_amount,
      updated_at = now()
  where user_id = v_user_id
  returning coins_balance into v_new_balance;

  insert into public.hungry_cat_spins (
    user_id, room_id, client_spin_id, bet_amount,
    food_id, food_name, food_icon, multiplier, rarity, reward_amount, status
  )
  values (
    v_user_id, p_room_id, p_client_spin_id, p_bet_amount,
    v_food.food_id, v_food.name, v_food.icon,
    v_food.multiplier, v_food.rarity, v_reward, 'settled'
  )
  returning id into v_spin_id;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_user_id, 'hungry_cat_bet', 'debit', -p_bet_amount, 0,
     'Hungry Cat Wheel bet',
     jsonb_build_object('spin_id', v_spin_id, 'food_id', v_food.food_id)),
    (v_user_id, 'hungry_cat_reward', 'credit', v_reward, 0,
     'Hungry Cat Wheel reward: ' || v_food.name || ' x' || v_food.multiplier,
     jsonb_build_object('spin_id', v_spin_id, 'food_id', v_food.food_id,
                        'multiplier', v_food.multiplier));

  return query select
    v_spin_id, v_food.food_id, v_food.name, v_food.icon,
    v_food.multiplier, v_food.rarity,
    p_bet_amount, v_reward, v_new_balance;
end;
$$;

grant execute on function public.play_hungry_cat_spin(integer, uuid, uuid) to authenticated;

-- ── 3. get_hungry_cat_history — latest N spins for the current user ───────────

create or replace function public.get_hungry_cat_history(
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
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  return query
  select
    s.food_icon,
    s.food_name,
    s.multiplier,
    s.rarity,
    s.reward_amount,
    s.bet_amount,
    s.created_at
  from public.hungry_cat_spins s
  where s.user_id = v_user_id
    and s.status = 'settled'
  order by s.created_at desc
  limit p_limit;
end;
$$;

grant execute on function public.get_hungry_cat_history(integer) to authenticated;
