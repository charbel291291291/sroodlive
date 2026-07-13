-- Discovery/Search compatibility columns.
-- Safe migration. Every column uses IF NOT EXISTS.

-- Rooms columns used by Discover, Search, Live, and Room cards.
alter table public.rooms
add column if not exists is_live boolean not null default false;

alter table public.rooms
add column if not exists ended_at timestamptz;

alter table public.rooms
add column if not exists cover_url text;

alter table public.rooms
add column if not exists member_count integer not null default 0;

alter table public.rooms
add column if not exists max_members integer;

alter table public.rooms
add column if not exists category text;

alter table public.rooms
add column if not exists tags text[] not null default '{}';

alter table public.rooms
add column if not exists language text;

alter table public.rooms
add column if not exists is_private boolean not null default false;

alter table public.rooms
add column if not exists updated_at timestamptz not null default now();

-- Profiles columns used by Discover, Search, Profile cards, Follow lists, and Leaderboards.
alter table public.profiles
add column if not exists follower_count integer not null default 0;

alter table public.profiles
add column if not exists following_count integer not null default 0;

alter table public.profiles
add column if not exists friends_count integer not null default 0;

alter table public.profiles
add column if not exists room_count integer not null default 0;

alter table public.profiles
add column if not exists total_gifts_sent integer not null default 0;

alter table public.profiles
add column if not exists total_gifts_received integer not null default 0;

alter table public.profiles
add column if not exists avatar_url text;

alter table public.profiles
add column if not exists cover_url text;

alter table public.profiles
add column if not exists bio text;

alter table public.profiles
add column if not exists country text;

alter table public.profiles
add column if not exists gender text;

alter table public.profiles
add column if not exists is_online boolean not null default false;

alter table public.profiles
add column if not exists last_seen timestamptz;

alter table public.profiles
add column if not exists level integer not null default 1;

alter table public.profiles
add column if not exists vip_level integer not null default 0;

alter table public.profiles
add column if not exists updated_at timestamptz not null default now();

-- Indexes for faster Discover/Search screens.
create index if not exists rooms_is_live_idx
on public.rooms (is_live);

create index if not exists rooms_member_count_idx
on public.rooms (member_count);

create index if not exists rooms_category_idx
on public.rooms (category);

create index if not exists rooms_language_idx
on public.rooms (language);

create index if not exists profiles_follower_count_idx
on public.profiles (follower_count);

create index if not exists profiles_is_online_idx
on public.profiles (is_online);

create index if not exists profiles_country_idx
on public.profiles (country);

create index if not exists profiles_level_idx
on public.profiles (level);