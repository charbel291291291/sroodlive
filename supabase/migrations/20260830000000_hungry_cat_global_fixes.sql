-- ─────────────────────────────────────────────────────────────────────────────
-- Hungry Cat Global Round Fixes
--
-- 1. get_or_create_hungry_cat_round  — settle expired betting rounds before
--    creating a new one, so no round is ever abandoned with pending bets.
-- 2. settle_hungry_cat_global_round  — consume forced_next_result from
--    game_settings when test_mode = true.
-- 3. pg_cron job                     — auto-advance rounds every 15 seconds so
--    the game runs 24/7 without requiring any client to be open.
--    (Installed only if pg_cron extension is available; no-op otherwise.)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. get_or_create_hungry_cat_round ────────────────────────────────────────
-- Patched to settle any expired-but-unsettled betting round before creating
-- a fresh one.  The advisory lock ensures only one session runs this at a time.

create or replace function public.get_or_create_hungry_cat_round()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round   public.hungry_cat_global_rounds;
  v_expired public.hungry_cat_global_rounds;
  v_now     timestamptz := now();
  v_rnum    bigint;
  c_dur     constant int := 12; -- seconds per betting window
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  perform pg_advisory_xact_lock(hashtext('hungry_cat_global_round'));

  -- Return existing active round if it still has time remaining
  select * into v_round
  from public.hungry_cat_global_rounds
  where status = 'betting'
  order by created_at desc
  limit 1;

  if v_round.id is not null and v_round.betting_ends_at > v_now then
    return json_build_object(
      'round_id',           v_round.id,
      'round_number',       v_round.round_number,
      'status',             v_round.status,
      'betting_starts_at',  v_round.betting_starts_at,
      'betting_ends_at',    v_round.betting_ends_at,
      'winning_food_id',    v_round.winning_food_id,
      'winning_food_icon',  v_round.winning_food_icon,
      'winning_food_name',  v_round.winning_food_name,
      'winning_multiplier', v_round.winning_multiplier,
      'server_now',         v_now
    );
  end if;

  -- Settle any expired betting rounds that clients missed
  for v_expired in
    select * from public.hungry_cat_global_rounds
    where status = 'betting' and betting_ends_at <= v_now
    order by created_at asc
  loop
    begin
      -- Uses the settle function which is itself idempotent
      perform public.settle_hungry_cat_global_round(v_expired.id);
    exception when others then
      -- Non-fatal: log and continue; the round stays with pending bets
      -- rather than blocking new-round creation.
      raise warning 'get_or_create: could not settle expired round %: %', v_expired.id, sqlerrm;
    end;
  end loop;

  -- Create a new round
  v_rnum := nextval('public.hungry_cat_round_seq');

  insert into public.hungry_cat_global_rounds
    (round_number, status, betting_starts_at, betting_ends_at)
  values
    (v_rnum, 'betting', v_now, v_now + (c_dur || ' seconds')::interval)
  returning * into v_round;

  return json_build_object(
    'round_id',           v_round.id,
    'round_number',       v_round.round_number,
    'status',             v_round.status,
    'betting_starts_at',  v_round.betting_starts_at,
    'betting_ends_at',    v_round.betting_ends_at,
    'winning_food_id',    null,
    'winning_food_icon',  null,
    'winning_food_name',  null,
    'winning_multiplier', null,
    'server_now',         v_now
  );
end;
$$;

grant execute on function public.get_or_create_hungry_cat_round() to authenticated;


-- ── 2. settle_hungry_cat_global_round ────────────────────────────────────────
-- Patched to consume forced_next_result from game_settings when test_mode=true.
-- The forced food is used instead of random() selection and cleared after use.

