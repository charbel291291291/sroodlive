-- Srood Blocks: Tetris-style mini-game
-- Economy rules:
--   - Players NEVER earn coins from playing (coins keep their value)
--   - Players may SPEND 50 coins to buy extra plays
--   - Players earn XP only (capped at 100 XP/day)

-- ── 1. Tables ────────────────────────────────────────────────────────────────

create table if not exists public.srood_blocks_scores (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references auth.users(id) on delete cascade,
  score        integer     not null check (score >= 0),
  lines_cleared integer    not null default 0,
  level        integer     not null default 1,
  duration_sec integer     not null check (duration_sec >= 30),
  xp_earned    integer     not null default 0,
  week_start   date        not null,
  created_at   timestamptz not null default now()
);

create index if not exists sbs_user_week_idx
  on public.srood_blocks_scores (user_id, week_start);

create index if not exists sbs_week_score_idx
  on public.srood_blocks_scores (week_start, score desc);

alter table public.srood_blocks_scores enable row level security;

drop policy if exists "blocks_scores_own_read" on public.srood_blocks_scores;
create policy "blocks_scores_own_read"
  on public.srood_blocks_scores for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "blocks_scores_insert" on public.srood_blocks_scores;
create policy "blocks_scores_insert"
  on public.srood_blocks_scores for insert to authenticated
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.srood_blocks_daily_limits (
  user_id      uuid        primary key references auth.users(id) on delete cascade,
  play_date    date        not null default current_date,
  plays_used   integer     not null default 0,
  xp_earned    integer     not null default 0,
  updated_at   timestamptz not null default now()
);

alter table public.srood_blocks_daily_limits enable row level security;

drop policy if exists "blocks_daily_own_read" on public.srood_blocks_daily_limits;
create policy "blocks_daily_own_read"
  on public.srood_blocks_daily_limits for select to authenticated
  using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.srood_blocks_active_plays (
  user_id      uuid        primary key references auth.users(id) on delete cascade,
  started_at   timestamptz not null default now(),
  is_paid      boolean     not null default false
);

alter table public.srood_blocks_active_plays enable row level security;

drop policy if exists "blocks_active_own" on public.srood_blocks_active_plays;
create policy "blocks_active_own"
  on public.srood_blocks_active_plays for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ── 2. Extend wallet_transactions type constraint ─────────────────────────────

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_type_check check (
    type in (
      'recharge_request','admin_adjustment','gift_sent','gift_received',
      'agency_recharge','refund','system','withdrawal','withdrawal_refund',
      'agency_commission',
      'red_envelope_sent','red_envelope_claimed',
      'hungry_cat_bet','hungry_cat_reward','hungry_cat_refund',
      'gold_ladder_entry','gold_ladder_win','gold_ladder_safe_payout',
      'crash_rocket_bet','crash_rocket_win','crash_rocket_refund',
      'room_game_bet','room_game_win','room_game_refund',
      'srood_loto_ticket','srood_treasure_entry','srood_treasure_win',
      'blocks_play'
    )
  );

-- ── 3. RPCs ───────────────────────────────────────────────────────────────────

