-- ─────────────────────────────────────────────────────────────────────────────
-- Rocket Crash Admin Tools
--
-- 1. Ensure game_settings row exists for crash_rocket.
-- 2. Ensure forced-multiplier columns exist (owner migration may have added them).
-- 3. Add 'voided' to crash_rounds status so rounds can be emergency-voided.
-- 4. RPC: admin_get_rocket_crash_game_config   — read current settings.
-- 5. RPC: admin_set_rocket_crash_test_mode     — toggle test mode.
-- 6. RPC: admin_preview_rocket_crash_result    — read forced multiplier state.
-- 7. RPC: set_rocket_crash_forced_next_multiplier — queue forced crash value.
-- 8. RPC: admin_clear_rocket_crash_forced_multiplier — clear it.
-- 9. RPC: admin_void_rocket_crash_round        — refund pending bets, void round.
-- 10. RPC: admin_get_rocket_crash_audit_log    — last N audit entries.
-- 11. Patch start_crash_round to consume forced multiplier when test_mode = true.
--
-- Security contract:
--   - Only super_admin (via has_app_role) may call admin RPCs.
--   - Force multiplier requires test_mode = true for crash_rocket in game_settings.
--   - Multiplier must be between 1.01 and 100.00.
--   - Force is rejected if any round has pending/running bets.
--   - Forced multiplier cleared immediately after one round consumes it.
--   - Cannot void a crashed (completed) round.
--   - Every action logged in admin_audit_logs.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Ensure crash_rocket row in game_settings ───────────────────────────────

insert into public.game_settings (game_key, is_enabled)
values ('crash_rocket', true)
on conflict (game_key) do nothing;

-- ── 2. Ensure forced-crash columns exist ─────────────────────────────────────
-- (owner_game_control migration may have already added these; if not exists is safe)

alter table public.game_settings
  add column if not exists forced_crash_multiplier            numeric(10,2) null,
  add column if not exists forced_crash_multiplier_expires_at timestamptz   null,
  add column if not exists forced_crash_multiplier_by         uuid          null;

-- ── 3. Allow 'voided' status on crash_rounds ─────────────────────────────────

alter table public.crash_rounds
  drop constraint if exists crash_rounds_status_check;

alter table public.crash_rounds
  add constraint crash_rounds_status_check
  check (status in ('flying', 'crashed', 'voided'));

-- ── 4. RPC: admin_get_rocket_crash_game_config ───────────────────────────────

create or replace function public.admin_get_rocket_crash_game_config()
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

  select * into v_row from public.game_settings where game_key = 'crash_rocket';

  return jsonb_build_object(
    'is_enabled',                        v_row.is_enabled,
    'test_mode',                         v_row.test_mode,
    'max_bet',                           v_row.max_bet,
    'max_payout',                        v_row.max_payout,
    'daily_payout_cap',                  v_row.daily_payout_cap,
    'forced_crash_multiplier',           v_row.forced_crash_multiplier,
    'forced_crash_multiplier_expires_at',v_row.forced_crash_multiplier_expires_at,
    'forced_crash_multiplier_by',        v_row.forced_crash_multiplier_by
  );
end;
$$;

grant execute on function public.admin_get_rocket_crash_game_config() to authenticated;

-- ── 5. RPC: admin_set_rocket_crash_test_mode ─────────────────────────────────

