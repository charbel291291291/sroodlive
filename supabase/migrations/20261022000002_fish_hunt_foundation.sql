-- =============================================================================
-- Srood Fish Hunt backend foundation (MVP)
--
-- Server-authoritative rounds/fish/shots. Wallet debit, hit/miss decision and
-- payout credit all happen inside fish_hunt_place_shot. Clients can only read
-- public game state and their own shots; all writes are RPC-only.
-- =============================================================================

-- Reuse the existing wallet ledger and add Fish Hunt entries.
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
      'magic_srood_bet','magic_srood_reward','magic_srood_refund',
      'fish_hunt_bet','fish_hunt_reward'
    ])
  );

create table if not exists public.fish_hunt_rounds (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid,
  status      text not null default 'active'
                constraint fish_hunt_rounds_status_valid
                check (status in ('active', 'closed')),
  started_at  timestamptz not null default now(),
  server_seed text not null default encode(gen_random_bytes(32), 'hex'),
  created_at  timestamptz not null default now()
);

create table if not exists public.fish_hunt_fish (
  id                uuid primary key default gen_random_uuid(),
  round_id          uuid not null
                      references public.fish_hunt_rounds(id) on delete cascade,
  fish_type         text not null,
  reward_multiplier numeric not null
                      constraint fish_hunt_fish_multiplier_positive
                      check (reward_multiplier > 0),
  hit_probability   numeric not null
                      constraint fish_hunt_fish_probability_valid
                      check (hit_probability between 0 and 1),
  spawned_at        timestamptz not null default now(),
  expires_at        timestamptz not null,
  status            text not null default 'alive'
                      constraint fish_hunt_fish_status_valid
                      check (status in ('alive', 'killed', 'expired')),
  killed_by         uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  constraint fish_hunt_fish_expiry_valid check (expires_at > spawned_at)
);

create table if not exists public.fish_hunt_shots (
  id              uuid primary key default gen_random_uuid(),
  client_shot_id  text not null unique,
  user_id         uuid not null references auth.users(id),
  round_id        uuid not null references public.fish_hunt_rounds(id),
  fish_id         uuid not null references public.fish_hunt_fish(id),
  bet_amount      bigint not null
                    constraint fish_hunt_shots_bet_amount_positive
                    check (bet_amount > 0),
  result          text not null
                    constraint fish_hunt_shots_result_valid
                    check (result in ('hit', 'miss')),
  payout_amount   bigint not null default 0
                    constraint fish_hunt_shots_payout_nonnegative
                    check (payout_amount >= 0),
  created_at      timestamptz not null default now()
);

create index if not exists fish_hunt_rounds_room_status_idx
  on public.fish_hunt_rounds (room_id, status);
create index if not exists fish_hunt_fish_round_status_expires_idx
  on public.fish_hunt_fish (round_id, status, expires_at);
create index if not exists fish_hunt_shots_user_created_idx
  on public.fish_hunt_shots (user_id, created_at desc);
create index if not exists fish_hunt_shots_round_created_idx
  on public.fish_hunt_shots (round_id, created_at desc);
create index if not exists fish_hunt_shots_fish_idx
  on public.fish_hunt_shots (fish_id);

alter table public.fish_hunt_rounds enable row level security;
alter table public.fish_hunt_fish enable row level security;
alter table public.fish_hunt_shots enable row level security;

drop policy if exists "fish_hunt_rounds_select" on public.fish_hunt_rounds;
create policy "fish_hunt_rounds_select"
  on public.fish_hunt_rounds for select to authenticated
  using (status = 'active');

drop policy if exists "fish_hunt_fish_select" on public.fish_hunt_fish;
create policy "fish_hunt_fish_select"
  on public.fish_hunt_fish for select to authenticated
  using (status = 'alive');

drop policy if exists "fish_hunt_shots_select_own" on public.fish_hunt_shots;
create policy "fish_hunt_shots_select_own"
  on public.fish_hunt_shots for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.fish_hunt_rounds from public, anon, authenticated;
