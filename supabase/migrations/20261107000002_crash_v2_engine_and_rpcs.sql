-- =============================================================================
-- Crash Rocket v2 — authoritative server engine + secure RPC surface.
--
-- Lifecycle: waiting -> betting_open -> betting_locked -> flying -> crashed
--            -> settling -> completed -> (next round: waiting)
--
-- All transitions are timestamp-driven and idempotent; a delayed tick
-- fast-forwards deterministically. A per-scope advisory transaction lock
-- guarantees only one engine execution advances a scope at a time.
-- The engine is driven by pg_cron (crash_v2_auto_advance) AND defensively by
-- the player RPCs themselves, so the game stays correct even if cron lags.
--
-- The Flutter client NEVER advances rounds, computes results, or writes any
-- game/wallet table. Server clock decides every outcome.
-- =============================================================================

-- ── Internal helpers ─────────────────────────────────────────────────────────

create or replace function public._crash_v2_cfg()
returns public.crash_v2_config
language sql stable
set search_path = ''
as $$
  select c from public.crash_v2_config c where singleton limit 1;
$$;
revoke all on function public._crash_v2_cfg() from public, anon, authenticated;

create or replace function public._crash_v2_enabled()
returns boolean
language sql stable
set search_path = ''
as $$
  select coalesce(
    (select gs.is_enabled from public.game_settings gs
     where gs.game_key = 'crash_rocket_v2'),
    false);
$$;
revoke all on function public._crash_v2_enabled() from public, anon, authenticated;

create or replace function public._crash_v2_is_admin()
returns boolean
language sql stable security definer
set search_path = 'public'
as $$
  select public.has_app_role('super_admin');
$$;
revoke all on function public._crash_v2_is_admin() from public, anon, authenticated;

create or replace function public._crash_v2_assert_room_access(p_room_id uuid)
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated';
  end if;
  if p_room_id is not null and not exists (
    select 1 from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = (select auth.uid())
      and rm.left_at is null
  ) then
    raise exception 'not_room_member';
  end if;
end;
$$;
revoke all on function public._crash_v2_assert_room_access(uuid) from public, anon, authenticated;

-- Flight curve: m(t) = floor(exp(growth_rate * t) * 100) / 100, clamped.
create or replace function public._crash_v2_multiplier_at(
  p_started_at timestamptz, p_at timestamptz,
  p_growth_rate numeric, p_max_multiplier numeric)
returns numeric
language sql immutable
set search_path = ''
as $$
  select least(
    p_max_multiplier,
    greatest(
      1.00,
      floor(
        exp(
          least(
            ln(p_max_multiplier::float8),
            p_growth_rate::float8 *
              greatest(0, extract(epoch from p_at - p_started_at))
          )
        ) * 100
      ) / 100
    )
  )::numeric(12,2);
$$;
revoke all on function public._crash_v2_multiplier_at(timestamptz, timestamptz, numeric, numeric)
  from public, anon, authenticated;

-- Provably fair target derivation. Public inputs (client_seed, nonce) combine
-- with the pre-committed server_seed: 52-bit roll -> u in [0,1) ->
-- floor((edge / (1-u)) * 100) / 100, clamped to [1.00, max].
create or replace function public._crash_v2_derive_target(
  p_server_seed text, p_client_seed text, p_nonce bigint,
  p_house_edge_factor numeric, p_max_multiplier numeric)
returns numeric
language plpgsql immutable
set search_path = ''
as $$
declare
  v_hash text;
  v_roll bigint;
  v_u numeric;
begin
  v_hash := encode(extensions.digest(
    p_server_seed || ':' || coalesce(p_client_seed, '') || ':' || p_nonce::text,
    'sha256'), 'hex');
  v_roll := ('x' || substr(v_hash, 1, 13))::bit(52)::bigint;
  v_u := v_roll::numeric / 4503599627370496::numeric;  -- 2^52
  return least(p_max_multiplier, greatest(1.00,
    floor((p_house_edge_factor / greatest(0.000001, 1 - v_u)) * 100) / 100
  ))::numeric(12,2);
end;
$$;
revoke all on function public._crash_v2_derive_target(text, text, bigint, numeric, numeric)
  from public, anon, authenticated;

create or replace function public._crash_v2_log(
  p_round_id uuid, p_type text, p_payload jsonb default '{}'::jsonb)
returns void
language sql
set search_path = ''
as $$
  insert into public.crash_v2_round_events (round_id, event_type, payload)
  values (p_round_id, p_type, coalesce(p_payload, '{}'::jsonb));
$$;
revoke all on function public._crash_v2_log(uuid, text, jsonb) from public, anon, authenticated;

-- ── Round creation ───────────────────────────────────────────────────────────
create or replace function public._crash_v2_create_round(
  p_room_id uuid, p_open_at timestamptz)
returns public.crash_v2_rounds
language plpgsql security definer
set search_path = ''
as $$
declare
  cfg public.crash_v2_config := public._crash_v2_cfg();
  v_seed text := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash text := encode(extensions.digest(v_seed, 'sha256'), 'hex');
  v_round public.crash_v2_rounds;
  v_num bigint := nextval('public.crash_v2_round_number_seq');
  v_target numeric(12,2);
