-- =============================================================================
-- Daily Reward / Sign-in system (additive)
--
-- 7-day repeating cycle. One claim per UTC calendar day. Server-authoritative:
-- the claim RPC computes the day, resets on a missed day, validates a single
-- claim per day (unique constraint), and credits coins using the app's existing
-- wallet pattern (atomic balance update + wallet_transactions ledger row).
--
-- Supported reward type now: 'coins' (safe, uses existing wallet ledger).
-- The schema stores reward_type/reward_key/duration so vip_days / inventory can
-- be added later; the claim + admin RPCs currently accept only 'coins' and
-- reject anything else with a clear error (no VIP/backpack logic touched).
--
-- Admin management is gated to super-admin tiers via existing role helpers.
-- Additive + idempotent. No destructive changes.
-- =============================================================================

-- ── 0. Allow 'daily_reward' in the wallet ledger type check (preserve all
--       existing types; based on the live constraint) ───────────────────────
alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_type_check;
alter table public.wallet_transactions
  add constraint wallet_transactions_type_check check (
    type = any (array[
      'recharge_request','admin_adjustment','gift_sent','gift_received',
      'agency_recharge','refund','system','withdrawal','withdrawal_refund',
      'agency_commission','red_envelope_sent','red_envelope_claimed',
      'hungry_cat_bet','hungry_cat_reward','hungry_cat_refund',
      'gold_ladder_entry','gold_ladder_win','gold_ladder_safe_payout',
      'crash_rocket_bet','crash_rocket_win','crash_rocket_refund',
      'room_game_bet','room_game_win','room_game_refund',
      'srood_loto_ticket','srood_treasure_entry','srood_treasure_win',
      'blocks_play',
      'daily_reward'
    ])
  );

-- ── 1. Tables ─────────────────────────────────────────────────────────────────
create table if not exists public.daily_reward_config (
  id            integer primary key default 1 check (id = 1),
  enabled       boolean not null default true,
  popup_enabled boolean not null default true,
  cycle_days    integer not null default 7 check (cycle_days = 7),
  updated_at    timestamptz not null default now()
);

create table if not exists public.daily_reward_rules (
  id            uuid primary key default gen_random_uuid(),
  day_number    integer not null unique check (day_number between 1 and 7),
  enabled       boolean not null default true,
  reward_type   text    not null default 'coins',
  reward_key    text,
  title         text    not null default '',
  description   text,
  amount        bigint  not null default 0 check (amount >= 0),
  duration_days integer,
  image_url     text,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.user_daily_rewards (
  user_id               uuid primary key references auth.users(id) on delete cascade,
  current_day           integer not null default 0 check (current_day between 0 and 7),
  streak_count          integer not null default 0,
  last_claim_date       date,
  cycle_completed_count integer not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table if not exists public.daily_reward_claims (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  claimed_day    integer not null check (claimed_day between 1 and 7),
  reward_rule_id uuid references public.daily_reward_rules(id),
  reward_type    text not null,
  reward_key     text,
  amount         bigint not null default 0,
  duration_days  integer,
  claimed_date   date not null,
  created_at     timestamptz not null default now(),
  constraint daily_reward_claims_one_per_day unique (user_id, claimed_date)
);

-- ── 2. RLS ────────────────────────────────────────────────────────────────────
alter table public.daily_reward_config enable row level security;
alter table public.daily_reward_rules  enable row level security;
alter table public.user_daily_rewards  enable row level security;
alter table public.daily_reward_claims enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='daily_reward_config' and policyname='dr_config_read') then
    create policy dr_config_read on public.daily_reward_config for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='daily_reward_rules' and policyname='dr_rules_read') then
    create policy dr_rules_read on public.daily_reward_rules for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='user_daily_rewards' and policyname='dr_user_own_read') then
    create policy dr_user_own_read on public.user_daily_rewards for select using (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='daily_reward_claims' and policyname='dr_claims_own_read') then
    create policy dr_claims_own_read on public.daily_reward_claims for select using (auth.uid() = user_id);
  end if;
end $$;

-- ── 3. Seed config + 7 coin rules ────────────────────────────────────────────
insert into public.daily_reward_config (id, enabled, popup_enabled)
values (1, true, true)
on conflict (id) do nothing;

