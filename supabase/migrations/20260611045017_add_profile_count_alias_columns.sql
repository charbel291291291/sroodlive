-- Compatibility aliases for profile count fields.
-- This keeps old and new app code working.

alter table public.profiles
add column if not exists followers_count integer not null default 0;

alter table public.profiles
add column if not exists follower_count integer not null default 0;

alter table public.profiles
add column if not exists following_count integer not null default 0;

alter table public.profiles
add column if not exists followings_count integer not null default 0;

alter table public.profiles
add column if not exists friends_count integer not null default 0;

alter table public.profiles
add column if not exists friend_count integer not null default 0;

alter table public.profiles
add column if not exists rooms_count integer not null default 0;

alter table public.profiles
add column if not exists room_count integer not null default 0;

alter table public.profiles
add column if not exists gifts_sent_count integer not null default 0;

alter table public.profiles
add column if not exists gifts_received_count integer not null default 0;

alter table public.profiles
add column if not exists total_gifts_sent integer not null default 0;

alter table public.profiles
add column if not exists total_gifts_received integer not null default 0;

alter table public.profiles
add column if not exists coins_sent integer not null default 0;

alter table public.profiles
add column if not exists coins_received integer not null default 0;

alter table public.profiles
add column if not exists total_earned integer not null default 0;

alter table public.profiles
add column if not exists total_spent integer not null default 0;

alter table public.profiles
add column if not exists username text;

alter table public.profiles
add column if not exists display_name text;

alter table public.profiles
add column if not exists full_name text;

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

update public.profiles
set followers_count = follower_count
where followers_count = 0 and follower_count <> 0;

update public.profiles
set follower_count = followers_count
where follower_count = 0 and followers_count <> 0;

update public.profiles
set followings_count = following_count
where followings_count = 0 and following_count <> 0;

update public.profiles
set following_count = followings_count
where following_count = 0 and followings_count <> 0;

update public.profiles
set rooms_count = room_count
where rooms_count = 0 and room_count <> 0;

update public.profiles
set room_count = rooms_count
where room_count = 0 and rooms_count <> 0;

update public.profiles
set gifts_sent_count = total_gifts_sent
where gifts_sent_count = 0 and total_gifts_sent <> 0;

update public.profiles
set total_gifts_sent = gifts_sent_count
where total_gifts_sent = 0 and gifts_sent_count <> 0;

update public.profiles
set gifts_received_count = total_gifts_received
where gifts_received_count = 0 and total_gifts_received <> 0;

update public.profiles
set total_gifts_received = gifts_received_count
where total_gifts_received = 0 and gifts_received_count <> 0;

create index if not exists profiles_followers_count_idx
on public.profiles (followers_count);

create index if not exists profiles_follower_count_idx
on public.profiles (follower_count);

create index if not exists profiles_following_count_idx
on public.profiles (following_count);

create index if not exists profiles_followings_count_idx
on public.profiles (followings_count);

create index if not exists profiles_is_online_idx
on public.profiles (is_online);

create index if not exists profiles_level_idx
on public.profiles (level);

create index if not exists profiles_vip_level_idx
on public.profiles (vip_level);