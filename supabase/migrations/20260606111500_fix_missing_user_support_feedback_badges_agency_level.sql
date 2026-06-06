create table if not exists public.app_user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

alter table public.app_user_roles enable row level security;

create or replace function public.has_app_role(required_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_user_roles aur
    where aur.user_id = auth.uid()
      and aur.role = any(required_roles)
  );
$$;

create or replace function public.profile_hub_admin_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_app_role(array[
    'super_admin',
    'admin',
    'finance_admin',
    'support_admin',
    'content_admin'
  ]);
$$;

create table if not exists public.user_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade unique,
  language text not null default 'en',
  theme text not null default 'dark',
  theme_mode text not null default 'dark',
  notifications_enabled boolean not null default true,
  push_notifications_enabled boolean not null default true,
  sound_enabled boolean not null default true,
  room_invites_enabled boolean not null default true,
  gift_notifications_enabled boolean not null default true,
  privacy_profile_visible boolean not null default true,
  privacy_profile_visibility text not null default 'public',
  privacy_show_online boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_settings
add column if not exists language text not null default 'en',
add column if not exists theme text not null default 'dark',
add column if not exists theme_mode text not null default 'dark',
add column if not exists notifications_enabled boolean not null default true,
add column if not exists push_notifications_enabled boolean not null default true,
add column if not exists sound_enabled boolean not null default true,
add column if not exists room_invites_enabled boolean not null default true,
add column if not exists gift_notifications_enabled boolean not null default true,
add column if not exists privacy_profile_visible boolean not null default true,
add column if not exists privacy_profile_visibility text not null default 'public',
add column if not exists privacy_show_online boolean not null default true,
add column if not exists created_at timestamptz not null default now(),
add column if not exists updated_at timestamptz not null default now();

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null default 'other',
  subject text,
  message text not null,
  status text not null default 'open',
  priority text not null default 'normal',
  admin_reply text,
  payment_reference text,
  room_id uuid,
  reported_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.support_tickets
add column if not exists category text not null default 'other',
add column if not exists subject text,
add column if not exists message text not null default '',
add column if not exists status text not null default 'open',
add column if not exists priority text not null default 'normal',
add column if not exists admin_reply text,
add column if not exists payment_reference text,
add column if not exists room_id uuid,
add column if not exists reported_user_id uuid references auth.users(id) on delete set null,
add column if not exists created_at timestamptz not null default now(),
add column if not exists updated_at timestamptz not null default now();

create table if not exists public.feedback_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null default 'feedback',
  category text not null default 'feedback',
  title text,
  message text not null,
  status text not null default 'new',
  priority text not null default 'normal',
  admin_reply text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.feedback_tickets
add column if not exists type text not null default 'feedback',
add column if not exists category text not null default 'feedback',
add column if not exists title text,
add column if not exists message text not null default '',
add column if not exists status text not null default 'new',
add column if not exists priority text not null default 'normal',
add column if not exists admin_reply text,
add column if not exists created_at timestamptz not null default now(),
add column if not exists updated_at timestamptz not null default now();

create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  badge_key text unique not null,
  name text not null,
  description text,
  icon text,
  category text not null default 'achievement',
  rarity text not null default 'common',
  required_level integer default 0,
  required_vip_level integer default 0,
  price_coins bigint not null default 0,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.badges
add column if not exists badge_key text unique,
add column if not exists name text not null default 'Badge',
add column if not exists description text,
add column if not exists icon text,
add column if not exists category text not null default 'achievement',
add column if not exists rarity text not null default 'common',
add column if not exists required_level integer default 0,
add column if not exists required_vip_level integer default 0,
add column if not exists price_coins bigint not null default 0,
add column if not exists is_active boolean not null default true,
add column if not exists sort_order integer not null default 0,
add column if not exists created_at timestamptz not null default now(),
add column if not exists updated_at timestamptz not null default now();