begin
  -- nonce == public_round_number for auditability; kept identical by design.
  insert into public.crash_v2_rounds (
    room_id, status, betting_open_at, betting_close_at,
    server_seed_hash, client_seed, nonce, public_round_number
  ) values (
    p_room_id, 'waiting', p_open_at,
    p_open_at + make_interval(secs => cfg.betting_seconds),
    v_hash, '', v_num, v_num
  ) returning * into v_round;

  v_target := public._crash_v2_derive_target(
    v_seed, '', v_round.nonce, cfg.house_edge_factor, cfg.max_multiplier);

  insert into public.crash_v2_round_secrets (round_id, server_seed, target_multiplier)
  values (v_round.id, v_seed, v_target);

  return v_round;
end;
$$;
revoke all on function public._crash_v2_create_round(uuid, timestamptz) from public, anon, authenticated;

-- ── Auto-cashout settlement for one flying round (internal) ──────────────────
create or replace function public._crash_v2_settle_auto_cashouts(
  p_round public.crash_v2_rounds,
  p_target numeric, p_now timestamptz)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  cfg public.crash_v2_config := public._crash_v2_cfg();
  v_current numeric;
  v_bet public.crash_v2_bets;
  v_payout integer;
  v_balance integer;
  v_effective_at timestamptz;
begin
  v_current := least(p_target, public._crash_v2_multiplier_at(
    p_round.started_at, p_now, cfg.growth_rate, cfg.max_multiplier));

  for v_bet in
    select * from public.crash_v2_bets
    where round_id = p_round.id
      and status = 'placed'
      and auto_cashout_multiplier is not null
      and auto_cashout_multiplier <= v_current
      and auto_cashout_multiplier < p_target
    order by id
    for update
  loop
    v_payout := least(
      floor(v_bet.amount * v_bet.auto_cashout_multiplier)::integer,
      cfg.max_payout);
    -- The moment the auto threshold was crossed (server-derived, not "now").
    v_effective_at := p_round.started_at + make_interval(
      secs => (ln(v_bet.auto_cashout_multiplier::float8) / cfg.growth_rate::float8));

    update public.wallets
    set coins_balance = coins_balance + v_payout, updated_at = p_now
    where user_id = v_bet.user_id
    returning coins_balance into v_balance;

    update public.crash_v2_bets
    set status = 'cashed_out',
        cashout_multiplier = v_bet.auto_cashout_multiplier,
        payout = v_payout,
        cashed_out_at = v_effective_at,
        settled_at = p_now
    where id = v_bet.id;

    insert into public.wallet_transactions (
      user_id, type, direction, coins_delta, diamonds_delta,
      balance_coins_after, note, metadata
    ) values (
      v_bet.user_id, 'crash_rocket_cashout', 'credit', v_payout, 0, v_balance,
      'Crash Rocket auto cashout',
      jsonb_build_object('round_id', p_round.id, 'bet_id', v_bet.id,
                         'multiplier', v_bet.auto_cashout_multiplier, 'v', 2)
    );

    perform public._crash_v2_log(p_round.id, 'bet_cashed_out', jsonb_build_object(
      'bet_id', v_bet.id, 'user_id', v_bet.user_id, 'bet_slot', v_bet.bet_slot,
      'payout', v_payout, 'cashout_multiplier', v_bet.auto_cashout_multiplier,
      'auto', true));
  end loop;
end;
$$;
revoke all on function public._crash_v2_settle_auto_cashouts(public.crash_v2_rounds, numeric, timestamptz)
  from public, anon, authenticated;

