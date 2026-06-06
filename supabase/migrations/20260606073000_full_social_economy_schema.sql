create table if not exists public.user_wallets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  coin_balance bigint not null default 0 check (coin_balance >= 0),
  diamond_balance bigint not null default 0 check (diamond_balance >= 0),
  total_recharged_usd numeric(12,2) not null default 0 check (total_recharged_usd >= 0),
  total_recharged_coins bigint not null default 0 check (total_recharged_coins >= 0),
  total_spent_coins bigint not null default 0 check (total_spent_coins >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.recharge_packages (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  price_usd numeric(12,2) not null check (price_usd > 0),
  coins_amount bigint not null check (coins_amount >= 0),
  bonus_coins bigint not null default 0 check (bonus_coins >= 0),
  total_coins bigint generated always as (coins_amount + bonus_coins) stored,
  is_active boolean not null default true,
  is_featured boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.recharge_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  package_id uuid null references public.recharge_packages(id) on delete set null,
  price_usd numeric(12,2) not null check (price_usd >= 0),
  coins_amount bigint not null check (coins_amount >= 0),
  bonus_coins bigint not null default 0 check (bonus_coins >= 0),
  total_coins bigint not null check (total_coins >= 0),
  payment_method text not null check (
    payment_method in ('cash', 'omt', 'wish', 'usdt', 'manual_admin', 'card_later')
  ),
  payment_reference text null,
  status text not null default 'pending' check (
    status in ('pending', 'approved', 'rejected', 'cancelled')
  ),
  admin_note text null,
  created_at timestamptz not null default now(),
  approved_at timestamptz null,
  approved_by uuid null references auth.users(id) on delete set null
);

create table if not exists public.coin_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  transaction_type text not null check (
    transaction_type in (
      'recharge',
      'gift_sent',
      'gift_received',
      'vip_purchase',
      'frame_purchase',
      'admin_add',
      'admin_deduct',
      'refund',
      'agency_reward',
      'host_reward'
    )
  ),
  amount bigint not null,
  balance_before bigint not null,
  balance_after bigint not null,
  source_type text null,
  source_id uuid null,
  description text null,
  created_at timestamptz not null default now(),
  created_by uuid null references auth.users(id) on delete set null
);

alter table public.gifts
add column if not exists icon_url text,
add column if not exists animation_url text,
add column if not exists is_featured boolean not null default false,
add column if not exists updated_at timestamptz not null default now();

alter table public.gifts
drop constraint if exists gifts_category_check;

alter table public.gifts
add constraint gifts_category_check
check (category in ('classic', 'love', 'luxury', 'lebanon', 'vip', 'event', 'legendary', 'hot'));

alter table public.gift_transactions
add column if not exists quantity integer not null default 1 check (quantity > 0),
add column if not exists total_cost_coins bigint;

update public.gift_transactions
set total_cost_coins = coalesce(total_cost_coins, gift_price_coins::bigint * quantity)
where total_cost_coins is null;

alter table public.gift_transactions
alter column total_cost_coins set default 0,
alter column total_cost_coins set not null;

create table if not exists public.vip_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  level integer not null check (level between 1 and 10),
  price_coins bigint not null default 0 check (price_coins >= 0),
  duration_days integer not null default 30 check (duration_days > 0),
  badge_style text null,
  frame_key text null,
  benefits jsonb not null default '[]'::jsonb,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_vip_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  vip_plan_id uuid not null references public.vip_plans(id) on delete restrict,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.avatar_frames
add column if not exists price_coins bigint not null default 0 check (price_coins >= 0),
add column if not exists updated_at timestamptz not null default now();

alter table public.avatar_frames
drop constraint if exists avatar_frames_category_check;

alter table public.avatar_frames
add constraint avatar_frames_category_check
check (category in ('normal', 'luxury', 'vip', 'admin', 'event', 'agency'));

create table if not exists public.user_avatar_frames (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  frame_id uuid not null references public.avatar_frames(id) on delete cascade,
  frame_key text not null,
  is_equipped boolean not null default false,
  source text not null default 'purchase',
  purchased_at timestamptz not null default now(),
  expires_at timestamptz null,
  unique (user_id, frame_id)
);