insert into public.daily_reward_rules (day_number, enabled, reward_type, title, amount, sort_order)
values
  (1, true, 'coins', 'Day 1',  1000, 1),
  (2, true, 'coins', 'Day 2',  2000, 2),
  (3, true, 'coins', 'Day 3',  3000, 3),
  (4, true, 'coins', 'Day 4',  5000, 4),
  (5, true, 'coins', 'Day 5',  8000, 5),
  (6, true, 'coins', 'Day 6', 12000, 6),
  (7, true, 'coins', 'Day 7', 30000, 7)
on conflict (day_number) do nothing;

-- ── 4. get_daily_reward_state() ──────────────────────────────────────────────
create or replace function public.get_daily_reward_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_cfg   public.daily_reward_config;
  v_row   public.user_daily_rewards;
  v_today date := (now() at time zone 'utc')::date;
  v_claim_day integer;
  v_claimed_today boolean;
  v_can_claim boolean;
  v_rules jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_cfg from public.daily_reward_config where id = 1;
  select * into v_row from public.user_daily_rewards where user_id = v_uid;

  v_claimed_today := v_row.last_claim_date is not null and v_row.last_claim_date = v_today;

  -- The day that would be claimed today (or that was claimed today).
  if v_claimed_today then
    v_claim_day := v_row.current_day;
  elsif v_row.last_claim_date is not null
        and v_row.last_claim_date = (v_today - 1)
        and v_row.current_day between 1 and 6 then
    v_claim_day := v_row.current_day + 1;          -- streak continues
  else
    v_claim_day := 1;                              -- new cycle / missed / first time
  end if;

  v_can_claim := coalesce(v_cfg.enabled, false) and not v_claimed_today;

  select coalesce(jsonb_agg(jsonb_build_object(
           'day_number',    r.day_number,
           'enabled',       r.enabled,
           'reward_type',   r.reward_type,
           'title',         r.title,
           'description',   r.description,
           'amount',        r.amount,
           'duration_days', r.duration_days,
           'image_url',     r.image_url
         ) order by r.day_number), '[]'::jsonb)
  into v_rules
  from public.daily_reward_rules r;

  return jsonb_build_object(
    'enabled',         coalesce(v_cfg.enabled, false),
    'popup_enabled',   coalesce(v_cfg.popup_enabled, false),
    'can_claim_today', v_can_claim,
    'claimed_today',   v_claimed_today,
    'claim_day',       v_claim_day,
    'current_day',     coalesce(v_row.current_day, 0),
    'streak_count',    coalesce(v_row.streak_count, 0),
    'last_claim_date', to_char(v_row.last_claim_date, 'YYYY-MM-DD'),
    'next_claim_date', case when v_claimed_today then to_char(v_today + 1, 'YYYY-MM-DD') else to_char(v_today, 'YYYY-MM-DD') end,
    'rules',           v_rules
  );
end;
$$;
grant execute on function public.get_daily_reward_state() to authenticated;

