create table if not exists public.user_levels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  level integer not null default 1 check (level >= 1),
  xp bigint not null default 0 check (xp >= 0),
  total_spent_coins bigint not null default 0 check (total_spent_coins >= 0),
  total_received_gifts_value bigint not null default 0 check (total_received_gifts_value >= 0),
  total_room_minutes bigint not null default 0 check (total_room_minutes >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.level_rules (
  id uuid primary key default gen_random_uuid(),
  level integer not null unique check (level >= 1),
  title text not null,
  required_xp bigint not null default 0 check (required_xp >= 0),
  badge_key text null,
  color_name text null,
  benefits jsonb not null default '[]'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.agencies
add column if not exists description text,
add column if not exists monthly_target_hours numeric(8,2) not null default 0;

alter table public.agency_members
add column if not exists created_at timestamptz not null default now(),
add column if not exists updated_at timestamptz not null default now();

alter table public.agency_members
drop constraint if exists agency_members_status_check;

alter table public.agency_members
add constraint agency_members_status_check
check (status in ('pending', 'active', 'suspended', 'removed'));

create table if not exists public.agency_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  agency_id uuid null references public.agencies(id) on delete set null,
  application_type text not null check (application_type in ('join_agency', 'create_agency', 'become_host')),
  message text null,
  phone text null,
  country text null,
  experience text null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  reviewed_by uuid null references auth.users(id) on delete set null,
  reviewed_at timestamptz null,
  admin_note text null,
  created_at timestamptz not null default now()
);

create table if not exists public.income_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  available_balance_usd numeric(12,2) not null default 0 check (available_balance_usd >= 0),
  pending_balance_usd numeric(12,2) not null default 0 check (pending_balance_usd >= 0),
  lifetime_income_usd numeric(12,2) not null default 0 check (lifetime_income_usd >= 0),
  available_coins_reward bigint not null default 0 check (available_coins_reward >= 0),
  pending_coins_reward bigint not null default 0 check (pending_coins_reward >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.income_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  agency_id uuid null references public.agencies(id) on delete set null,
  source_type text not null check (source_type in ('gift_commission', 'agency_reward', 'host_target_reward', 'event_bonus', 'manual_admin')),
  source_id uuid null,
  amount_usd numeric(12,2) not null default 0 check (amount_usd >= 0),
  coins_value bigint not null default 0 check (coins_value >= 0),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'paid')),
  description text null,
  created_at timestamptz not null default now(),
  approved_at timestamptz null,
  approved_by uuid null references auth.users(id) on delete set null
);

create table if not exists public.payout_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_usd numeric(12,2) not null check (amount_usd > 0),
  method text not null check (method in ('OMT', 'Wish', 'Cash', 'USDT', 'Bank later')),
  account_details text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'paid')),
  admin_note text null,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz null,
  reviewed_by uuid null references auth.users(id) on delete set null,
  paid_at timestamptz null
);

create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  badge_key text not null unique,
  name text not null,
  description text null,
  icon_url text null,
  category text not null check (category in ('level', 'vip', 'agency', 'event', 'admin', 'achievement', 'premium')),
  rarity text not null default 'common' check (rarity in ('common', 'rare', 'epic', 'legendary', 'royal')),
  required_level integer null check (required_level is null or required_level >= 1),
  required_vip_level integer null check (required_vip_level is null or required_vip_level between 1 and 5),
  price_coins bigint not null default 0 check (price_coins >= 0),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  badge_key text not null,
  is_equipped boolean not null default false,
  source text not null check (source in ('level_reward', 'vip_reward', 'agency_reward', 'event_reward', 'admin_grant', 'purchase')),
  earned_at timestamptz not null default now(),
  expires_at timestamptz null,
  unique (user_id, badge_id)
);

create table if not exists public.feedback_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('bug', 'suggestion', 'complaint', 'room_problem', 'gift_problem', 'wallet_problem', 'vip_problem', 'other')),
  title text not null,
  message text not null,
  screenshot_url text null,
  status text not null default 'open' check (status in ('open', 'in_review', 'answered', 'closed')),
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  admin_reply text null,
  assigned_to uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz null
);

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('recharge_support', 'account_problem', 'report_user', 'report_room', 'agency_support', 'vip_gifts_support', 'technical_problem', 'other')),
  subject text not null,
  message text not null,
  payment_reference text null,
  room_id uuid null,
  reported_user_id uuid null references auth.users(id) on delete set null,
  status text not null default 'open' check (status in ('open', 'waiting_admin', 'answered', 'closed')),
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  admin_reply text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz null
);

create table if not exists public.user_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  language text not null default 'en' check (language in ('en', 'ar')),
  theme_mode text not null default 'dark' check (theme_mode in ('dark', 'light', 'system')),
  notifications_enabled boolean not null default true,
  room_invites_enabled boolean not null default true,
  gift_notifications_enabled boolean not null default true,
  privacy_profile_visibility text not null default 'public' check (privacy_profile_visibility in ('public', 'friends', 'private')),
  privacy_show_online boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_levels_user_idx on public.user_levels (user_id);