-- ── The engine tick: advances one scope (room or global) ─────────────────────
create or replace function public.crash_v2_tick(p_room_id uuid default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  cfg public.crash_v2_config := public._crash_v2_cfg();
  v_round public.crash_v2_rounds;
  v_secret public.crash_v2_round_secrets;
  v_now timestamptz := clock_timestamp();
  v_progressed boolean := true;
  v_guard integer := 0;
  v_fly_at timestamptz;
begin
  -- Single engine per scope: serializes cron, defensive RPC ticks, retries.
  perform pg_advisory_xact_lock(hashtextextended(
    'crash_v2:' || coalesce(p_room_id::text, 'global'), 0));

  select * into v_round from public.crash_v2_rounds
  where room_id is not distinct from p_room_id
  order by public_round_number desc
  limit 1
  for update;

  if v_round.id is null then
    if not public._crash_v2_enabled() or cfg.is_paused then
      return jsonb_build_object('status', 'idle', 'server_now', v_now);
    end if;
    v_round := public._crash_v2_create_round(
      p_room_id, v_now + make_interval(secs => cfg.waiting_seconds));
  end if;

  while v_progressed and v_guard < 12 loop
    v_progressed := false;
    v_guard := v_guard + 1;

    if v_round.status = 'waiting'
       and v_now >= v_round.betting_open_at
       and public._crash_v2_enabled()
       and not cfg.is_paused then
      update public.crash_v2_rounds
      set status = 'betting_open', updated_at = v_now
      where id = v_round.id
      returning * into v_round;
      perform public._crash_v2_log(v_round.id, 'round_opened', jsonb_build_object(
        'public_round_number', v_round.public_round_number,
        'betting_close_at', v_round.betting_close_at,
        'server_seed_hash', v_round.server_seed_hash));
      v_progressed := true;

    elsif v_round.status = 'betting_open'
          and v_now >= v_round.betting_close_at then
      update public.crash_v2_rounds
      set status = 'betting_locked', updated_at = v_now
      where id = v_round.id
      returning * into v_round;
      perform public._crash_v2_log(v_round.id, 'betting_locked', '{}');
      v_progressed := true;

    elsif v_round.status = 'betting_locked' then
      v_fly_at := v_round.betting_close_at + make_interval(secs => cfg.lock_seconds);
      if v_now >= v_fly_at then
        select * into v_secret from public.crash_v2_round_secrets
        where round_id = v_round.id for update;

        update public.crash_v2_rounds
        set status = 'flying', started_at = v_fly_at, updated_at = v_now
        where id = v_round.id
        returning * into v_round;

        update public.crash_v2_round_secrets
        set target_crashed_at = v_fly_at + make_interval(
              secs => (ln(v_secret.target_multiplier::float8) / cfg.growth_rate::float8))
        where round_id = v_round.id
        returning * into v_secret;

        perform public._crash_v2_log(v_round.id, 'flight_started',
          jsonb_build_object('started_at', v_round.started_at));
        v_progressed := true;
      end if;

    elsif v_round.status = 'flying' then
      if v_secret.round_id is null then
        select * into v_secret from public.crash_v2_round_secrets
        where round_id = v_round.id for update;
      end if;

      perform public._crash_v2_settle_auto_cashouts(
        v_round, v_secret.target_multiplier, v_now);

      if v_now >= v_secret.target_crashed_at then
        update public.crash_v2_rounds
        set status = 'crashed',
            crashed_at = v_secret.target_crashed_at,
            crash_multiplier = v_secret.target_multiplier,
            updated_at = v_now
        where id = v_round.id
        returning * into v_round;

        update public.crash_v2_bets
        set status = 'lost', settled_at = v_now
        where round_id = v_round.id and status = 'placed';

        perform public._crash_v2_log(v_round.id, 'round_crashed', jsonb_build_object(
          'crash_multiplier', v_round.crash_multiplier,
          'crashed_at', v_round.crashed_at));
        v_progressed := true;
      end if;

    elsif v_round.status = 'crashed'
          and v_now >= v_round.crashed_at
                       + make_interval(secs => cfg.crash_display_seconds) then
      update public.crash_v2_rounds
      set status = 'settling', updated_at = v_now
      where id = v_round.id
      returning * into v_round;
      v_progressed := true;

    elsif v_round.status = 'settling' then
      -- Defensive residual settlement (idempotent), then reveal + complete.
      update public.crash_v2_bets
      set status = 'lost', settled_at = v_now
      where round_id = v_round.id and status = 'placed';

      if v_secret.round_id is null then
        select * into v_secret from public.crash_v2_round_secrets
        where round_id = v_round.id;
      end if;

      update public.crash_v2_rounds
      set status = 'completed',
          completed_at = v_now,
          server_seed = v_secret.server_seed,
          updated_at = v_now
      where id = v_round.id
      returning * into v_round;

      perform public._crash_v2_log(v_round.id, 'round_completed', jsonb_build_object(
        'public_round_number', v_round.public_round_number,
        'crash_multiplier', v_round.crash_multiplier,
        'server_seed', v_round.server_seed,
        'server_seed_hash', v_round.server_seed_hash,
        'client_seed', v_round.client_seed,
        'nonce', v_round.nonce));
      v_progressed := true;

    elsif v_round.status = 'completed' then
      if public._crash_v2_enabled() and not cfg.is_paused then
        v_round := public._crash_v2_create_round(
          p_room_id, v_now + make_interval(secs => cfg.waiting_seconds));
        v_secret := null;
        v_progressed := true;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'round_id', v_round.id, 'status', v_round.status, 'server_now', v_now);
end;
$$;
revoke all on function public.crash_v2_tick(uuid) from public, anon, authenticated;

-- Cron entry point: ticks the global scope and every room scope that still has
-- a non-completed round. Idempotent; safe under overlapping executions.
create or replace function public.crash_v2_tick_all()
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_room uuid;
begin
  perform public.crash_v2_tick(null);
  for v_room in
    select distinct room_id from public.crash_v2_rounds
    where room_id is not null and status <> 'completed'
  loop
    perform public.crash_v2_tick(v_room);
  end loop;
end;
$$;
revoke all on function public.crash_v2_tick_all() from public, anon, authenticated;
grant execute on function public.crash_v2_tick_all() to service_role;

-- =============================================================================
-- Player RPCs
-- =============================================================================

