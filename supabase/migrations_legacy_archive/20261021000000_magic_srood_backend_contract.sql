-- =============================================================================
-- Magic Srood global betting backend
--
-- Server-authoritative shared rounds. Clients can read configuration/rounds
-- and call narrowly granted RPCs, but cannot mutate bets, rounds, or wallets.
-- =============================================================================

-- Preserve the existing wallet ledger types and add Magic Srood entries.
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
      'blocks_play','daily_reward',
      'magic_srood_bet','magic_srood_reward','magic_srood_refund'
    ])
  );

insert into public.game_settings (game_key, is_enabled)
values ('magic_srood', true)
on conflict (game_key) do nothing;

create table if not exists public.magic_srood_config (
  id         uuid primary key default gen_random_uuid(),
  food_id    text not null unique,
  name       text not null,
  icon       text not null,
  multiplier numeric(8,2) not null
               constraint magic_srood_config_multiplier_positive
               check (multiplier > 0),
  weight     numeric(14,4) not null
               constraint magic_srood_config_weight_positive
               check (weight > 0),
  rarity     text not null default 'common',
  sort_order integer not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists magic_srood_config_food_id_idx
  on public.magic_srood_config (food_id);

-- Mirror the currently deployed production configuration. The weights are
-- approximately inverse to the multipliers and preserve the established odds.
insert into public.magic_srood_config
  (food_id, name, icon, multiplier, weight, rarity, sort_order)
values
  ('spain',     'Spain',     '🇪🇸',   2, 42.0, 'common',    10),
  ('italy',     'Italy',     '🇮🇹',   3, 28.0, 'common',    20),
  ('portugal',  'Portugal',  '🇵🇹',  12,  7.0, 'uncommon',  30),
  ('argentina', 'Argentina', '🇦🇷', 200,  0.4, 'legendary', 40),
  ('germany',   'Germany',   '🇩🇪',  40,  2.2, 'rare',      50),
  ('england',   'England',   '🇬🇧',  40,  2.2, 'rare',      60),
  ('brazil',    'Brazil',    '🇧🇷', 160,  0.5, 'epic',      70),
  ('france',    'France',    '🇫🇷',  16,  5.5, 'uncommon',  80)
on conflict (food_id) do nothing;

create sequence if not exists public.magic_srood_round_seq start 1;

create table if not exists public.magic_srood_global_rounds (
  id                 uuid primary key default gen_random_uuid(),
  round_number       bigint not null unique,
  status             text not null default 'betting'
                       constraint magic_srood_round_status_valid
                       check (status in ('betting', 'settled')),
  betting_starts_at  timestamptz not null default now(),
  betting_ends_at    timestamptz not null,
  result_reveals_at  timestamptz,
  winning_food_id    text,
  winning_food_icon  text,
  winning_food_name  text,
  winning_multiplier numeric(8,2),
  winning_rarity     text,
  total_pool         bigint not null default 0
                       constraint magic_srood_total_pool_nonnegative
                       check (total_pool >= 0),
  total_payout       bigint not null default 0
                       constraint magic_srood_total_payout_nonnegative
                       check (total_payout >= 0),
  result_roll        numeric,
  result_total_weight numeric,
  result_config      jsonb,
  result_algorithm   text,
  settled_at         timestamptz,
  created_at         timestamptz not null default now(),
  constraint magic_srood_round_window_valid
    check (betting_ends_at > betting_starts_at)
);

alter table public.magic_srood_global_rounds
  add column if not exists winning_rarity text;
alter table public.magic_srood_global_rounds
  add column if not exists total_pool bigint not null default 0;
alter table public.magic_srood_global_rounds
  add column if not exists total_payout bigint not null default 0;
alter table public.magic_srood_global_rounds
  add column if not exists result_roll numeric;
alter table public.magic_srood_global_rounds
  add column if not exists result_total_weight numeric;
alter table public.magic_srood_global_rounds
  add column if not exists result_config jsonb;
alter table public.magic_srood_global_rounds
  add column if not exists result_algorithm text;
alter table public.magic_srood_global_rounds
  add column if not exists settled_at timestamptz;

create table if not exists public.magic_srood_global_bets (
  id                uuid primary key default gen_random_uuid(),
  round_id          uuid not null
                      references public.magic_srood_global_rounds(id)
                      on delete cascade,
  user_id           uuid not null
                      constraint magic_srood_bet_user_fkey
                      references auth.users(id) on delete cascade,
  food_id           text not null,
  food_name         text not null,
  food_icon         text not null,
  multiplier_at_bet numeric(8,2) not null
                      constraint magic_srood_bet_multiplier_positive
                      check (multiplier_at_bet > 0),
  bet_amount        integer not null
                      constraint magic_srood_bet_amount_valid
                      check (bet_amount between 100 and 100000),
  status            text not null default 'pending'
                      constraint magic_srood_bet_status_valid
                      check (status in ('pending', 'won', 'lost')),
  win_amount        integer not null default 0
                      constraint magic_srood_win_amount_nonnegative
                      check (win_amount >= 0),
  created_at        timestamptz not null default now()
);

-- Reconcile constraints for deployments where these tables were created
-- manually before this migration was added to source control.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_config'::regclass
      and conname = 'magic_srood_config_multiplier_positive'
  ) then
    alter table public.magic_srood_config
      add constraint magic_srood_config_multiplier_positive
      check (multiplier > 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_config'::regclass
      and conname = 'magic_srood_config_weight_positive'
  ) then
    alter table public.magic_srood_config
      add constraint magic_srood_config_weight_positive
      check (weight > 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_global_rounds'::regclass
      and conname = 'magic_srood_round_status_valid'
  ) then
    alter table public.magic_srood_global_rounds
      add constraint magic_srood_round_status_valid
      check (status in ('betting', 'settled'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_global_rounds'::regclass
      and conname = 'magic_srood_round_window_valid'
  ) then
    alter table public.magic_srood_global_rounds
      add constraint magic_srood_round_window_valid
      check (betting_ends_at > betting_starts_at);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_global_rounds'::regclass
      and conname = 'magic_srood_total_pool_nonnegative'
  ) then
    alter table public.magic_srood_global_rounds
      add constraint magic_srood_total_pool_nonnegative
      check (total_pool >= 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_global_rounds'::regclass
      and conname = 'magic_srood_total_payout_nonnegative'
  ) then
    alter table public.magic_srood_global_rounds
      add constraint magic_srood_total_payout_nonnegative
      check (total_payout >= 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_global_bets'::regclass
      and conname = 'magic_srood_bet_user_fkey'
  ) then
    alter table public.magic_srood_global_bets
      add constraint magic_srood_bet_user_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_global_bets'::regclass
      and conname = 'magic_srood_bet_amount_valid'
  ) then
    alter table public.magic_srood_global_bets
      add constraint magic_srood_bet_amount_valid
      check (bet_amount between 100 and 100000);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_global_bets'::regclass
      and conname = 'magic_srood_bet_status_valid'
  ) then
    alter table public.magic_srood_global_bets
      add constraint magic_srood_bet_status_valid
      check (status in ('pending', 'won', 'lost'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_global_bets'::regclass
      and conname = 'magic_srood_bet_multiplier_positive'
  ) then
    alter table public.magic_srood_global_bets
      add constraint magic_srood_bet_multiplier_positive
      check (multiplier_at_bet > 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.magic_srood_global_bets'::regclass
      and conname = 'magic_srood_win_amount_nonnegative'
  ) then
    alter table public.magic_srood_global_bets
      add constraint magic_srood_win_amount_nonnegative
      check (win_amount >= 0);
  end if;
end;
$$;

create unique index if not exists magic_srood_round_number_idx
  on public.magic_srood_global_rounds (round_number);
create index if not exists magic_srood_rounds_history_idx
  on public.magic_srood_global_rounds (created_at desc)
  where status = 'settled';
create index if not exists magic_srood_rounds_status_end_idx
  on public.magic_srood_global_rounds (status, betting_ends_at);
create index if not exists magic_srood_active_round_end_idx
  on public.magic_srood_global_rounds (betting_ends_at)
  where status = 'betting';
create index if not exists magic_srood_bets_round_status_idx
  on public.magic_srood_global_bets (round_id, status);
create index if not exists magic_srood_bets_round_food_idx
  on public.magic_srood_global_bets (round_id, food_id);
create index if not exists magic_srood_bets_user_created_idx
  on public.magic_srood_global_bets (user_id, created_at desc);

alter table public.magic_srood_config enable row level security;
alter table public.magic_srood_global_rounds enable row level security;
alter table public.magic_srood_global_bets enable row level security;

drop policy if exists "magic_srood_config_select" on public.magic_srood_config;
create policy "magic_srood_config_select"
  on public.magic_srood_config for select to authenticated
  using (true);

drop policy if exists "magic_srood_rounds_select" on public.magic_srood_global_rounds;
create policy "magic_srood_rounds_select"
  on public.magic_srood_global_rounds for select to authenticated
  using (true);

drop policy if exists "magic_srood_bets_select_own" on public.magic_srood_global_bets;
create policy "magic_srood_bets_select_own"
  on public.magic_srood_global_bets for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.magic_srood_config from public, anon, authenticated;
revoke all on public.magic_srood_global_rounds from public, anon, authenticated;
revoke all on public.magic_srood_global_bets from public, anon, authenticated;
grant select on public.magic_srood_config to authenticated;
grant select on public.magic_srood_global_rounds to authenticated;
grant select on public.magic_srood_global_bets to authenticated;

-- Settle one round. The row lock makes concurrent calls wait and then take the
-- idempotent return path. Round and wallet locks are always acquired in that
-- order, matching bet placement and preventing lock-order inversions.
create or replace function public.settle_magic_srood_global_round(
  p_round_id uuid
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id      uuid := auth.uid();
  v_round        public.magic_srood_global_rounds;
  v_food         public.magic_srood_config;
  v_total_weight numeric;
  v_roll         numeric;
  v_food_id      uuid;
  v_result_config jsonb;
  v_total_pool   bigint;
  v_total_payout bigint;
  v_payout       record;
  v_new_balance  integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into v_round
  from public.magic_srood_global_rounds
  where id = p_round_id
  for update;

  if not found then
    raise exception 'round_not_found';
  end if;

  if v_round.status = 'settled' then
    return json_build_object(
      'round_id', v_round.id,
      'status', v_round.status,
      'winning_food_id', v_round.winning_food_id,
      'winning_food_icon', v_round.winning_food_icon,
      'winning_food_name', v_round.winning_food_name,
      'winning_multiplier', v_round.winning_multiplier,
      'total_pool', v_round.total_pool,
      'total_payout', v_round.total_payout,
      'settled_at', v_round.settled_at,
      'server_now', now()
    );
  end if;

  if v_round.betting_ends_at > now() then
    raise exception 'betting_still_open';
  end if;

  select coalesce(sum(weight), 0),
         jsonb_agg(
           jsonb_build_object(
             'food_id', food_id,
             'name', name,
             'icon', icon,
             'multiplier', multiplier,
             'weight', weight,
             'rarity', rarity,
             'sort_order', sort_order
           )
           order by sort_order, food_id
         )
  into v_total_weight, v_result_config
  from public.magic_srood_config
  where is_active and weight > 0;

  if v_total_weight <= 0 then
    raise exception 'invalid_game_config';
  end if;

  v_roll := random() * v_total_weight;

  select ranked.id
  into v_food_id
  from (
    select c.*,
           sum(c.weight) over (order by c.sort_order, c.food_id) as cumulative_weight
    from public.magic_srood_config c
    where c.is_active and c.weight > 0
  ) ranked
  where ranked.cumulative_weight >= v_roll
  order by ranked.cumulative_weight
  limit 1;

  if v_food_id is null then
    select id
    into v_food_id
    from public.magic_srood_config
    where is_active and weight > 0
    order by sort_order desc, food_id desc
    limit 1;
  end if;

  select *
  into v_food
  from public.magic_srood_config
  where id = v_food_id;

  if not found then
    raise exception 'invalid_game_config';
  end if;

  select coalesce(sum(bet_amount), 0)
  into v_total_pool
  from public.magic_srood_global_bets
  where round_id = p_round_id;

  select coalesce(
    sum(floor(bet_amount * multiplier_at_bet)),
    0
  )
  into v_total_payout
  from public.magic_srood_global_bets
  where round_id = p_round_id
    and status = 'pending'
    and food_id = v_food.food_id;

  -- Aggregate by user so each wallet is locked and updated once, in stable
  -- UUID order. Individual bets are still retained for audit/history.
  for v_payout in
    select b.user_id,
           sum(floor(b.bet_amount * b.multiplier_at_bet))::integer as amount
    from public.magic_srood_global_bets b
    where b.round_id = p_round_id
      and b.status = 'pending'
      and b.food_id = v_food.food_id
    group by b.user_id
    order by b.user_id
  loop
    update public.wallets
    set coins_balance = coins_balance + v_payout.amount,
        updated_at = now()
    where user_id = v_payout.user_id
    returning coins_balance into v_new_balance;

    if not found then
      raise exception 'wallet_not_found';
    end if;

    insert into public.wallet_transactions (
      user_id, type, direction, coins_delta, diamonds_delta,
      balance_coins_after, note, metadata
    )
    values (
      v_payout.user_id, 'magic_srood_reward', 'credit', v_payout.amount, 0,
      v_new_balance, 'Magic Srood round reward',
      jsonb_build_object(
        'round_id', p_round_id,
        'food_id', v_food.food_id,
        'multiplier', v_food.multiplier
      )
    );
  end loop;

  update public.magic_srood_global_bets
  set status = case when food_id = v_food.food_id then 'won' else 'lost' end,
      win_amount = case
        when food_id = v_food.food_id
          then floor(bet_amount * multiplier_at_bet)::integer
        else 0
      end
  where round_id = p_round_id
    and status = 'pending';

  update public.magic_srood_global_rounds
  set status = 'settled',
      result_reveals_at = now(),
      winning_food_id = v_food.food_id,
      winning_food_icon = v_food.icon,
      winning_food_name = v_food.name,
      winning_multiplier = v_food.multiplier,
      winning_rarity = v_food.rarity,
      total_pool = v_total_pool,
      total_payout = v_total_payout,
      result_roll = v_roll,
      result_total_weight = v_total_weight,
      result_config = v_result_config,
      result_algorithm = 'weighted_v1',
      settled_at = now()
  where id = p_round_id;

  return json_build_object(
    'round_id', p_round_id,
    'status', 'settled',
    'winning_food_id', v_food.food_id,
    'winning_food_icon', v_food.icon,
    'winning_food_name', v_food.name,
    'winning_multiplier', v_food.multiplier,
    'total_pool', v_total_pool,
    'total_payout', v_total_payout,
    'settled_at', now(),
    'server_now', now()
  );
end;
$$;

create or replace function public.get_or_create_magic_srood_round()
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round   public.magic_srood_global_rounds;
  v_expired public.magic_srood_global_rounds;
  v_now     timestamptz := now();
  v_number  bigint;
  c_duration constant interval := interval '30 seconds';
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  perform pg_advisory_xact_lock(hashtext('magic_srood_global_round'));

  -- Adopt and settle any expired rounds that may have been created by the
  -- pre-migration production functions. This preserves all pending wagers.
  for v_expired in
    select *
    from public.magic_srood_global_rounds
    where status = 'betting'
      and betting_ends_at <= v_now
    order by betting_ends_at, id
  loop
    perform public.settle_magic_srood_global_round(v_expired.id);
  end loop;

  select *
  into v_round
  from public.magic_srood_global_rounds
  where status = 'betting'
    and betting_ends_at > v_now
  order by created_at desc
  limit 1;

  if v_round.id is null then
    v_number := nextval('public.magic_srood_round_seq');
    insert into public.magic_srood_global_rounds (
      round_number, status, betting_starts_at, betting_ends_at
    )
    values (v_number, 'betting', v_now, v_now + c_duration)
    returning * into v_round;
  end if;

  return json_build_object(
    'round_id', v_round.id,
    'round_number', v_round.round_number,
    'status', v_round.status,
    'betting_starts_at', v_round.betting_starts_at,
    'betting_ends_at', v_round.betting_ends_at,
    'winning_food_id', v_round.winning_food_id,
    'winning_food_icon', v_round.winning_food_icon,
    'winning_food_name', v_round.winning_food_name,
    'winning_multiplier', v_round.winning_multiplier,
    'server_now', now()
  );
end;
$$;

create or replace function public.place_magic_srood_global_bet(
  p_round_id uuid,
  p_food_id text,
  p_amount integer
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id     uuid := auth.uid();
  v_round       public.magic_srood_global_rounds;
  v_food        public.magic_srood_config;
  v_bet_id      uuid;
  v_new_balance integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if not exists (
    select 1
    from public.game_settings
    where game_key = 'magic_srood' and is_enabled
  ) then
    raise exception 'game_disabled';
  end if;

  if p_amount is null or p_amount not in (100, 1000, 10000, 100000) then
    raise exception 'invalid_bet_amount';
  end if;

  -- Lock the round first so settlement cannot pass the deadline while this
  -- transaction is debiting the wallet and inserting the bet.
  select *
  into v_round
  from public.magic_srood_global_rounds
  where id = p_round_id
  for update;

  if not found then
    raise exception 'round_not_found';
  end if;

  if v_round.status <> 'betting' or v_round.betting_ends_at <= now() then
    raise exception 'betting_closed';
  end if;

  select *
  into v_food
  from public.magic_srood_config
  where food_id = p_food_id and is_active;

  if not found then
    raise exception 'invalid_food';
  end if;

  update public.wallets
  set coins_balance = coins_balance - p_amount,
      lifetime_coins_spent = lifetime_coins_spent + p_amount,
      updated_at = now()
  where user_id = v_user_id
    and coins_balance >= p_amount
  returning coins_balance into v_new_balance;

  if not found then
    raise exception 'insufficient_coins';
  end if;

  insert into public.magic_srood_global_bets (
    round_id, user_id, food_id, food_name, food_icon,
    multiplier_at_bet, bet_amount, status
  )
  values (
    p_round_id, v_user_id, v_food.food_id, v_food.name, v_food.icon,
    v_food.multiplier, p_amount, 'pending'
  )
  returning id into v_bet_id;

  update public.magic_srood_global_rounds
  set total_pool = total_pool + p_amount
  where id = p_round_id;

  insert into public.wallet_transactions (
    user_id, type, direction, coins_delta, diamonds_delta,
    balance_coins_after, note, metadata
  )
  values (
    v_user_id, 'magic_srood_bet', 'debit', -p_amount, 0,
    v_new_balance, 'Magic Srood bet',
    jsonb_build_object(
      'bet_id', v_bet_id,
      'round_id', p_round_id,
      'food_id', v_food.food_id,
      'multiplier', v_food.multiplier
    )
  );

  return json_build_object('bet_id', v_bet_id, 'new_balance', v_new_balance);
end;
$$;

create or replace function public.get_magic_srood_team_totals(
  p_round_id uuid
)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result json;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if not exists (
    select 1 from public.magic_srood_global_rounds where id = p_round_id
  ) then
    raise exception 'round_not_found';
  end if;

  select coalesce(json_object_agg(t.food_id, t.total), '{}'::json)
  into v_result
  from (
    select food_id, sum(bet_amount)::bigint as total
    from public.magic_srood_global_bets
    where round_id = p_round_id
    group by food_id
  ) t;

  return v_result;
end;
$$;

create or replace function public.get_magic_srood_global_history(
  p_limit integer default 20
)
returns table (
  food_icon text,
  food_name text,
  multiplier numeric,
  rarity text,
  reward_amount integer,
  bet_amount integer,
  created_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  return query
  select r.winning_food_icon,
         r.winning_food_name,
         r.winning_multiplier,
         coalesce(r.winning_rarity, 'common'),
         0,
         0,
         r.created_at
  from public.magic_srood_global_rounds r
  where r.status = 'settled'
    and r.winning_food_id is not null
  order by r.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
end;
$$;

revoke all on function public.get_or_create_magic_srood_round()
  from public, anon, authenticated;
revoke all on function public.place_magic_srood_global_bet(uuid, text, integer)
  from public, anon, authenticated;
revoke all on function public.settle_magic_srood_global_round(uuid)
  from public, anon, authenticated;
revoke all on function public.get_magic_srood_team_totals(uuid)
  from public, anon, authenticated;
revoke all on function public.get_magic_srood_global_history(integer)
  from public, anon, authenticated;

grant execute on function public.get_or_create_magic_srood_round()
  to authenticated;
grant execute on function public.place_magic_srood_global_bet(uuid, text, integer)
  to authenticated;
grant execute on function public.settle_magic_srood_global_round(uuid)
  to authenticated;
grant execute on function public.get_magic_srood_team_totals(uuid)
  to authenticated;
grant execute on function public.get_magic_srood_global_history(integer)
  to authenticated;

-- Add the rounds table to Realtime once. Realtime clients still need the
-- authenticated SELECT grant and RLS policy above to receive row changes.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'magic_srood_global_rounds'
  ) then
    alter publication supabase_realtime
      add table public.magic_srood_global_rounds;
  end if;
end;
$$;
