-- ─────────────────────────────────────────────────────────────────────────────
-- Hungry Cat Admin Tools
--
-- 1. Extend game_settings with admin/test columns.
-- 2. RPC: admin_update_hungry_cat_odds    — super_admin: edit food weights etc.
-- 3. RPC: admin_update_hungry_cat_config  — super_admin: edit global limits.
-- 4. RPC: admin_preview_hungry_cat_result — super_admin: read forced result.
-- 5. RPC: set_hungry_cat_forced_next_result — super_admin: force test-round.
-- 6. RPC: admin_void_hungry_cat_round       — super_admin: refund broken round.
-- 7. Patch settle_hungry_cat_round to consume forced result in test mode.
--
-- Security contract:
--   - Only super_admin (via has_app_role) may call admin RPCs.
--   - Force result is rejected unless game_settings.test_mode = true.
--   - Force result is rejected if any non-refunded bet exists for the round.
--   - forced_next_result is cleared immediately after consumption.
--   - Every admin action is written to admin_audit_logs.
--   - Normal users cannot read forced_next_result (column-level policy).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Extend game_settings ───────────────────────────────────────────────────

alter table public.game_settings
  add column if not exists test_mode                    boolean      not null default false,
  add column if not exists forced_next_result           text         null,
  add column if not exists forced_next_result_expires_at timestamptz null,
  add column if not exists forced_next_result_by        uuid         null,
  add column if not exists max_bet                      integer      not null default 100000,
  add column if not exists max_payout                   integer      not null default 1000000,
  add column if not exists daily_payout_cap             integer      not null default 10000000,
  add column if not exists risk_mode                    text         not null default 'normal'
                                                          check (risk_mode in ('normal', 'conservative', 'aggressive')),
  add column if not exists event_mode                   boolean      not null default false,
  add column if not exists event_multiplier_boost       numeric(4,2) not null default 1.0
                                                          check (event_multiplier_boost between 0.5 and 5.0);

-- Ensure the hungry_cat row exists
insert into public.game_settings (game_key, is_enabled)
values ('hungry_cat', true)
on conflict (game_key) do nothing;

-- ── 2. Valid outcome keys helper ─────────────────────────────────────────────

-- We keep this as a set check inside the RPCs rather than a separate table so
-- the source of truth remains hungry_cat_config.

-- ── 3. RPC: admin_update_hungry_cat_odds ────────────────────────────────────

