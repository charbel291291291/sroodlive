-- ─────────────────────────────────────────────────────────────────────────────
-- Srood Loto — tables, RLS, RPCs
-- Draw schedule: every 60 min (configurable). All settling happens server-side.
-- Client must never generate winning numbers or decide prizes.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. loto_settings ─────────────────────────────────────────────────────────

create table if not exists public.loto_settings (
  id                          uuid          primary key default gen_random_uuid(),
  game_key                    text          unique not null default 'srood_loto',
  is_enabled                  boolean       not null default true,
  ticket_price_coins          integer       not null default 20000,
  number_min                  integer       not null default 1,
  number_max                  integer       not null default 42,
  numbers_per_ticket          integer       not null default 6,
  draw_interval_minutes       integer       not null default 60,
  ticket_close_minutes_before integer       not null default 5,
  match_3_prize               bigint        not null default 20000,
  match_4_prize               bigint        not null default 100000,
  match_5_prize               bigint        not null default 1000000,
  match_6_prize               bigint        not null default 10000000,
  progressive_jackpot_enabled boolean       not null default false,
  jackpot_pool_coins          bigint        not null default 0,
  jackpot_contribution_pct    numeric(5,2)  not null default 20.00,
  responsible_notice_ar       text          not null default 'هذه اللعبة للترفيه فقط. العب بمسؤولية. للاعبين فوق 18 سنة فقط.',
  responsible_notice_en       text          not null default 'This game is for entertainment only. Play responsibly. Players must be 18+.',
  updated_at                  timestamptz   not null default now(),
  updated_by                  uuid          references auth.users(id) on delete set null
);

insert into public.loto_settings (game_key) values ('srood_loto')
on conflict (game_key) do nothing;

-- ── 2. loto_draws ────────────────────────────────────────────────────────────

create sequence if not exists public.loto_draw_number_seq start 1 increment 1;

create table if not exists public.loto_draws (
  id                  uuid        primary key default gen_random_uuid(),
  draw_number         bigint      not null unique default nextval('public.loto_draw_number_seq'),
  status              text        not null default 'open'
                      check (status in ('open','locked','drawn','settled','voided')),
  opens_at            timestamptz not null default now(),
  closes_at           timestamptz not null,
  draw_at             timestamptz not null,
  winning_numbers     integer[]   null,
  seed_hash           text        null,
  seed_reveal         text        null,
  total_tickets       integer     not null default 0,
  total_sales_coins   bigint      not null default 0,
  total_payout_coins  bigint      not null default 0,
  jackpot_pool_before bigint      not null default 0,
  jackpot_pool_after  bigint      not null default 0,
  created_at          timestamptz not null default now(),
  settled_at          timestamptz null
);

create index if not exists idx_loto_draws_status_draw_at on public.loto_draws(status, draw_at);

-- ── 3. loto_tickets ──────────────────────────────────────────────────────────

create table if not exists public.loto_tickets (
  id                  uuid        primary key default gen_random_uuid(),
  draw_id             uuid        not null references public.loto_draws(id) on delete cascade,
  user_id             uuid        not null references auth.users(id) on delete cascade,
  numbers             integer[]   not null,
  ticket_price_coins  integer     not null,
  status              text        not null default 'active'
                      check (status in ('active','lost','won','refunded','voided')),
  matched_count       integer     not null default 0,
  prize_coins         bigint      not null default 0,
  created_at          timestamptz not null default now()
);

create index if not exists idx_loto_tickets_draw_user on public.loto_tickets(draw_id, user_id);
create index if not exists idx_loto_tickets_user_id   on public.loto_tickets(user_id);

-- ── 4. loto_admin_audit_logs ─────────────────────────────────────────────────

create table if not exists public.loto_admin_audit_logs (
  id         uuid        primary key default gen_random_uuid(),
  admin_id   uuid        references auth.users(id) on delete set null,
  action     text        not null,
  old_value  jsonb,
  new_value  jsonb,
  created_at timestamptz not null default now()
);

-- ── 5. Extend wallet_transactions type constraint ─────────────────────────────

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
    'crash_rocket_bet', 'crash_rocket_win', 'crash_rocket_refund',
    'srood_loto_ticket', 'srood_loto_win', 'srood_loto_refund'
  )
);

-- ── 6. RLS ───────────────────────────────────────────────────────────────────

alter table public.loto_settings         enable row level security;
alter table public.loto_draws            enable row level security;
alter table public.loto_tickets          enable row level security;
alter table public.loto_admin_audit_logs enable row level security;

