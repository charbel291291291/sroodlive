-- ────────────────────────────────────────────────────────────────────────────
-- Crash Rocket — server-side round & bet management
--
--   Per-user round model: each Flutter session owns one flying round.
--   Multiplier formula (matches HTML client exactly):
--     m(t) = exp(0.15 * elapsed_seconds)
--   Crash point is pre-committed at round start using provably-fair
--   weighted-random distribution; never revealed until the round settles.
--
--   All coin logic lives in SQL — the WebView and Flutter only animate results.
-- ────────────────────────────────────────────────────────────────────────────

-- ── 1. crash_rounds ──────────────────────────────────────────────────────────

create table if not exists public.crash_rounds (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  status           text not null default 'flying'
                     check (status in ('flying', 'crashed')),
  -- Pre-committed crash multiplier, hidden until settlement.
  crash_multiplier numeric(10,2) not null,
  started_at       timestamptz not null default now(),
  crashed_at       timestamptz,
  created_at       timestamptz not null default now()
);

alter table public.crash_rounds enable row level security;

drop policy if exists "crash_rounds_own" on public.crash_rounds;
create policy "crash_rounds_own"
  on public.crash_rounds for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ── 2. crash_bets ────────────────────────────────────────────────────────────

create table if not exists public.crash_bets (
  id                     uuid primary key default gen_random_uuid(),
  round_id               uuid not null references public.crash_rounds(id) on delete cascade,
  user_id                uuid not null references auth.users(id) on delete cascade,
  bet_amount             integer not null check (bet_amount > 0),
  mode                   text not null default 'manual'
                           check (mode in ('manual', 'auto')),
  auto_cashout_multiplier numeric(10,2),
  cashout_multiplier     numeric(10,2),
  win_amount             integer not null default 0,
  status                 text not null default 'running'
                           check (status in ('running', 'cashed_out', 'lost')),
  created_at             timestamptz not null default now()
);

alter table public.crash_bets enable row level security;

drop policy if exists "crash_bets_own" on public.crash_bets;
create policy "crash_bets_own"
  on public.crash_bets for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ── 3. Extend wallet_transactions type constraint ────────────────────────────

alter table public.wallet_transactions
drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
add constraint wallet_transactions_type_check check (
  type in (
    'recharge_request', 'admin_adjustment', 'gift_sent', 'gift_received',
    'agency_recharge', 'refund', 'system', 'withdrawal', 'withdrawal_refund',
    'agency_commission',
    'hungry_cat_bet', 'hungry_cat_reward', 'hungry_cat_refund',
    'gold_ladder_entry', 'gold_ladder_win', 'gold_ladder_safe_payout',
    'crash_rocket_bet', 'crash_rocket_win', 'crash_rocket_refund'
  )
);

-- ── 4. start_crash_round ─────────────────────────────────────────────────────
-- Deducts the total bet from the real wallet, pre-commits crash multiplier,
-- and returns the round_id, started_at, and per-bet IDs.

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
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  -- Optional: respect game_settings kill-switch if the row exists
  if exists (
    select 1 from public.game_settings
    where game_key = 'crash_rocket' and is_enabled = false
  ) then
    raise exception 'game_disabled';
  end if;

  if p_bets is null or jsonb_array_length(p_bets) = 0 then
    raise exception 'no_bets';
  end if;
  if jsonb_array_length(p_bets) > 2 then
    raise exception 'too_many_bets';
  end if;

  -- Sum total bet from JSON array
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

  -- Provably-fair crash multiplier:
  --   1% chance of instant crash at 1.00×
  --   Otherwise: 0.99 / (1 - rand), capped at 1000×
  v_rand := random();
  if v_rand < 0.01 then
    v_crash_at := 1.00;
  else
    v_crash_at := round((0.99 / (1.0 - v_rand))::numeric, 2);
    if v_crash_at < 1.00  then v_crash_at := 1.00;   end if;
    if v_crash_at > 1000  then v_crash_at := 1000.00; end if;
  end if;

  -- Create round (crash_multiplier is the hidden secret)
  insert into public.crash_rounds(id, user_id, status, crash_multiplier, started_at)
  values (v_round_id, v_user_id, 'flying', v_crash_at, v_started_at);

  -- Single wallet transaction for the total bet
  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_user_id, 'crash_rocket_bet', 'debit', -v_total_bet, 0,
     'Crash Rocket bet',
     jsonb_build_object('round_id', v_round_id, 'total_bet', v_total_bet));

  -- Create individual bet records, preserve insertion order for slot mapping
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
    'bets',        v_bet_ids
  );