create table if not exists public.agencies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_user_id uuid null references auth.users(id) on delete set null,
  country text null,
  status text not null default 'pending' check (status in ('pending', 'active', 'suspended', 'closed')),
  commission_rate numeric(6,4) not null default 0 check (commission_rate >= 0),
  monthly_target_coins bigint not null default 0 check (monthly_target_coins >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.agency_members (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null references public.agencies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'manager', 'host', 'agent')),
  status text not null default 'active',
  joined_at timestamptz not null default now(),
  unique (agency_id, user_id)
);

create table if not exists public.host_targets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  agency_id uuid null references public.agencies(id) on delete set null,
  month date not null,
  target_hours numeric(8,2) not null default 0,
  target_coins bigint not null default 0,
  actual_hours numeric(8,2) not null default 0,
  actual_coins bigint not null default 0,
  reward_coins bigint not null default 0,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, month)
);

alter table public.admin_audit_logs
add column if not exists old_value jsonb,
add column if not exists new_value jsonb;

create index if not exists user_wallets_user_idx on public.user_wallets (user_id);
create index if not exists recharge_packages_active_sort_idx on public.recharge_packages (is_active, sort_order);
create index if not exists recharge_transactions_user_created_idx on public.recharge_transactions (user_id, created_at desc);
create index if not exists recharge_transactions_status_created_idx on public.recharge_transactions (status, created_at desc);
create index if not exists coin_transactions_user_created_idx on public.coin_transactions (user_id, created_at desc);
create index if not exists user_vip_subscriptions_user_active_idx on public.user_vip_subscriptions (user_id, is_active, ends_at desc);
create index if not exists user_avatar_frames_user_idx on public.user_avatar_frames (user_id, is_equipped);
create index if not exists agency_members_user_idx on public.agency_members (user_id, status);
create index if not exists host_targets_agency_month_idx on public.host_targets (agency_id, month);

alter table public.user_wallets enable row level security;
alter table public.recharge_packages enable row level security;
alter table public.recharge_transactions enable row level security;
alter table public.coin_transactions enable row level security;
alter table public.vip_plans enable row level security;
alter table public.user_vip_subscriptions enable row level security;
alter table public.user_avatar_frames enable row level security;
alter table public.agencies enable row level security;
alter table public.agency_members enable row level security;
alter table public.host_targets enable row level security;

drop policy if exists "Users can view own user wallet" on public.user_wallets;
create policy "Users can view own user wallet"
on public.user_wallets for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can view active recharge packages" on public.recharge_packages;
create policy "Users can view active recharge packages"
on public.recharge_packages for select to authenticated
using (is_active or public.has_admin_access());

drop policy if exists "Users can view own recharge transactions" on public.recharge_transactions;
create policy "Users can view own recharge transactions"
on public.recharge_transactions for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can view own coin transactions" on public.coin_transactions;
create policy "Users can view own coin transactions"
on public.coin_transactions for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can view active vip plans" on public.vip_plans;
create policy "Users can view active vip plans"
on public.vip_plans for select to authenticated
using (is_active or public.has_admin_access());

drop policy if exists "Users can view own vip subscriptions" on public.user_vip_subscriptions;
create policy "Users can view own vip subscriptions"
on public.user_vip_subscriptions for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can view own avatar frames" on public.user_avatar_frames;
create policy "Users can view own avatar frames"
on public.user_avatar_frames for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Admins can view agencies" on public.agencies;
create policy "Admins can view agencies"
on public.agencies for select to authenticated
using (public.has_admin_access());

drop policy if exists "Admins can view agency members" on public.agency_members;
create policy "Admins can view agency members"
on public.agency_members for select to authenticated
using (public.has_admin_access());

drop policy if exists "Admins can view host targets" on public.host_targets;
create policy "Admins can view host targets"
on public.host_targets for select to authenticated
using (public.has_admin_access());

