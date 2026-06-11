-- Profile social stats compatibility columns.
-- Covers Discover, Search, Profile, Follow, Visitor, Leaderboard, and social cards.

alter table public.profiles
add column if not exists visitors_count integer not null default 0;

alter table public.profiles
add column if not exists visitor_count integer not null default 0;

alter table public.profiles
add column if not exists views_count integer not null default 0;

alter table public.profiles
add column if not exists view_count integer not null default 0;

alter table public.profiles
add column if not exists likes_count integer not null default 0;

alter table public.profiles
add column if not exists like_count integer not null default 0;

alter table public.profiles
add column if not exists posts_count integer not null default 0;

alter table public.profiles
add column if not exists post_count integer not null default 0;

alter table public.profiles
add column if not exists fans_count integer not null default 0;

alter table public.profiles
add column if not exists fan_count integer not null default 0;

alter table public.profiles
add column if not exists badge_count integer not null default 0;

alter table public.profiles
add column if not exists badges_count integer not null default 0;

alter table public.profiles
add column if not exists charm_count integer not null default 0;

alter table public.profiles
add column if not exists charms_count integer not null default 0;

alter table public.profiles
add column if not exists popularity_score integer not null default 0;

alter table public.profiles
add column if not exists wealth_score integer not null default 0;

alter table public.profiles
add column if not exists charm_score integer not null default 0;

alter table public.profiles
add column if not exists contribution_score integer not null default 0;

alter table public.profiles
add column if not exists experience_points integer not null default 0;

alter table public.profiles
add column if not exists xp integer not null default 0;

alter table public.profiles
add column if not exists status text;

alter table public.profiles
add column if not exists mood text;

alter table public.profiles
add column if not exists city text;

alter table public.profiles
add column if not exists birthdate date;

alter table public.profiles
add column if not exists public_user_id text;

create index if not exists profiles_visitors_count_idx
on public.profiles (visitors_count);

create index if not exists profiles_likes_count_idx
on public.profiles (likes_count);

create index if not exists profiles_popularity_score_idx
on public.profiles (popularity_score);

create index if not exists profiles_wealth_score_idx
on public.profiles (wealth_score);

create index if not exists profiles_public_user_id_idx
on public.profiles (public_user_id);