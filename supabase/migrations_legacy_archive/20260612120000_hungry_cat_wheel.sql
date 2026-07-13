-- ────────────────────────────────────────────────────────────────────────────
-- Hungry Cat Wheel — WebView mini game
--   All money logic lives here (SQL-side): bet deduction, weighted random
--   food selection, reward credit, spin history. The WebView only animates
--   the result the server already decided.
-- ────────────────────────────────────────────────────────────────────────────

-- ── 1. game_settings: per-game enable flag ───────────────────────────────────

create table if not exists public.game_settings (
  game_key   text primary key,
  is_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.game_settings enable row level security;

drop policy if exists "game_settings_select" on public.game_settings;
create policy "game_settings_select"
  on public.game_settings for select to authenticated
  using (true);

grant select on public.game_settings to authenticated;

insert into public.game_settings (game_key, is_enabled)
values ('hungry_cat', true)
on conflict (game_key) do nothing;

-- ── 2. hungry_cat_config: food items, multipliers, weights ───────────────────
-- Single source of truth for probabilities — admin/service role edits here.

create table if not exists public.hungry_cat_config (
  id          uuid primary key default gen_random_uuid(),
  food_id     text not null unique,
  name        text not null,
  icon        text not null default '🍽️',
  multiplier  numeric(8,2) not null check (multiplier > 0),
  weight      numeric(8,2) not null check (weight >= 0),
  rarity      text not null default 'common'
                check (rarity in ('common', 'uncommon', 'rare', 'epic', 'legendary')),
  sort_order  integer not null default 0,
  is_active   boolean not null default true,
  updated_at  timestamptz not null default now()
);

alter table public.hungry_cat_config enable row level security;

drop policy if exists "hungry_cat_config_select" on public.hungry_cat_config;
create policy "hungry_cat_config_select"
  on public.hungry_cat_config for select to authenticated
  using (true);

grant select on public.hungry_cat_config to authenticated;

insert into public.hungry_cat_config
  (food_id, name, icon, multiplier, weight, rarity, sort_order) values
  ('milk',        'Milk',        '🥛', 1.2,  22,  'common',    10),
  ('cookie',      'Cookie',      '🍪', 1.5,  20,  'common',    20),
  ('fish',        'Fish',        '🐟', 2,    18,  'common',    30),
  ('chicken',     'Chicken',     '🍗', 3,    13,  'uncommon',  40),
  ('shrimp',      'Shrimp',      '🍤', 4,    10,  'uncommon',  50),
  ('burger',      'Burger',      '🍔', 5,    7,   'uncommon',  60),
  ('pizza',       'Pizza',       '🍕', 8,    4,   'rare',      70),
  ('cake',        'Cake',        '🍰', 10,   3,   'rare',      80),
  ('tuna',        'Tuna',        '🍣', 12,   2,   'rare',      90),
  ('ice_cream',   'Ice Cream',   '🍨', 15,   0.8, 'epic',      100),
  ('golden_fish', 'Golden Fish', '🐠', 25,   0.2, 'legendary', 110)
on conflict (food_id) do nothing;

-- ── 3. hungry_cat_spins: full spin history ───────────────────────────────────

create table if not exists public.hungry_cat_spins (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  room_id        uuid references public.rooms(id) on delete set null,
  client_spin_id uuid not null unique,
  bet_amount     integer not null check (bet_amount > 0),
  food_id        text not null,
  food_name      text not null,
  multiplier     numeric(8,2) not null,
  reward_amount  integer not null default 0,
  status         text not null default 'settled'
                   check (status in ('settled', 'refunded')),
  created_at     timestamptz not null default now(),
  settled_at     timestamptz not null default now()
);

create index if not exists hungry_cat_spins_user_created_idx
  on public.hungry_cat_spins (user_id, created_at desc);

alter table public.hungry_cat_spins enable row level security;

drop policy if exists "hungry_cat_spins_select_own" on public.hungry_cat_spins;
create policy "hungry_cat_spins_select_own"
  on public.hungry_cat_spins for select to authenticated
  using (user_id = auth.uid() or public.has_finance_access());

-- Spins are written only by the security-definer RPC below
grant select on public.hungry_cat_spins to authenticated;

-- ── 4. Extend wallet_transactions types ──────────────────────────────────────

alter table public.wallet_transactions
drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
add constraint wallet_transactions_type_check check (
  type in (
    'recharge_request',
    'admin_adjustment',
    'gift_sent',
    'gift_received',
    'agency_recharge',
    'refund',
    'system',
    'withdrawal',
    'withdrawal_refund',
    'agency_commission',
    'hungry_cat_bet',
    'hungry_cat_reward',
    'hungry_cat_refund'
  )
);

-- ── 5. play_hungry_cat_spin RPC ──────────────────────────────────────────────
-- One atomic call: validate → deduct bet → pick weighted food → credit reward
-- → record spin + transactions → return result. Idempotent on client_spin_id.

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

  -- Idempotency: if this client_spin_id was already settled (e.g. the app
  -- retried after a network failure), return the original result instead of
  -- charging twice.
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
      coalesce(v_food.icon, '🍽️'), v_existing.multiplier,
      coalesce(v_food.rarity, 'common'),
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
    -- Numeric edge case at the very top of the range — take the last item
    select c.* into v_food
    from public.hungry_cat_config c
    where c.is_active and c.weight > 0
    order by c.sort_order desc, c.food_id desc
    limit 1;
  end if;

  v_reward := floor(p_bet_amount * v_food.multiplier)::integer;

  -- Apply net wallet change (bet out, reward in) atomically
  update public.wallets
  set coins_balance = coins_balance - p_bet_amount + v_reward,
      lifetime_coins_spent = lifetime_coins_spent + p_bet_amount,
      updated_at = now()
  where user_id = v_user_id
  returning coins_balance into v_new_balance;

  insert into public.hungry_cat_spins (
    user_id, room_id, client_spin_id, bet_amount,
    food_id, food_name, multiplier, reward_amount, status
  )
  values (
    v_user_id, p_room_id, p_client_spin_id, p_bet_amount,
    v_food.food_id, v_food.name, v_food.multiplier, v_reward, 'settled'
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

-- ── 6. Read-only admin stats ─────────────────────────────────────────────────

create or replace function public.admin_hungry_cat_stats()
returns table (
  total_spins bigint,
  total_bet bigint,
  total_reward bigint,
  net_platform_coins bigint,
  biggest_win integer,
  spins_today bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_finance_access() then
    raise exception 'not_authorized';
  end if;

  return query select
    count(*)::bigint,
    coalesce(sum(s.bet_amount), 0)::bigint,
    coalesce(sum(s.reward_amount), 0)::bigint,
    coalesce(sum(s.bet_amount) - sum(s.reward_amount), 0)::bigint,
    coalesce(max(s.reward_amount), 0)::integer,
    count(*) filter (where s.created_at >= date_trunc('day', now()))::bigint
  from public.hungry_cat_spins s;
end;
$$;

grant execute on function public.admin_hungry_cat_stats() to authenticated;
