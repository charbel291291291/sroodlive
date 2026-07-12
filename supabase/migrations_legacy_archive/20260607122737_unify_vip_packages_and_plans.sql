-- Unify SrOOd Live VIP system.
-- Official pricing follows 1 USD = 500,000 coins.
-- vip_packages is used by Admin Dashboard.
-- vip_plans is used by user purchase flow.
-- Both must stay aligned.

alter table public.vip_packages
drop constraint if exists vip_packages_vip_level_check;

alter table public.vip_packages
add constraint vip_packages_vip_level_check
check (vip_level between 1 and 10);

alter table public.vip_plans
drop constraint if exists vip_plans_level_check;

alter table public.vip_plans
add constraint vip_plans_level_check
check (level between 1 and 10);

delete from public.vip_packages
where vip_level not between 1 and 10;

delete from public.vip_plans
where level not between 1 and 10;

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
  sort_order,
  updated_at
)
values
  (1, 'vip_1_silver', 'VIP 1 Silver', 'VIP 1 فضي', 1000000, 30, 'VIP 1', 'vip_1_gold', true, 10, now()),
  (2, 'vip_2_gold', 'VIP 2 Gold', 'VIP 2 ذهبي', 2500000, 30, 'VIP 2', 'vip_2_flame', true, 20, now()),
  (3, 'vip_3_diamond', 'VIP 3 Diamond', 'VIP 3 ألماسي', 5000000, 30, 'VIP 3', 'vip_3_royal', true, 30, now()),
  (4, 'vip_4_royal', 'VIP 4 Royal', 'VIP 4 ملكي', 10000000, 30, 'VIP 4', 'vip_4_diamond', true, 40, now()),
  (5, 'vip_5_legend', 'VIP 5 Legend', 'VIP 5 أسطوري', 20000000, 30, 'VIP 5', 'vip_5_king', true, 50, now()),
  (6, 'vip_6_elite', 'VIP 6 Elite', 'VIP 6 نخبة', 30000000, 30, 'VIP 6', 'vip_6_elite', true, 60, now()),
  (7, 'vip_7_mythic', 'VIP 7 Mythic', 'VIP 7 خرافي', 45000000, 30, 'VIP 7', 'vip_7_mythic', true, 70, now()),
  (8, 'vip_8_emperor', 'VIP 8 Emperor', 'VIP 8 إمبراطور', 65000000, 30, 'VIP 8', 'vip_8_emperor', true, 80, now()),
  (9, 'vip_9_celestial', 'VIP 9 Celestial', 'VIP 9 سماوي', 90000000, 30, 'VIP 9', 'vip_9_celestial', true, 90, now()),
  (10, 'vip_10_srood_legend', 'VIP 10 SrOOd Legend', 'VIP 10 أسطورة SrOOd', 120000000, 30, 'VIP 10', 'vip_10_srood', true, 100, now())
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
  sort_order,
  updated_at
)
values
  ('VIP 1 Silver', 1, 1000000, 30, 'silver', null, '["special badge", "colored username", "profile glow"]'::jsonb, true, 10, now()),
  ('VIP 2 Gold', 2, 2500000, 30, 'gold', 'custom_luxury_gold', '["special badge", "avatar frame", "colored username", "profile glow"]'::jsonb, true, 20, now()),
  ('VIP 3 Diamond', 3, 5000000, 30, 'diamond', 'custom_luxury_diamond', '["special badge", "avatar frame", "room entrance effect", "exclusive gifts"]'::jsonb, true, 30, now()),
  ('VIP 4 Royal', 4, 10000000, 30, 'royal', 'custom_srood_live', '["priority mic seat request", "premium room badge", "profile glow"]'::jsonb, true, 40, now()),
  ('VIP 5 Legend', 5, 20000000, 30, 'legend', 'custom_srood_live', '["all VIP benefits", "legend profile glow", "premium room badge", "strong kick protection"]'::jsonb, true, 50, now()),
  ('VIP 6 Elite', 6, 30000000, 30, 'elite', 'custom_srood_live', '["VIP 5 benefits", "elite entrance banner", "stronger profile glow", "priority support"]'::jsonb, true, 60, now()),
  ('VIP 7 Mythic', 7, 45000000, 30, 'mythic', 'custom_luxury_diamond', '["VIP 6 benefits", "mythic badge style", "premium room highlight", "exclusive gift access"]'::jsonb, true, 70, now()),
  ('VIP 8 Emperor', 8, 65000000, 30, 'emperor', 'custom_luxury_gold', '["VIP 7 benefits", "emperor entrance", "top profile priority", "advanced anti-kick protection"]'::jsonb, true, 80, now()),
  ('VIP 9 Celestial', 9, 90000000, 30, 'celestial', 'custom_luxury_diamond', '["VIP 8 benefits", "celestial profile glow", "elite identity effects", "highest room prestige"]'::jsonb, true, 90, now()),
  ('VIP 10 SrOOd Legend', 10, 120000000, 30, 'srood_legend', 'custom_srood_live', '["all VIP benefits", "SrOOd legend badge", "maximum profile glow", "legend entrance", "top priority support"]'::jsonb, true, 100, now())
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

-- Keep entrance banners aligned from VIP 1 to VIP 10.
update public.entrance_banners
set is_active = true
where vip_level between 1 and 10;