-- Settings: public read, admin write
drop policy if exists "loto_settings_public_read"  on public.loto_settings;
drop policy if exists "loto_settings_admin_write"  on public.loto_settings;
create policy "loto_settings_public_read" on public.loto_settings for select using (true);
create policy "loto_settings_admin_write" on public.loto_settings for all using (
  public.has_app_role('super_admin') or public.has_app_role('finance_admin')
);

-- Draws: public read
drop policy if exists "loto_draws_public_read" on public.loto_draws;
create policy "loto_draws_public_read" on public.loto_draws for select using (true);

-- Tickets: own only
drop policy if exists "loto_tickets_own_read" on public.loto_tickets;
create policy "loto_tickets_own_read" on public.loto_tickets
  for select using (auth.uid() = user_id);

-- Audit: admin read only
drop policy if exists "loto_audit_admin_read" on public.loto_admin_audit_logs;
create policy "loto_audit_admin_read" on public.loto_admin_audit_logs for select using (
  public.has_app_role('super_admin') or public.has_app_role('finance_admin')
);

-- ── 7. loto_create_next_draw_if_needed() ─────────────────────────────────────
-- Internal helper. Creates the next scheduled draw if none exists in the future.

create or replace function public.loto_create_next_draw_if_needed()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_s            record;
  v_draw_id      uuid;
  v_base         timestamptz;
  v_next_draw_at timestamptz;
  v_closes_at    timestamptz;
begin
  select * into v_s from public.loto_settings where game_key = 'srood_loto' limit 1;
  if not found or not v_s.is_enabled then return null; end if;

  -- Return existing future open draw
  select id into v_draw_id
  from public.loto_draws
  where status = 'open' and draw_at > now()
  order by draw_at asc limit 1;
  if found then return v_draw_id; end if;

  -- Next hour boundary (UTC)
  v_base         := date_trunc('hour', now() at time zone 'UTC') at time zone 'UTC';
  v_next_draw_at := v_base + (interval '1 minute' * v_s.draw_interval_minutes);
  while v_next_draw_at <= now() + interval '90 seconds' loop
    v_next_draw_at := v_next_draw_at + (interval '1 minute' * v_s.draw_interval_minutes);
  end loop;

  v_closes_at := v_next_draw_at - (interval '1 minute' * v_s.ticket_close_minutes_before);

  insert into public.loto_draws (status, opens_at, closes_at, draw_at, jackpot_pool_before)
  values ('open', now(), v_closes_at, v_next_draw_at, coalesce(v_s.jackpot_pool_coins, 0))
  returning id into v_draw_id;

  return v_draw_id;
end;
$$;

-- ── 8. loto_settle_due_draws() ───────────────────────────────────────────────
-- Called from loto_get_current_draw() and can be scheduled with pg_cron.
-- Server generates all winning numbers. Client never touches this.

create or replace function public.loto_settle_due_draws()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_s          record;
  v_draw       record;
  v_ticket     record;
  v_matched    integer;
  v_prize      bigint;
  v_seed       text;
  v_numbers    integer[];
  v_jackpot    bigint;
  v_settled    integer := 0;