insert into public.recharge_packages (title, price_usd, coins_amount, bonus_coins, is_active, is_featured, sort_order)
values
  ('$1 Starter', 1, 10000, 0, true, false, 10),
  ('$2 Basic', 2, 20000, 0, true, false, 20),
  ('$5 Popular', 5, 50000, 0, true, true, 30),
  ('$10 Premium', 10, 100000, 0, true, false, 40),
  ('$20 Deluxe', 20, 200000, 0, true, false, 50),
  ('$50 Royal', 50, 500000, 0, true, false, 60),
  ('$100 Legend', 100, 1000000, 0, true, false, 70)
on conflict do nothing;

insert into public.vip_plans (name, level, price_coins, duration_days, badge_style, frame_key, benefits, is_active, sort_order)
values
  ('VIP Silver', 1, 1000000, 30, 'silver', null, '["special badge", "colored username", "profile glow"]'::jsonb, true, 10),
  ('VIP Gold', 2, 2500000, 30, 'gold', 'custom_luxury_gold', '["special badge", "avatar frame", "colored username", "profile glow"]'::jsonb, true, 20),
  ('VIP Diamond', 3, 5000000, 30, 'diamond', 'custom_luxury_diamond', '["special badge", "avatar frame", "room entrance effect", "exclusive gifts"]'::jsonb, true, 30),
  ('VIP Royal', 4, 10000000, 30, 'royal', 'custom_srood_live', '["priority mic seat request", "premium room badge", "profile glow"]'::jsonb, true, 40),
  ('VIP Legend', 5, 20000000, 30, 'legend', 'custom_srood_live', '["all VIP benefits", "legend profile glow", "premium room badge", "strong kick protection"]'::jsonb, true, 50),
  ('VIP Elite', 6, 30000000, 30, 'elite', 'custom_srood_live', '["VIP 5 benefits", "elite entrance banner", "stronger profile glow", "priority support"]'::jsonb, true, 60),
  ('VIP Mythic', 7, 45000000, 30, 'mythic', 'custom_luxury_diamond', '["VIP 6 benefits", "mythic badge style", "premium room highlight", "exclusive gift access"]'::jsonb, true, 70),
  ('VIP Emperor', 8, 65000000, 30, 'emperor', 'custom_luxury_gold', '["VIP 7 benefits", "emperor entrance", "top profile priority", "advanced anti-kick protection"]'::jsonb, true, 80),
  ('VIP Celestial', 9, 90000000, 30, 'celestial', 'custom_luxury_diamond', '["VIP 8 benefits", "celestial profile glow", "elite identity effects", "highest room prestige"]'::jsonb, true, 90),
  ('VIP SrOOd Legend', 10, 120000000, 30, 'srood_legend', 'custom_srood_live', '["all VIP benefits", "SrOOd legend badge", "maximum profile glow", "legend entrance", "top priority support"]'::jsonb, true, 100)
on conflict do nothing;

create or replace function public.ensure_user_wallet(p_user_id uuid default auth.uid())
returns public.user_wallets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wallet public.user_wallets;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id is null then
    raise exception 'missing_user_id';
  end if;

  if p_user_id <> auth.uid() and not public.has_admin_access() then
    raise exception 'not_authorized';
  end if;

  insert into public.user_wallets (
    user_id,
    coin_balance,
    diamond_balance,
    total_recharged_coins,
    total_spent_coins
  )
  select
    p_user_id,
    coalesce(w.coins_balance, 0),
    coalesce(w.diamonds_balance, 0),
    coalesce(w.lifetime_coins_charged, 0),
    coalesce(w.lifetime_coins_spent, 0)
  from (select 1) seed
  left join public.wallets w on w.user_id = p_user_id
  on conflict (user_id) do update
    set updated_at = public.user_wallets.updated_at
  returning * into v_wallet;

  return v_wallet;
end;
$$;

