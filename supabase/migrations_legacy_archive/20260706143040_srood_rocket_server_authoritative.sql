-- Srood Rocket: server-authoritative shared crash game.
-- This is intentionally separate from the historical crash_rounds and
-- rocket_crash_global_* implementations.

create extension if not exists pgcrypto with schema extensions;

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
      'crash_rocket_bet','crash_rocket_win','crash_rocket_cashout',
      'crash_rocket_refund','room_game_bet','room_game_win','room_game_refund',
      'srood_loto_ticket','srood_treasure_entry','srood_treasure_win',
      'blocks_play','daily_reward',
      'magic_srood_bet','magic_srood_reward','magic_srood_refund',
      'fish_hunt_bet','fish_hunt_reward',
      'roulette_bet','roulette_win','roulette_refund'
    ])
  );

create sequence if not exists public.crash_rocket_round_number_seq;

create table if not exists public.crash_rocket_rounds (
  id uuid primary key default gen_random_uuid(),
  room_id uuid null references public.rooms(id) on delete cascade,
  status text not null default 'betting_open'
    check (status in ('waiting','betting_open','flying','crashed','settled')),
  round_number bigint not null default nextval('public.crash_rocket_round_number_seq'),
  starts_at timestamptz not null default now(),
  betting_closes_at timestamptz not null,
  fly_started_at timestamptz null,
  crashed_at timestamptz null,
  crash_multiplier numeric(12,2) null,
  crash_seed_hash text not null,
  crash_seed_reveal text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (betting_closes_at > starts_at),
  check (crash_multiplier is null or crash_multiplier >= 1.00)
);

-- Never grant this table to API roles or add it to realtime.
create table if not exists public.crash_rocket_round_secrets (
  round_id uuid primary key references public.crash_rocket_rounds(id)
    on delete cascade,
  crash_seed_secret text not null,
  target_multiplier numeric(12,2) not null check (target_multiplier >= 1.00),
  target_crashed_at timestamptz null,
  created_at timestamptz not null default now()
);

create table if not exists public.crash_rocket_bets (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.crash_rocket_rounds(id)
    on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  bet_slot integer not null check (bet_slot in (1, 2)),
  amount integer not null check (amount between 100 and 1000000),
  auto_cashout_multiplier numeric(12,2) null
    check (auto_cashout_multiplier is null
      or auto_cashout_multiplier between 1.01 and 1000.00),
  status text not null default 'placed'
    check (status in ('placed','cashed_out','lost','refunded')),
  cashout_multiplier numeric(12,2) null,
  payout_amount integer null check (payout_amount is null or payout_amount >= 0),
  client_bet_id text not null,
  client_cashout_id text null,
  created_at timestamptz not null default now(),
  cashed_out_at timestamptz null,
  unique (user_id, round_id, bet_slot),
  unique (user_id, client_bet_id),
  unique (user_id, client_cashout_id)
);

