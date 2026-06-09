-- ============================================================================
-- Correct recharge_packages coin rate to the real business rule.
--
-- Business rule: 1 USD = 500,000 coins  ->  coins_amount = price_usd * 500000
--
-- Background:
--   * The recharge_packages table is defined in
--     20260606073000_full_social_economy_schema.sql and was seeded (together
--     with 20260606102000_update_coin_recharge_rate_to_10000.sql) at the WRONG
--     rate of 10,000 coins per USD.
--   * That economy-schema lineage is NOT applied to every environment. The
--     primary production database, for example, has no recharge_packages table;
--     it serves packages through the Flutter fallback
--     (CoinConstants.coinsPerUsd = 500000), which is already correct.
--
-- This migration therefore GUARDS on table existence so it is valid in every
-- environment:
--   * Where recharge_packages exists, it corrects every active row to
--     coins_amount = price_usd * 500000.
--   * Where it does not exist, it is a safe no-op (no error).
--
-- Scope and safety:
--   * Additive. Old migrations are left untouched.
--   * Idempotent: only updates active rows whose coins_amount does not already
--     equal price_usd * 500000, so re-running is a no-op.
--   * Non-destructive: no DELETEs. Titles, price_usd, bonus_coins, is_active,
--     is_featured and sort_order are left exactly as they are.
--   * total_coins is a GENERATED column (coins_amount + bonus_coins) and is
--     recomputed automatically by Postgres.
--   * Does NOT touch wallet balances, recharge requests/transactions, or any
--     coin/transaction ledgers.
-- ============================================================================

do $$
begin
  if to_regclass('public.recharge_packages') is not null then
    update public.recharge_packages
    set coins_amount = (price_usd * 500000)::bigint,
        updated_at = now()
    where is_active = true
      and coins_amount is distinct from (price_usd * 500000)::bigint;
  end if;
end;
$$;