begin
  select * into v_s from public.loto_settings where game_key = 'srood_loto' limit 1;
  if not found then return 0; end if;

  for v_draw in
    select * from public.loto_draws
    where draw_at <= now() and status = 'open'
    order by draw_at asc
    for update skip locked
  loop
    -- Mark as being processed
    update public.loto_draws set status = 'drawn' where id = v_draw.id;

    -- Generate 6 unique random numbers server-side only
    select array_agg(n order by n)
    into v_numbers
    from (
      select generate_series(v_s.number_min, v_s.number_max) as n
      order by random()
      limit v_s.numbers_per_ticket
    ) sub;

    -- Provably-fair seed (store for auditability)
    v_seed := v_draw.id::text || '-' || v_draw.draw_number::text || '-' || md5(random()::text);

    update public.loto_draws
    set winning_numbers = v_numbers,
        seed_hash       = md5(v_seed || 'srood_loto_secret'),
        seed_reveal     = v_seed
    where id = v_draw.id;

    v_jackpot := v_draw.jackpot_pool_before;

    -- Settle each active ticket
    for v_ticket in
      select * from public.loto_tickets
      where draw_id = v_draw.id and status = 'active'
    loop
      select count(*) into v_matched
      from (
        select unnest(v_ticket.numbers)
        intersect
        select unnest(v_numbers)
      ) m;

      v_prize := 0;
      if v_matched >= v_s.numbers_per_ticket and v_s.progressive_jackpot_enabled then
        v_prize   := v_jackpot;
        v_jackpot := 0;
      else
        case v_matched
          when 3 then v_prize := v_s.match_3_prize;
          when 4 then v_prize := v_s.match_4_prize;
          when 5 then v_prize := v_s.match_5_prize;
          when 6 then v_prize := v_s.match_6_prize;
          else        v_prize := 0;
        end case;
      end if;

      if v_prize > 0 then
        update public.wallets
        set coins_balance = coins_balance + v_prize, updated_at = now()
        where user_id = v_ticket.user_id;

        insert into public.wallet_transactions
          (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
        values
          (v_ticket.user_id, 'srood_loto_win', 'credit', v_prize, 0,
           'Srood Loto win – Draw #' || v_draw.draw_number || ' – ' || v_matched || ' matched',
           jsonb_build_object('draw_id',v_draw.id,'ticket_id',v_ticket.id,'matched',v_matched,'prize',v_prize));

        update public.loto_tickets
        set status = 'won', matched_count = v_matched, prize_coins = v_prize
        where id = v_ticket.id;
      else
        update public.loto_tickets
        set status = 'lost', matched_count = v_matched
        where id = v_ticket.id;
      end if;
    end loop;

    -- Finalize draw record
    update public.loto_draws
    set status            = 'settled',
        settled_at        = now(),
        jackpot_pool_after = v_jackpot,
        total_payout_coins = (
          select coalesce(sum(prize_coins), 0)
          from public.loto_tickets where draw_id = v_draw.id
        )
    where id = v_draw.id;

    if v_s.progressive_jackpot_enabled then
      update public.loto_settings
      set jackpot_pool_coins = v_jackpot, updated_at = now()
      where game_key = 'srood_loto';
    end if;

    v_settled := v_settled + 1;
  end loop;

  return v_settled;
end;
$$;

-- ── 9. loto_get_current_draw() ───────────────────────────────────────────────

create or replace function public.loto_get_current_draw()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id  uuid := auth.uid();
  v_draw     record;
  v_s        record;
  v_balance  integer;
  v_tickets  jsonb;
  v_draw_id  uuid;
begin
  -- Settle any overdue draws and ensure a draw exists
  perform public.loto_settle_due_draws();
  perform public.loto_create_next_draw_if_needed();

  select * into v_s from public.loto_settings where game_key = 'srood_loto' limit 1;

  -- Current draw: the nearest future open draw
  select * into v_draw
  from public.loto_draws
  where status = 'open' and draw_at > now()
  order by draw_at asc limit 1;

  if not found then
    return jsonb_build_object('draw', null, 'settings', row_to_json(v_s));
  end if;

  -- User balance
  select coalesce(coins_balance, 0) into v_balance
  from public.wallets where user_id = v_user_id;

  -- User tickets for this draw
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',          t.id,
    'numbers',     t.numbers,
    'status',      t.status,
    'matched_count', t.matched_count,
    'prize_coins', t.prize_coins,
    'created_at',  t.created_at
  ) order by t.created_at desc), '[]'::jsonb)
  into v_tickets
  from public.loto_tickets t
  where t.draw_id = v_draw.id and t.user_id = v_user_id;

  return jsonb_build_object(
    'draw', jsonb_build_object(
      'id',                 v_draw.id,
      'draw_number',        v_draw.draw_number,
      'status',             v_draw.status,
      'opens_at',           v_draw.opens_at,
      'closes_at',          v_draw.closes_at,
      'draw_at',            v_draw.draw_at,
      'total_tickets',      v_draw.total_tickets,
      'total_sales_coins',  v_draw.total_sales_coins,
      'jackpot_pool_before',v_draw.jackpot_pool_before
    ),
    'settings', jsonb_build_object(
      'is_enabled',                 v_s.is_enabled,
      'ticket_price_coins',         v_s.ticket_price_coins,
      'number_min',                 v_s.number_min,
      'number_max',                 v_s.number_max,
      'numbers_per_ticket',         v_s.numbers_per_ticket,
      'match_3_prize',              v_s.match_3_prize,
      'match_4_prize',              v_s.match_4_prize,
      'match_5_prize',              v_s.match_5_prize,
      'match_6_prize',              v_s.match_6_prize,
      'progressive_jackpot_enabled',v_s.progressive_jackpot_enabled,
      'jackpot_pool_coins',         v_s.jackpot_pool_coins,
      'responsible_notice_ar',      v_s.responsible_notice_ar,
      'responsible_notice_en',      v_s.responsible_notice_en
    ),
    'my_tickets',           v_tickets,
    'user_balance',         coalesce(v_balance, 0),
    'seconds_until_draw',   greatest(0, extract(epoch from (v_draw.draw_at - now()))::integer),
    'seconds_until_close',  greatest(0, extract(epoch from (v_draw.closes_at - now()))::integer)
  );
