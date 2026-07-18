-- Adds the new country/heritage luxury gifts and normalizes the luxury
-- gift price ladder. Idempotent upsert keyed on `code`, safe to rerun.
-- Uses U&'\XXXX' Unicode escape string literals for arabic_name to avoid
-- terminal/PowerShell encoding corruption (see 20260611120000_fix_corrupted_gift_arabic_names.sql).
--
-- Note: 'odrob' is intentionally excluded from this migration and left
-- untouched — its existing gift row, price, and thumbnail are out of scope.

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
values
  (
    'baalbek_temple',
    'Baalbek Temple',
    U&'\0642\0644\0639\0629 \0628\0639\0644\0628\0643',
    350000,
    'gift',
    'vip',
    true,
    941
  ),
  (
    'golden_lion',
    'Golden Lion',
    U&'\0627\0644\0623\0633\062f \0627\0644\0630\0647\0628\064a',
    500000,
    'gift',
    'vip',
    true,
    942
  ),
  (
    'egypt_royal',
    'Egypt Royal',
    U&'\0645\0635\0631 \0627\0644\0645\0644\0643\064a\0629',
    650000,
    'gift',
    'vip',
    true,
    943
  ),
  (
    'jordan_royal',
    'Jordan Royal',
    U&'\0627\0644\0623\0631\062f\0646 \0627\0644\0645\0644\0643\064a',
    700000,
    'gift',
    'vip',
    true,
    944
  ),
  (
    'iraq_royal',
    'Iraq Royal',
    U&'\0627\0644\0639\0631\0627\0642 \0627\0644\0645\0644\0643\064a',
    750000,
    'gift',
    'vip',
    true,
    945
  ),
  (
    'palestine_royal',
    'Palestine Royal',
    U&'\0641\0644\0633\0637\064a\0646 \0627\0644\0645\0644\0643\064a\0629',
    850000,
    'gift',
    'vip',
    true,
    946
  ),
  (
    'saudi_arabia_royal',
    'Saudi Arabia Royal',
    U&'\0627\0644\0633\0639\0648\062f\064a\0629 \0627\0644\0645\0644\0643\064a\0629',
    900000,
    'gift',
    'vip',
    true,
    947
  ),
  (
    'lebanon_royal',
    'Lebanon Royal',
    U&'\0644\0628\0646\0627\0646 \0627\0644\0645\0644\0643\064a',
    1000000,
    'gift',
    'vip',
    true,
    948
  ),
  (
    'cedar_throne',
    'Cedar Throne',
    U&'\0639\0631\0634 \0627\0644\0623\0631\0632',
    1100000,
    'gift',
    'vip',
    true,
    949
  ),
  (
    'byblos_royal_crown',
    'Byblos Royal Crown',
    U&'\062a\0627\062c \062c\0628\064a\0644 \0627\0644\0645\0644\0643\064a',
    1300000,
    'gift',
    'vip',
    true,
    950
  ),
  (
    'jeita_crystal_palace',
    'Jeita Crystal Palace',
    U&'\0642\0635\0631 \062c\0639\064a\062a\0627 \0627\0644\0643\0631\064a\0633\062a\0627\0644\064a',
    1500000,
    'gift',
    'vip',
    true,
    951
  ),
  (
    'phoenician_ship',
    'Phoenician Ship',
    U&'\0627\0644\0633\0641\064a\0646\0629 \0627\0644\0641\064a\0646\064a\0642\064a\0629',
    1800000,
    'gift',
    'vip',
    true,
    952
  ),
  (
    'lebanese_phoenix',
    'Lebanese Phoenix',
    U&'\0627\0644\0639\0646\0642\0627\0621 \0627\0644\0644\0628\0646\0627\0646\064a',
    2500000,
    'gift',
    'vip',
    true,
    953
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