create or replace function public.crash_v2_get_state(p_room_id uuid default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  cfg public.crash_v2_config := public._crash_v2_cfg();
  v_uid uuid := auth.uid();
  v_round public.crash_v2_rounds;
  v_wallet integer;
  v_bets jsonb;
  v_feed jsonb;
  v_history jsonb;
  v_players integer;
  v_total_bet bigint;
begin
  perform public._crash_v2_assert_room_access(p_room_id);

  if not public._crash_v2_enabled() then
    return jsonb_build_object(
      'enabled', false,
      'maintenance_message', cfg.maintenance_message,
      'server_now', clock_timestamp());
  end if;

  perform public.crash_v2_tick(p_room_id);

  select * into v_round from public.crash_v2_rounds
  where room_id is not distinct from p_room_id
  order by public_round_number desc limit 1;

  select coalesce(coins_balance, 0) into v_wallet
  from public.wallets where user_id = v_uid;

  select coalesce(jsonb_agg(to_jsonb(b) order by b.bet_slot), '[]')
  into v_bets from public.crash_v2_bets b
  where b.round_id = v_round.id and b.user_id = v_uid;

  select count(distinct b.user_id), coalesce(sum(b.amount), 0)
  into v_players, v_total_bet
  from public.crash_v2_bets b
  where b.round_id = v_round.id and b.status <> 'canceled';

  select coalesce(jsonb_agg(x.item order by x.id desc), '[]')
  into v_feed from (
    select e.id, e.payload || jsonb_build_object('event_type', e.event_type) as item
    from public.crash_v2_round_events e
    where e.round_id = v_round.id
      and e.event_type in ('bet_placed', 'bet_cashed_out')
    order by e.id desc limit 30
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'public_round_number', h.public_round_number,
    'crash_multiplier', h.crash_multiplier,
    'crashed_at', h.crashed_at
  ) order by h.public_round_number desc), '[]')
  into v_history from (
    select * from public.crash_v2_rounds
    where room_id is not distinct from p_room_id
      and status = 'completed' and crash_multiplier is not null
    order by public_round_number desc limit 12
  ) h;

  return jsonb_build_object(
    'enabled', true,
    'paused', cfg.is_paused,
    'maintenance_message', cfg.maintenance_message,
    'server_now', clock_timestamp(),
    'config', jsonb_build_object(
      'min_bet', cfg.min_bet, 'max_bet', cfg.max_bet,
      'max_payout', cfg.max_payout,
      'min_auto_cashout', cfg.min_auto_cashout,
      'max_auto_cashout', cfg.max_auto_cashout,
      'growth_rate', cfg.growth_rate,
      'max_multiplier', cfg.max_multiplier,
      'betting_seconds', cfg.betting_seconds,
      'waiting_seconds', cfg.waiting_seconds,
      'lock_seconds', cfg.lock_seconds,
      'crash_display_seconds', cfg.crash_display_seconds),
    'round', to_jsonb(v_round),
    'my_bets', v_bets,
    'players', coalesce(v_players, 0),
    'total_bet', coalesce(v_total_bet, 0),
    'public_feed', v_feed,
    'history', v_history,
    'wallet_balance', coalesce(v_wallet, 0));
end;
$$;
revoke all on function public.crash_v2_get_state(uuid) from public, anon;
grant execute on function public.crash_v2_get_state(uuid) to authenticated;