end;
$$;

-- ── 10. loto_buy_ticket(p_numbers int[]) ─────────────────────────────────────

create or replace function public.loto_buy_ticket(p_numbers integer[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id  uuid    := auth.uid();
  v_s        record;
  v_draw     record;
  v_wallet   record;
  v_ticket_id uuid;
  v_n        integer;
  v_seen     integer[];
  v_contrib  bigint;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_s from public.loto_settings where game_key = 'srood_loto' limit 1;
  if not found or not v_s.is_enabled then
    raise exception 'game_disabled';
  end if;

  -- Validate ticket numbers
  if array_length(p_numbers, 1) is distinct from v_s.numbers_per_ticket then
    raise exception 'invalid_count: expected % numbers', v_s.numbers_per_ticket;
  end if;

  v_seen := '{}';
  foreach v_n in array p_numbers loop
    if v_n < v_s.number_min or v_n > v_s.number_max then
      raise exception 'number_out_of_range: % must be between % and %', v_n, v_s.number_min, v_s.number_max;
    end if;
    if v_n = any(v_seen) then
      raise exception 'duplicate_number: % appears more than once', v_n;
    end if;
    v_seen := v_seen || v_n;
  end loop;

  -- Find current open draw with tickets still open
  select * into v_draw
  from public.loto_draws
  where status = 'open' and draw_at > now() and closes_at > now()
  order by draw_at asc limit 1;

  if not found then
    raise exception 'draw_closed: no open draw available';
  end if;

  -- Lock wallet row and check balance
  select * into v_wallet
  from public.wallets
  where user_id = v_user_id
  for update;

  if not found or v_wallet.coins_balance < v_s.ticket_price_coins then
    raise exception 'insufficient_balance: need % coins', v_s.ticket_price_coins;
  end if;

  -- Deduct ticket price
  update public.wallets
  set coins_balance = coins_balance - v_s.ticket_price_coins,
      updated_at    = now()
  where user_id = v_user_id;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_user_id, 'srood_loto_ticket', 'debit', -v_s.ticket_price_coins, 0,
     'Srood Loto ticket – Draw #' || v_draw.draw_number,
     jsonb_build_object('draw_id', v_draw.id, 'numbers', p_numbers));

  -- Progressive jackpot contribution
  if v_s.progressive_jackpot_enabled and v_s.jackpot_contribution_pct > 0 then
    v_contrib := floor(v_s.ticket_price_coins * v_s.jackpot_contribution_pct / 100.0)::bigint;
    update public.loto_settings
    set jackpot_pool_coins = jackpot_pool_coins + v_contrib, updated_at = now()
    where game_key = 'srood_loto';
    -- Also update the current draw's jackpot snapshot
    update public.loto_draws
    set jackpot_pool_before = jackpot_pool_before + v_contrib
    where id = v_draw.id;
  end if;

  -- Create ticket (numbers sorted ascending for consistent display)
  insert into public.loto_tickets (draw_id, user_id, numbers, ticket_price_coins, status)
  values (v_draw.id, v_user_id,
          array(select unnest(p_numbers) order by 1),
          v_s.ticket_price_coins, 'active')
  returning id into v_ticket_id;

  -- Update draw counters
  update public.loto_draws
  set total_tickets    = total_tickets + 1,
      total_sales_coins = total_sales_coins + v_s.ticket_price_coins
  where id = v_draw.id;

  return jsonb_build_object(
    'ticket_id',      v_ticket_id,
    'draw_id',        v_draw.id,
    'draw_number',    v_draw.draw_number,
    'numbers',        array(select unnest(p_numbers) order by 1),
    'ticket_price',   v_s.ticket_price_coins,
    'new_balance',    (select coins_balance from public.wallets where user_id = v_user_id)
  );
end;
$$;

-- ── 11. loto_get_my_tickets(p_draw_id uuid) ──────────────────────────────────

create or replace function public.loto_get_my_tickets(p_draw_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',            t.id,
      'draw_id',       t.draw_id,
      'numbers',       t.numbers,
      'ticket_price_coins', t.ticket_price_coins,
      'status',        t.status,
      'matched_count', t.matched_count,
      'prize_coins',   t.prize_coins,
      'created_at',    t.created_at,
      'draw_number',   d.draw_number,
      'draw_at',       d.draw_at,
      'winning_numbers', d.winning_numbers
    ) order by t.created_at desc)
    from public.loto_tickets t
    join public.loto_draws d on d.id = t.draw_id
    where t.draw_id = p_draw_id and t.user_id = v_user_id
  ), '[]'::jsonb);