create index if not exists level_rules_active_level_idx on public.level_rules (is_active, level);
create index if not exists agency_applications_user_created_idx on public.agency_applications (user_id, created_at desc);
create index if not exists income_accounts_user_idx on public.income_accounts (user_id);
create index if not exists income_transactions_user_created_idx on public.income_transactions (user_id, created_at desc);
create index if not exists payout_requests_user_requested_idx on public.payout_requests (user_id, requested_at desc);
create index if not exists badges_active_sort_idx on public.badges (is_active, sort_order);
create index if not exists user_badges_user_equipped_idx on public.user_badges (user_id, is_equipped);
create index if not exists feedback_tickets_user_created_idx on public.feedback_tickets (user_id, created_at desc);
create index if not exists support_tickets_user_created_idx on public.support_tickets (user_id, created_at desc);
create index if not exists user_settings_user_idx on public.user_settings (user_id);

alter table public.user_levels enable row level security;
alter table public.level_rules enable row level security;
alter table public.agency_applications enable row level security;
alter table public.income_accounts enable row level security;
alter table public.income_transactions enable row level security;
alter table public.payout_requests enable row level security;
alter table public.badges enable row level security;
alter table public.user_badges enable row level security;
alter table public.feedback_tickets enable row level security;
alter table public.support_tickets enable row level security;
alter table public.user_settings enable row level security;

drop policy if exists "Users can view own levels" on public.user_levels;
create policy "Users can view own levels" on public.user_levels for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Authenticated users can view active level rules" on public.level_rules;
create policy "Authenticated users can view active level rules" on public.level_rules for select to authenticated
using (is_active or public.has_admin_access());

drop policy if exists "Users can view own agency applications" on public.agency_applications;
create policy "Users can view own agency applications" on public.agency_applications for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can create own agency applications" on public.agency_applications;
create policy "Users can create own agency applications" on public.agency_applications for insert to authenticated
with check (user_id = auth.uid() and status = 'pending');

drop policy if exists "Users can view own income account" on public.income_accounts;
create policy "Users can view own income account" on public.income_accounts for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can view own income transactions" on public.income_transactions;
create policy "Users can view own income transactions" on public.income_transactions for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can view own payout requests" on public.payout_requests;
create policy "Users can view own payout requests" on public.payout_requests for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can create own payout requests" on public.payout_requests;
create policy "Users can create own payout requests" on public.payout_requests for insert to authenticated
with check (user_id = auth.uid() and status = 'pending');

drop policy if exists "Authenticated users can view active badges" on public.badges;
create policy "Authenticated users can view active badges" on public.badges for select to authenticated
using (is_active or public.has_admin_access());

drop policy if exists "Users can view own badges" on public.user_badges;
create policy "Users can view own badges" on public.user_badges for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can view own feedback tickets" on public.feedback_tickets;
create policy "Users can view own feedback tickets" on public.feedback_tickets for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can create own feedback tickets" on public.feedback_tickets;
create policy "Users can create own feedback tickets" on public.feedback_tickets for insert to authenticated
with check (user_id = auth.uid() and status = 'open');

drop policy if exists "Users can view own support tickets" on public.support_tickets;
create policy "Users can view own support tickets" on public.support_tickets for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can create own support tickets" on public.support_tickets;
create policy "Users can create own support tickets" on public.support_tickets for insert to authenticated
with check (user_id = auth.uid() and status in ('open', 'waiting_admin'));

drop policy if exists "Users can view own settings" on public.user_settings;
create policy "Users can view own settings" on public.user_settings for select to authenticated
using (user_id = auth.uid() or public.has_admin_access());

drop policy if exists "Users can update own settings" on public.user_settings;
create policy "Users can update own settings" on public.user_settings for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Users can create own settings" on public.user_settings;
create policy "Users can create own settings" on public.user_settings for insert to authenticated
with check (user_id = auth.uid());

insert into public.level_rules (level, title, required_xp, badge_key, color_name, benefits, is_active)
values
  (1, 'New Voice', 0, 'level_1', 'purple', '["Join live rooms", "Send gifts"]'::jsonb, true),
  (2, 'Room Friend', 1000, 'level_2', 'gold', '["Profile level badge", "Better visibility"]'::jsonb, true),
  (3, 'Live Star', 5000, 'level_3', 'diamond', '["Premium badge style", "Priority profile glow"]'::jsonb, true),
  (4, 'SrOOd Elite', 15000, 'level_4', 'royal', '["Elite profile badge", "Special room presence"]'::jsonb, true),
  (5, 'Legend Voice', 40000, 'level_5', 'legendary', '["Legend badge", "Top profile status"]'::jsonb, true)
