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
  (
    'luxury_ruby_royal',
    'Ruby Royal Frame',
    'luxury',
    null,
    'assets/avatar_frames/luxury_ruby_royal.png',
    true,
    40
  ),
  (
    'luxury_ruby_royal_dark',
    'Ruby Royal Dark Frame',
    'luxury',
    null,
    'assets/avatar_frames/luxury_ruby_royal_dark.png',
    true,
    41
  )
on conflict (frame_key) do update set
  name = excluded.name,
  category = excluded.category,
  vip_level = excluded.vip_level,
  asset_url = excluded.asset_url,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;
