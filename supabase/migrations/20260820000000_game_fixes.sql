-- ─────────────────────────────────────────────────────────────────────────────
-- Game Fixes: duplicate-bet protection + game_settings safety seed
-- Idempotent: safe to run multiple times.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Unique constraint: one bet per user per Hungry Cat round
--    Prevents double-payout even if the client sends duplicate requests.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hcgb_unique_user_round'
      and conrelid = 'public.hungry_cat_global_bets'::regclass
  ) then
    alter table public.hungry_cat_global_bets
      add constraint hcgb_unique_user_round unique (round_id, user_id);
  end if;
end;
$$;

-- 2. Update place_hungry_cat_global_bet to raise a clear error on duplicates
--    (the unique constraint above will also enforce this at DB level).
create or replace function public.place_hungry_cat_global_bet(
  p_round_id uuid,
  p_food_id  text,
  p_amount   integer
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid := auth.uid();
  v_round       public.hungry_cat_global_rounds;
  v_food        public.hungry_cat_config;
  v_wallet      public.wallets;
  v_bet_id      uuid;
  v_new_balance integer;
  c_min constant integer := 100;
  c_max constant integer := 100000;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  if not exists (
    select 1 from public.game_settings
    where game_key = 'hungry_cat' and is_enabled
  ) then
    raise exception 'game_disabled';
  end if;

  if p_amount is null or p_amount < c_min or p_amount > c_max then
    raise exception 'invalid_bet_amount';
  end if;

  select * into v_round
  from public.hungry_cat_global_rounds
  where id = p_round_id;

  if v_round.id is null then raise exception 'round_not_found'; end if;

  if v_round.status <> 'betting' or v_round.betting_ends_at <= now() then
    raise exception 'betting_closed';
  end if;

  -- Duplicate bet check
  if exists (
    select 1 from public.hungry_cat_global_bets
    where round_id = p_round_id and user_id = v_user_id
  ) then
    raise exception 'duplicate_bet';
  end if;

  select * into v_food
  from public.hungry_cat_config
  where food_id = p_food_id and is_active;

  if v_food.id is null then raise exception 'invalid_food'; end if;

  select * into v_wallet
  from public.wallets
  where user_id = v_user_id
  for update;

  if v_wallet is null or v_wallet.coins_balance < p_amount then
    raise exception 'insufficient_coins';
  end if;

  update public.wallets
  set coins_balance        = coins_balance - p_amount,
      lifetime_coins_spent = lifetime_coins_spent + p_amount,
      updated_at           = now()
  where user_id = v_user_id
  returning coins_balance into v_new_balance;

  insert into public.hungry_cat_global_bets
    (round_id, user_id, food_id, food_name, food_icon, multiplier_at_bet, bet_amount, status)
  values
    (p_round_id, v_user_id, p_food_id,
     v_food.name, v_food.icon, v_food.multiplier, p_amount, 'pending')
  returning id into v_bet_id;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_user_id, 'hungry_cat_bet', 'debit', -p_amount, 0,
     'Hungry Cat bet on ' || v_food.name,
     jsonb_build_object('bet_id', v_bet_id, 'round_id', p_round_id, 'food_id', p_food_id));

  return json_build_object(
    'bet_id',      v_bet_id,
    'new_balance', v_new_balance
  );
end;
$$;

grant execute on function public.place_hungry_cat_global_bet(uuid, text, integer) to authenticated;

-- 3. Safety seed: ensure both game rows exist and are enabled
insert into public.game_settings (game_key, is_enabled)
values
  ('hungry_cat',  true),
  ('crash_rocket', true)
on conflict (game_key) do nothing;
