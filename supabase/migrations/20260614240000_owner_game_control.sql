-- ─────────────────────────────────────────────────────────────────────────────
-- Owner Game Control Panel
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Owner control users ────────────────────────────────────────────────────

create table if not exists owner_control_users (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  email     text,
  enabled   boolean default true,
  created_at timestamptz default now()
);

-- RLS: no policy = nobody can query directly; access only via security-definer RPCs
alter table owner_control_users enable row level security;

-- ── 2. Owner audit logs ───────────────────────────────────────────────────────

create table if not exists owner_game_control_audit_logs (
  id            uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id),
  action        text not null,
  game_type     text not null,
  old_value     jsonb,
  new_value     jsonb,
  created_at    timestamptz default now()
);

alter table owner_game_control_audit_logs enable row level security;

-- Owner can read their own audit logs
create policy "owner audit self read"
  on owner_game_control_audit_logs
  for select
  using (
    exists (
      select 1 from owner_control_users
      where user_id = auth.uid() and enabled = true
    )
  );

-- ── 3. is_owner_control_user() ────────────────────────────────────────────────

create or replace function is_owner_control_user()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from owner_control_users
    where user_id = auth.uid() and enabled = true
  );
$$;

-- ── 4. owner_get_game_risk_snapshot() ────────────────────────────────────────
-- Returns current round metrics for all games: active bets, exposure, projected payout.

create or replace function owner_get_game_risk_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_is_owner boolean;
  v_hungry_cat_open jsonb;
  v_crash_open jsonb;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = v_caller and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  -- Hungry Cat: current betting round
  select jsonb_build_object(
    'round_id', r.id,
    'status', r.status,
    'betting_ends_at', r.betting_ends_at,
    'total_bets', count(b.id),
    'total_exposure', coalesce(sum(b.bet_amount * b.multiplier_at_bet), 0),
    'total_wagered', coalesce(sum(b.bet_amount), 0),
    'projected_payout', coalesce(
      (select sum(b2.bet_amount * b2.multiplier_at_bet)
       from hungry_cat_bets b2
       where b2.round_id = r.id and b2.food_id = (
         select forced_next_result from game_settings where game_key = 'hungry_cat'
       ) and b2.status = 'pending'),
      0
    )
  )
  into v_hungry_cat_open
  from hungry_cat_rounds r
  left join hungry_cat_bets b on b.round_id = r.id and b.status = 'pending'
  where r.status in ('betting', 'locked')
  group by r.id, r.status, r.betting_ends_at
  order by r.created_at desc
  limit 1;

  -- Crash Rocket: active rounds
  select jsonb_build_object(
    'active_rounds', count(*),
    'total_exposure', coalesce(sum(b.bet_amount * coalesce(b.auto_cashout_multiplier, 5.0)), 0),
    'total_wagered', coalesce(sum(b.bet_amount), 0)
  )
  into v_crash_open
  from crash_rounds r
  join crash_bets b on b.round_id = r.id
  where r.status = 'flying' and b.status = 'running';

  return jsonb_build_object(
    'hungry_cat', coalesce(v_hungry_cat_open, '{}'::jsonb),
    'crash_rocket', coalesce(v_crash_open, '{}'::jsonb),
    'snapshot_at', now()
  );
end;
$$;

-- ── 5. owner_get_hungry_cat_full_config() ────────────────────────────────────

create or replace function owner_get_hungry_cat_full_config()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_owner boolean;
  v_settings jsonb;
  v_foods jsonb;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = auth.uid() and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  select to_jsonb(gs.*) into v_settings
  from game_settings gs where gs.game_key = 'hungry_cat';

  select jsonb_agg(to_jsonb(hc.*) order by hc.sort_order) into v_foods
  from hungry_cat_config hc;

  return jsonb_build_object(
    'settings', coalesce(v_settings, '{}'::jsonb),
    'foods', coalesce(v_foods, '[]'::jsonb)
  );
end;
$$;

-- ── 6. owner_get_crash_full_config() ─────────────────────────────────────────

create or replace function owner_get_crash_full_config()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_owner boolean;
  v_settings jsonb;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = auth.uid() and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  select to_jsonb(gs.*) into v_settings
  from game_settings gs where gs.game_key = 'crash_rocket';

  return coalesce(v_settings, '{}'::jsonb);