create or replace function public.admin_update_hungry_cat_odds(
  p_food_id   text,
  p_weight    numeric  default null,
  p_is_active boolean  default null,
  p_max_bet   integer  default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := auth.uid();
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  if not exists (
    select 1 from public.hungry_cat_config where food_id = p_food_id
  ) then
    raise exception 'invalid_food_id';
  end if;

  update public.hungry_cat_config
  set
    weight     = coalesce(p_weight,    weight),
    is_active  = coalesce(p_is_active, is_active),
    updated_at = now()
  where food_id = p_food_id;

  insert into public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  values
    (v_admin, 'hungry_cat_odds_updated', 'hungry_cat_config', p_food_id,
     jsonb_build_object(
       'food_id',   p_food_id,
       'weight',    p_weight,
       'is_active', p_is_active
     ));

  return jsonb_build_object('ok', true, 'food_id', p_food_id);
end;
$$;

grant execute on function public.admin_update_hungry_cat_odds(text, numeric, boolean, integer)
  to authenticated;

-- ── 4. RPC: admin_update_hungry_cat_config ──────────────────────────────────

create or replace function public.admin_update_hungry_cat_config(
  p_is_enabled         boolean  default null,
  p_max_bet            integer  default null,
  p_max_payout         integer  default null,
  p_daily_payout_cap   integer  default null,
  p_risk_mode          text     default null,
  p_event_mode         boolean  default null,
  p_event_boost        numeric  default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := auth.uid();
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  if p_risk_mode is not null
     and p_risk_mode not in ('normal', 'conservative', 'aggressive') then
    raise exception 'invalid_risk_mode';
  end if;

  update public.game_settings
  set
    is_enabled       = coalesce(p_is_enabled,       is_enabled),
    max_bet          = coalesce(p_max_bet,           max_bet),
    max_payout       = coalesce(p_max_payout,        max_payout),
    daily_payout_cap = coalesce(p_daily_payout_cap,  daily_payout_cap),
    risk_mode        = coalesce(p_risk_mode,         risk_mode),
    event_mode       = coalesce(p_event_mode,        event_mode),
    event_multiplier_boost = coalesce(p_event_boost, event_multiplier_boost),
    updated_at       = now()
  where game_key = 'hungry_cat';

  insert into public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  values
    (v_admin, 'hungry_cat_config_updated', 'game_settings', 'hungry_cat',
     jsonb_build_object(
       'is_enabled',       p_is_enabled,
       'max_bet',          p_max_bet,
       'max_payout',       p_max_payout,
       'daily_payout_cap', p_daily_payout_cap,
       'risk_mode',        p_risk_mode,
       'event_mode',       p_event_mode,
       'event_boost',      p_event_boost
     ));

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.admin_update_hungry_cat_config(boolean, integer, integer, integer, text, boolean, numeric)
  to authenticated;

-- ── 5. RPC: admin_preview_hungry_cat_result ─────────────────────────────────
-- Read-only. Returns the forced result if set, or null. Does NOT generate or
-- change anything. Only super_admin can call it.

create or replace function public.admin_preview_hungry_cat_result()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row public.game_settings;
  v_food public.hungry_cat_config;
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  select * into v_row
  from public.game_settings
  where game_key = 'hungry_cat';

  if v_row.forced_next_result is null then
    return jsonb_build_object(
      'forced_result', null,
      'test_mode',     v_row.test_mode,
      'expires_at',    null
    );
  end if;

  -- Expired?
  if v_row.forced_next_result_expires_at is not null
     and now() > v_row.forced_next_result_expires_at then
    return jsonb_build_object(
      'forced_result', null,
      'test_mode',     v_row.test_mode,
      'expires_at',    null,
      'note',          'expired'
    );
  end if;

  select * into v_food
  from public.hungry_cat_config
  where food_id = v_row.forced_next_result;

  return jsonb_build_object(
    'forced_result', v_row.forced_next_result,
    'test_mode',     v_row.test_mode,
    'expires_at',    v_row.forced_next_result_expires_at,
    'set_by',        v_row.forced_next_result_by,
    'food_name',     v_food.name,
    'food_icon',     v_food.icon,
    'multiplier',    v_food.multiplier
  );
end;
$$;

grant execute on function public.admin_preview_hungry_cat_result()
  to authenticated;

-- ── 6. RPC: set_hungry_cat_forced_next_result ────────────────────────────────
-- Super-admin can queue a forced outcome for the next TEST-MODE round only.
-- Blocked when: test_mode=false, active round with bets, invalid food_id.

create or replace function public.set_hungry_cat_forced_next_result(
  p_outcome_key text  -- must match a food_id in hungry_cat_config
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin      uuid := auth.uid();
  v_settings   public.game_settings;
  v_food       public.hungry_cat_config;
  v_active_bets integer;
begin
  -- ── Auth ──
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  -- ── Read config ──
  select * into v_settings
  from public.game_settings
  where game_key = 'hungry_cat'
  for update;

  -- ── test_mode guard ──
  if not v_settings.test_mode then
    raise exception 'test_mode_disabled: forced results are only allowed when game_settings.test_mode = true for hungry_cat';
  end if;

  -- ── Validate outcome key ──
  select * into v_food
  from public.hungry_cat_config
  where food_id = p_outcome_key and is_active = true;

  if not found then
    raise exception 'invalid_outcome_key';
  end if;

  -- ── No active betting/running rounds with accepted bets ──
  -- "Active" = any round in status 'betting' or 'locked' that has pending bets.
  -- We intentionally do NOT block if a round exists with zero bets placed yet,
  -- since the force will only apply to the *next* round that gets created.
  select coalesce(sum(b.bet_amount), 0) into v_active_bets
  from public.hungry_cat_rounds r
  join public.hungry_cat_bets b on b.round_id = r.id
  where r.status in ('betting', 'locked')
    and b.status = 'pending';

  if v_active_bets > 0 then
    raise exception 'active_bets_exist: cannot force result while a round has accepted bets';
  end if;

  -- ── Set forced result (expires in 30 minutes — auto-clears if unused) ──
  update public.game_settings
  set forced_next_result              = p_outcome_key,
      forced_next_result_expires_at   = now() + interval '30 minutes',
      forced_next_result_by           = v_admin,
      updated_at                      = now()
  where game_key = 'hungry_cat';

  -- ── Audit ──
  insert into public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  values
    (v_admin, 'hungry_cat_forced_result_set', 'game_settings', 'hungry_cat',
     jsonb_build_object(
       'outcome_key', p_outcome_key,
       'food_name',   v_food.name,
       'multiplier',  v_food.multiplier,
       'warning',     'TEST MODE ONLY — forced result queued for next round'
     ));

  return jsonb_build_object(
    'ok',          true,
    'outcome_key', p_outcome_key,
    'food_name',   v_food.name,
    'icon',        v_food.icon,
    'multiplier',  v_food.multiplier,
    'expires_at',  now() + interval '30 minutes',
    'warning',     'TEST MODE ONLY. This forced result will be consumed by the next Hungry Cat round.'
  );
end;
$$;

grant execute on function public.set_hungry_cat_forced_next_result(text)
  to authenticated;

-- ── 7. RPC: admin_clear_hungry_cat_forced_result ─────────────────────────────

create or replace function public.admin_clear_hungry_cat_forced_result()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := auth.uid();
  v_prev  text;
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  select forced_next_result into v_prev
  from public.game_settings
  where game_key = 'hungry_cat';

  update public.game_settings
  set forced_next_result             = null,
      forced_next_result_expires_at  = null,
      forced_next_result_by          = null,
      updated_at                     = now()
  where game_key = 'hungry_cat';

  insert into public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  values
    (v_admin, 'hungry_cat_forced_result_cleared', 'game_settings', 'hungry_cat',
     jsonb_build_object('cleared_outcome', v_prev));

  return jsonb_build_object('ok', true, 'cleared', v_prev);
end;
$$;

grant execute on function public.admin_clear_hungry_cat_forced_result()
  to authenticated;

-- ── 8. RPC: admin_void_hungry_cat_round ─────────────────────────────────────
-- Emergency tool: refund all pending bets in a broken round, mark it voided.

alter table public.hungry_cat_rounds
  drop constraint if exists hungry_cat_rounds_status_check;

alter table public.hungry_cat_rounds
  add constraint hungry_cat_rounds_status_check
  check (status in ('betting', 'locked', 'completed', 'voided'));

create or replace function public.admin_void_hungry_cat_round(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin         uuid := auth.uid();
  v_round         public.hungry_cat_rounds;
  v_refund_total  integer := 0;
  v_bet           record;
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  select * into v_round
  from public.hungry_cat_rounds
  where id = p_round_id
  for update;

  if not found then
    raise exception 'round_not_found';
  end if;

  if v_round.status = 'voided' then
    raise exception 'already_voided';
  end if;

  if v_round.status = 'completed' then
    raise exception 'round_already_completed: cannot void a settled round';
  end if;

  -- Refund all pending bets to their respective users
  for v_bet in (
    select b.*, b.user_id as bet_user_id
    from public.hungry_cat_bets b
    where b.round_id = p_round_id and b.status = 'pending'
    for update
  ) loop
    update public.wallets
    set coins_balance = coins_balance + v_bet.bet_amount,
        updated_at    = now()
    where user_id = v_bet.bet_user_id;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
    values
      (v_bet.bet_user_id, 'hungry_cat_refund', 'credit', v_bet.bet_amount, 0,
       'Hungry Cat round voided by admin',
       jsonb_build_object(
         'round_id', p_round_id,
         'bet_id',   v_bet.id,
         'voided_by', v_admin
       ));

    update public.hungry_cat_bets
    set status = 'refunded'
    where id = v_bet.id;

    v_refund_total := v_refund_total + v_bet.bet_amount;
  end loop;

  -- Mark round voided
  update public.hungry_cat_rounds
  set status       = 'voided',
      completed_at = now()
  where id = p_round_id;

  insert into public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  values
    (v_admin, 'hungry_cat_round_voided', 'hungry_cat_rounds', p_round_id::text,
     jsonb_build_object(
       'round_id',      p_round_id,
       'refund_total',  v_refund_total,
       'round_owner',   v_round.user_id
     ));

  return jsonb_build_object(
    'ok',           true,
    'round_id',     p_round_id,
    'refund_total', v_refund_total
  );
end;
$$;

grant execute on function public.admin_void_hungry_cat_round(uuid)
  to authenticated;

-- ── 9. RPC: admin_set_hungry_cat_test_mode ───────────────────────────────────

create or replace function public.admin_set_hungry_cat_test_mode(
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := auth.uid();
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  update public.game_settings
  set test_mode  = p_enabled,
      -- Disabling test_mode also clears any pending forced result
      forced_next_result             = case when not p_enabled then null else forced_next_result end,
      forced_next_result_expires_at  = case when not p_enabled then null else forced_next_result_expires_at end,
      forced_next_result_by          = case when not p_enabled then null else forced_next_result_by end,
      updated_at = now()
  where game_key = 'hungry_cat';

  insert into public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  values
    (v_admin,
     case when p_enabled then 'hungry_cat_test_mode_enabled' else 'hungry_cat_test_mode_disabled' end,
     'game_settings', 'hungry_cat',
     jsonb_build_object('test_mode', p_enabled));

  return jsonb_build_object('ok', true, 'test_mode', p_enabled);
end;
$$;

grant execute on function public.admin_set_hungry_cat_test_mode(boolean)
  to authenticated;

-- ── 10. RPC: admin_get_hungry_cat_audit_log ─────────────────────────────────

create or replace function public.admin_get_hungry_cat_audit_log(
  p_limit integer default 20
)
returns table (
  id         uuid,
  admin_id   uuid,
  action     text,
  metadata   jsonb,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  return query
  select
    al.id,
    al.admin_user_id,
    al.action,
    al.metadata,
    al.created_at
  from public.admin_audit_logs al
  where al.entity_type = 'game_settings'
    and al.entity_id   = 'hungry_cat'
    and al.action like 'hungry_cat%'
  order by al.created_at desc
  limit p_limit;
end;
$$;

grant execute on function public.admin_get_hungry_cat_audit_log(integer)
  to authenticated;

-- ── 11. Patch play_hungry_cat_spin to consume forced result ──────────────────
-- When test_mode = true and forced_next_result is set (and not expired),
-- the spin uses that food instead of random selection. The forced result is
-- cleared immediately after consumption.

create or replace function public.play_hungry_cat_spin(
  p_bet_amount integer,
  p_client_spin_id uuid,
  p_room_id uuid default null
)
returns table (
  spin_id uuid,
  food_id text,
  food_name text,
  food_icon text,
  multiplier numeric,
  rarity text,
  bet_amount integer,
  reward_amount integer,
  new_balance integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet public.wallets;
  v_existing public.hungry_cat_spins;
  v_food public.hungry_cat_config;
  v_settings public.game_settings;
  v_total_weight numeric;
  v_roll numeric;
  v_reward integer;
  v_spin_id uuid;
  v_new_balance integer;
  v_used_forced boolean := false;
  c_min_bet constant integer := 100;
  c_max_bet constant integer := 100000;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_client_spin_id is null then
    raise exception 'missing_client_spin_id';
  end if;

  -- Load settings (includes test_mode + forced_next_result)
  select * into v_settings
  from public.game_settings
  where game_key = 'hungry_cat'
  for update;

  if not v_settings.is_enabled then
    raise exception 'game_disabled';
  end if;

  if p_bet_amount is null
     or p_bet_amount < c_min_bet
     or p_bet_amount > c_max_bet then
    raise exception 'invalid_bet_amount';
  end if;

  -- Idempotency check
  select * into v_existing
  from public.hungry_cat_spins s
  where s.client_spin_id = p_client_spin_id;

  if v_existing.id is not null then
    select w.coins_balance into v_new_balance
    from public.wallets w where w.user_id = v_user_id;

    select * into v_food
    from public.hungry_cat_config c
    where c.food_id = v_existing.food_id;

    return query select
      v_existing.id, v_existing.food_id, v_existing.food_name,
      coalesce(v_food.icon, '🍽️'), v_existing.multiplier,
      coalesce(v_food.rarity, 'common'),
      v_existing.bet_amount, v_existing.reward_amount,
      coalesce(v_new_balance, 0);
    return;
  end if;

  -- Lock wallet row, verify balance
  select * into v_wallet
  from public.wallets
  where user_id = v_user_id
  for update;

  if v_wallet is null or v_wallet.coins_balance < p_bet_amount then
    raise exception 'insufficient_coins';
  end if;

  -- ── Result selection ────────────────────────────────────────────────────────
  -- In test_mode: consume forced_next_result if valid and not expired.
  -- In production: always use weighted random selection.

  if v_settings.test_mode
     and v_settings.forced_next_result is not null
     and (v_settings.forced_next_result_expires_at is null
          or now() <= v_settings.forced_next_result_expires_at)
  then
    -- Use forced result
    select * into v_food
    from public.hungry_cat_config
    where food_id = v_settings.forced_next_result
      and is_active = true;

    if v_food.id is not null then
      v_used_forced := true;
      -- Clear forced result immediately after consumption
      update public.game_settings
      set forced_next_result             = null,
          forced_next_result_expires_at  = null,
          forced_next_result_by          = null,
          updated_at                     = now()
      where game_key = 'hungry_cat';

      -- Audit consumption
      insert into public.admin_audit_logs
        (admin_user_id, action, entity_type, entity_id, metadata)
      values
        (null, 'hungry_cat_forced_result_consumed', 'game_settings', 'hungry_cat',
         jsonb_build_object(
           'outcome_key',    v_food.food_id,
           'food_name',      v_food.name,
           'consumed_by_user', v_user_id,
           'test_mode',      true
         ));
    end if;
  end if;

  -- Fallback to weighted random if forced result was not used
  if v_food.id is null then
    select coalesce(sum(weight), 0) into v_total_weight
    from public.hungry_cat_config
    where is_active and weight > 0;

    if v_total_weight <= 0 then
      raise exception 'invalid_food_config';
    end if;

    v_roll := random() * v_total_weight;

    select * into v_food
    from (
      select c.*,
             sum(c.weight) over (order by c.sort_order, c.food_id) as cum_weight
      from public.hungry_cat_config c
      where c.is_active and c.weight > 0
    ) ranked
    where ranked.cum_weight >= v_roll
    order by ranked.cum_weight
    limit 1;

    if v_food.id is null then
      select c.* into v_food
      from public.hungry_cat_config c
      where c.is_active and c.weight > 0
      order by c.sort_order desc, c.food_id desc
      limit 1;
    end if;
  end if;

  v_reward := floor(p_bet_amount * v_food.multiplier)::integer;

  -- Apply net wallet change atomically
  update public.wallets
  set coins_balance = coins_balance - p_bet_amount + v_reward,
      lifetime_coins_spent = lifetime_coins_spent + p_bet_amount,
      updated_at = now()
  where user_id = v_user_id
  returning coins_balance into v_new_balance;

  insert into public.hungry_cat_spins (
    user_id, room_id, client_spin_id, bet_amount,
    food_id, food_name, multiplier, reward_amount, status
  )
  values (
    v_user_id, p_room_id, p_client_spin_id, p_bet_amount,
    v_food.food_id, v_food.name, v_food.multiplier, v_reward, 'settled'
  )
  returning id into v_spin_id;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_user_id, 'hungry_cat_bet', 'debit', -p_bet_amount, 0,
     'Hungry Cat Wheel bet',
     jsonb_build_object('spin_id', v_spin_id, 'food_id', v_food.food_id,
                        'forced', v_used_forced)),
    (v_user_id, 'hungry_cat_reward', 'credit', v_reward, 0,
     'Hungry Cat Wheel reward: ' || v_food.name || ' x' || v_food.multiplier,
     jsonb_build_object('spin_id', v_spin_id, 'food_id', v_food.food_id,
                        'multiplier', v_food.multiplier, 'forced', v_used_forced));

  return query select
    v_spin_id, v_food.food_id, v_food.name, v_food.icon,
    v_food.multiplier, v_food.rarity,
    p_bet_amount, v_reward, v_new_balance;
end;
$$;

grant execute on function public.play_hungry_cat_spin(integer, uuid, uuid) to authenticated;

-- ── 12. RPC: admin_get_hungry_cat_game_config ────────────────────────────────
-- Returns the full game_settings row for hungry_cat. Super_admin only.

create or replace function public.admin_get_hungry_cat_game_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row public.game_settings;
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  select * into v_row from public.game_settings where game_key = 'hungry_cat';

  return jsonb_build_object(
    'is_enabled',          v_row.is_enabled,
    'test_mode',           v_row.test_mode,
    'max_bet',             v_row.max_bet,
    'max_payout',          v_row.max_payout,
    'daily_payout_cap',    v_row.daily_payout_cap,
    'risk_mode',           v_row.risk_mode,
    'event_mode',          v_row.event_mode,
    'event_multiplier_boost', v_row.event_multiplier_boost,
    'forced_next_result',  v_row.forced_next_result,
    'forced_expires_at',   v_row.forced_next_result_expires_at,
    'forced_by',           v_row.forced_next_result_by
  );
end;
$$;

grant execute on function public.admin_get_hungry_cat_game_config()
  to authenticated;
