insert into public.gifts (
  code,
  name,
  arabic_name,
  price_coins,
  icon,
  category,
  is_active,
  sort_order
)
values (
  'odrob',
  'Odrob',
  '????',
  120000,
  '?',
  'vip',
  true,
  940
)
on conflict (code) do update
set
  name = excluded.name,
  arabic_name = excluded.arabic_name,
  price_coins = excluded.price_coins,
  icon = excluded.icon,
  category = excluded.category,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;