end;
$$;

grant execute on function public.start_crash_round(jsonb) to authenticated;

-- ── 5. cashout_crash_bet ─────────────────────────────────────────────────────
-- Computes the current server-side multiplier and pays out if still flying.

create or replace function public.cashout_crash_bet(p_bet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_bet          public.crash_bets%rowtype;
  v_started_at   timestamptz;
  v_crash_at     numeric;
  v_round_status text;
  v_elapsed      numeric;
  v_current_m    numeric;
  v_win          integer;
  v_new_balance  integer;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  -- Lock the bet row to prevent concurrent cashouts
  select * into v_bet
  from public.crash_bets
  where id = p_bet_id and user_id = v_user_id
  for update;

  if not found then raise exception 'bet_not_found'; end if;

  -- Idempotent: already settled
  if v_bet.status != 'running' then
    return jsonb_build_object(
      'status',             v_bet.status,
      'cashout_multiplier', v_bet.cashout_multiplier,
      'win_amount',         coalesce(v_bet.win_amount, 0)
    );
  end if;

  -- Fetch round metadata (no lock needed here — we have the bet lock)
  select crash_multiplier, started_at, status
  into v_crash_at, v_started_at, v_round_status
  from public.crash_rounds
  where id = v_bet.round_id;

  -- Compute server-side multiplier using same formula as client
  v_elapsed   := greatest(0, extract(epoch from (now() - v_started_at)));
  v_current_m := round(exp(0.15 * v_elapsed)::numeric, 2);

  -- Crashed before cashout request arrived
  if v_round_status = 'crashed' or v_current_m >= v_crash_at then
    update public.crash_bets
    set status = 'lost', win_amount = 0
    where id = p_bet_id;

    return jsonb_build_object(
      'status',             'lost',
      'cashout_multiplier', null,
      'win_amount',         0
    );
  end if;

  -- Cash out at current server multiplier
  v_win := floor(v_bet.bet_amount * v_current_m)::integer;

  update public.crash_bets
  set status             = 'cashed_out',
      cashout_multiplier = v_current_m,
      win_amount         = v_win
  where id = p_bet_id;

  update public.wallets
  set coins_balance = coins_balance + v_win, updated_at = now()
  where user_id = v_user_id
  returning coins_balance into v_new_balance;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_user_id, 'crash_rocket_win', 'credit', v_win, 0,
     'Crash Rocket cashout at ' || v_current_m || '×',
     jsonb_build_object('round_id', v_bet.round_id, 'bet_id', p_bet_id,
                        'multiplier', v_current_m));

  return jsonb_build_object(
    'status',             'cashed_out',
    'cashout_multiplier', v_current_m,
    'win_amount',         v_win,
    'new_balance',        v_new_balance
  );
end;
$$;

grant execute on function public.cashout_crash_bet(uuid) to authenticated;

-- ── 6. get_crash_round_status ─────────────────────────────────────────────────
-- Flutter polls this every ~280 ms during flight.
-- On first call where server time exceeds crash point, atomically settles the
-- round (auto-cashouts + mark remaining bets lost) and returns 'crashed'.
-- Subsequent calls return cached results without re-settling.

