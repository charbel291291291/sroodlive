alter table public.profiles
drop constraint if exists profiles_vip_level_range;

update public.profiles
set vip_level = greatest(0, least(coalesce(vip_level, 0), 10))
where vip_level < 0 or vip_level > 10;

alter table public.profiles
add constraint profiles_vip_level_range
check (vip_level between 0 and 10);

alter table public.vip_packages
drop constraint if exists vip_packages_vip_level_check;

alter table public.vip_packages
add constraint vip_packages_vip_level_check
check (vip_level between 1 and 10);

alter table public.entrance_banners
drop constraint if exists entrance_banners_vip_level_check;

alter table public.entrance_banners
add constraint entrance_banners_vip_level_check
check (vip_level is null or vip_level between 1 and 10);

alter table public.vip_plans
drop constraint if exists vip_plans_level_check;

alter table public.vip_plans
add constraint vip_plans_level_check
check (level between 1 and 10);

alter table public.badges
drop constraint if exists badges_required_vip_level_check;

alter table public.badges
add constraint badges_required_vip_level_check
check (required_vip_level is null or required_vip_level between 1 and 10);

insert into public.entrance_banners (
  banner_key,
  name,
  arabic_name,
  vip_level,
  gradient_start,
  gradient_end,
  message_template,
  is_active,
  sort_order
)
values
  ('vip_6_elite', 'VIP Elite Entry', 'VIP 6', 6, '#081D32', '#5DDCFF', '{name} entered with elite aura', true, 60),
  ('vip_7_mythic', 'VIP Mythic Entry', 'VIP 7', 7, '#230C3D', '#C875FF', '{name} entered with mythic presence', true, 70),
  ('vip_8_emperor', 'VIP Emperor Entry', 'VIP 8', 8, '#331000', '#FFB44C', '{name} entered with emperor prestige', true, 80),
  ('vip_9_celestial', 'VIP Celestial Entry', 'VIP 9', 9, '#071F24', '#75FFE8', '{name} entered with celestial glow', true, 90),
  ('vip_10_srood', 'VIP 10 SrOOd Legend Entry', 'VIP 10', 10, '#240012', '#FF4FD8', '{name} entered as a SrOOd legend', true, 100)
on conflict (banner_key) do update set
  name = excluded.name,
  arabic_name = excluded.arabic_name,
  vip_level = excluded.vip_level,
  gradient_start = excluded.gradient_start,
  gradient_end = excluded.gradient_end,
  message_template = excluded.message_template,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.vip_packages (
  vip_level,
  code,
  name,
  arabic_name,
  price_coins,
  duration_days,
  badge_label,
  entrance_banner_key,
  is_active,
  sort_order
)
values
  (1, 'vip_1_bronze', 'VIP 1 Bronze', 'VIP 1', 1000, 30, 'VIP 1', 'vip_1_gold', true, 10),
  (2, 'vip_2_silver', 'VIP 2 Silver', 'VIP 2', 3000, 30, 'VIP 2', 'vip_2_flame', true, 20),
  (3, 'vip_3_gold', 'VIP 3 Gold', 'VIP 3', 8000, 30, 'VIP 3', 'vip_3_royal', true, 30),
  (4, 'vip_4_diamond', 'VIP 4 Diamond', 'VIP 4', 18000, 30, 'VIP 4', 'vip_4_diamond', true, 40),
  (5, 'vip_5_royal', 'VIP 5 Royal King', 'VIP 5+', 40000, 30, 'VIP 5+', 'vip_5_king', true, 50),
  (6, 'vip_6_elite', 'VIP 6 Elite', 'VIP 6+', 70000, 30, 'VIP 6+', 'vip_6_elite', true, 60),
  (7, 'vip_7_mythic', 'VIP 7 Mythic', 'VIP 7+', 110000, 30, 'VIP 7+', 'vip_7_mythic', true, 70),
  (8, 'vip_8_emperor', 'VIP 8 Emperor', 'VIP 8+', 160000, 30, 'VIP 8+', 'vip_8_emperor', true, 80),
  (9, 'vip_9_celestial', 'VIP 9 Celestial', 'VIP 9+', 220000, 30, 'VIP 9+', 'vip_9_celestial', true, 90),
  (10, 'vip_10_srood_legend', 'VIP 10 SrOOd Legend', 'VIP 10+', 300000, 30, 'VIP 10+', 'vip_10_srood', true, 100)