revoke all on public.fish_hunt_fish from public, anon, authenticated;
revoke all on public.fish_hunt_shots from public, anon, authenticated;
grant select on public.fish_hunt_rounds to authenticated;
grant select on public.fish_hunt_fish to authenticated;
grant select on public.fish_hunt_shots to authenticated;

-- ---------------------------------------------------------------------------
-- fish_hunt_get_state: read-only snapshot of active round, live fish, the
-- caller's wallet balance and their recent shots.
-- ---------------------------------------------------------------------------
create or replace function public.fish_hunt_get_state(
  p_room_id uuid default null
)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id  uuid := auth.uid();
  v_round    public.fish_hunt_rounds;
  v_balance  integer;
  v_fish     json;
  v_shots    json;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into v_round
  from public.fish_hunt_rounds
  where status = 'active'
    and (p_room_id is null or room_id = p_room_id)
  order by started_at desc
  limit 1;

  select coalesce(json_agg(
           json_build_object(
             'fish_id', f.id,
             'fish_type', f.fish_type,
             'reward_multiplier', f.reward_multiplier,
             'hit_probability', f.hit_probability,
             'spawned_at', f.spawned_at,
             'expires_at', f.expires_at
           )
           order by f.spawned_at
         ), '[]'::json)
  into v_fish
  from public.fish_hunt_fish f
  where v_round.id is not null
    and f.round_id = v_round.id
    and f.status = 'alive'
    and f.expires_at > now();

  select coins_balance
  into v_balance
  from public.wallets
  where user_id = v_user_id;

  select coalesce(json_agg(
           json_build_object(
             'shot_id', s.id,
             'fish_id', s.fish_id,
             'bet_amount', s.bet_amount,
             'result', s.result,
             'payout_amount', s.payout_amount,
             'created_at', s.created_at
           )
           order by s.created_at desc
         ), '[]'::json)
  into v_shots
  from (
    select *
    from public.fish_hunt_shots
    where user_id = v_user_id
    order by created_at desc
    limit 20
  ) s;

  return json_build_object(
    'round_id', v_round.id,
    'room_id', v_round.room_id,
    'round_status', v_round.status,
    'fish', v_fish,
    'balance', coalesce(v_balance, 0),
    'recent_shots', v_shots,
    'server_now', now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- fish_hunt_place_shot: server-authoritative bet debit, hit/miss decision
-- and payout credit. Idempotent on client_shot_id.
-- ---------------------------------------------------------------------------
create or replace function public.fish_hunt_place_shot(
  p_room_id uuid,
  p_fish_id uuid,
  p_bet_amount bigint,
  p_client_shot_id text
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id     uuid := auth.uid();
  v_existing    public.fish_hunt_shots;
  v_round       public.fish_hunt_rounds;
  v_fish        public.fish_hunt_fish;
  v_new_balance integer;
  v_result      text;
  v_payout      bigint := 0;
  v_shot_id     uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_client_shot_id is null or length(trim(p_client_shot_id)) = 0 then
    raise exception 'invalid_client_shot_id';
  end if;

  select *
  into v_existing
  from public.fish_hunt_shots
  where client_shot_id = p_client_shot_id;

  if found then
    return json_build_object(
      'result', v_existing.result,
      'payout_amount', v_existing.payout_amount,
      'fish_id', v_existing.fish_id,
      'new_balance', (
        select coins_balance from public.wallets where user_id = v_user_id
      )
    );
  end if;

  if p_bet_amount is null
     or p_bet_amount not in (100, 500, 1000, 5000, 10000, 20000, 100000) then
    raise exception 'invalid_bet_amount';
  end if;

  -- Lock the round first to keep round/fish/wallet lock order consistent
  -- with every other money-moving RPC in this codebase.
  select *
  into v_round
  from public.fish_hunt_rounds
  where id = (
    select round_id from public.fish_hunt_fish where id = p_fish_id
  )
  for update;

  if not found or v_round.status <> 'active' then
    raise exception 'round_not_found';
  end if;

  if p_room_id is not null and v_round.room_id is not null
     and v_round.room_id <> p_room_id then
    raise exception 'room_mismatch';
  end if;

  select *
  into v_fish
  from public.fish_hunt_fish
  where id = p_fish_id
  for update;

  if not found then
    raise exception 'fish_not_found';
  end if;

  if v_fish.status <> 'alive' or v_fish.expires_at <= now() then
    raise exception 'fish_unavailable';
  end if;

  update public.wallets
  set coins_balance = coins_balance - p_bet_amount,
      lifetime_coins_spent = lifetime_coins_spent + p_bet_amount,
      updated_at = now()
  where user_id = v_user_id
    and coins_balance >= p_bet_amount
  returning coins_balance into v_new_balance;

  if not found then
    raise exception 'insufficient_coins';
  end if;

  insert into public.wallet_transactions (
    user_id, type, direction, coins_delta, diamonds_delta,
    balance_coins_after, note, metadata
  )
  values (
    v_user_id, 'fish_hunt_bet', 'debit', -p_bet_amount, 0,
    v_new_balance, 'Fish Hunt shot',
    jsonb_build_object('fish_id', v_fish.id, 'round_id', v_round.id)
  );

  if random() < v_fish.hit_probability then
    v_result := 'hit';
    v_payout := floor(p_bet_amount * v_fish.reward_multiplier)::bigint;

    update public.fish_hunt_fish
    set status = 'killed',
        killed_by = v_user_id
    where id = v_fish.id;

    if v_payout > 0 then
      update public.wallets
      set coins_balance = coins_balance + v_payout,
          updated_at = now()
      where user_id = v_user_id
      returning coins_balance into v_new_balance;

      insert into public.wallet_transactions (
        user_id, type, direction, coins_delta, diamonds_delta,
        balance_coins_after, note, metadata
      )
      values (
        v_user_id, 'fish_hunt_reward', 'credit', v_payout, 0,
        v_new_balance, 'Fish Hunt reward',
        jsonb_build_object('fish_id', v_fish.id, 'round_id', v_round.id)
      );
    end if;
  else
    v_result := 'miss';
  end if;

  insert into public.fish_hunt_shots (
    client_shot_id, user_id, round_id, fish_id, bet_amount, result,
    payout_amount
  )
  values (
    p_client_shot_id, v_user_id, v_round.id, v_fish.id, p_bet_amount,
    v_result, v_payout
  )
  returning id into v_shot_id;

  return json_build_object(
    'result', v_result,
    'payout_amount', v_payout,
    'new_balance', v_new_balance,
    'fish_id', v_fish.id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- fish_hunt_get_leaderboard: top users by net winnings over a recent window.
-- ---------------------------------------------------------------------------
create or replace function public.fish_hunt_get_leaderboard(
  p_room_id uuid default null
)
returns table (
  user_id uuid,
  total_payout bigint,
  total_bet bigint,
  net_winnings bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  return query
  select s.user_id,
         sum(s.payout_amount)::bigint as total_payout,
         sum(s.bet_amount)::bigint as total_bet,
         (sum(s.payout_amount) - sum(s.bet_amount))::bigint as net_winnings
  from public.fish_hunt_shots s
  join public.fish_hunt_rounds r on r.id = s.round_id
  where s.created_at > now() - interval '24 hours'
    and (p_room_id is null or r.room_id = p_room_id)
  group by s.user_id
  order by net_winnings desc
  limit 50;
end;
$$;

revoke all on function public.fish_hunt_get_state(uuid)
  from public, anon, authenticated;
revoke all on function public.fish_hunt_place_shot(uuid, uuid, bigint, text)
  from public, anon, authenticated;
revoke all on function public.fish_hunt_get_leaderboard(uuid)
  from public, anon, authenticated;

grant execute on function public.fish_hunt_get_state(uuid) to authenticated;
grant execute on function public.fish_hunt_place_shot(uuid, uuid, bigint, text)
  to authenticated;
grant execute on function public.fish_hunt_get_leaderboard(uuid)
  to authenticated;

-- Add round/fish tables to Realtime, matching the existing publication
-- convention used by Magic Srood.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fish_hunt_rounds'
  ) then
    alter publication supabase_realtime add table public.fish_hunt_rounds;
  end if;
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fish_hunt_fish'
  ) then
    alter publication supabase_realtime add table public.fish_hunt_fish;
  end if;
end;
$$;