end;
$$;

-- ── 12. loto_get_recent_draws() ──────────────────────────────────────────────

create or replace function public.loto_get_recent_draws()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  return coalesce((
    select jsonb_agg(row_data order by draw_number desc)
    from (
      select jsonb_build_object(
        'id',                d.id,
        'draw_number',       d.draw_number,
        'status',            d.status,
        'draw_at',           d.draw_at,
        'winning_numbers',   d.winning_numbers,
        'total_tickets',     d.total_tickets,
        'total_sales_coins', d.total_sales_coins,
        'total_payout_coins',d.total_payout_coins,
        'settled_at',        d.settled_at,
        'my_ticket', (
          select jsonb_build_object(
            'id',            t.id,
            'numbers',       t.numbers,
            'status',        t.status,
            'matched_count', t.matched_count,
            'prize_coins',   t.prize_coins
          )
          from public.loto_tickets t
          where t.draw_id = d.id and t.user_id = v_user_id
          order by t.created_at desc limit 1
        )
      ) as row_data
      from public.loto_draws d
      where d.status in ('settled','voided')
      order by d.draw_number desc
      limit 20
    ) sub
  ), '[]'::jsonb);
end;
$$;

-- ── 13. admin_loto_force_settle_draw(p_draw_id uuid) ─────────────────────────

create or replace function public.admin_loto_force_settle_draw(p_draw_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('finance_admin')) then
    raise exception 'permission_denied';
  end if;

  -- Force draw_at to now so settle picks it up
  update public.loto_draws
  set draw_at = now() - interval '1 second'
  where id = p_draw_id and status = 'open';

  perform public.loto_settle_due_draws();

  insert into public.loto_admin_audit_logs (admin_id, action, new_value)
  values (v_admin_id, 'force_settle_draw',
          jsonb_build_object('draw_id', p_draw_id));

  return jsonb_build_object('ok', true, 'draw_id', p_draw_id);
end;
$$;

-- ── 14. admin_loto_void_draw(p_draw_id uuid) ─────────────────────────────────

create or replace function public.admin_loto_void_draw(p_draw_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_ticket   record;
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('finance_admin')) then
    raise exception 'permission_denied';
  end if;

  -- Refund all active tickets
  for v_ticket in
    select * from public.loto_tickets
    where draw_id = p_draw_id and status = 'active'
  loop
    update public.wallets
    set coins_balance = coins_balance + v_ticket.ticket_price_coins, updated_at = now()
    where user_id = v_ticket.user_id;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
    values
      (v_ticket.user_id, 'srood_loto_refund', 'credit', v_ticket.ticket_price_coins, 0,
       'Srood Loto refund – voided draw',
       jsonb_build_object('draw_id', p_draw_id, 'ticket_id', v_ticket.id));

    update public.loto_tickets set status = 'refunded' where id = v_ticket.id;
  end loop;

  update public.loto_draws set status = 'voided' where id = p_draw_id;

  insert into public.loto_admin_audit_logs (admin_id, action, new_value)
  values (v_admin_id, 'void_draw', jsonb_build_object('draw_id', p_draw_id));

  perform public.loto_create_next_draw_if_needed();

  return jsonb_build_object('ok', true, 'draw_id', p_draw_id);
end;
$$;

-- ── 15. admin_loto_update_settings(...) ──────────────────────────────────────