create table if not exists public.crash_rocket_round_events (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.crash_rocket_rounds(id)
    on delete cascade,
  event_type text not null check (event_type in (
    'round_opened','flight_started','round_crashed','round_settled',
    'bet_placed','bet_cashed_out','bet_lost','bet_refunded'
  )),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create unique index if not exists crash_rocket_one_global_active_idx
  on public.crash_rocket_rounds ((room_id is null))
  where room_id is null and status in ('waiting','betting_open','flying','crashed');
create unique index if not exists crash_rocket_one_room_active_idx
  on public.crash_rocket_rounds (room_id)
  where room_id is not null and status in ('waiting','betting_open','flying','crashed');
create index if not exists crash_rocket_round_history_idx
  on public.crash_rocket_rounds (room_id, round_number desc);
create index if not exists crash_rocket_round_status_idx
  on public.crash_rocket_rounds (status, betting_closes_at);
create index if not exists crash_rocket_bets_round_created_idx
  on public.crash_rocket_bets (round_id, created_at desc);
create index if not exists crash_rocket_bets_user_round_idx
  on public.crash_rocket_bets (user_id, round_id);
create index if not exists crash_rocket_bets_auto_idx
  on public.crash_rocket_bets (round_id, auto_cashout_multiplier)
  where status = 'placed' and auto_cashout_multiplier is not null;
create index if not exists crash_rocket_events_round_idx
  on public.crash_rocket_round_events (round_id, created_at desc);

alter table public.crash_rocket_rounds enable row level security;
alter table public.crash_rocket_round_secrets enable row level security;
alter table public.crash_rocket_bets enable row level security;
alter table public.crash_rocket_round_events enable row level security;

drop policy if exists crash_rocket_rounds_read on public.crash_rocket_rounds;
create policy crash_rocket_rounds_read on public.crash_rocket_rounds
  for select to authenticated using (
    room_id is null or exists (
      select 1 from public.room_members rm
      where rm.room_id = crash_rocket_rounds.room_id
        and rm.user_id = (select auth.uid())
        and rm.left_at is null
    )
  );
drop policy if exists crash_rocket_bets_read_own on public.crash_rocket_bets;
create policy crash_rocket_bets_read_own on public.crash_rocket_bets
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists crash_rocket_events_read on public.crash_rocket_round_events;
create policy crash_rocket_events_read on public.crash_rocket_round_events
  for select to authenticated using (
    exists (
      select 1 from public.crash_rocket_rounds r
      where r.id = crash_rocket_round_events.round_id
        and (
          r.room_id is null or exists (
            select 1 from public.room_members rm
            where rm.room_id = r.room_id
              and rm.user_id = (select auth.uid())
              and rm.left_at is null
          )
        )
    )
  );

revoke all on public.crash_rocket_rounds from public, anon, authenticated;
revoke all on public.crash_rocket_round_secrets from public, anon, authenticated;
revoke all on public.crash_rocket_bets from public, anon, authenticated;
revoke all on public.crash_rocket_round_events from public, anon, authenticated;
grant select on public.crash_rocket_rounds to authenticated;
grant select on public.crash_rocket_bets to authenticated;
grant select on public.crash_rocket_round_events to authenticated;

-- Display curve only. Authoritative cashout uses the same formula server-side.
-- multiplier(t) = exp(0.09 * seconds_since_launch), capped at the committed
-- target. The 9% rate gives readable early growth without client authority.
create or replace function public._crash_rocket_multiplier_at(
  p_fly_started_at timestamptz,
  p_at timestamptz
)
returns numeric
language sql immutable
set search_path = ''
as $$
  select greatest(
    1.00,
    floor(exp(0.09 * greatest(0, extract(epoch from p_at - p_fly_started_at))) * 100) / 100
  )::numeric(12,2);
$$;

revoke all on function public._crash_rocket_multiplier_at(timestamptz,timestamptz)
  from public, anon, authenticated;

create or replace function public._crash_rocket_assert_room_access(p_room_id uuid)
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then raise exception 'not_authenticated'; end if;
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
revoke all on function public._crash_rocket_assert_room_access(uuid)
  from public, anon, authenticated;

-- SHA-256 provably-fair target:
-- u is a deterministic 52-bit uniform value derived from the secret.
-- target = floor(0.97 / (1-u) * 100) / 100, minimum 1.00x, capped 1000x.
-- The 0.97 factor is a 3% mathematical house edge. The hash is committed
-- before betting and the seed is revealed only after the crash.
create or replace function public._create_crash_rocket_round(p_room_id uuid)
returns public.crash_rocket_rounds
language plpgsql security definer
set search_path = ''
as $$
declare
  v_round public.crash_rocket_rounds;
  v_seed text := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash text := encode(extensions.digest(v_seed, 'sha256'), 'hex');
  v_roll bigint;
  v_u numeric;
  v_target numeric;
begin
  v_roll := ('x' || substr(v_hash, 1, 13))::bit(52)::bigint;
  v_u := v_roll::numeric / 4503599627370496::numeric;
  v_target := least(1000.00, greatest(1.00,
    floor((0.97 / greatest(0.000001, 1 - v_u)) * 100) / 100));

  insert into public.crash_rocket_rounds (
    room_id, status, starts_at, betting_closes_at, crash_seed_hash
  ) values (
    p_room_id, 'betting_open', now(), now() + interval '8 seconds', v_hash
  ) returning * into v_round;

  insert into public.crash_rocket_round_secrets (
    round_id, crash_seed_secret, target_multiplier
  ) values (v_round.id, v_seed, v_target);
  insert into public.crash_rocket_round_events(round_id,event_type,payload)
  values (v_round.id,'round_opened',jsonb_build_object(
    'round_number',v_round.round_number,'betting_closes_at',v_round.betting_closes_at
  ));
  return v_round;
end;
$$;
revoke all on function public._create_crash_rocket_round(uuid)
  from public, anon, authenticated;

create or replace function public.advance_crash_rocket_round(p_room_id uuid default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_round public.crash_rocket_rounds;
  v_secret public.crash_rocket_round_secrets;
  v_now timestamptz := clock_timestamp();
  v_current numeric;
  v_bet public.crash_rocket_bets;
  v_payout integer;
  v_balance integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(
    'srood_rocket:' || coalesce(p_room_id::text, 'global'), 0
  ));

  select * into v_round from public.crash_rocket_rounds
  where room_id is not distinct from p_room_id
    and status in ('waiting','betting_open','flying','crashed')
  order by round_number desc limit 1 for update;

  if v_round.id is null then
    v_round := public._create_crash_rocket_round(p_room_id);
  end if;

  select * into v_secret from public.crash_rocket_round_secrets
  where round_id = v_round.id for update;

  if v_round.status = 'betting_open' and v_now >= v_round.betting_closes_at then
    update public.crash_rocket_rounds set
      status = 'flying',
      fly_started_at = v_round.betting_closes_at,
      updated_at = v_now
    where id = v_round.id returning * into v_round;
    update public.crash_rocket_round_secrets set
      target_crashed_at = v_round.fly_started_at
        + (ln(v_secret.target_multiplier) / 0.09) * interval '1 second'
    where round_id = v_round.id returning * into v_secret;
    insert into public.crash_rocket_round_events(round_id,event_type,payload)
    values (v_round.id,'flight_started',jsonb_build_object(
      'fly_started_at',v_round.fly_started_at
    ));
  end if;

  if v_round.status = 'flying' then
    v_current := least(v_secret.target_multiplier,
      public._crash_rocket_multiplier_at(v_round.fly_started_at, v_now));

    -- Auto-cashout is settled server-side and locked per bet.
    for v_bet in
      select * from public.crash_rocket_bets
      where round_id = v_round.id and status = 'placed'
        and auto_cashout_multiplier is not null
        and auto_cashout_multiplier <= v_current
        and auto_cashout_multiplier < v_secret.target_multiplier
      order by id for update
    loop
      v_payout := floor(v_bet.amount * v_bet.auto_cashout_multiplier)::integer;
      update public.wallets set
        coins_balance = coins_balance + v_payout, updated_at = v_now
      where user_id = v_bet.user_id returning coins_balance into v_balance;
      update public.crash_rocket_bets set
        status='cashed_out',
        cashout_multiplier=v_bet.auto_cashout_multiplier,
        payout_amount=v_payout,
        cashed_out_at=v_now
      where id=v_bet.id;
      insert into public.wallet_transactions(
        user_id,type,direction,coins_delta,diamonds_delta,
        balance_coins_after,note,metadata
      ) values (
        v_bet.user_id,'crash_rocket_cashout','credit',v_payout,0,v_balance,
        'Srood Rocket auto cashout',
        jsonb_build_object('round_id',v_round.id,'bet_id',v_bet.id,
          'multiplier',v_bet.auto_cashout_multiplier)
      );
      insert into public.crash_rocket_round_events(round_id,event_type,payload)
      values (v_round.id,'bet_cashed_out',jsonb_build_object(
        'bet_id',v_bet.id,'user_id',v_bet.user_id,
        'payout_amount',v_payout,'cashout_multiplier',v_bet.auto_cashout_multiplier
      ));
    end loop;

    if v_now >= v_secret.target_crashed_at then
      update public.crash_rocket_rounds set
        status='crashed',
        crashed_at=v_secret.target_crashed_at,
        crash_multiplier=v_secret.target_multiplier,
        crash_seed_reveal=v_secret.crash_seed_secret,
        updated_at=v_now
      where id=v_round.id returning * into v_round;
      update public.crash_rocket_bets set status='lost'
      where round_id=v_round.id and status='placed';
      insert into public.crash_rocket_round_events(round_id,event_type,payload)
      values (v_round.id,'round_crashed',jsonb_build_object(
        'crash_multiplier',v_secret.target_multiplier,
        'crashed_at',v_secret.target_crashed_at
      ));
    end if;
  end if;

  if v_round.status = 'crashed'
     and v_now >= v_round.crashed_at + interval '4 seconds' then
    update public.crash_rocket_rounds set status='settled',updated_at=v_now
    where id=v_round.id returning * into v_round;
    insert into public.crash_rocket_round_events(round_id,event_type,payload)
    values (v_round.id,'round_settled','{}');
  end if;

  return jsonb_build_object('round_id',v_round.id,'status',v_round.status);
end;
$$;

create or replace function public.get_active_crash_rocket_round(p_room_id uuid default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_round public.crash_rocket_rounds;
  v_wallet integer;
  v_bets jsonb;
  v_feed jsonb;
  v_history jsonb;
begin
  perform public._crash_rocket_assert_room_access(p_room_id);
  perform public.advance_crash_rocket_round(p_room_id);

  select * into v_round from public.crash_rocket_rounds
  where room_id is not distinct from p_room_id
  order by round_number desc limit 1;
  select coalesce(coins_balance,0) into v_wallet from public.wallets
  where user_id=v_uid;
  select coalesce(jsonb_agg(to_jsonb(b) order by b.bet_slot),'[]')
  into v_bets from public.crash_rocket_bets b
  where b.round_id=v_round.id and b.user_id=v_uid;
  select coalesce(jsonb_agg(x.payload order by x.created_at desc),'[]')
  into v_feed from (
    select e.created_at, e.payload from public.crash_rocket_round_events e
    where e.round_id=v_round.id
      and e.event_type in ('bet_placed','bet_cashed_out')
    order by e.created_at desc limit 30
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object(
    'round_number',h.round_number,'crash_multiplier',h.crash_multiplier,
    'crashed_at',h.crashed_at
  ) order by h.round_number desc),'[]')
  into v_history from (
    select * from public.crash_rocket_rounds
    where room_id is not distinct from p_room_id and crash_multiplier is not null
    order by round_number desc limit 12
  ) h;

  return jsonb_build_object(
    'server_now',clock_timestamp(),
    'wallet_balance',coalesce(v_wallet,0),
    'round',to_jsonb(v_round),
    'my_bets',v_bets,
    'public_feed',v_feed,
    'history',v_history
  );
end;
$$;

create or replace function public.place_crash_rocket_bet(
  p_room_id uuid,
  p_bet_slot integer,
  p_amount integer,
  p_auto_cashout_multiplier numeric,
  p_client_bet_id text
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_round public.crash_rocket_rounds;
  v_bet public.crash_rocket_bets;
  v_balance integer;
begin
  perform public._crash_rocket_assert_room_access(p_room_id);
  if p_bet_slot not in (1,2) then raise exception 'invalid_bet_slot'; end if;
  if p_amount not between 100 and 1000000 then raise exception 'invalid_bet_amount'; end if;
  if p_auto_cashout_multiplier is not null and
     p_auto_cashout_multiplier not between 1.01 and 1000 then
    raise exception 'invalid_auto_cashout';
  end if;
  if length(trim(coalesce(p_client_bet_id,''))) not between 8 and 100 then
    raise exception 'invalid_client_bet_id';
  end if;

  select * into v_bet from public.crash_rocket_bets
  where user_id=v_uid and client_bet_id=p_client_bet_id;
  if v_bet.id is not null then
    select coins_balance into v_balance from public.wallets where user_id=v_uid;
    return jsonb_build_object('bet',to_jsonb(v_bet),
      'wallet_balance',coalesce(v_balance,0),'idempotent',true);
  end if;

  perform public.advance_crash_rocket_round(p_room_id);
  select * into v_round from public.crash_rocket_rounds
  where room_id is not distinct from p_room_id
  order by round_number desc limit 1 for update;
  if v_round.status <> 'betting_open' or clock_timestamp() >= v_round.betting_closes_at then
    raise exception 'betting_closed';
  end if;

  insert into public.wallets(user_id) values(v_uid) on conflict(user_id) do nothing;
  select coins_balance into v_balance from public.wallets
  where user_id=v_uid for update;
  if v_balance < p_amount then raise exception 'insufficient_balance'; end if;
  update public.wallets set coins_balance=coins_balance-p_amount,updated_at=now()
  where user_id=v_uid returning coins_balance into v_balance;

  insert into public.crash_rocket_bets(
    round_id,user_id,bet_slot,amount,auto_cashout_multiplier,client_bet_id
  ) values (
    v_round.id,v_uid,p_bet_slot,p_amount,p_auto_cashout_multiplier,
    trim(p_client_bet_id)
  ) returning * into v_bet;
  insert into public.wallet_transactions(
    user_id,type,direction,coins_delta,diamonds_delta,
    balance_coins_after,note,metadata
  ) values (
    v_uid,'crash_rocket_bet','debit',-p_amount,0,v_balance,
    'Srood Rocket bet',jsonb_build_object(
      'round_id',v_round.id,'bet_id',v_bet.id,'bet_slot',p_bet_slot
    )
  );
  insert into public.crash_rocket_round_events(round_id,event_type,payload)
  values (v_round.id,'bet_placed',jsonb_build_object(
    'bet_id',v_bet.id,'user_id',v_uid,'bet_slot',p_bet_slot,
    'amount',p_amount,'display_name',coalesce(
      (select nullif(trim(p.display_name),'') from public.profiles p where p.id=v_uid),
      'Srood Player'
    ),'avatar_url',(select p.avatar_url from public.profiles p where p.id=v_uid)
  ));
  return jsonb_build_object('bet',to_jsonb(v_bet),
    'wallet_balance',v_balance,'idempotent',false);
exception when unique_violation then
  select * into v_bet from public.crash_rocket_bets
  where user_id=v_uid and client_bet_id=p_client_bet_id;
  if v_bet.id is null then raise; end if;
  select coins_balance into v_balance from public.wallets where user_id=v_uid;
  return jsonb_build_object('bet',to_jsonb(v_bet),
    'wallet_balance',coalesce(v_balance,0),'idempotent',true);
end;
$$;

create or replace function public.cashout_crash_rocket_bet(
  p_bet_id uuid,
  p_client_cashout_id text
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_bet public.crash_rocket_bets;
  v_round public.crash_rocket_rounds;
  v_secret public.crash_rocket_round_secrets;
  v_now timestamptz := clock_timestamp();
  v_multiplier numeric;
  v_payout integer;
  v_balance integer;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if length(trim(coalesce(p_client_cashout_id,''))) not between 8 and 100 then
    raise exception 'invalid_client_cashout_id';
  end if;
  select * into v_bet from public.crash_rocket_bets where id=p_bet_id for update;
  if v_bet.id is null or v_bet.user_id<>v_uid then raise exception 'bet_not_found'; end if;
  if v_bet.status='cashed_out' then
    select coins_balance into v_balance from public.wallets where user_id=v_uid;
    return jsonb_build_object('bet',to_jsonb(v_bet),
      'wallet_balance',coalesce(v_balance,0),'idempotent',true);
  end if;
  if v_bet.status<>'placed' then raise exception 'bet_not_cashable'; end if;

  select * into v_round from public.crash_rocket_rounds
  where id=v_bet.round_id for update;
  select * into v_secret from public.crash_rocket_round_secrets
  where round_id=v_round.id for update;
  if v_round.status<>'flying' or v_now>=v_secret.target_crashed_at then
    perform public.advance_crash_rocket_round(v_round.room_id);
    raise exception 'round_crashed';
  end if;
  v_multiplier := least(v_secret.target_multiplier,
    public._crash_rocket_multiplier_at(v_round.fly_started_at,v_now));
  v_payout := floor(v_bet.amount*v_multiplier)::integer;
  update public.wallets set coins_balance=coins_balance+v_payout,updated_at=v_now
  where user_id=v_uid returning coins_balance into v_balance;
  update public.crash_rocket_bets set
    status='cashed_out',cashout_multiplier=v_multiplier,payout_amount=v_payout,
    client_cashout_id=trim(p_client_cashout_id),cashed_out_at=v_now
  where id=v_bet.id returning * into v_bet;
  insert into public.wallet_transactions(
    user_id,type,direction,coins_delta,diamonds_delta,
    balance_coins_after,note,metadata
  ) values (
    v_uid,'crash_rocket_cashout','credit',v_payout,0,v_balance,
    'Srood Rocket cashout',jsonb_build_object(
      'round_id',v_round.id,'bet_id',v_bet.id,'multiplier',v_multiplier
    )
  );
  insert into public.crash_rocket_round_events(round_id,event_type,payload)
  values (v_round.id,'bet_cashed_out',jsonb_build_object(
    'bet_id',v_bet.id,'user_id',v_uid,'payout_amount',v_payout,
    'cashout_multiplier',v_multiplier
  ));
  return jsonb_build_object('bet',to_jsonb(v_bet),
    'wallet_balance',v_balance,'idempotent',false);
exception when unique_violation then
  select * into v_bet from public.crash_rocket_bets
  where user_id=v_uid and client_cashout_id=p_client_cashout_id;
  select coins_balance into v_balance from public.wallets where user_id=v_uid;
  return jsonb_build_object('bet',to_jsonb(v_bet),
    'wallet_balance',coalesce(v_balance,0),'idempotent',true);
end;
$$;

create or replace function public.settle_crash_rocket_round(p_round_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare v_round public.crash_rocket_rounds;
begin
  select * into v_round from public.crash_rocket_rounds
  where id=p_round_id for update;
  if v_round.id is null then raise exception 'round_not_found'; end if;
  perform public.advance_crash_rocket_round(v_round.room_id);
  select * into v_round from public.crash_rocket_rounds where id=p_round_id;
  return jsonb_build_object('round_id',v_round.id,'status',v_round.status,
    'crash_multiplier',v_round.crash_multiplier);
end;
$$;

create or replace function public.admin_or_cron_start_next_crash_round(
  p_room_id uuid default null
)
returns jsonb language sql security definer set search_path = ''
as $$ select public.advance_crash_rocket_round(p_room_id); $$;

create or replace function public.admin_or_cron_crash_round(p_round_id uuid)
returns jsonb language sql security definer set search_path = ''
as $$ select public.settle_crash_rocket_round(p_round_id); $$;

revoke all on function public.advance_crash_rocket_round(uuid)
  from public, anon;
revoke all on function public.get_active_crash_rocket_round(uuid)
  from public, anon;
revoke all on function public.place_crash_rocket_bet(uuid,integer,integer,numeric,text)
  from public, anon;
revoke all on function public.cashout_crash_rocket_bet(uuid,text)
  from public, anon;
revoke all on function public.settle_crash_rocket_round(uuid)
  from public, anon;
revoke all on function public.admin_or_cron_start_next_crash_round(uuid)
  from public, anon;
revoke all on function public.admin_or_cron_crash_round(uuid)
  from public, anon;
grant execute on function public.advance_crash_rocket_round(uuid) to authenticated;
grant execute on function public.get_active_crash_rocket_round(uuid) to authenticated;
grant execute on function public.place_crash_rocket_bet(uuid,integer,integer,numeric,text)
  to authenticated;
grant execute on function public.cashout_crash_rocket_bet(uuid,text) to authenticated;
grant execute on function public.settle_crash_rocket_round(uuid) to authenticated;
grant execute on function public.admin_or_cron_start_next_crash_round(uuid)
  to authenticated;
grant execute on function public.admin_or_cron_crash_round(uuid) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public'
      and tablename='crash_rocket_rounds'
  ) then
    alter publication supabase_realtime add table public.crash_rocket_rounds;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public'
      and tablename='crash_rocket_round_events'
  ) then
    alter publication supabase_realtime
      add table public.crash_rocket_round_events;
  end if;
end $$;

-- The scheduled function contains no caller-controlled outcome. If pg_cron is
-- unavailable, authenticated clients may call advance_crash_rocket_round;
-- advisory locks and server time keep that fallback safe and idempotent.
do $$
begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    if exists(select 1 from cron.job where jobname='srood_rocket_advance') then
      perform cron.unschedule('srood_rocket_advance');
    end if;
    perform cron.schedule(
      'srood_rocket_advance','* * * * * *',
      'select public.advance_crash_rocket_round(null);'
    );
  end if;
exception when others then
  raise notice 'Srood Rocket cron not scheduled: %', sqlerrm;
end $$;

comment on table public.crash_rocket_round_secrets is
  'Private Srood Rocket seed and committed target. Never exposed to API roles or realtime.';
comment on function public.cashout_crash_rocket_bet(uuid,text) is
  'Atomic idempotent server-time cashout; client multiplier is never accepted.';
