update public.recharge_packages
set coins_amount = (price_usd * 10000)::bigint,
    bonus_coins = 0,
    updated_at = now()
where price_usd in (1, 2, 5, 10, 20, 50, 100)
  and bonus_coins = 0
  and coins_amount = (price_usd * 500000)::bigint;

insert into public.recharge_packages (
  title,
  price_usd,
  coins_amount,
  bonus_coins,
  is_active,
  is_featured,
  sort_order
)
select *
from (
  values
    ('$1 Starter', 1::numeric, 10000::bigint, 0::bigint, true, false, 10),
    ('$2 Basic', 2::numeric, 20000::bigint, 0::bigint, true, false, 20),
    ('$5 Popular', 5::numeric, 50000::bigint, 0::bigint, true, true, 30),
    ('$10 Premium', 10::numeric, 100000::bigint, 0::bigint, true, false, 40),
    ('$20 Deluxe', 20::numeric, 200000::bigint, 0::bigint, true, false, 50),
    ('$50 Royal', 50::numeric, 500000::bigint, 0::bigint, true, false, 60),
    ('$100 Legend', 100::numeric, 1000000::bigint, 0::bigint, true, false, 70)
) as package_seed(title, price_usd, coins_amount, bonus_coins, is_active, is_featured, sort_order)
where not exists (
  select 1
  from public.recharge_packages existing
  where existing.price_usd = package_seed.price_usd
    and existing.coins_amount = package_seed.coins_amount
    and existing.bonus_coins = package_seed.bonus_coins
);