create or replace function public.create_recharge_transaction(
  p_package_id uuid,
  p_payment_method text,
  p_payment_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_package public.recharge_packages;
  v_method text := lower(trim(coalesce(p_payment_method, '')));
  v_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if v_method not in ('cash', 'omt', 'wish', 'usdt', 'manual_admin', 'card_later') then
    raise exception 'invalid_payment_method';
  end if;

  select *
  into v_package
  from public.recharge_packages
  where id = p_package_id
    and is_active
  limit 1;

  if not found then
    raise exception 'recharge_package_not_found';
  end if;

  insert into public.recharge_transactions (
    user_id,
    package_id,
    price_usd,
    coins_amount,
    bonus_coins,
    total_coins,
    payment_method,
    payment_reference
  )
  values (
    v_user_id,
    v_package.id,
    v_package.price_usd,
    v_package.coins_amount,
    v_package.bonus_coins,
    v_package.total_coins,
    v_method,
    nullif(trim(coalesce(p_payment_reference, '')), '')
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.approve_recharge_transaction(
  p_transaction_id uuid,
  p_payment_reference text default null,
  p_admin_note text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_tx public.recharge_transactions;
  v_wallet public.user_wallets;
  v_before bigint;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated';
  end if;

  if not public.has_finance_access() then
    raise exception 'not_authorized';
  end if;

  select *
  into v_tx
  from public.recharge_transactions
  where id = p_transaction_id
  for update;

  if not found then
    raise exception 'recharge_transaction_not_found';
  end if;

  if v_tx.status <> 'pending' then
    raise exception 'recharge_transaction_not_pending';
  end if;

  perform public.ensure_user_wallet(v_tx.user_id);

  select *
  into v_wallet
  from public.user_wallets
  where user_id = v_tx.user_id
  for update;

  v_before := v_wallet.coin_balance;

  update public.user_wallets
  set coin_balance = coin_balance + v_tx.total_coins,
      total_recharged_usd = total_recharged_usd + v_tx.price_usd,
      total_recharged_coins = total_recharged_coins + v_tx.total_coins,
      updated_at = now()
  where user_id = v_tx.user_id
  returning * into v_wallet;

  insert into public.wallets (user_id)
  values (v_tx.user_id)
  on conflict (user_id) do nothing;

  update public.wallets
  set coins_balance = v_wallet.coin_balance::integer,
      diamonds_balance = v_wallet.diamond_balance::integer,
      lifetime_coins_charged = v_wallet.total_recharged_coins::integer,
      updated_at = now()
  where user_id = v_tx.user_id;

  update public.recharge_transactions
  set status = 'approved',
      payment_reference = coalesce(nullif(trim(coalesce(p_payment_reference, '')), ''), payment_reference),
      admin_note = nullif(trim(coalesce(p_admin_note, '')), ''),
      approved_at = now(),
      approved_by = v_admin_id
  where id = v_tx.id;

  insert into public.coin_transactions (
    user_id,
    transaction_type,
    amount,
    balance_before,
    balance_after,
    source_type,
    source_id,
    description,
    created_by
  )
  values (
    v_tx.user_id,
    'recharge',
    v_tx.total_coins,
    v_before,
    v_wallet.coin_balance,
    'recharge_transactions',
    v_tx.id,
    'Recharge approved',
    v_admin_id
  );

  return true;
end;
$$;

create or replace function public.purchase_vip_plan(p_vip_plan_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_plan public.vip_plans;
  v_wallet public.user_wallets;
  v_before bigint;
  v_subscription_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_plan from public.vip_plans where id = p_vip_plan_id and is_active limit 1;
  if not found then
    raise exception 'vip_plan_not_found';
  end if;

  perform public.ensure_user_wallet(v_user_id);
  select * into v_wallet from public.user_wallets where user_id = v_user_id for update;

  if v_wallet.coin_balance < v_plan.price_coins then
    raise exception 'insufficient_coins';
  end if;

  v_before := v_wallet.coin_balance;

  update public.user_wallets
  set coin_balance = coin_balance - v_plan.price_coins,
      total_spent_coins = total_spent_coins + v_plan.price_coins,
      updated_at = now()
  where user_id = v_user_id
  returning * into v_wallet;

  update public.profiles
  set vip_level = greatest(coalesce(vip_level, 0), v_plan.level),
      vip_started_at = now(),
      vip_expires_at = now() + make_interval(days => v_plan.duration_days),
      vip_title = v_plan.name
  where id = v_user_id;

  insert into public.user_vip_subscriptions (user_id, vip_plan_id, ends_at)
  values (v_user_id, v_plan.id, now() + make_interval(days => v_plan.duration_days))
  returning id into v_subscription_id;

  insert into public.coin_transactions (
    user_id, transaction_type, amount, balance_before, balance_after,
    source_type, source_id, description, created_by
  )
  values (
    v_user_id, 'vip_purchase', -v_plan.price_coins, v_before, v_wallet.coin_balance,
    'vip_plans', v_plan.id, 'VIP purchase: ' || v_plan.name, v_user_id
  );

  return v_subscription_id;
end;
$$;

create or replace function public.purchase_avatar_frame(p_frame_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_frame public.avatar_frames;
  v_wallet public.user_wallets;
  v_before bigint;
  v_owned_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_frame from public.avatar_frames where id = p_frame_id and is_active limit 1;
  if not found then
    raise exception 'avatar_frame_not_found';
  end if;

  if coalesce(v_frame.required_vip_level, 0) > coalesce((select vip_level from public.profiles where id = v_user_id), 0) then
    raise exception 'vip_level_required';
  end if;

  perform public.ensure_user_wallet(v_user_id);
  select * into v_wallet from public.user_wallets where user_id = v_user_id for update;

  if v_wallet.coin_balance < coalesce(v_frame.price_coins, 0) then
    raise exception 'insufficient_coins';
  end if;

  v_before := v_wallet.coin_balance;

  update public.user_wallets
  set coin_balance = coin_balance - coalesce(v_frame.price_coins, 0),
      total_spent_coins = total_spent_coins + coalesce(v_frame.price_coins, 0),
      updated_at = now()
  where user_id = v_user_id
  returning * into v_wallet;

  insert into public.user_avatar_frames (user_id, frame_id, frame_key, source)
  values (v_user_id, v_frame.id, v_frame.frame_key, 'purchase')
  on conflict (user_id, frame_id) do update
    set purchased_at = public.user_avatar_frames.purchased_at
  returning id into v_owned_id;

  insert into public.coin_transactions (
    user_id, transaction_type, amount, balance_before, balance_after,
    source_type, source_id, description, created_by
  )
  values (
    v_user_id, 'frame_purchase', -coalesce(v_frame.price_coins, 0), v_before, v_wallet.coin_balance,
    'avatar_frames', v_frame.id, 'Avatar frame purchase: ' || v_frame.name, v_user_id
  );

  return v_owned_id;
end;
$$;

create or replace function public.equip_avatar_frame(p_frame_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_frame_key text;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select uaf.frame_key
  into v_frame_key
  from public.user_avatar_frames uaf
  where uaf.user_id = v_user_id
    and uaf.frame_id = p_frame_id
    and (uaf.expires_at is null or uaf.expires_at > now())
  limit 1;

  if v_frame_key is null then
    raise exception 'avatar_frame_not_owned';
  end if;

  update public.user_avatar_frames set is_equipped = false where user_id = v_user_id;
  update public.user_avatar_frames set is_equipped = true where user_id = v_user_id and frame_id = p_frame_id;
  update public.profiles set selected_avatar_frame_key = v_frame_key where id = v_user_id;

  return true;
end;
$$;

grant select on public.user_wallets to authenticated;
grant select on public.recharge_packages to authenticated;
grant select on public.recharge_transactions to authenticated;
grant select on public.coin_transactions to authenticated;
grant select on public.vip_plans to authenticated;
grant select on public.user_vip_subscriptions to authenticated;
grant select on public.user_avatar_frames to authenticated;
grant select on public.agencies to authenticated;
grant select on public.agency_members to authenticated;
grant select on public.host_targets to authenticated;

grant execute on function public.ensure_user_wallet(uuid) to authenticated;
grant execute on function public.create_recharge_transaction(uuid, text, text) to authenticated;
grant execute on function public.approve_recharge_transaction(uuid, text, text) to authenticated;
grant execute on function public.purchase_vip_plan(uuid) to authenticated;
grant execute on function public.purchase_avatar_frame(uuid) to authenticated;
grant execute on function public.equip_avatar_frame(uuid) to authenticated;
