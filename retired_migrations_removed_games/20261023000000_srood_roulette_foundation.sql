-- =============================================================================
-- Srood Roulette backend foundation.
--
-- Tables, RLS, wallet transaction types, and the read/bet RPCs only. Round
-- advance and settlement (the actual spin/payout) land in a follow-up
-- migration once this foundation is reviewed — this commit places bets and
-- debits coins, but nothing here resolves a round or pays out winnings.
-- =============================================================================

-- ── Tables ───────────────────────────────────────────────────────────────────

create table if not exists public.roulette_rounds (
  id                 uuid primary key default gen_random_uuid(),
  room_id            uuid null,
  status             text not null default 'betting_open',
  winning_number     int null,
  server_seed_hash   text null,
  started_at         timestamptz not null default now(),
  betting_closes_at  timestamptz not null,
  settled_at         timestamptz null,
  created_at         timestamptz not null default now(),
  constraint roulette_rounds_status_valid check (
    status in ('betting_open', 'locked', 'spinning', 'settled')
  ),
  constraint roulette_rounds_winning_number_valid check (
    winning_number is null or winning_number between 0 and 36
  )
);

create table if not exists public.roulette_bets (
  id                 uuid primary key default gen_random_uuid(),
  client_bet_id      text not null unique,
  round_id           uuid not null references public.roulette_rounds(id) on delete cascade,
  user_id            uuid not null references auth.users(id),
  bet_zone           text not null,
  bet_amount         bigint not null,
  payout_multiplier  numeric not null,
  status             text not null default 'active',
  payout_amount      bigint not null default 0,
  created_at         timestamptz not null default now(),
  constraint roulette_bets_zone_valid check (
    bet_zone in (
      'straight_zero', 'low', 'mid', 'high', 'red', 'black', 'even', 'odd'
    )
  ),
  constraint roulette_bets_amount_positive check (bet_amount > 0),
  constraint roulette_bets_multiplier_positive check (payout_multiplier > 0),
  constraint roulette_bets_status_valid check (
    status in ('active', 'won', 'lost', 'refunded')
  ),
  constraint roulette_bets_payout_non_negative check (payout_amount >= 0)
);

-- ── Indexes ──────────────────────────────────────────────────────────────────

create index if not exists roulette_rounds_room_status_idx
  on public.roulette_rounds (room_id, status);

create index if not exists roulette_rounds_created_at_idx
  on public.roulette_rounds (created_at desc);

create index if not exists roulette_bets_round_user_idx
  on public.roulette_bets (round_id, user_id);

create index if not exists roulette_bets_user_created_at_idx
  on public.roulette_bets (user_id, created_at desc);

create index if not exists roulette_bets_client_bet_id_idx
  on public.roulette_bets (client_bet_id);

create index if not exists roulette_bets_round_zone_idx
  on public.roulette_bets (round_id, bet_zone);

-- ── RLS ──────────────────────────────────────────────────────────────────────

alter table public.roulette_rounds enable row level security;
alter table public.roulette_bets enable row level security;

drop policy if exists roulette_rounds_select_authenticated on public.roulette_rounds;
create policy roulette_rounds_select_authenticated
  on public.roulette_rounds
  for select
  to authenticated
  using (true);

drop policy if exists roulette_bets_select_own on public.roulette_bets;
create policy roulette_bets_select_own
  on public.roulette_bets
  for select
  to authenticated
  using (user_id = auth.uid());

-- No anon access, no direct write grants — all writes go through the
-- SECURITY DEFINER RPCs below, which bypass RLS as the table owner.
revoke all on public.roulette_rounds from public, anon, authenticated;
revoke all on public.roulette_bets from public, anon, authenticated;
grant select on public.roulette_rounds to authenticated;
grant select on public.roulette_bets to authenticated;

-- ── Wallet transaction types (additive) ─────────────────────────────────────

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
      'fish_hunt_bet','fish_hunt_reward',
      'roulette_bet','roulette_win','roulette_refund'
    ])
  );

-- ── RPC: roulette_get_state ──────────────────────────────────────────────────

