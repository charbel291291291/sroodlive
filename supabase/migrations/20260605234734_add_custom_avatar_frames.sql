insert into public.avatar_frames (
  frame_key,
  name,
  category,
  vip_level,
  required_vip_level,
  asset_url,
  is_active,
  sort_order
)
values
  (
    'custom_srood_live',
    'SrOOd Live Frame',
    'vip',
    1,
    1,
    'assets/avatar_frames/custom/srood_live_frame.png',
    true,
    42
  ),
  (
    'custom_super_admin',
    'Super Admin Frame',
    'vip',
    5,
    5,
    'assets/avatar_frames/custom/super_admin_frame.png',
    true,
    43
  ),
  (
    'custom_admin',
    'Admin Frame',
    'vip',
    4,
    4,
    'assets/avatar_frames/custom/admin_frame.png',
    true,
    44
  ),
  (
    'custom_luxury_gold',
    'Luxury Gold Frame',
    'luxury',
    null,
    0,
    'assets/avatar_frames/custom/luxury_gold_frame.png',
    true,
    45
  ),
  (
    'custom_luxury_diamond',
    'Luxury Diamond Frame',
    'luxury',
    null,
    0,
    'assets/avatar_frames/custom/luxury_diamond_frame.png',
    true,
    46
  )
on conflict (frame_key) do update set
  name = excluded.name,
  category = excluded.category,
  vip_level = excluded.vip_level,
  required_vip_level = excluded.required_vip_level,
  asset_url = excluded.asset_url,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;