-- ── 5. claim_daily_reward() ──────────────────────────────────────────────────
create or replace function public.claim_daily_reward()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_cfg    public.daily_reward_config;
  v_row    public.user_daily_rewards;
  v_today  date := (now() at time zone 'utc')::date;
  v_claim_day integer;
  v_new_streak integer;
  v_cycle_inc  integer := 0;
  v_rule   public.daily_reward_rules;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_cfg from public.daily_reward_config where id = 1;
  if not coalesce(v_cfg.enabled, false) then raise exception 'daily_reward_disabled'; end if;

  -- Lock / create the user's row.
  insert into public.user_daily_rewards (user_id) values (v_uid)
  on conflict (user_id) do nothing;
  select * into v_row from public.user_daily_rewards where user_id = v_uid for update;

  if v_row.last_claim_date is not null and v_row.last_claim_date = v_today then
    raise exception 'already_claimed_today';
  end if;

  -- Determine the day to claim + streak.
  if v_row.last_claim_date = (v_today - 1) and v_row.current_day between 1 and 6 then
    v_claim_day  := v_row.current_day + 1;
    v_new_streak := coalesce(v_row.streak_count, 0) + 1;
  elsif v_row.last_claim_date = (v_today - 1) and v_row.current_day = 7 then
    v_claim_day  := 1;                 -- new cycle after completing day 7
    v_new_streak := 1;
    v_cycle_inc  := 1;
  else
    v_claim_day  := 1;                 -- first claim / missed a day -> reset
    v_new_streak := 1;
  end if;

  select * into v_rule from public.daily_reward_rules where day_number = v_claim_day;
  if v_rule.id is null or not v_rule.enabled then
    raise exception 'reward_day_disabled';
  end if;

  -- Apply reward (server-trusted amount from the rule; never the client).
  if v_rule.reward_type = 'coins' then
    if v_rule.amount > 0 then
      insert into public.wallets (user_id) values (v_uid) on conflict (user_id) do nothing;
      update public.wallets
      set coins_balance = coins_balance + v_rule.amount, updated_at = now()
      where user_id = v_uid;

      insert into public.wallet_transactions
        (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
      values
        (v_uid, 'daily_reward', 'credit', v_rule.amount, 0,
         'Daily reward - day ' || v_claim_day,
         jsonb_build_object('day', v_claim_day, 'rule_id', v_rule.id));
    end if;
  else
    raise exception 'unsupported_reward_type';
  end if;

  -- Record the claim (unique (user_id, claimed_date) blocks any double claim).
  insert into public.daily_reward_claims
    (user_id, claimed_day, reward_rule_id, reward_type, reward_key, amount, duration_days, claimed_date)
  values
    (v_uid, v_claim_day, v_rule.id, v_rule.reward_type, v_rule.reward_key,
     v_rule.amount, v_rule.duration_days, v_today);

  update public.user_daily_rewards
  set current_day           = v_claim_day,
      streak_count          = v_new_streak,
      last_claim_date       = v_today,
      cycle_completed_count = cycle_completed_count + v_cycle_inc,
      updated_at            = now()
  where user_id = v_uid;

  return jsonb_build_object(
    'success',       true,
    'claimed_day',   v_claim_day,
    'reward_type',   v_rule.reward_type,
    'title',         v_rule.title,
    'amount',        v_rule.amount,
    'duration_days', v_rule.duration_days,
    'streak_count',  v_new_streak
  );
exception
  when unique_violation then
    raise exception 'already_claimed_today';
end;
$$;
grant execute on function public.claim_daily_reward() to authenticated;

-- ── 6. Admin RPCs (super-admin tiers only) ───────────────────────────────────
create or replace function public.admin_set_daily_reward_config(
  p_enabled boolean,
  p_popup_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null
     or not (public.is_o_super_admin(auth.uid())
             or public.is_p_super_admin(auth.uid())
             or public.is_super_admin(auth.uid())) then
    raise exception 'not_authorized';
  end if;

  insert into public.daily_reward_config (id, enabled, popup_enabled, updated_at)
  values (1, p_enabled, p_popup_enabled, now())
  on conflict (id) do update
    set enabled = excluded.enabled,
        popup_enabled = excluded.popup_enabled,
        updated_at = now();
end;
$$;
grant execute on function public.admin_set_daily_reward_config(boolean, boolean) to authenticated;

create or replace function public.admin_upsert_daily_reward_rule(
  p_day_number    integer,
  p_enabled       boolean,
  p_reward_type   text,
  p_title         text,
  p_description   text,
  p_amount        bigint,
  p_duration_days integer,
  p_image_url     text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null
     or not (public.is_o_super_admin(auth.uid())
             or public.is_p_super_admin(auth.uid())
             or public.is_super_admin(auth.uid())) then
    raise exception 'not_authorized';
  end if;

  if p_day_number < 1 or p_day_number > 7 then raise exception 'invalid_day'; end if;
  -- Only coins are safely supported at the moment.
  if p_reward_type <> 'coins' then raise exception 'unsupported_reward_type'; end if;
  if coalesce(p_amount, 0) < 0 then raise exception 'invalid_amount'; end if;

  insert into public.daily_reward_rules
    (day_number, enabled, reward_type, title, description, amount, duration_days, image_url, sort_order, updated_at)
  values
    (p_day_number, p_enabled, p_reward_type, coalesce(p_title, 'Day ' || p_day_number),
     p_description, coalesce(p_amount, 0), p_duration_days, p_image_url, p_day_number, now())
  on conflict (day_number) do update
    set enabled       = excluded.enabled,
        reward_type   = excluded.reward_type,
        title         = excluded.title,
        description   = excluded.description,
        amount        = excluded.amount,
        duration_days = excluded.duration_days,
        image_url     = excluded.image_url,
        updated_at    = now();
end;
$$;
grant execute on function public.admin_upsert_daily_reward_rule(integer, boolean, text, text, text, bigint, integer, text) to authenticated;

-- =============================================================================
-- End of 20260912000000_daily_rewards.sql
-- =============================================================================