on conflict (vip_level) do update set
  code = excluded.code,
  name = excluded.name,
  arabic_name = excluded.arabic_name,
  price_coins = excluded.price_coins,
  duration_days = excluded.duration_days,
  badge_label = excluded.badge_label,
  entrance_banner_key = excluded.entrance_banner_key,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  updated_at = now();

delete from public.vip_plans stale
using public.vip_plans keeper
where stale.level = keeper.level
  and stale.ctid < keeper.ctid;

create unique index if not exists vip_plans_level_unique_idx
on public.vip_plans (level);

insert into public.vip_plans (
  name,
  level,
  price_coins,
  duration_days,
  badge_style,
  frame_key,
  benefits,
  is_active,
  sort_order
)
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
on conflict (level) do update set
  name = excluded.name,
  price_coins = excluded.price_coins,
  duration_days = excluded.duration_days,
  badge_style = excluded.badge_style,
  frame_key = excluded.frame_key,
  benefits = excluded.benefits,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  updated_at = now();

create or replace function public.admin_grant_vip(
  p_user_id uuid,
  p_vip_level integer,
  p_days integer default 30,
  p_title text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level integer := greatest(0, least(coalesce(p_vip_level, 0), 10));
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('support_admin')) then
    raise exception 'not_authorized';
  end if;

  update public.profiles
  set vip_level = v_level,
      vip_started_at = case when v_level > 0 then now() else null end,
      vip_expires_at = case when v_level > 0 then now() + make_interval(days => greatest(coalesce(p_days, 30), 1)) else null end,
      vip_title = nullif(trim(coalesce(p_title, '')), '')
  where id = p_user_id;

  perform public.admin_record_audit(
    'grant_vip',
    'profiles',
    p_user_id::text,
    p_user_id,
    jsonb_build_object('vip_level', v_level, 'days', p_days, 'title', p_title)
  );
end;
$$;

create or replace function public.admin_update_vip_package(
  p_vip_level integer,
  p_code text,
  p_name text,
  p_arabic_name text default null,
  p_price_coins integer default 0,
  p_duration_days integer default 30,
  p_badge_label text default null,
  p_entrance_banner_key text default null,
  p_is_active boolean default true,
  p_sort_order integer default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('content_admin')) then
    raise exception 'not_authorized';
  end if;

  insert into public.vip_packages (
    vip_level, code, name, arabic_name, price_coins, duration_days,
    badge_label, entrance_banner_key, is_active, sort_order, updated_at
  )
  values (
    greatest(1, least(p_vip_level, 10)),
    lower(trim(p_code)),
    trim(p_name),
    nullif(trim(coalesce(p_arabic_name, '')), ''),
    greatest(coalesce(p_price_coins, 0), 0),
    greatest(coalesce(p_duration_days, 30), 1),
    nullif(trim(coalesce(p_badge_label, '')), ''),
    nullif(trim(coalesce(p_entrance_banner_key, '')), ''),
    coalesce(p_is_active, true),
    coalesce(p_sort_order, 0),
    now()
  )
  on conflict (vip_level) do update set
    code = excluded.code,
    name = excluded.name,
    arabic_name = excluded.arabic_name,
    price_coins = excluded.price_coins,
    duration_days = excluded.duration_days,
    badge_label = excluded.badge_label,
    entrance_banner_key = excluded.entrance_banner_key,
    is_active = excluded.is_active,
    sort_order = excluded.sort_order,
    updated_at = now()
  returning id into v_id;

  perform public.admin_record_audit(
    'update_vip_package',
    'vip_packages',
    greatest(1, least(p_vip_level, 10))::text,
    null,
    jsonb_build_object('vip_level', p_vip_level, 'price_coins', p_price_coins)
  );

  return v_id;
end;
$$;
