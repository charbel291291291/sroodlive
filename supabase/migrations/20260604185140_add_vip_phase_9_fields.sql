alter table public.profiles
add column if not exists vip_level integer not null default 0,
add column if not exists vip_started_at timestamptz null,
add column if not exists vip_expires_at timestamptz null,
add column if not exists vip_title text null;

update public.profiles
set vip_level = greatest(0, least(vip_level, 5))
where vip_level < 0 or vip_level > 5;

alter table public.profiles
drop constraint if exists profiles_vip_level_range;

alter table public.profiles
add constraint profiles_vip_level_range
check (vip_level between 0 and 5);
