-- Promotional banners for Srood Live carousel.

create table if not exists public.promo_banners (
  id uuid primary key default gen_random_uuid(),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  slide_key text not null unique,

  label_en text not null default '',
  label_ar text not null default '',
  title_en text not null default '',
  title_ar text not null default '',
  subtitle_en text not null default '',
  subtitle_ar text not null default '',
  cta_en text not null default '',
  cta_ar text not null default '',

  gradient_start text,
  gradient_mid text,
  gradient_end text,
  icon_name text not null default 'mic_rounded',
  icon_bg_color text,
  image_url text,
  target_route text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.promo_banners enable row level security;

drop policy if exists "promo_banners_select" on public.promo_banners;
create policy "promo_banners_select"
  on public.promo_banners for select to authenticated
  using (true);

drop policy if exists "promo_banners_insert" on public.promo_banners;
create policy "promo_banners_insert"
  on public.promo_banners for insert to authenticated
  with check (
    public.has_app_role('super_admin') or public.has_app_role('content_admin')
  );

drop policy if exists "promo_banners_update" on public.promo_banners;
create policy "promo_banners_update"
  on public.promo_banners for update to authenticated
  using (
    public.has_app_role('super_admin') or public.has_app_role('content_admin')
  );

drop policy if exists "promo_banners_delete" on public.promo_banners;
create policy "promo_banners_delete"
  on public.promo_banners for delete to authenticated
  using (
    public.has_app_role('super_admin') or public.has_app_role('content_admin')
  );

grant select, insert, update, delete on public.promo_banners to authenticated;

insert into public.promo_banners (
  sort_order, is_active, slide_key,
  label_en, label_ar, title_en, title_ar,
  subtitle_en, subtitle_ar, cta_en, cta_ar,
  gradient_start, gradient_mid, gradient_end,
  icon_name, icon_bg_color, target_route
) values
(
  1, true, 'explore_rooms',
  'Srood Live', '',
  'Pick a room and start the night', '',
  'Join live voice rooms, hosts, and listeners.', '',
  'Explore Rooms', '',
  'FF2D0D5E', 'FF5B1A9A', 'FF8B26D9',
  'mic_rounded', 'FF6E14B8', 'discovery'
),
(
  2, true, 'rewards',
  'Rewards', '',
  'Send gifts and rise faster', '',
  'Support your favorite hosts and unlock rewards.', '',
  'View Gifts', '',
  'FF1A0D2E', 'FF4A1A5E', 'FFB8860B',
  'redeem_rounded', 'FF3D1A5A', 'gifts'
),
(
  3, true, 'vip',
  'VIP', '',
  'Unlock VIP perks', '',
  'Get badges, profile style, and premium presence.', '',
  'VIP Center', '',
  'FF10142E', 'FF2D0D5E', 'FF8B26D9',
  'workspace_premium_rounded', 'FF5B1A9A', 'vip'
)
on conflict (slide_key) do update set
  sort_order = excluded.sort_order,
  is_active = excluded.is_active,
  label_en = excluded.label_en,
  title_en = excluded.title_en,
  subtitle_en = excluded.subtitle_en,
  cta_en = excluded.cta_en,
  gradient_start = excluded.gradient_start,
  gradient_mid = excluded.gradient_mid,
  gradient_end = excluded.gradient_end,
  icon_name = excluded.icon_name,
  icon_bg_color = excluded.icon_bg_color,
  target_route = excluded.target_route,
  updated_at = now();