create or replace function public.get_crash_round_status(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid := auth.uid();
  v_round       public.crash_rounds%rowtype;
  v_elapsed     numeric;
  v_current_m   numeric;
  v_bet         public.crash_bets%rowtype;
  v_bet_results jsonb    := '[]'::jsonb;
  v_auto_win    integer;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  -- Lock round row to serialize concurrent settle attempts
  select * into v_round
  from public.crash_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found then raise exception 'round_not_found'; end if;

  -- Already settled — return cached bet results
  if v_round.status = 'crashed' then
    for v_bet in
      select * from public.crash_bets
      where round_id = p_round_id and user_id = v_user_id
    loop
      v_bet_results := v_bet_results || jsonb_build_array(jsonb_build_object(
        'bet_id',             v_bet.id,
        'status',             v_bet.status,
        'cashout_multiplier', v_bet.cashout_multiplier,
        'win_amount',         coalesce(v_bet.win_amount, 0)
      ));
    end loop;
    return jsonb_build_object(
      'status',           'crashed',
      'crash_multiplier', v_round.crash_multiplier,
      'bets',             v_bet_results
    );
  end if;

  -- Compute server-side multiplier
  v_elapsed   := greatest(0, extract(epoch from (now() - v_round.started_at)));
  v_current_m := round(exp(0.15 * v_elapsed)::numeric, 2);

  -- Still flying
  if v_current_m < v_round.crash_multiplier then
    return jsonb_build_object('status', 'flying');
  end if;

  -- ── CRASH DETECTED — settle now ───────────────────────────────────────────

  -- Auto-cashout bets: mode='auto' with target below crash point
  for v_bet in
    select * from public.crash_bets
    where round_id = p_round_id
      and user_id  = v_user_id
      and status   = 'running'
      and mode     = 'auto'
      and auto_cashout_multiplier is not null
      and auto_cashout_multiplier < v_round.crash_multiplier
  loop
    v_auto_win := floor(v_bet.bet_amount * v_bet.auto_cashout_multiplier)::integer;

    update public.crash_bets
    set status             = 'cashed_out',
        cashout_multiplier = v_bet.auto_cashout_multiplier,
        win_amount         = v_auto_win
    where id = v_bet.id;

    update public.wallets
    set coins_balance = coins_balance + v_auto_win, updated_at = now()
    where user_id = v_user_id;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
    values
      (v_user_id, 'crash_rocket_win', 'credit', v_auto_win, 0,
       'Crash Rocket auto-cashout at ' || v_bet.auto_cashout_multiplier || '×',
       jsonb_build_object('round_id', p_round_id, 'bet_id', v_bet.id,
                          'multiplier', v_bet.auto_cashout_multiplier));
  end loop;

  -- Remaining running bets are lost
  update public.crash_bets
  set status = 'lost', win_amount = 0
  where round_id = p_round_id and user_id = v_user_id and status = 'running';

  -- Mark round as crashed (reveals crash_multiplier to client)
  update public.crash_rounds
  set status     = 'crashed',
      crashed_at = now()
  where id = p_round_id;

  -- Build final bet results
  for v_bet in
    select * from public.crash_bets
    where round_id = p_round_id and user_id = v_user_id
  loop
    v_bet_results := v_bet_results || jsonb_build_array(jsonb_build_object(
      'bet_id',             v_bet.id,
      'status',             v_bet.status,
      'cashout_multiplier', v_bet.cashout_multiplier,
      'win_amount',         coalesce(v_bet.win_amount, 0)
    ));
  end loop;

  return jsonb_build_object(
    'status',           'crashed',
    'crash_multiplier', v_round.crash_multiplier,
    'bets',             v_bet_results
  );
end;
$$;

grant execute on function public.get_crash_round_status(uuid) to authenticated;

-- ── 7. get_recent_crash_rounds ────────────────────────────────────────────────
-- Returns the last N globally-completed rounds for the history strip.
-- crash_multiplier is public info (revealed results only).

create or replace function public.get_recent_crash_rounds(
  p_limit integer default 20
)
returns table (
  crash_multiplier numeric,
  crashed_at       timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query
  select r.crash_multiplier, r.crashed_at
  from public.crash_rounds r
  where r.status = 'crashed'
  order by r.crashed_at desc
  limit p_limit;
end;
$$;

grant execute on function public.get_recent_crash_rounds(integer) to authenticated;