end;
$$;

-- ── 7. owner_get_gold_ladder_full_config() ───────────────────────────────────

create or replace function owner_get_gold_ladder_full_config()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_owner boolean;
  v_settings jsonb;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = auth.uid() and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  select to_jsonb(gs.*) into v_settings
  from game_settings gs where gs.game_key = 'gold_ladder';

  return coalesce(v_settings, '{}'::jsonb);
end;
$$;

-- ── 8. owner_set_game_config() ───────────────────────────────────────────────
-- Generic update for game_settings shared columns (is_enabled, test_mode, risk_mode,
-- event_mode, event_multiplier_boost, max_bet, max_payout, daily_payout_cap).

create or replace function owner_set_game_config(
  p_game_key             text,
  p_is_enabled           boolean  default null,
  p_test_mode            boolean  default null,
  p_risk_mode            text     default null,
  p_event_mode           boolean  default null,
  p_event_multiplier_boost numeric default null,
  p_max_bet              int      default null,
  p_max_payout           int      default null,
  p_daily_payout_cap     int      default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller   uuid := auth.uid();
  v_is_owner boolean;
  v_old      jsonb;
  v_new      jsonb;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = v_caller and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  if p_game_key not in ('hungry_cat', 'crash_rocket', 'gold_ladder', 'spin_wheel') then
    raise exception 'invalid_game_key';
  end if;

  -- Snapshot old values
  select to_jsonb(gs.*) into v_old from game_settings gs where gs.game_key = p_game_key;

  -- Insert row if it does not exist yet
  insert into game_settings (game_key) values (p_game_key) on conflict do nothing;

  update game_settings
  set
    is_enabled            = coalesce(p_is_enabled,            is_enabled),
    test_mode             = coalesce(p_test_mode,             test_mode),
    risk_mode             = coalesce(p_risk_mode,             risk_mode),
    event_mode            = coalesce(p_event_mode,            event_mode),
    event_multiplier_boost = coalesce(p_event_multiplier_boost, event_multiplier_boost),
    max_bet               = coalesce(p_max_bet,               max_bet),
    max_payout            = coalesce(p_max_payout,            max_payout),
    daily_payout_cap      = coalesce(p_daily_payout_cap,      daily_payout_cap),
    updated_at            = now()
  where game_key = p_game_key;

  select to_jsonb(gs.*) into v_new from game_settings gs where gs.game_key = p_game_key;

  insert into owner_game_control_audit_logs
    (owner_user_id, action, game_type, old_value, new_value)
  values
    (v_caller, 'update_game_config', p_game_key, v_old, v_new);
end;
$$;

-- ── 9. owner_update_hungry_cat_food_odds() ───────────────────────────────────

create or replace function owner_update_hungry_cat_food_odds(
  p_food_id  text,
  p_weight   numeric default null,
  p_is_active boolean default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller   uuid := auth.uid();
  v_is_owner boolean;
  v_old      jsonb;
  v_new      jsonb;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = v_caller and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  select to_jsonb(hc.*) into v_old
  from hungry_cat_config hc where hc.food_id = p_food_id;

  if v_old is null then
    raise exception 'food_not_found' using hint = p_food_id;
  end if;

  if p_weight is not null and (p_weight < 0.1 or p_weight > 1000) then
    raise exception 'invalid_weight' using hint = 'Weight must be 0.1–1000';
  end if;

  update hungry_cat_config
  set
    weight    = coalesce(p_weight,    weight),
    is_active = coalesce(p_is_active, is_active),
    updated_at = now()
  where food_id = p_food_id;

  select to_jsonb(hc.*) into v_new
  from hungry_cat_config hc where hc.food_id = p_food_id;

  insert into owner_game_control_audit_logs
    (owner_user_id, action, game_type, old_value, new_value)
  values
    (v_caller, 'update_hungry_cat_food_odds', 'hungry_cat', v_old, v_new);
end;
$$;

-- ── 10. owner_set_hungry_cat_forced_result() ─────────────────────────────────
-- Force the next round result (test mode only, blocks if open bets exist).

create or replace function owner_set_hungry_cat_forced_result(
  p_outcome_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller    uuid := auth.uid();
  v_is_owner  boolean;
  v_test_mode boolean;
  v_open_bets int;
  v_food      record;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = v_caller and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  -- Must be in test mode
  select test_mode into v_test_mode
  from game_settings where game_key = 'hungry_cat';

  if not coalesce(v_test_mode, false) then
    raise exception 'not_in_test_mode'
      using hint = 'Enable test mode before forcing a result';
  end if;

  -- Block if active bets exist
  select count(*) into v_open_bets
  from hungry_cat_bets b
  join hungry_cat_rounds r on r.id = b.round_id
  where r.status in ('betting', 'locked') and b.status = 'pending';

  if v_open_bets > 0 then
    raise exception 'open_bets_exist'
      using hint = 'Cannot force result while bets are open';
  end if;

  -- Validate food exists and is active
  select * into v_food
  from hungry_cat_config
  where food_id = p_outcome_key and is_active = true;

  if v_food is null then
    raise exception 'food_not_found'
      using hint = 'Food ID not found or inactive: ' || p_outcome_key;
  end if;

  -- Store forced result with 30-minute expiry
  update game_settings
  set
    forced_next_result            = p_outcome_key,
    forced_next_result_expires_at = now() + interval '30 minutes',
    forced_next_result_by         = v_caller,
    updated_at                    = now()
  where game_key = 'hungry_cat';

  insert into owner_game_control_audit_logs
    (owner_user_id, action, game_type, old_value, new_value)
  values
    (v_caller, 'set_hungry_cat_forced_result', 'hungry_cat',
     null,
     jsonb_build_object('outcome_key', p_outcome_key, 'food_name', v_food.name,
                        'multiplier', v_food.multiplier,
                        'expires_at', now() + interval '30 minutes'));

  return jsonb_build_object(
    'ok', true,
    'food_id', v_food.food_id,
    'food_name', v_food.name,
    'icon', v_food.icon,
    'multiplier', v_food.multiplier,
    'expires_at', now() + interval '30 minutes'
  );
end;
$$;

-- ── 11. owner_clear_hungry_cat_forced_result() ───────────────────────────────

create or replace function owner_clear_hungry_cat_forced_result()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller   uuid := auth.uid();
  v_is_owner boolean;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = v_caller and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  update game_settings
  set
    forced_next_result            = null,
    forced_next_result_expires_at = null,
    forced_next_result_by         = null,
    updated_at                    = now()
  where game_key = 'hungry_cat';

  insert into owner_game_control_audit_logs
    (owner_user_id, action, game_type, old_value, new_value)
  values (v_caller, 'clear_hungry_cat_forced_result', 'hungry_cat', null, null);
end;
$$;

-- ── 12. owner_set_rocket_crash_forced_multiplier() ───────────────────────────
-- Stores a forced crash multiplier for the next crash round (test mode only).
-- The crash game RPC should check this before committing crash_multiplier.

alter table game_settings
  add column if not exists forced_crash_multiplier          numeric(10,2),
  add column if not exists forced_crash_multiplier_expires_at timestamptz,
  add column if not exists forced_crash_multiplier_by       uuid;

create or replace function owner_set_rocket_crash_forced_multiplier(
  p_multiplier numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller   uuid := auth.uid();
  v_is_owner boolean;
  v_test_mode boolean;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = v_caller and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  select test_mode into v_test_mode
  from game_settings where game_key = 'crash_rocket';

  if not coalesce(v_test_mode, false) then
    raise exception 'not_in_test_mode'
      using hint = 'Enable test mode before forcing a crash multiplier';
  end if;

  if p_multiplier < 1.01 or p_multiplier > 1000 then
    raise exception 'invalid_multiplier'
      using hint = 'Multiplier must be between 1.01 and 1000';
  end if;

  -- Ensure row exists
  insert into game_settings (game_key) values ('crash_rocket') on conflict do nothing;

  update game_settings
  set
    forced_crash_multiplier            = p_multiplier,
    forced_crash_multiplier_expires_at = now() + interval '30 minutes',
    forced_crash_multiplier_by         = v_caller,
    updated_at                         = now()
  where game_key = 'crash_rocket';

  insert into owner_game_control_audit_logs
    (owner_user_id, action, game_type, old_value, new_value)
  values
    (v_caller, 'set_crash_forced_multiplier', 'crash_rocket',
     null,
     jsonb_build_object('multiplier', p_multiplier,
                        'expires_at', now() + interval '30 minutes'));

  return jsonb_build_object(
    'ok', true,
    'multiplier', p_multiplier,
    'expires_at', now() + interval '30 minutes'
  );
end;
$$;

-- ── 13. owner_clear_rocket_crash_forced_multiplier() ─────────────────────────

create or replace function owner_clear_rocket_crash_forced_multiplier()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller   uuid := auth.uid();
  v_is_owner boolean;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = v_caller and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  update game_settings
  set
    forced_crash_multiplier            = null,
    forced_crash_multiplier_expires_at = null,
    forced_crash_multiplier_by         = null,
    updated_at                         = now()
  where game_key = 'crash_rocket';

  insert into owner_game_control_audit_logs
    (owner_user_id, action, game_type, old_value, new_value)
  values (v_caller, 'clear_crash_forced_multiplier', 'crash_rocket', null, null);
end;
$$;

-- ── 14. owner_void_hungry_cat_round() ────────────────────────────────────────
-- Emergency void: refunds all pending bets and marks round voided.

create or replace function owner_void_hungry_cat_round(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller     uuid := auth.uid();
  v_is_owner   boolean;
  v_round      record;
  v_refunded   int := 0;
  v_total_refund bigint := 0;
  v_bet        record;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = v_caller and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  select * into v_round from hungry_cat_rounds
  where id = p_round_id for update;

  if v_round is null then
    raise exception 'round_not_found';
  end if;

  if v_round.status = 'voided' then
    raise exception 'already_voided';
  end if;

  -- Refund each pending bet
  for v_bet in
    select * from hungry_cat_bets
    where round_id = p_round_id and status = 'pending'
    for update
  loop
    update hungry_cat_bets
    set status = 'refunded'
    where id = v_bet.id;

    -- Restore wallet
    update wallets
    set coins = coins + v_bet.bet_amount
    where user_id = v_bet.user_id;

    insert into wallet_transactions
      (user_id, type, coins_delta, description)
    values
      (v_bet.user_id, 'hungry_cat_refund', v_bet.bet_amount,
       'Round voided by owner — refund');

    v_refunded   := v_refunded + 1;
    v_total_refund := v_total_refund + v_bet.bet_amount;
  end loop;

  update hungry_cat_rounds
  set status = 'voided', completed_at = now()
  where id = p_round_id;

  insert into owner_game_control_audit_logs
    (owner_user_id, action, game_type, old_value, new_value)
  values
    (v_caller, 'void_hungry_cat_round', 'hungry_cat',
     jsonb_build_object('round_id', p_round_id, 'status', v_round.status),
     jsonb_build_object('refunded_bets', v_refunded, 'total_refund', v_total_refund));

  return jsonb_build_object(
    'ok', true,
    'refunded_bets', v_refunded,
    'total_refund', v_total_refund
  );
end;
$$;

-- ── 15. owner_get_audit_log() ─────────────────────────────────────────────────

create or replace function owner_get_audit_log(
  p_game_type text default null,
  p_limit     int  default 50
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller   uuid := auth.uid();
  v_is_owner boolean;
  v_rows     jsonb;
begin
  select exists (
    select 1 from owner_control_users
    where user_id = v_caller and enabled = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'not_owner' using hint = 'Owner access required';
  end if;

  select jsonb_agg(to_jsonb(l.*) order by l.created_at desc)
  into v_rows
  from (
    select * from owner_game_control_audit_logs
    where (p_game_type is null or game_type = p_game_type)
    order by created_at desc
    limit p_limit
  ) l;

  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

-- ── 16. Seed the owner account ────────────────────────────────────────────────
-- Insert the project owner's user_id. This runs at migration time.
-- Replace the email lookup with the actual owner email.

do $$
declare
  v_uid uuid;
begin
  select id into v_uid
  from auth.users
  where email = 'albasma12182@gmail.com'
  limit 1;

  if v_uid is not null then
    insert into owner_control_users (user_id, email, enabled)
    values (v_uid, 'albasma12182@gmail.com', true)
    on conflict (user_id) do update set enabled = true, email = excluded.email;
  end if;
end;
$$;