create or replace function public.crash_v2_place_bet(
  p_room_id uuid,
  p_bet_slot integer,
  p_amount integer,
  p_auto_cashout_multiplier numeric,
  p_idempotency_key text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  cfg public.crash_v2_config := public._crash_v2_cfg();
  v_uid uuid := auth.uid();
  v_round public.crash_v2_rounds;
  v_bet public.crash_v2_bets;
  v_balance integer;
begin
  perform public._crash_v2_assert_room_access(p_room_id);

  if not public._crash_v2_enabled() then raise exception 'game_disabled'; end if;
  if cfg.is_paused then raise exception 'game_paused'; end if;
  if p_bet_slot not in (1, 2) then raise exception 'invalid_bet_slot'; end if;
  if p_amount is null or p_amount < cfg.min_bet or p_amount > cfg.max_bet then
    raise exception 'invalid_bet_amount';
  end if;
  if p_auto_cashout_multiplier is not null
     and (p_auto_cashout_multiplier < cfg.min_auto_cashout
          or p_auto_cashout_multiplier > cfg.max_auto_cashout) then
    raise exception 'invalid_auto_cashout';
  end if;
  if length(trim(coalesce(p_idempotency_key, ''))) not between 8 and 100 then
    raise exception 'invalid_idempotency_key';
  end if;

  -- Idempotent retry: return the already-created bet unchanged.
  select * into v_bet from public.crash_v2_bets
  where user_id = v_uid and idempotency_key = trim(p_idempotency_key);
  if v_bet.id is not null then
    select coins_balance into v_balance from public.wallets where user_id = v_uid;
    return jsonb_build_object('bet', to_jsonb(v_bet),
      'wallet_balance', coalesce(v_balance, 0), 'idempotent', true);
  end if;

  perform public.crash_v2_tick(p_room_id);

  select * into v_round from public.crash_v2_rounds
  where room_id is not distinct from p_room_id
  order by public_round_number desc limit 1
  for update;

  if v_round.id is null or v_round.status <> 'betting_open'
     or clock_timestamp() >= v_round.betting_close_at then
    raise exception 'betting_closed';
  end if;

  if exists (select 1 from public.crash_v2_bets
             where round_id = v_round.id and user_id = v_uid
               and bet_slot = p_bet_slot and status <> 'canceled') then
    raise exception 'slot_taken';
  end if;

  insert into public.wallets (user_id) values (v_uid)
  on conflict (user_id) do nothing;

  select coins_balance into v_balance
  from public.wallets where user_id = v_uid for update;
  if coalesce(v_balance, 0) < p_amount then
    raise exception 'insufficient_balance';
  end if;

  update public.wallets
  set coins_balance = coins_balance - p_amount, updated_at = clock_timestamp()
  where user_id = v_uid
  returning coins_balance into v_balance;

  insert into public.crash_v2_bets (
    round_id, user_id, bet_slot, amount, auto_cashout_multiplier, idempotency_key
  ) values (
    v_round.id, v_uid, p_bet_slot, p_amount, p_auto_cashout_multiplier,
    trim(p_idempotency_key)
  ) returning * into v_bet;

  insert into public.wallet_transactions (
    user_id, type, direction, coins_delta, diamonds_delta,
    balance_coins_after, note, metadata
  ) values (
    v_uid, 'crash_rocket_bet', 'debit', -p_amount, 0, v_balance,
    'Crash Rocket bet',
    jsonb_build_object('round_id', v_round.id, 'bet_id', v_bet.id,
                       'bet_slot', p_bet_slot, 'v', 2)
  );

  perform public._crash_v2_log(v_round.id, 'bet_placed', jsonb_build_object(
    'bet_id', v_bet.id, 'user_id', v_uid, 'bet_slot', p_bet_slot,
    'amount', p_amount,
    'display_name', coalesce(
      (select nullif(trim(p.display_name), '') from public.profiles p where p.id = v_uid),
      'Srood Player'),
    'avatar_url', (select p.avatar_url from public.profiles p where p.id = v_uid)));

  return jsonb_build_object('bet', to_jsonb(v_bet),
    'wallet_balance', v_balance, 'idempotent', false);

exception when unique_violation then
  select * into v_bet from public.crash_v2_bets
  where user_id = v_uid and idempotency_key = trim(p_idempotency_key);
  if v_bet.id is null then raise; end if;
  select coins_balance into v_balance from public.wallets where user_id = v_uid;
  return jsonb_build_object('bet', to_jsonb(v_bet),
    'wallet_balance', coalesce(v_balance, 0), 'idempotent', true);
end;
$$;
revoke all on function public.crash_v2_place_bet(uuid, integer, integer, numeric, text)
  from public, anon;
grant execute on function public.crash_v2_place_bet(uuid, integer, integer, numeric, text)
  to authenticated;

create or replace function public.crash_v2_cancel_bet(p_bet_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_bet public.crash_v2_bets;
  v_round public.crash_v2_rounds;
  v_round_id uuid;
  v_balance integer;
  v_now timestamptz := clock_timestamp();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- Lock order: round first, then bet (matches the engine; prevents deadlock).
  select round_id into v_round_id
  from public.crash_v2_bets where id = p_bet_id;
  if v_round_id is null then raise exception 'bet_not_found'; end if;

  select * into v_round from public.crash_v2_rounds
  where id = v_round_id for update;

  select * into v_bet from public.crash_v2_bets
  where id = p_bet_id for update;

  if v_bet.id is null or v_bet.user_id <> v_uid then
    raise exception 'bet_not_found';
  end if;
  if v_bet.status = 'canceled' then
    select coins_balance into v_balance from public.wallets where user_id = v_uid;
    return jsonb_build_object('bet', to_jsonb(v_bet),
      'wallet_balance', coalesce(v_balance, 0), 'idempotent', true);
  end if;
  if v_bet.status <> 'placed' or v_round.status <> 'betting_open'
     or v_now >= v_round.betting_close_at then
    raise exception 'bet_not_cancelable';
  end if;

  update public.wallets
  set coins_balance = coins_balance + v_bet.amount, updated_at = v_now
  where user_id = v_uid
  returning coins_balance into v_balance;

  update public.crash_v2_bets
  set status = 'canceled', settled_at = v_now
  where id = v_bet.id
  returning * into v_bet;

  insert into public.wallet_transactions (
    user_id, type, direction, coins_delta, diamonds_delta,
    balance_coins_after, note, metadata
  ) values (
    v_uid, 'crash_rocket_refund', 'credit', v_bet.amount, 0, v_balance,
    'Crash Rocket bet canceled',
    jsonb_build_object('round_id', v_round.id, 'bet_id', v_bet.id, 'v', 2)
  );

  perform public._crash_v2_log(v_round.id, 'bet_canceled', jsonb_build_object(
    'bet_id', v_bet.id, 'user_id', v_uid, 'bet_slot', v_bet.bet_slot,
    'amount', v_bet.amount));

  return jsonb_build_object('bet', to_jsonb(v_bet),
    'wallet_balance', v_balance, 'idempotent', false);
end;
$$;
revoke all on function public.crash_v2_cancel_bet(uuid) from public, anon;
grant execute on function public.crash_v2_cancel_bet(uuid) to authenticated;

create or replace function public.crash_v2_cash_out(
  p_bet_id uuid, p_idempotency_key text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  cfg public.crash_v2_config := public._crash_v2_cfg();
  v_uid uuid := auth.uid();
  v_bet public.crash_v2_bets;
  v_round public.crash_v2_rounds;
  v_secret public.crash_v2_round_secrets;
  v_now timestamptz := clock_timestamp();
  v_multiplier numeric;
  v_payout integer;
  v_balance integer;
  v_round_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if length(trim(coalesce(p_idempotency_key, ''))) not between 8 and 100 then
    raise exception 'invalid_idempotency_key';
  end if;

  select round_id into v_round_id from public.crash_v2_bets where id = p_bet_id;
  if v_round_id is null then raise exception 'bet_not_found'; end if;

  -- Lock order: round -> bet (same as engine).
  select * into v_round from public.crash_v2_rounds
  where id = v_round_id for update;

  select * into v_bet from public.crash_v2_bets
  where id = p_bet_id for update;

  if v_bet.id is null or v_bet.user_id <> v_uid then
    raise exception 'bet_not_found';
  end if;
  if v_bet.status = 'cashed_out' then
    select coins_balance into v_balance from public.wallets where user_id = v_uid;
    return jsonb_build_object('bet', to_jsonb(v_bet),
      'wallet_balance', coalesce(v_balance, 0), 'idempotent', true);
  end if;
  if v_bet.status <> 'placed' then raise exception 'bet_not_cashable'; end if;

  select * into v_secret from public.crash_v2_round_secrets
  where round_id = v_round.id;

  -- Server clock is the referee: at/after the pre-derived crash instant the
  -- rocket has crashed, whether or not the status row caught up yet.
  if v_round.status <> 'flying'
     or v_secret.target_crashed_at is null
     or v_now >= v_secret.target_crashed_at then
    raise exception 'round_crashed';
  end if;

  v_multiplier := least(v_secret.target_multiplier,
    public._crash_v2_multiplier_at(
      v_round.started_at, v_now, cfg.growth_rate, cfg.max_multiplier));
  v_payout := least(floor(v_bet.amount * v_multiplier)::integer, cfg.max_payout);

  update public.wallets
  set coins_balance = coins_balance + v_payout, updated_at = v_now
  where user_id = v_uid
  returning coins_balance into v_balance;

  update public.crash_v2_bets
  set status = 'cashed_out',
      cashout_multiplier = v_multiplier,
      payout = v_payout,
      cashout_idempotency_key = trim(p_idempotency_key),
      cashed_out_at = v_now,
      settled_at = v_now
  where id = v_bet.id
  returning * into v_bet;

  insert into public.wallet_transactions (
    user_id, type, direction, coins_delta, diamonds_delta,
    balance_coins_after, note, metadata
  ) values (
    v_uid, 'crash_rocket_cashout', 'credit', v_payout, 0, v_balance,
    'Crash Rocket cashout',
    jsonb_build_object('round_id', v_round.id, 'bet_id', v_bet.id,
                       'multiplier', v_multiplier, 'v', 2)
  );

  perform public._crash_v2_log(v_round.id, 'bet_cashed_out', jsonb_build_object(
    'bet_id', v_bet.id, 'user_id', v_uid, 'bet_slot', v_bet.bet_slot,
    'payout', v_payout, 'cashout_multiplier', v_multiplier, 'auto', false));

  return jsonb_build_object('bet', to_jsonb(v_bet),
    'wallet_balance', v_balance, 'idempotent', false);

exception when unique_violation then
  select * into v_bet from public.crash_v2_bets
  where user_id = v_uid and cashout_idempotency_key = trim(p_idempotency_key);
  if v_bet.id is null then raise; end if;
  select coins_balance into v_balance from public.wallets where user_id = v_uid;
  return jsonb_build_object('bet', to_jsonb(v_bet),
    'wallet_balance', coalesce(v_balance, 0), 'idempotent', true);
end;
$$;
revoke all on function public.crash_v2_cash_out(uuid, text) from public, anon;
grant execute on function public.crash_v2_cash_out(uuid, text) to authenticated;

create or replace function public.crash_v2_set_auto_cashout(
  p_bet_id uuid, p_auto_cashout_multiplier numeric)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  cfg public.crash_v2_config := public._crash_v2_cfg();
  v_uid uuid := auth.uid();
  v_bet public.crash_v2_bets;
  v_round public.crash_v2_rounds;
  v_round_id uuid;
  v_current numeric;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_auto_cashout_multiplier is not null
     and (p_auto_cashout_multiplier < cfg.min_auto_cashout
          or p_auto_cashout_multiplier > cfg.max_auto_cashout) then
    raise exception 'invalid_auto_cashout';
  end if;

  select round_id into v_round_id from public.crash_v2_bets where id = p_bet_id;
  if v_round_id is null then raise exception 'bet_not_found'; end if;

  select * into v_round from public.crash_v2_rounds
  where id = v_round_id for update;

  select * into v_bet from public.crash_v2_bets
  where id = p_bet_id for update;

  if v_bet.id is null or v_bet.user_id <> v_uid then
    raise exception 'bet_not_found';
  end if;
  if v_bet.status <> 'placed'
     or v_round.status not in ('betting_open', 'betting_locked', 'flying') then
    raise exception 'bet_not_editable';
  end if;

  if v_round.status = 'flying' and p_auto_cashout_multiplier is not null then
    v_current := public._crash_v2_multiplier_at(
      v_round.started_at, clock_timestamp(), cfg.growth_rate, cfg.max_multiplier);
    if p_auto_cashout_multiplier <= v_current then
      raise exception 'auto_cashout_below_current';
    end if;
  end if;

  update public.crash_v2_bets
  set auto_cashout_multiplier = p_auto_cashout_multiplier
  where id = v_bet.id
  returning * into v_bet;

  return jsonb_build_object('bet', to_jsonb(v_bet));
end;
$$;
revoke all on function public.crash_v2_set_auto_cashout(uuid, numeric) from public, anon;
grant execute on function public.crash_v2_set_auto_cashout(uuid, numeric) to authenticated;

create or replace function public.crash_v2_get_my_round_bets(p_round_id uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(b) order by b.bet_slot), '[]')
  from public.crash_v2_bets b
  where b.round_id = p_round_id and b.user_id = auth.uid();
$$;
revoke all on function public.crash_v2_get_my_round_bets(uuid) from public, anon;
grant execute on function public.crash_v2_get_my_round_bets(uuid) to authenticated;

create or replace function public.crash_v2_get_recent_rounds(
  p_room_id uuid default null, p_limit integer default 20)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'public_round_number', r.public_round_number,
    'crash_multiplier', r.crash_multiplier,
    'crashed_at', r.crashed_at,
    'completed_at', r.completed_at,
    'server_seed_hash', r.server_seed_hash,
    'server_seed', r.server_seed,
    'client_seed', r.client_seed,
    'nonce', r.nonce
  ) order by r.public_round_number desc), '[]')
  from (
    select * from public.crash_v2_rounds
    where room_id is not distinct from p_room_id and status = 'completed'
    order by public_round_number desc
    limit least(greatest(coalesce(p_limit, 20), 1), 100)
  ) r
  where auth.uid() is not null;