create or replace function public.roulette_get_state(p_room_id uuid default null)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round   public.roulette_rounds;
begin
  select *
  into v_round
  from public.roulette_rounds
  where status <> 'settled'
    and (p_room_id is null or room_id is null or room_id = p_room_id)
  order by created_at desc
  limit 1;

  return json_build_object(
    'server_now', now(),
    'round', case
      when v_round.id is null then null
      else json_build_object(
        'round_id', v_round.id,
        'room_id', v_round.room_id,
        'status', v_round.status,
        'winning_number', v_round.winning_number,
        'started_at', v_round.started_at,
        'betting_closes_at', v_round.betting_closes_at,
        'settled_at', v_round.settled_at
      )
    end,
    'recent_results', (
      select coalesce(json_agg(n order by created_at desc), '[]'::json)
      from (
        select winning_number as n, settled_at as created_at
        from public.roulette_rounds
        where status = 'settled'
          and winning_number is not null
          and (p_room_id is null or room_id is null or room_id = p_room_id)
        order by settled_at desc
        limit 10
      ) recent
    ),
    'balance', (
      select coins_balance
      from public.wallets
      where user_id = v_user_id
    ),
    'my_bets', case
      when v_user_id is null or v_round.id is null then '[]'::json
      else (
        select coalesce(json_agg(json_build_object(
          'bet_id', id,
          'bet_zone', bet_zone,
          'bet_amount', bet_amount,
          'payout_multiplier', payout_multiplier,
          'status', status,
          'payout_amount', payout_amount
        )), '[]'::json)
        from public.roulette_bets
        where round_id = v_round.id
          and user_id = v_user_id
      )
    end,
    'zone_totals', case
      when v_round.id is null then '[]'::json
      else (
        select coalesce(json_agg(json_build_object(
          'bet_zone', bet_zone,
          'total_amount', total_amount
        )), '[]'::json)
        from (
          select bet_zone, sum(bet_amount) as total_amount
          from public.roulette_bets
          where round_id = v_round.id
          group by bet_zone
        ) totals
      )
    end
  );
end;
$$;

-- ── RPC: roulette_place_bet ──────────────────────────────────────────────────

create or replace function public.roulette_place_bet(
  p_round_id uuid,
  p_bet_zone text,
  p_bet_amount bigint,
  p_client_bet_id text
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id     uuid := auth.uid();
  v_existing    public.roulette_bets;
  v_round       public.roulette_rounds;
  v_multiplier  numeric;
  v_new_balance bigint;
  v_bet_id      uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_client_bet_id is null or length(trim(p_client_bet_id)) = 0 then
    raise exception 'invalid_client_bet_id';
  end if;

  select *
  into v_existing
  from public.roulette_bets
  where client_bet_id = p_client_bet_id;

  if found then
    return json_build_object(
      'bet_id', v_existing.id,
      'new_balance', (
        select coins_balance from public.wallets where user_id = v_user_id
      ),
      'bet_zone', v_existing.bet_zone,
      'bet_amount', v_existing.bet_amount,
      'round_id', v_existing.round_id
    );
  end if;

  if p_bet_zone is null or p_bet_zone not in (
    'straight_zero', 'low', 'mid', 'high', 'red', 'black', 'even', 'odd'
  ) then
    raise exception 'invalid_bet_zone';
  end if;

  if p_bet_amount is null
     or p_bet_amount not in (100, 1000, 5000, 10000, 20000, 100000) then
    raise exception 'invalid_bet_amount';
  end if;

  v_multiplier := case p_bet_zone
    when 'straight_zero' then 36
    when 'low' then 3
    when 'mid' then 3
    when 'high' then 3
    when 'red' then 2
    when 'black' then 2
    when 'even' then 2
    when 'odd' then 2
  end;

  select *
  into v_round
  from public.roulette_rounds
  where id = p_round_id
  for update;

  if not found then
    raise exception 'round_not_found';
  end if;

  if v_round.status <> 'betting_open' then
    raise exception 'betting_closed';
  end if;

  if v_round.betting_closes_at <= now() then
    raise exception 'betting_closed';
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

  insert into public.roulette_bets (
    client_bet_id, round_id, user_id, bet_zone, bet_amount, payout_multiplier
  )
  values (
    p_client_bet_id, v_round.id, v_user_id, p_bet_zone, p_bet_amount, v_multiplier
  )
  returning id into v_bet_id;

  insert into public.wallet_transactions (
    user_id, type, direction, coins_delta, diamonds_delta,
    balance_coins_after, note, metadata
  )
  values (
    v_user_id, 'roulette_bet', 'debit', -p_bet_amount, 0,
    v_new_balance, 'Srood Roulette bet',
    jsonb_build_object('round_id', v_round.id, 'bet_zone', p_bet_zone, 'bet_id', v_bet_id)
  );

  return json_build_object(
    'bet_id', v_bet_id,
    'new_balance', v_new_balance,
    'bet_zone', p_bet_zone,
    'bet_amount', p_bet_amount,
    'round_id', v_round.id
  );
end;
$$;

-- ── Grants ───────────────────────────────────────────────────────────────────

revoke all on function public.roulette_get_state(uuid)
  from public, anon, authenticated;
revoke all on function public.roulette_place_bet(uuid, text, bigint, text)
  from public, anon, authenticated;

grant execute on function public.roulette_get_state(uuid) to authenticated;
grant execute on function public.roulette_place_bet(uuid, text, bigint, text) to authenticated;