create or replace function public.admin_set_rocket_crash_test_mode(
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
  set test_mode = p_enabled,
      -- Disabling test_mode clears any queued forced multiplier
      forced_crash_multiplier            = case when not p_enabled then null else forced_crash_multiplier end,
      forced_crash_multiplier_expires_at = case when not p_enabled then null else forced_crash_multiplier_expires_at end,
      forced_crash_multiplier_by         = case when not p_enabled then null else forced_crash_multiplier_by end,
      updated_at = now()
  where game_key = 'crash_rocket';

  insert into public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  values
    (v_admin,
     case when p_enabled then 'rocket_crash_test_mode_enabled' else 'rocket_crash_test_mode_disabled' end,
     'game_settings', 'crash_rocket',
     jsonb_build_object('test_mode', p_enabled));

  return jsonb_build_object('ok', true, 'test_mode', p_enabled);
end;
$$;

grant execute on function public.admin_set_rocket_crash_test_mode(boolean) to authenticated;

-- ── 6. RPC: admin_preview_rocket_crash_result ────────────────────────────────
-- Read-only. Returns the forced multiplier state. Does not mutate anything.

create or replace function public.admin_preview_rocket_crash_result()
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

  select * into v_row from public.game_settings where game_key = 'crash_rocket';

  if v_row.forced_crash_multiplier is null then
    return jsonb_build_object(
      'test_mode',         v_row.test_mode,
      'forced_multiplier', null,
      'expires_at',        null
    );
  end if;

  -- Check expiry
  if v_row.forced_crash_multiplier_expires_at is not null
     and now() > v_row.forced_crash_multiplier_expires_at then
    return jsonb_build_object(
      'test_mode',         v_row.test_mode,
      'forced_multiplier', null,
      'expires_at',        null,
      'note',              'expired'
    );
  end if;

  return jsonb_build_object(
    'test_mode',         v_row.test_mode,
    'forced_multiplier', v_row.forced_crash_multiplier,
    'expires_at',        v_row.forced_crash_multiplier_expires_at,
    'set_by',            v_row.forced_crash_multiplier_by
  );
end;
$$;

grant execute on function public.admin_preview_rocket_crash_result() to authenticated;

-- ── 7. RPC: set_rocket_crash_forced_next_multiplier ──────────────────────────
-- Queue a forced crash multiplier for the next TEST-MODE round only.
-- Blocked when: test_mode=false, active pending/running bets, invalid range.

create or replace function public.set_rocket_crash_forced_next_multiplier(
  p_multiplier numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin       uuid := auth.uid();
  v_settings    public.game_settings;
  v_active_bets integer;
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  -- Validate range: 1.01 – 100.00
  if p_multiplier is null or p_multiplier < 1.01 or p_multiplier > 100.00 then
    raise exception 'invalid_multiplier: must be between 1.01 and 100.00';
  end if;

  select * into v_settings
  from public.game_settings
  where game_key = 'crash_rocket'
  for update;

  if not v_settings.test_mode then
    raise exception 'test_mode_disabled: forced multiplier only allowed when test_mode = true for crash_rocket';
  end if;

  -- Block if any round has pending or running bets
  select coalesce(count(*), 0) into v_active_bets
  from public.crash_bets
  where status in ('pending', 'running');

  if v_active_bets > 0 then
    raise exception 'active_bets_exist: cannot force multiplier while rounds have accepted bets';
  end if;

  update public.game_settings
  set forced_crash_multiplier            = p_multiplier,
      forced_crash_multiplier_expires_at = now() + interval '30 minutes',
      forced_crash_multiplier_by         = v_admin,
      updated_at                         = now()
  where game_key = 'crash_rocket';

  insert into public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  values
    (v_admin, 'rocket_crash_forced_multiplier_set', 'game_settings', 'crash_rocket',
     jsonb_build_object(
       'multiplier', p_multiplier,
       'warning',    'TEST MODE ONLY — forced multiplier queued for next round'
     ));

  return jsonb_build_object(
    'ok',          true,
    'multiplier',  p_multiplier,
    'expires_at',  now() + interval '30 minutes',
    'warning',     'TEST MODE ONLY. Forced multiplier will be consumed by the next Rocket Crash round.'
  );
end;
$$;

grant execute on function public.set_rocket_crash_forced_next_multiplier(numeric) to authenticated;

-- ── 8. RPC: admin_clear_rocket_crash_forced_multiplier ───────────────────────

create or replace function public.admin_clear_rocket_crash_forced_multiplier()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := auth.uid();
  v_prev  numeric;
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  select forced_crash_multiplier into v_prev
  from public.game_settings
  where game_key = 'crash_rocket';

  update public.game_settings
  set forced_crash_multiplier            = null,
      forced_crash_multiplier_expires_at = null,
      forced_crash_multiplier_by         = null,
      updated_at                         = now()
  where game_key = 'crash_rocket';

  insert into public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  values
    (v_admin, 'rocket_crash_forced_multiplier_cleared', 'game_settings', 'crash_rocket',
     jsonb_build_object('cleared_multiplier', v_prev));

  return jsonb_build_object('ok', true, 'cleared_multiplier', v_prev);
end;
$$;

grant execute on function public.admin_clear_rocket_crash_forced_multiplier() to authenticated;

-- ── 9. RPC: admin_void_rocket_crash_round ────────────────────────────────────
-- Emergency: refund all pending/running bets in a broken round, mark it voided.
-- Cannot void a round that has already crashed (completed).

create or replace function public.admin_void_rocket_crash_round(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin        uuid := auth.uid();
  v_round        public.crash_rounds;
  v_refund_total integer := 0;
  v_bet          record;
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  select * into v_round
  from public.crash_rounds
  where id = p_round_id
  for update;

  if not found then
    raise exception 'round_not_found';
  end if;

  if v_round.status = 'voided' then
    raise exception 'already_voided';
  end if;

  if v_round.status = 'crashed' then
    raise exception 'round_already_completed: cannot void a settled round';
  end if;

  -- Refund all pending/running bets
  for v_bet in (
    select b.*
    from public.crash_bets b
    where b.round_id = p_round_id
      and b.status in ('pending', 'running')
    for update
  ) loop
    update public.wallets
    set coins_balance = coins_balance + v_bet.bet_amount,
        updated_at    = now()
    where user_id = v_bet.user_id;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
    values
      (v_bet.user_id, 'crash_rocket_refund', 'credit', v_bet.bet_amount, 0,
       'Rocket Crash round voided by admin',
       jsonb_build_object(
         'round_id',  p_round_id,
         'bet_id',    v_bet.id,
         'voided_by', v_admin
       ));

    update public.crash_bets
    set status = 'refunded'
    where id = v_bet.id;

    v_refund_total := v_refund_total + v_bet.bet_amount;
  end loop;

  update public.crash_rounds
  set status     = 'voided',
      crashed_at = now()
  where id = p_round_id;

  insert into public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  values
    (v_admin, 'rocket_crash_round_voided', 'crash_rounds', p_round_id::text,
     jsonb_build_object(
       'round_id',     p_round_id,
       'refund_total', v_refund_total,
       'round_owner',  v_round.user_id
     ));

  return jsonb_build_object(
    'ok',           true,
    'round_id',     p_round_id,
    'refund_total', v_refund_total
  );
end;
$$;

grant execute on function public.admin_void_rocket_crash_round(uuid) to authenticated;

-- ── 10. RPC: admin_get_rocket_crash_audit_log ────────────────────────────────

create or replace function public.admin_get_rocket_crash_audit_log(
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
  where al.action like 'rocket_crash%'
  order by al.created_at desc
  limit p_limit;
end;
$$;

grant execute on function public.admin_get_rocket_crash_audit_log(integer) to authenticated;

-- ── 11. Patch start_crash_round to consume forced multiplier ─────────────────
-- When test_mode = true and forced_crash_multiplier is set (and not expired),
-- use that exact crash point. Clear immediately after consumption.

create or replace function public.start_crash_round(p_bets jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid    := auth.uid();
  v_round_id    uuid    := gen_random_uuid();
  v_total_bet   integer;
  v_new_balance integer;
  v_rand        numeric;
  v_crash_at    numeric;
  v_started_at  timestamptz := now();
  v_bet_ids     jsonb   := '[]'::jsonb;
  v_bet_id      uuid;
  v_i           integer;
  v_bet_amount  integer;
  v_bet_mode    text;
  v_auto_target numeric;
  v_settings    public.game_settings;
  v_used_forced boolean := false;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  -- Load settings (includes test_mode + forced_crash_multiplier)
  select * into v_settings
  from public.game_settings
  where game_key = 'crash_rocket'
  for update;

  -- Kill-switch check
  if v_settings.is_enabled = false then
    raise exception 'game_disabled';
  end if;

  if p_bets is null or jsonb_array_length(p_bets) = 0 then
    raise exception 'no_bets';
  end if;
  if jsonb_array_length(p_bets) > 2 then
    raise exception 'too_many_bets';
  end if;

  -- Sum total bet
  select coalesce(sum((val->>'bet_amount')::integer), 0)
  into v_total_bet
  from jsonb_array_elements(p_bets) as val;

  if v_total_bet <= 0 then raise exception 'invalid_bet_amount'; end if;

  -- Deduct from real wallet atomically
  update public.wallets
  set coins_balance        = coins_balance - v_total_bet,
      lifetime_coins_spent = lifetime_coins_spent + v_total_bet,
      updated_at           = now()
  where user_id = v_user_id
    and coins_balance >= v_total_bet
  returning coins_balance into v_new_balance;

  if not found then raise exception 'insufficient_coins'; end if;

  -- ── Crash point selection ──────────────────────────────────────────────────
  -- test_mode + valid forced multiplier → use it; else provably-fair random.

  if v_settings.test_mode
     and v_settings.forced_crash_multiplier is not null
     and (v_settings.forced_crash_multiplier_expires_at is null
          or now() <= v_settings.forced_crash_multiplier_expires_at)
  then
    v_crash_at    := v_settings.forced_crash_multiplier;
    v_used_forced := true;

    -- Clear forced multiplier immediately (single-use)
    update public.game_settings
    set forced_crash_multiplier            = null,
        forced_crash_multiplier_expires_at = null,
        forced_crash_multiplier_by         = null,
        updated_at                         = now()
    where game_key = 'crash_rocket';

    insert into public.admin_audit_logs
      (admin_user_id, action, entity_type, entity_id, metadata)
    values
      (null, 'rocket_crash_forced_multiplier_consumed', 'game_settings', 'crash_rocket',
       jsonb_build_object(
         'multiplier',       v_crash_at,
         'consumed_by_user', v_user_id,
         'test_mode',        true
       ));
  else
    -- Provably-fair: 1% instant crash; otherwise 0.99 / (1 - rand), capped 1000×
    v_rand := random();
    if v_rand < 0.01 then
      v_crash_at := 1.00;
    else
      v_crash_at := round((0.99 / (1.0 - v_rand))::numeric, 2);
      if v_crash_at < 1.00  then v_crash_at := 1.00;    end if;
      if v_crash_at > 1000  then v_crash_at := 1000.00; end if;
    end if;
  end if;

  -- Create round
  insert into public.crash_rounds(id, user_id, status, crash_multiplier, started_at)
  values (v_round_id, v_user_id, 'flying', v_crash_at, v_started_at);

  -- Wallet transaction for total bet
  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_user_id, 'crash_rocket_bet', 'debit', -v_total_bet, 0,
     'Crash Rocket bet',
     jsonb_build_object('round_id', v_round_id, 'total_bet', v_total_bet,
                        'forced', v_used_forced));

  -- Individual bet records
  for v_i in 0..jsonb_array_length(p_bets) - 1 loop
    v_bet_id     := gen_random_uuid();
    v_bet_amount := (p_bets->v_i->>'bet_amount')::integer;
    v_bet_mode   := coalesce(p_bets->v_i->>'mode', 'manual');
    v_auto_target := (p_bets->v_i->>'auto_cashout_multiplier')::numeric;

    insert into public.crash_bets
      (id, round_id, user_id, bet_amount, mode, auto_cashout_multiplier, status)
    values
      (v_bet_id, v_round_id, v_user_id, v_bet_amount, v_bet_mode, v_auto_target, 'running');

    v_bet_ids := v_bet_ids || jsonb_build_array(jsonb_build_object('id', v_bet_id));
  end loop;

  return jsonb_build_object(
    'round_id',    v_round_id,
    'started_at',  v_started_at,
    'new_balance', v_new_balance,
    'bets',        v_bet_ids,
    'forced',      v_used_forced
  );
end;
$$;

grant execute on function public.start_crash_round(jsonb) to authenticated;