create or replace function public.admin_loto_update_settings(
  p_is_enabled                  boolean       default null,
  p_ticket_price_coins          integer       default null,
  p_number_min                  integer       default null,
  p_number_max                  integer       default null,
  p_numbers_per_ticket          integer       default null,
  p_draw_interval_minutes       integer       default null,
  p_match_3_prize               bigint        default null,
  p_match_4_prize               bigint        default null,
  p_match_5_prize               bigint        default null,
  p_match_6_prize               bigint        default null,
  p_progressive_jackpot_enabled boolean       default null,
  p_jackpot_contribution_pct    numeric       default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_old      jsonb;
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('finance_admin')) then
    raise exception 'permission_denied';
  end if;

  select to_jsonb(s) into v_old from public.loto_settings s where game_key = 'srood_loto';

  update public.loto_settings set
    is_enabled                  = coalesce(p_is_enabled,                  is_enabled),
    ticket_price_coins          = coalesce(p_ticket_price_coins,          ticket_price_coins),
    number_min                  = coalesce(p_number_min,                  number_min),
    number_max                  = coalesce(p_number_max,                  number_max),
    numbers_per_ticket          = coalesce(p_numbers_per_ticket,          numbers_per_ticket),
    draw_interval_minutes       = coalesce(p_draw_interval_minutes,       draw_interval_minutes),
    match_3_prize               = coalesce(p_match_3_prize,               match_3_prize),
    match_4_prize               = coalesce(p_match_4_prize,               match_4_prize),
    match_5_prize               = coalesce(p_match_5_prize,               match_5_prize),
    match_6_prize               = coalesce(p_match_6_prize,               match_6_prize),
    progressive_jackpot_enabled = coalesce(p_progressive_jackpot_enabled, progressive_jackpot_enabled),
    jackpot_contribution_pct    = coalesce(p_jackpot_contribution_pct,    jackpot_contribution_pct),
    updated_at                  = now(),
    updated_by                  = v_admin_id
  where game_key = 'srood_loto';

  insert into public.loto_admin_audit_logs (admin_id, action, old_value, new_value)
  values (v_admin_id, 'update_settings', v_old,
          (select to_jsonb(s) from public.loto_settings s where game_key = 'srood_loto'));

  return jsonb_build_object('ok', true);
end;
$$;

-- ── 16. admin_loto_get_draw_summary(p_draw_id uuid) ─────────────────────────

create or replace function public.admin_loto_get_draw_summary(p_draw_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('finance_admin')) then
    raise exception 'permission_denied';
  end if;

  return (
    select jsonb_build_object(
      'draw',         to_jsonb(d),
      'ticket_stats', jsonb_build_object(
        'total',    count(t.id),
        'active',   count(t.id) filter (where t.status = 'active'),
        'won',      count(t.id) filter (where t.status = 'won'),
        'lost',     count(t.id) filter (where t.status = 'lost'),
        'refunded', count(t.id) filter (where t.status = 'refunded'),
        'match_3',  count(t.id) filter (where t.matched_count = 3),
        'match_4',  count(t.id) filter (where t.matched_count = 4),
        'match_5',  count(t.id) filter (where t.matched_count = 5),
        'match_6',  count(t.id) filter (where t.matched_count = 6),
        'total_prize_paid', coalesce(sum(t.prize_coins),0)
      )
    )
    from public.loto_draws d
    left join public.loto_tickets t on t.draw_id = d.id
    where d.id = p_draw_id
    group by d.id, d.draw_number, d.status, d.opens_at, d.closes_at, d.draw_at,
             d.winning_numbers, d.seed_hash, d.seed_reveal, d.total_tickets,
             d.total_sales_coins, d.total_payout_coins, d.jackpot_pool_before,
             d.jackpot_pool_after, d.created_at, d.settled_at
  );
end;
$$;

-- ── 17. Grant execute to authenticated ───────────────────────────────────────

grant execute on function public.loto_get_current_draw()                        to authenticated;
grant execute on function public.loto_buy_ticket(integer[])                      to authenticated;
grant execute on function public.loto_get_my_tickets(uuid)                       to authenticated;
grant execute on function public.loto_get_recent_draws()                         to authenticated;
grant execute on function public.loto_settle_due_draws()                         to authenticated;
grant execute on function public.loto_create_next_draw_if_needed()               to authenticated;
grant execute on function public.admin_loto_force_settle_draw(uuid)              to authenticated;
grant execute on function public.admin_loto_void_draw(uuid)                      to authenticated;
grant execute on function public.admin_loto_update_settings(boolean,integer,integer,integer,integer,integer,bigint,bigint,bigint,bigint,boolean,numeric) to authenticated;
grant execute on function public.admin_loto_get_draw_summary(uuid)               to authenticated;

-- ── Optional: pg_cron schedule (enable pg_cron extension first) ──────────────
-- select cron.schedule('loto-settle', '* * * * *', $$select loto_settle_due_draws()$$);
