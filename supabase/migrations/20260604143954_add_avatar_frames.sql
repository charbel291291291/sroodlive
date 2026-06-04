create table if not exists public.avatar_frames (
  id uuid primary key default gen_random_uuid(),
  frame_key text unique not null,
  name text not null,
  category text not null check (category in ('normal', 'luxury', 'vip')),
  vip_level int,
  asset_url text,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.avatar_frames enable row level security;

grant select on public.avatar_frames to authenticated;

drop policy if exists "Authenticated users can view active avatar frames" on public.avatar_frames;

create policy "Authenticated users can view active avatar frames"
on public.avatar_frames
for select
to authenticated
using (is_active = true);

alter table public.profiles
add column if not exists selected_avatar_frame_key text,
add column if not exists vip_level int not null default 0;

alter table public.profiles
drop constraint if exists profiles_selected_avatar_frame_key_fkey;

alter table public.profiles
add constraint profiles_selected_avatar_frame_key_fkey
foreign key (selected_avatar_frame_key)
references public.avatar_frames(frame_key)
on update cascade
on delete set null;

insert into public.avatar_frames (
  frame_key,
  name,
  category,
  vip_level,
  asset_url,
  is_active,
  sort_order
)
values
  ('normal_silver_ring', 'Silver Ring', 'normal', null, null, true, 10),
  ('normal_blue_glow', 'Blue Glow', 'normal', null, null, true, 20),
  ('normal_soft_gold', 'Soft Gold', 'normal', null, null, true, 30),
  ('luxury_royal_gold', 'Royal Gold', 'luxury', null, null, true, 110),
  ('luxury_diamond_purple', 'Diamond Purple', 'luxury', null, null, true, 120),
  ('luxury_black_gold_crown', 'Black Gold Crown', 'luxury', null, null, true, 130),
  ('vip_bronze_star', 'Bronze Star', 'vip', 1, null, true, 210),
  ('vip_silver_flame', 'Silver Flame', 'vip', 2, null, true, 220),
  ('vip_gold_crown', 'Gold Crown', 'vip', 3, null, true, 230),
  ('vip_platinum_diamond', 'Platinum Diamond', 'vip', 4, null, true, 240),
  ('vip_royal_king', 'Royal King', 'vip', 5, null, true, 250)
on conflict (frame_key) do update set
  name = excluded.name,
  category = excluded.category,
  vip_level = excluded.vip_level,
  asset_url = excluded.asset_url,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;