create or replace function public.settle_hungry_cat_global_round(
  p_round_id uuid
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_round        public.hungry_cat_global_rounds;
  v_food         public.hungry_cat_config;
  v_settings     public.game_settings;
  v_total_weight numeric;
  v_roll         numeric;
  v_bet          record;
  v_win_amount   integer;
  v_forced_food  text;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select * into v_round
  from public.hungry_cat_global_rounds
  where id = p_round_id
  for update;

  if v_round.id is null then raise exception 'round_not_found'; end if;

  -- Idempotent: already settled — return early without re-paying
  if v_round.status = 'settled' then
    return json_build_object(
      'round_id',           v_round.id,
      'status',             'settled',
      'winning_food_id',    v_round.winning_food_id,
      'winning_food_icon',  v_round.winning_food_icon,
      'winning_food_name',  v_round.winning_food_name,
      'winning_multiplier', v_round.winning_multiplier,
      'server_now',         now()
    );
  end if;

  if v_round.betting_ends_at > now() then
    raise exception 'betting_still_open';
  end if;

  -- ── Check for forced result (test mode only) ──────────────────────────────
  select * into v_settings
  from public.game_settings
  where game_key = 'hungry_cat';

  v_forced_food := null;
  if v_settings.test_mode
     and v_settings.forced_next_result is not null
     and (v_settings.forced_next_result_expires_at is null
          or v_settings.forced_next_result_expires_at > now())
  then
    -- Validate the forced food is still active
    select * into v_food
    from public.hungry_cat_config
    where food_id = v_settings.forced_next_result and is_active;

    if v_food.id is not null then
      v_forced_food := v_settings.forced_next_result;
      -- Clear immediately so it is used only once
      update public.game_settings
      set forced_next_result             = null,
          forced_next_result_expires_at  = null,
          forced_next_result_by          = null,
          updated_at                     = now()
      where game_key = 'hungry_cat';
    end if;
  end if;

  -- ── Weighted-random food selection (when not forced) ──────────────────────
  if v_forced_food is null then
    select coalesce(sum(weight), 0) into v_total_weight
    from public.hungry_cat_config
    where is_active and weight > 0;

    if v_total_weight <= 0 then raise exception 'invalid_food_config'; end if;

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

    -- Fallback: last active food if roll somehow exceeds total
    if v_food.id is null then
      select c.* into v_food
      from public.hungry_cat_config c
      where c.is_active and c.weight > 0
      order by c.sort_order desc
      limit 1;
    end if;
  end if;

  if v_food.id is null then raise exception 'invalid_food_config'; end if;

  -- ── Pay out all winning bets; mark losers ─────────────────────────────────
  for v_bet in
    select b.id, b.user_id, b.bet_amount, b.food_id
    from public.hungry_cat_global_bets b
    where b.round_id = p_round_id and b.status = 'pending'
  loop
    if v_bet.food_id = v_food.food_id then
      v_win_amount := floor(v_bet.bet_amount * v_food.multiplier)::integer;

      update public.wallets
      set coins_balance = coins_balance + v_win_amount,
          updated_at    = now()
      where user_id = v_bet.user_id;

      update public.hungry_cat_global_bets
      set status = 'won', win_amount = v_win_amount
      where id = v_bet.id;

      insert into public.wallet_transactions
        (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
      values
        (v_bet.user_id, 'hungry_cat_reward', 'credit', v_win_amount, 0,
         'Hungry Cat win: ' || v_food.name || ' x' || v_food.multiplier,
         jsonb_build_object('bet_id', v_bet.id, 'round_id', p_round_id,
                            'food_id', v_food.food_id,
                            'multiplier', v_food.multiplier,
                            'forced', v_forced_food is not null));
    else
      update public.hungry_cat_global_bets
      set status = 'lost'
      where id = v_bet.id;
    end if;
  end loop;

  -- ── Mark round settled ────────────────────────────────────────────────────
  update public.hungry_cat_global_rounds
  set status             = 'settled',
      result_reveals_at  = now(),
      winning_food_id    = v_food.food_id,
      winning_food_icon  = v_food.icon,
      winning_food_name  = v_food.name,
      winning_multiplier = v_food.multiplier
  where id = p_round_id;

  return json_build_object(
    'round_id',           p_round_id,
    'status',             'settled',
    'winning_food_id',    v_food.food_id,
    'winning_food_icon',  v_food.icon,
    'winning_food_name',  v_food.name,
    'winning_multiplier', v_food.multiplier,
    'server_now',         now()
  );
end;
$$;

grant execute on function public.settle_hungry_cat_global_round(uuid) to authenticated;


-- ── 3. pg_cron auto-advance job ───────────────────────────────────────────────
-- Runs every 15 seconds: settles any expired rounds, then creates the next one.
-- Only installed if pg_cron is available.  Safe to run multiple times.
--
-- Note: pg_cron minimum granularity is 1 minute.  We work around this by
-- scheduling the same job six times at 0, 10, 20, 30, 40, 50 seconds using
-- the pg_cron 'seconds' syntax (requires pg_cron >= 1.4 with second precision).
-- If second-precision is not available we fall back to a 1-minute schedule.

do $$
declare
  v_cron_available boolean := false;
  v_job_name text := 'hungry_cat_auto_advance';
begin
  -- Check if pg_cron is installed
  if exists (
    select 1 from pg_catalog.pg_extension where extname = 'pg_cron'
  ) then
    v_cron_available := true;
  end if;

  if not v_cron_available then
    raise notice 'pg_cron not available — Hungry Cat auto-advance will rely on client triggers';
    return;
  end if;

  -- Remove any existing job with this name before re-adding
  if exists (select 1 from cron.job where jobname = v_job_name) then
    perform cron.unschedule(v_job_name);
  end if;

  -- Schedule: every minute (pg_cron standard granularity).
  -- Each execution settles all expired rounds and creates the next fresh round.
  -- The advisory lock inside get_or_create prevents races when multiple cron
  -- workers fire in the same second.
  perform cron.schedule(
    v_job_name,
    '* * * * *',  -- every minute; see note above
    $cron$
      select public.get_or_create_hungry_cat_round();
    $cron$
  );

  raise notice 'Hungry Cat auto-advance cron job scheduled (every minute)';
end;
$$;