on conflict (level) do update set
  title = excluded.title,
  required_xp = excluded.required_xp,
  badge_key = excluded.badge_key,
  color_name = excluded.color_name,
  benefits = excluded.benefits,
  is_active = excluded.is_active,
  updated_at = now();

insert into public.badges (badge_key, name, description, category, rarity, required_level, required_vip_level, price_coins, is_active, sort_order)
values
  ('level_1', 'New Voice', 'Welcome badge for new members.', 'level', 'common', 1, null, 0, true, 10),
  ('level_3', 'Live Star', 'Reach level 3 to unlock this badge.', 'level', 'rare', 3, null, 0, true, 20),
  ('vip_gold', 'VIP Gold', 'VIP visual badge.', 'vip', 'epic', null, 2, 0, true, 30),
  ('agency_host', 'Agency Host', 'Granted to active agency hosts.', 'agency', 'rare', null, null, 0, true, 40),
  ('royal_supporter', 'Royal Supporter', 'Premium supporter badge.', 'premium', 'royal', null, null, 5000000, true, 50)
on conflict (badge_key) do update set
  name = excluded.name,
  description = excluded.description,
  category = excluded.category,
  rarity = excluded.rarity,
  required_level = excluded.required_level,
  required_vip_level = excluded.required_vip_level,
  price_coins = excluded.price_coins,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  updated_at = now();

create or replace function public.ensure_user_level(p_user_id uuid default auth.uid())
returns public.user_levels
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level public.user_levels;
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

  insert into public.user_levels (user_id)
  values (p_user_id)
  on conflict (user_id) do update set updated_at = public.user_levels.updated_at
  returning * into v_level;

  return v_level;
end;
$$;

create or replace function public.add_user_xp(
  p_user_id uuid,
  p_xp bigint,
  p_source text default null
)
returns public.user_levels
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level public.user_levels;
  v_new_level integer;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id <> auth.uid() and not public.has_admin_access() then
    raise exception 'not_authorized';
  end if;

  if coalesce(p_xp, 0) <= 0 then
    raise exception 'invalid_xp';
  end if;

  perform public.ensure_user_level(p_user_id);

  update public.user_levels
  set xp = xp + p_xp,
      updated_at = now()
  where user_id = p_user_id
  returning * into v_level;

  select coalesce(max(level), 1)
  into v_new_level
  from public.level_rules
  where is_active
    and required_xp <= v_level.xp;

  update public.user_levels
  set level = greatest(level, v_new_level),
      updated_at = now()
  where user_id = p_user_id
  returning * into v_level;

  return v_level;
end;
$$;

create or replace function public.ensure_income_account(p_user_id uuid default auth.uid())
returns public.income_accounts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.income_accounts;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id <> auth.uid() and not public.has_admin_access() then
    raise exception 'not_authorized';
  end if;

  insert into public.income_accounts (user_id)
  values (p_user_id)
  on conflict (user_id) do update set updated_at = public.income_accounts.updated_at
  returning * into v_account;

  return v_account;
end;
$$;

create or replace function public.ensure_user_settings(p_user_id uuid default auth.uid())
returns public.user_settings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.user_settings;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id <> auth.uid() and not public.has_admin_access() then
    raise exception 'not_authorized';
  end if;

  insert into public.user_settings (user_id)
  values (p_user_id)
  on conflict (user_id) do update set updated_at = public.user_settings.updated_at
  returning * into v_settings;

  return v_settings;
end;
$$;

create or replace function public.equip_user_badge(p_badge_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if not exists (
    select 1
    from public.user_badges ub
    where ub.user_id = v_user_id
      and ub.badge_id = p_badge_id
      and (ub.expires_at is null or ub.expires_at > now())
  ) then
    raise exception 'badge_not_owned';
  end if;

  update public.user_badges set is_equipped = false where user_id = v_user_id;
  update public.user_badges set is_equipped = true where user_id = v_user_id and badge_id = p_badge_id;

  return true;
end;
$$;

grant select on public.user_levels to authenticated;
grant select on public.level_rules to authenticated;
grant select, insert on public.agency_applications to authenticated;
grant select on public.income_accounts to authenticated;
grant select on public.income_transactions to authenticated;
grant select, insert on public.payout_requests to authenticated;
grant select on public.badges to authenticated;
grant select on public.user_badges to authenticated;
grant select, insert on public.feedback_tickets to authenticated;
grant select, insert on public.support_tickets to authenticated;
grant select, insert, update on public.user_settings to authenticated;

grant execute on function public.ensure_user_level(uuid) to authenticated;
grant execute on function public.add_user_xp(uuid, bigint, text) to authenticated;
grant execute on function public.ensure_income_account(uuid) to authenticated;
grant execute on function public.ensure_user_settings(uuid) to authenticated;
grant execute on function public.equip_user_badge(uuid) to authenticated;
