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
  ('luxury_crystal_feather', 'Crystal Feather', 'luxury', null, null, true, 140),
  ('luxury_autumn_bloom', 'Autumn Bloom', 'luxury', null, null, true, 150)
on conflict (frame_key) do update set
  name = excluded.name,
  category = excluded.category,
  vip_level = excluded.vip_level,
  asset_url = excluded.asset_url,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;
