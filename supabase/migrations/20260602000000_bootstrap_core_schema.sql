-- ============================================================
-- Local-dev bootstrap for tables created directly in prod
-- outside of migration history (schema drift).
-- Mirrors production's current column set for these tables so
-- `supabase start` can replay migration history from empty.
-- Columns with function-based defaults (public_user_id,
-- public_room_code) are left nullable/default-less here; their
-- owning migrations (20260926030000, 20260926040000) set the
-- real default/not-null/constraint once the generator functions
-- exist.
-- ============================================================

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  username text unique,
  display_name text,
  avatar_url text,
  role text not null default 'user',
  is_banned boolean not null default false,
  coins_balance integer not null default 0,
  vip_level integer not null default 0,
  vip_expires_at timestamptz,
  public_user_id text unique,
  date_of_birth date,
  bio text,
  selected_avatar_frame_key text,
  vip_started_at timestamptz,
  vip_title text,
  is_golden_id boolean not null default false,
  golden_id_expires_at timestamptz,
  follower_count integer not null default 0,
  following_count integer not null default 0,
  friends_count integer not null default 0,
  room_count integer not null default 0,
  total_gifts_sent integer not null default 0,
  total_gifts_received integer not null default 0,
  cover_url text,
  country text,
  gender text,
  is_online boolean not null default false,
  last_seen timestamptz,
  level integer not null default 1,
  full_name text,
  golden_id_style text not null default 'gold',
  golden_id_frame text not null default 'classic',
  country_code text,
  country_flag_style text not null default 'normal',
  country_flag_frame text not null default 'classic',
  country_flag_expires_at timestamptz,
  gender_changed_once boolean not null default false,
  country_changed_once boolean not null default false,
  gender_changed_at timestamptz,
  country_changed_at timestamptz,
  vip_recharge_exp bigint not null default 0,
  vip_monthly_exp bigint not null default 0,
  vip_cycle_started_at timestamptz,
  vip_last_recharge_at timestamptz,
  status text,
  mood text,
  city text,
  birthdate date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  description text,
  language text not null default 'ar',
  is_private boolean not null default false,
  is_locked boolean not null default false,
  max_seats integer not null default 12,
  livekit_room_name text not null unique,
  member_count integer not null default 0,
  max_members integer,
  public_room_code text,
  room_password_hash text,
  is_closed boolean not null default false,
  closed_at timestamptz,
  closed_by uuid references auth.users(id) on delete set null,
  closed_reason text,
  is_live boolean not null default false,
  ended_at timestamptz,
  cover_url text,
  category text,
  tags text[] not null default '{}',
  background_url text,
  room_avatar_url text,
  room_pin_enabled boolean not null default false,
  room_pin_hash text,
  is_personal_room boolean not null default false,
  closed_seats integer[] not null default '{}',
  room_level smallint not null default 1,
  allow_images boolean not null default true,
  is_room_muted boolean not null default false,
  country_code text,
  golden_room_id text unique,
  is_golden_room boolean not null default false,
  golden_room_expires_at timestamptz,
  room_xp bigint not null default 0,
  xp_today_gift integer not null default 0,
  xp_today_passive integer not null default 0,
  xp_week bigint not null default 0,
  daily_streak smallint not null default 0,
  streak_multiplier numeric not null default 1.00,
  last_active_date date,
  last_xp_at timestamptz,
  archived_at timestamptz,
  archived_by uuid references auth.users(id) on delete set null,
  archive_reason text,
  deleted_at timestamptz,
  deleted_by uuid references auth.users(id) on delete set null,
  delete_reason text,
  access_mode text not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.room_members (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'listener',
  seat_number integer,
  is_muted boolean not null default false,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  force_muted boolean not null default false,
  unique (room_id, user_id)
);

create table if not exists public.gifts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  arabic_name text not null,
  price_coins integer not null,
  icon text not null default 'gift',
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.gift_transactions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  gift_id uuid not null references public.gifts(id),
  gift_code text not null,
  gift_name text not null,
  gift_price_coins integer not null,
  created_at timestamptz not null default now()
);

create table if not exists public.red_envelopes (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  total_coins integer not null,
  envelope_count integer not null,
  claimed_count integer not null default 0,
  is_expired boolean not null default false,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '5 minutes')
);

create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  badge_key text not null unique,
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

create table if not exists public.room_schedules (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text,
  scheduled_at timestamptz not null,
  rsvp_count integer not null default 0,
  created_at timestamptz not null default now()
);

-- Columns are the union of what two conflicting migration-history
-- versions of this table's schema reference (20260617000000 defines
-- target_type/target_id/resolved_by; 20260629000000's hotfix uses
-- reported_user_id/room_id, matching prod's actual current shape).
create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid references auth.users(id) on delete cascade,
  room_id uuid references public.rooms(id) on delete set null,
  target_type text,
  target_id text,
  reason text not null,
  details text,
  status text not null default 'open',
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  resolution_note text,
  created_at timestamptz not null default now()
);

create table if not exists public.startup_promos (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  image_url text not null,
  storage_path text,
  is_active boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  duration_seconds integer not null default 5,
  frequency text not null default 'once_per_day',
  priority integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.room_schedules enable row level security;
alter table public.user_reports enable row level security;
alter table public.startup_promos enable row level security;

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.gifts enable row level security;
alter table public.gift_transactions enable row level security;
alter table public.red_envelopes enable row level security;
alter table public.badges enable row level security;