create table if not exists public.user_badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid references public.badges(id) on delete cascade,
  badge_key text references public.badges(badge_key) on delete cascade,
  is_equipped boolean not null default false,
  source text not null default 'admin_grant',
  created_at timestamptz not null default now(),
  earned_at timestamptz not null default now(),
  expires_at timestamptz
);

alter table public.user_badges
add column if not exists badge_id uuid references public.badges(id) on delete cascade,
add column if not exists badge_key text references public.badges(badge_key) on delete cascade,
add column if not exists is_equipped boolean not null default false,
add column if not exists source text not null default 'admin_grant',
add column if not exists created_at timestamptz not null default now(),
add column if not exists earned_at timestamptz not null default now(),
add column if not exists expires_at timestamptz;

update public.user_badges ub
set badge_key = b.badge_key
from public.badges b
where ub.badge_id = b.id
  and ub.badge_key is null;

create unique index if not exists user_badges_user_badge_id_unique_idx
on public.user_badges (user_id, badge_id)
where badge_id is not null;

create unique index if not exists user_badges_user_badge_key_unique_idx
on public.user_badges (user_id, badge_key)
where badge_key is not null;

create table if not exists public.user_levels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade unique,
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
  badge_key text,
  color_name text,
  benefits jsonb not null default '[]'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.agencies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_user_id uuid references auth.users(id) on delete set null,
  country text,
  description text,
  status text not null default 'pending',
  commission_rate numeric(6,4) not null default 0 check (commission_rate >= 0),
  monthly_target_coins bigint not null default 0 check (monthly_target_coins >= 0),
  monthly_target_hours numeric(8,2) not null default 0 check (monthly_target_hours >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.agencies
add column if not exists owner_user_id uuid references auth.users(id) on delete set null,
add column if not exists country text,
add column if not exists description text,
add column if not exists status text not null default 'pending',
add column if not exists commission_rate numeric(6,4) not null default 0,
add column if not exists monthly_target_coins bigint not null default 0,
add column if not exists monthly_target_hours numeric(8,2) not null default 0,
add column if not exists created_at timestamptz not null default now(),
add column if not exists updated_at timestamptz not null default now();

create table if not exists public.agency_members (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null references public.agencies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'host',
  status text not null default 'pending',
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (agency_id, user_id)
);

alter table public.agency_members
add column if not exists role text not null default 'host',
add column if not exists status text not null default 'pending',
add column if not exists joined_at timestamptz not null default now(),
add column if not exists created_at timestamptz not null default now(),
add column if not exists updated_at timestamptz not null default now();

create table if not exists public.agency_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  agency_id uuid references public.agencies(id) on delete set null,
  application_type text not null default 'join_agency',
  message text,
  phone text,
  country text,
  experience text,
  status text not null default 'pending',
  admin_reply text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.income_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade unique,
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
  agency_id uuid references public.agencies(id) on delete set null,
  source_type text not null default 'manual_admin',
  amount_usd numeric(12,2) not null default 0 check (amount_usd >= 0),
  coins_value bigint not null default 0 check (coins_value >= 0),
  description text,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

create table if not exists public.payout_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_usd numeric(12,2) not null check (amount_usd > 0),
  method text not null,
  account_details text,
  status text not null default 'pending',
  admin_reply text,
  requested_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_settings_user_idx on public.user_settings (user_id);
create index if not exists support_tickets_user_created_idx on public.support_tickets (user_id, created_at desc);
create index if not exists feedback_tickets_user_created_idx on public.feedback_tickets (user_id, created_at desc);
create index if not exists badges_active_sort_idx on public.badges (is_active, sort_order);
create index if not exists user_levels_user_idx on public.user_levels (user_id);
create index if not exists level_rules_active_level_idx on public.level_rules (is_active, level);
create index if not exists agency_members_user_idx on public.agency_members (user_id, status);
create index if not exists agency_applications_user_created_idx on public.agency_applications (user_id, created_at desc);
create index if not exists income_accounts_user_idx on public.income_accounts (user_id);
create index if not exists income_transactions_user_created_idx on public.income_transactions (user_id, created_at desc);
create index if not exists payout_requests_user_requested_idx on public.payout_requests (user_id, requested_at desc);

alter table public.user_settings enable row level security;
alter table public.support_tickets enable row level security;
alter table public.feedback_tickets enable row level security;
alter table public.badges enable row level security;
alter table public.user_badges enable row level security;
alter table public.user_levels enable row level security;
alter table public.level_rules enable row level security;
alter table public.agencies enable row level security;
alter table public.agency_members enable row level security;
alter table public.agency_applications enable row level security;
alter table public.income_accounts enable row level security;
alter table public.income_transactions enable row level security;
alter table public.payout_requests enable row level security;

drop policy if exists "Profile hub app roles can view roles" on public.app_user_roles;
create policy "Profile hub app roles can view roles"
on public.app_user_roles for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can view own user settings" on public.user_settings;
create policy "Users can view own user settings"
on public.user_settings for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can insert own user settings" on public.user_settings;
create policy "Users can insert own user settings"
on public.user_settings for insert to authenticated
with check (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can update own user settings" on public.user_settings;
create policy "Users can update own user settings"
on public.user_settings for update to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access())
with check (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can view own support tickets" on public.support_tickets;
create policy "Users can view own support tickets"
on public.support_tickets for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can create own support tickets" on public.support_tickets;
create policy "Users can create own support tickets"
on public.support_tickets for insert to authenticated
with check (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Admins can update support tickets" on public.support_tickets;
create policy "Admins can update support tickets"
on public.support_tickets for update to authenticated
using (public.profile_hub_admin_access())
with check (public.profile_hub_admin_access());

drop policy if exists "Users can view own feedback tickets" on public.feedback_tickets;
create policy "Users can view own feedback tickets"
on public.feedback_tickets for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can create own feedback tickets" on public.feedback_tickets;
create policy "Users can create own feedback tickets"
on public.feedback_tickets for insert to authenticated
with check (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Admins can update feedback tickets" on public.feedback_tickets;
create policy "Admins can update feedback tickets"
on public.feedback_tickets for update to authenticated
using (public.profile_hub_admin_access())
with check (public.profile_hub_admin_access());

drop policy if exists "Authenticated users can view active badges" on public.badges;
create policy "Authenticated users can view active badges"
on public.badges for select to authenticated
using (is_active or public.profile_hub_admin_access());

drop policy if exists "Admins can manage badges" on public.badges;
create policy "Admins can manage badges"
on public.badges for all to authenticated
using (public.profile_hub_admin_access())
with check (public.profile_hub_admin_access());

drop policy if exists "Users can view own badges" on public.user_badges;
create policy "Users can view own badges"
on public.user_badges for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can insert own badges" on public.user_badges;
create policy "Users can insert own badges"
on public.user_badges for insert to authenticated
with check (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can update own badges" on public.user_badges;
create policy "Users can update own badges"
on public.user_badges for update to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access())
with check (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can view own levels" on public.user_levels;
create policy "Users can view own levels"
on public.user_levels for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can update own levels" on public.user_levels;
create policy "Users can update own levels"
on public.user_levels for update to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access())
with check (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Authenticated users can view active level rules" on public.level_rules;
create policy "Authenticated users can view active level rules"
on public.level_rules for select to authenticated
using (is_active or public.profile_hub_admin_access());

drop policy if exists "Admins can manage level rules" on public.level_rules;
create policy "Admins can manage level rules"
on public.level_rules for all to authenticated
using (public.profile_hub_admin_access())
with check (public.profile_hub_admin_access());

drop policy if exists "Users can view own agencies" on public.agencies;
create policy "Users can view own agencies"
on public.agencies for select to authenticated
using (
  owner_user_id = auth.uid()
  or exists (
    select 1 from public.agency_members am
    where am.agency_id = agencies.id and am.user_id = auth.uid()
  )
  or public.profile_hub_admin_access()
);

drop policy if exists "Users can view own agency memberships" on public.agency_members;
create policy "Users can view own agency memberships"
on public.agency_members for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can view own agency applications" on public.agency_applications;
create policy "Users can view own agency applications"
on public.agency_applications for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can create own agency applications" on public.agency_applications;
create policy "Users can create own agency applications"
on public.agency_applications for insert to authenticated
with check (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Admins can update agency applications" on public.agency_applications;
create policy "Admins can update agency applications"
on public.agency_applications for update to authenticated
using (public.profile_hub_admin_access())
with check (public.profile_hub_admin_access());

drop policy if exists "Users can view own income account" on public.income_accounts;
create policy "Users can view own income account"
on public.income_accounts for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can update own income account" on public.income_accounts;
create policy "Users can update own income account"
on public.income_accounts for update to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access())
with check (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can view own income transactions" on public.income_transactions;
create policy "Users can view own income transactions"
on public.income_transactions for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can view own payout requests" on public.payout_requests;
create policy "Users can view own payout requests"
on public.payout_requests for select to authenticated
using (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Users can create own payout requests" on public.payout_requests;
create policy "Users can create own payout requests"
on public.payout_requests for insert to authenticated
with check (user_id = auth.uid() or public.profile_hub_admin_access());

drop policy if exists "Admins can update payout requests" on public.payout_requests;
create policy "Admins can update payout requests"
on public.payout_requests for update to authenticated
using (public.profile_hub_admin_access())
with check (public.profile_hub_admin_access());

insert into public.badges (badge_key, name, description, icon, category, rarity, required_level, required_vip_level, price_coins, is_active, sort_order)
values
  ('new_member', 'New Member', 'Welcome badge for new SrOOd Live members.', 'person_add', 'achievement', 'common', 1, 0, 0, true, 10),
  ('vip_member', 'VIP Member', 'Granted to active VIP members.', 'workspace_premium', 'vip', 'rare', 0, 1, 0, true, 20),
  ('gift_sender', 'Gift Sender', 'For users who support rooms with gifts.', 'card_giftcard', 'achievement', 'common', 2, 0, 0, true, 30),
  ('room_host', 'Room Host', 'For creators and room hosts.', 'mic', 'achievement', 'rare', 3, 0, 0, true, 40),
  ('agency_member', 'Agency Member', 'Granted to active agency members.', 'groups', 'agency', 'rare', 0, 0, 0, true, 50),
  ('top_supporter', 'Top Supporter', 'Premium supporter badge.', 'favorite', 'premium', 'epic', 0, 0, 0, true, 60)
on conflict (badge_key) do update set
  name = excluded.name,
  description = excluded.description,
  icon = excluded.icon,
  category = excluded.category,
  rarity = excluded.rarity,
  required_level = excluded.required_level,
  required_vip_level = excluded.required_vip_level,
  price_coins = excluded.price_coins,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.level_rules (level, title, required_xp, badge_key, color_name, benefits, is_active)
values
  (1, 'New Voice', 0, 'new_member', 'bronze', '["Basic profile badge"]'::jsonb, true),
  (2, 'Rising Voice', 1000, 'gift_sender', 'silver', '["Gift sender badge"]'::jsonb, true),
  (3, 'Room Regular', 5000, 'room_host', 'gold', '["Room host badge"]'::jsonb, true),
  (4, 'Known Voice', 15000, null, 'purple', '["Profile level highlight"]'::jsonb, true),
  (5, 'SrOOd Star', 35000, null, 'diamond', '["Premium profile presence"]'::jsonb, true)
on conflict (level) do update set
  title = excluded.title,
  required_xp = excluded.required_xp,
  badge_key = excluded.badge_key,
  color_name = excluded.color_name,
  benefits = excluded.benefits,
  is_active = excluded.is_active,
  updated_at = now();

create or replace function public.ensure_user_settings()
returns public.user_settings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_settings public.user_settings;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  insert into public.user_settings (user_id)
  values (v_user_id)
  on conflict (user_id) do update set updated_at = public.user_settings.updated_at
  returning * into v_settings;

  return v_settings;
end;
$$;

create or replace function public.ensure_user_settings(p_user_id uuid)
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

  if p_user_id <> auth.uid() and not public.profile_hub_admin_access() then
    raise exception 'not_authorized';
  end if;

  insert into public.user_settings (user_id)
  values (p_user_id)
  on conflict (user_id) do update set updated_at = public.user_settings.updated_at
  returning * into v_settings;

  return v_settings;
end;
$$;

create or replace function public.ensure_user_level()
returns public.user_levels
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_level public.user_levels;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  insert into public.user_levels (user_id)
  values (v_user_id)
  on conflict (user_id) do update set updated_at = public.user_levels.updated_at
  returning * into v_level;

  return v_level;
end;
$$;

create or replace function public.ensure_user_level(p_user_id uuid)
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

  if p_user_id <> auth.uid() and not public.profile_hub_admin_access() then
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

  if p_user_id <> auth.uid() and not public.profile_hub_admin_access() then
    raise exception 'not_authorized';
  end if;

  insert into public.user_levels (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  update public.user_levels
  set xp = xp + greatest(coalesce(p_xp, 0), 0),
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

create or replace function public.ensure_income_account()
returns public.income_accounts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_account public.income_accounts;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  insert into public.income_accounts (user_id)
  values (v_user_id)
  on conflict (user_id) do update set updated_at = public.income_accounts.updated_at
  returning * into v_account;

  return v_account;
end;
$$;

create or replace function public.ensure_income_account(p_user_id uuid)
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

  if p_user_id <> auth.uid() and not public.profile_hub_admin_access() then
    raise exception 'not_authorized';
  end if;

  insert into public.income_accounts (user_id)
  values (p_user_id)
  on conflict (user_id) do update set updated_at = public.income_accounts.updated_at
  returning * into v_account;

  return v_account;
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

  update public.user_badges
  set is_equipped = false
  where user_id = v_user_id;

  update public.user_badges
  set is_equipped = true
  where user_id = v_user_id
    and badge_id = p_badge_id;

  return true;
end;
$$;

grant select on public.app_user_roles to authenticated;
grant select, insert, update on public.user_settings to authenticated;
grant select, insert, update on public.support_tickets to authenticated;
grant select, insert, update on public.feedback_tickets to authenticated;
grant select on public.badges to authenticated;
grant select, insert, update on public.user_badges to authenticated;
grant select, update on public.user_levels to authenticated;
grant select on public.level_rules to authenticated;
grant select on public.agencies to authenticated;
grant select on public.agency_members to authenticated;
grant select, insert, update on public.agency_applications to authenticated;
grant select, update on public.income_accounts to authenticated;
grant select on public.income_transactions to authenticated;
grant select, insert, update on public.payout_requests to authenticated;

grant execute on function public.has_app_role(text[]) to authenticated;
grant execute on function public.profile_hub_admin_access() to authenticated;
grant execute on function public.ensure_user_settings() to authenticated;
grant execute on function public.ensure_user_settings(uuid) to authenticated;
grant execute on function public.ensure_user_level() to authenticated;
grant execute on function public.ensure_user_level(uuid) to authenticated;
grant execute on function public.add_user_xp(uuid, bigint, text) to authenticated;
grant execute on function public.ensure_income_account() to authenticated;
grant execute on function public.ensure_income_account(uuid) to authenticated;
grant execute on function public.equip_user_badge(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