-- Returns daily status for the current user.
-- free_plays depends on VIP level stored in profiles.vip_level.
create or replace function public.get_srood_blocks_daily_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_vip_level  int  := 0;
  v_free_plays int;
  v_plays_used int  := 0;
  v_xp_today   int  := 0;
  v_play_date  date;
  v_coins_bal  bigint := 0;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- VIP level
  select coalesce(vip_level, 0) into v_vip_level
  from public.profiles where id = v_user_id;

  -- free plays by VIP tier
  v_free_plays := case
    when v_vip_level >= 3 then 6
    when v_vip_level = 2  then 5
    when v_vip_level = 1  then 4
    else 3
  end;

  -- daily record (may not exist yet)
  select plays_used, xp_earned, play_date
  into v_plays_used, v_xp_today, v_play_date
  from public.srood_blocks_daily_limits
  where user_id = v_user_id;

  -- reset if stale date
  if v_play_date is null or v_play_date < current_date then
    v_plays_used := 0;
    v_xp_today   := 0;
  end if;

  -- coin balance
  select coalesce(coins_balance, 0) into v_coins_bal
  from public.wallets where user_id = v_user_id;

  return jsonb_build_object(
    'free_plays',    v_free_plays,
    'plays_used',    v_plays_used,
    'xp_today',      v_xp_today,
    'xp_cap',        100,
    'coins_balance', v_coins_bal,
    'extra_play_cost', 50
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────

-- Starts a play session.
-- p_is_paid = true  → deduct 50 coins, allowed even if free_plays exhausted
-- p_is_paid = false → count against free_plays quota
create or replace function public.start_srood_blocks_play(p_is_paid boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_vip_level  int  := 0;
  v_free_plays int;
  v_plays_used int  := 0;
  v_xp_today   int  := 0;
  v_play_date  date;
  v_coins_bal  bigint;
  v_bal_after  bigint;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select coalesce(vip_level, 0) into v_vip_level
  from public.profiles where id = v_user_id;

  v_free_plays := case
    when v_vip_level >= 3 then 6
    when v_vip_level = 2  then 5
    when v_vip_level = 1  then 4
    else 3
  end;

  -- upsert daily record
  insert into public.srood_blocks_daily_limits (user_id, play_date, plays_used, xp_earned)
  values (v_user_id, current_date, 0, 0)
  on conflict (user_id) do update
    set play_date  = case when srood_blocks_daily_limits.play_date < current_date then current_date else srood_blocks_daily_limits.play_date end,
        plays_used = case when srood_blocks_daily_limits.play_date < current_date then 0            else srood_blocks_daily_limits.plays_used end,
        xp_earned  = case when srood_blocks_daily_limits.play_date < current_date then 0            else srood_blocks_daily_limits.xp_earned end,
        updated_at = now();

  select plays_used, xp_earned, play_date
  into v_plays_used, v_xp_today, v_play_date
  from public.srood_blocks_daily_limits where user_id = v_user_id;

  if p_is_paid then
    -- deduct 50 coins
    select coalesce(coins_balance, 0) into v_coins_bal
    from public.wallets where user_id = v_user_id;

    if v_coins_bal < 50 then
      raise exception 'insufficient_coins';
    end if;

    update public.wallets
    set coins_balance          = coins_balance - 50,
        lifetime_coins_spent   = coalesce(lifetime_coins_spent, 0) + 50,
        updated_at             = now()
    where user_id = v_user_id
    returning coins_balance into v_bal_after;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
    values
      (v_user_id, 'blocks_play', 'debit', -50, 0, 'Srood Blocks extra play',
       jsonb_build_object('is_paid', true));
  else
    if v_plays_used >= v_free_plays then
      raise exception 'no_free_plays_left';
    end if;

    update public.srood_blocks_daily_limits
    set plays_used = plays_used + 1, updated_at = now()
    where user_id = v_user_id;
  end if;

  -- record active play
  insert into public.srood_blocks_active_plays (user_id, started_at, is_paid)
  values (v_user_id, now(), p_is_paid)
  on conflict (user_id) do update set started_at = now(), is_paid = p_is_paid;

  return jsonb_build_object('ok', true, 'is_paid', p_is_paid);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────

-- Submits a completed play score. Anti-abuse: min 30s duration, score ceiling.
create or replace function public.submit_srood_blocks_score(
  p_score        integer,
  p_lines        integer,
  p_level        integer,
  p_duration_sec integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id   uuid := auth.uid();
  v_started   timestamptz;
  v_is_paid   boolean;
  v_xp_today  int := 0;
  v_xp_cap    int := 100;
  v_xp_earn   int := 0;
  v_xp_avail  int;
  v_week_start date;
  v_play_date  date;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- must have an active play session
  select started_at, is_paid into v_started, v_is_paid
  from public.srood_blocks_active_plays where user_id = v_user_id;

  if v_started is null then
    raise exception 'no_active_play';
  end if;

  -- server-side min duration check
  if p_duration_sec < 30 then
    raise exception 'play_too_short';
  end if;

  -- sanity: score can't exceed ~40 points/line * 10 lines/s * duration
  if p_score > (p_duration_sec * 400) then
    raise exception 'score_rejected';
  end if;

  -- week start (Monday)
  v_week_start := date_trunc('week', current_date)::date;

  -- XP calculation
  -- base: 5 XP per play
  -- milestones: +5 per score milestone (100/250/500/1000/2500/5000)
  v_xp_earn := 5;
  if p_score >=  100 then v_xp_earn := v_xp_earn + 5; end if;
  if p_score >=  250 then v_xp_earn := v_xp_earn + 5; end if;
  if p_score >=  500 then v_xp_earn := v_xp_earn + 5; end if;
  if p_score >= 1000 then v_xp_earn := v_xp_earn + 10; end if;
  if p_score >= 2500 then v_xp_earn := v_xp_earn + 10; end if;
  if p_score >= 5000 then v_xp_earn := v_xp_earn + 10; end if;

  -- cap by daily remaining
  select coalesce(xp_earned, 0), coalesce(play_date, current_date)
  into v_xp_today, v_play_date
  from public.srood_blocks_daily_limits where user_id = v_user_id;

  if v_play_date < current_date then v_xp_today := 0; end if;

  v_xp_avail := greatest(0, v_xp_cap - v_xp_today);
  v_xp_earn  := least(v_xp_earn, v_xp_avail);

  -- save score
  insert into public.srood_blocks_scores
    (user_id, score, lines_cleared, level, duration_sec, xp_earned, week_start)
  values
    (v_user_id, p_score, p_lines, p_level, p_duration_sec, v_xp_earn, v_week_start);

  -- update daily XP
  update public.srood_blocks_daily_limits
  set xp_earned  = case when play_date < current_date then v_xp_earn else xp_earned + v_xp_earn end,
      play_date  = current_date,
      updated_at = now()
  where user_id = v_user_id;

  -- award XP via existing system
  if v_xp_earn > 0 then
    perform public.add_user_xp(v_user_id, v_xp_earn, 'srood_blocks');
  end if;

  -- clear active play
  delete from public.srood_blocks_active_plays where user_id = v_user_id;

  return jsonb_build_object(
    'ok',       true,
    'xp_earned', v_xp_earn,
    'score',     p_score
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────

-- Weekly leaderboard (top N by best score in the current ISO week).
create or replace function public.get_srood_blocks_weekly_leaderboard(p_limit integer default 50)
returns table (
  rank         bigint,
  user_id      uuid,
  display_name text,
  avatar_url   text,
  best_score   integer,
  total_lines  bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_start date := date_trunc('week', current_date)::date;
begin
  return query
  with best as (
    select
      s.user_id,
      max(s.score)          as best_score,
      sum(s.lines_cleared)  as total_lines
    from public.srood_blocks_scores s
    where s.week_start = v_week_start
    group by s.user_id
  )
  select
    row_number() over (order by b.best_score desc, b.total_lines desc) as rank,
    b.user_id,
    coalesce(p.display_name, p.username, 'Player')::text,
    p.avatar_url::text,
    b.best_score::integer,
    b.total_lines
  from best b
  left join public.profiles p on p.id = b.user_id
  order by b.best_score desc, b.total_lines desc
  limit least(p_limit, 100);
end;
$$;

-- ── 4. Grants ─────────────────────────────────────────────────────────────────

grant execute on function public.get_srood_blocks_daily_status()                                         to authenticated;
grant execute on function public.start_srood_blocks_play(boolean)                                        to authenticated;
grant execute on function public.submit_srood_blocks_score(integer, integer, integer, integer)            to authenticated;
grant execute on function public.get_srood_blocks_weekly_leaderboard(integer)                            to authenticated;