$$;
revoke all on function public.crash_v2_get_recent_rounds(uuid, integer) from public, anon;
grant execute on function public.crash_v2_get_recent_rounds(uuid, integer) to authenticated;

create or replace function public.crash_v2_verify_round(
  p_public_round_number bigint, p_room_id uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  cfg public.crash_v2_config := public._crash_v2_cfg();
  v_round public.crash_v2_rounds;
  v_recomputed numeric;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  select * into v_round from public.crash_v2_rounds
  where public_round_number = p_public_round_number
    and room_id is not distinct from p_room_id;

  if v_round.id is null then raise exception 'round_not_found'; end if;
  if v_round.status <> 'completed' or v_round.server_seed is null then
    raise exception 'round_not_completed';
  end if;

  v_recomputed := public._crash_v2_derive_target(
    v_round.server_seed, v_round.client_seed, v_round.nonce,
    cfg.house_edge_factor, cfg.max_multiplier);

  return jsonb_build_object(
    'public_round_number', v_round.public_round_number,
    'server_seed', v_round.server_seed,
    'server_seed_hash', v_round.server_seed_hash,
    'hash_matches', encode(extensions.digest(v_round.server_seed, 'sha256'), 'hex')
                    = v_round.server_seed_hash,
    'client_seed', v_round.client_seed,
    'nonce', v_round.nonce,
    'stored_crash_multiplier', v_round.crash_multiplier,
    'recomputed_crash_multiplier', v_recomputed,
    'result_matches', v_recomputed = v_round.crash_multiplier);
end;
$$;
revoke all on function public.crash_v2_verify_round(bigint, uuid) from public, anon;
grant execute on function public.crash_v2_verify_round(bigint, uuid) to authenticated;

-- =============================================================================
-- Admin RPCs (super_admin gated; every mutation audited; NO forced multiplier
-- capability exists anywhere in this surface)
-- =============================================================================

create or replace function public.crash_v2_admin_get_config()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  cfg public.crash_v2_config := public._crash_v2_cfg();
begin
  if not public._crash_v2_is_admin() then raise exception 'not_authorized'; end if;
  return to_jsonb(cfg) || jsonb_build_object(
    'is_enabled', public._crash_v2_enabled());
end;
$$;
revoke all on function public.crash_v2_admin_get_config() from public, anon;
grant execute on function public.crash_v2_admin_get_config() to authenticated;

create or replace function public.crash_v2_admin_update_config(p_patch jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_allowed text[] := array[
    'waiting_seconds','betting_seconds','lock_seconds','crash_display_seconds',
    'min_bet','max_bet','max_payout','min_auto_cashout','max_auto_cashout',
    'maintenance_message','is_enabled'];
  v_key text;
begin
  if not public._crash_v2_is_admin() then raise exception 'not_authorized'; end if;
  if p_patch is null or p_patch = '{}'::jsonb then
    raise exception 'empty_patch';
  end if;
  for v_key in select jsonb_object_keys(p_patch) loop
    if v_key <> all (v_allowed) then
      raise exception 'config_key_not_allowed: %', v_key;
    end if;
  end loop;

  update public.crash_v2_config set
    waiting_seconds       = coalesce((p_patch->>'waiting_seconds')::integer, waiting_seconds),
    betting_seconds       = coalesce((p_patch->>'betting_seconds')::integer, betting_seconds),
    lock_seconds          = coalesce((p_patch->>'lock_seconds')::integer, lock_seconds),
    crash_display_seconds = coalesce((p_patch->>'crash_display_seconds')::integer, crash_display_seconds),
    min_bet               = coalesce((p_patch->>'min_bet')::integer, min_bet),
    max_bet               = coalesce((p_patch->>'max_bet')::integer, max_bet),
    max_payout            = coalesce((p_patch->>'max_payout')::integer, max_payout),
    min_auto_cashout      = coalesce((p_patch->>'min_auto_cashout')::numeric, min_auto_cashout),
    max_auto_cashout      = coalesce((p_patch->>'max_auto_cashout')::numeric, max_auto_cashout),
    maintenance_message   = case when p_patch ? 'maintenance_message'
                                 then nullif(p_patch->>'maintenance_message', '')
                                 else maintenance_message end,
    updated_at = now(),
    updated_by = v_uid
  where singleton;

  if p_patch ? 'is_enabled' then
    update public.game_settings
    set is_enabled = (p_patch->>'is_enabled')::boolean, updated_at = now()
    where game_key = 'crash_rocket_v2';
  end if;

  insert into public.crash_v2_admin_actions (admin_id, action, detail)
  values (v_uid, 'update_config', p_patch);

  return public.crash_v2_admin_get_config();
end;
$$;
revoke all on function public.crash_v2_admin_update_config(jsonb) from public, anon;
grant execute on function public.crash_v2_admin_update_config(jsonb) to authenticated;

create or replace function public.crash_v2_admin_pause_game(p_message text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public._crash_v2_is_admin() then raise exception 'not_authorized'; end if;
  update public.crash_v2_config
  set is_paused = true,
      maintenance_message = coalesce(nullif(trim(p_message), ''), maintenance_message),
      updated_at = now(), updated_by = v_uid
  where singleton;
  insert into public.crash_v2_admin_actions (admin_id, action, detail)
  values (v_uid, 'pause_game', jsonb_build_object('message', p_message));
  return public.crash_v2_admin_get_config();
end;
$$;
revoke all on function public.crash_v2_admin_pause_game(text) from public, anon;
grant execute on function public.crash_v2_admin_pause_game(text) to authenticated;

create or replace function public.crash_v2_admin_resume_game()
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public._crash_v2_is_admin() then raise exception 'not_authorized'; end if;
  update public.crash_v2_config
  set is_paused = false, maintenance_message = null,
      updated_at = now(), updated_by = v_uid
  where singleton;
  insert into public.crash_v2_admin_actions (admin_id, action, detail)
  values (v_uid, 'resume_game', '{}');
  return public.crash_v2_admin_get_config();
end;
$$;
revoke all on function public.crash_v2_admin_resume_game() from public, anon;
grant execute on function public.crash_v2_admin_resume_game() to authenticated;

create or replace function public.crash_v2_admin_get_overview()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_current jsonb;
  v_recent jsonb;
  v_today_wagered bigint;
  v_today_payout bigint;
  v_open_exposure bigint;
  v_stuck jsonb;
begin
  if not public._crash_v2_is_admin() then raise exception 'not_authorized'; end if;

  select to_jsonb(r) into v_current from public.crash_v2_rounds r
  where r.room_id is null
  order by r.public_round_number desc limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'public_round_number', r.public_round_number,
    'status', r.status,
    'crash_multiplier', r.crash_multiplier,
    'completed_at', r.completed_at,
    'wagered', (select coalesce(sum(b.amount),0) from public.crash_v2_bets b
                where b.round_id = r.id and b.status <> 'canceled'),
    'paid_out', (select coalesce(sum(b.payout),0) from public.crash_v2_bets b
                 where b.round_id = r.id and b.status = 'cashed_out')
  ) order by r.public_round_number desc), '[]')
  into v_recent from (
    select * from public.crash_v2_rounds
    order by public_round_number desc limit 10
  ) r;

  select coalesce(sum(b.amount), 0) into v_today_wagered
  from public.crash_v2_bets b
  where b.created_at >= date_trunc('day', now()) and b.status <> 'canceled';

  select coalesce(sum(b.payout), 0) into v_today_payout
  from public.crash_v2_bets b
  where b.settled_at >= date_trunc('day', now()) and b.status = 'cashed_out';

  select coalesce(sum(b.amount), 0) into v_open_exposure
  from public.crash_v2_bets b
  join public.crash_v2_rounds r on r.id = b.round_id
  where b.status = 'placed' and r.status <> 'completed';

  -- Failed-settlement alert: rounds stalled in a non-terminal state.
  select coalesce(jsonb_agg(jsonb_build_object(
    'round_id', r.id, 'status', r.status,
    'public_round_number', r.public_round_number,
    'updated_at', r.updated_at)), '[]')
  into v_stuck from public.crash_v2_rounds r
  where r.status not in ('completed')
    and r.updated_at < now() - interval '2 minutes';

  return jsonb_build_object(
    'current_round', v_current,
    'recent_rounds', v_recent,
    'today_wagered', v_today_wagered,
    'today_payout', v_today_payout,
    'open_exposure', v_open_exposure,
    'stuck_rounds', v_stuck,
    'server_now', clock_timestamp());
end;
$$;
revoke all on function public.crash_v2_admin_get_overview() from public, anon;
grant execute on function public.crash_v2_admin_get_overview() to authenticated;

create or replace function public.crash_v2_admin_get_audit_log(p_limit integer default 50)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_log jsonb;
begin
  if not public._crash_v2_is_admin() then raise exception 'not_authorized'; end if;
  select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]')
  into v_log
  from (
    select * from public.crash_v2_admin_actions
    order by id desc
    limit least(greatest(coalesce(p_limit, 50), 1), 500)
  ) a;
  return v_log;
end;
$$;
revoke all on function public.crash_v2_admin_get_audit_log(integer) from public, anon;
grant execute on function public.crash_v2_admin_get_audit_log(integer) to authenticated;

-- ── Cron: authoritative engine heartbeat (guarded for cron-less validation) ──
do $$
begin
  if to_regnamespace('cron') is not null then
    perform cron.schedule('crash_v2_auto_advance', '3 seconds',
      $cron$ select public.crash_v2_tick_all(); $cron$);
  else
    raise notice 'pg_cron not present; crash_v2 engine will be driven by RPC ticks (validation env)';
  end if;
end $$;
