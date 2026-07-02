-- ────────────────────────────────────────────────────────────────────────────
-- Spin Wheel — server-authoritative RPC (the client-called spin_wheel() never
-- existed in migrations, leaving the game non-functional). This adds:
--   * a server-owned prize catalog (weights + rewards),
--   * an audit / idempotency ledger,
--   * spin_wheel(): the ONLY place a spin is decided, coins are debited, and a
--     reward is credited. The client is never trusted for the result or payout.
--
-- Security model (why each choice):
--   * SECURITY DEFINER + explicit search_path so the function runs as the owner
--     with a fixed schema resolution and cannot be hijacked by a rogue
--     search_path.
--   * The wheel outcome and reward are computed from the server-owned
--     spin_wheel_prizes table. The client's local _kPrizes list is display-only;
--     it never tells the server which segment won or how much to pay.
--   * The spin cost is debited atomically (`coins_balance >= cost` in the same
--     UPDATE) so a client can never spin without enough coins or race a debit.
--   * Idempotent on (user_id, client_spin_id): a retried spin returns the
--     original result and never double-charges or double-pays. An advisory xact
--     lock serializes concurrent duplicates so the "already spun?" check is safe.
--   * Direct table writes are revoked from anon/authenticated; only the
--     SECURITY DEFINER RPC (running as owner) mutates wallets and the ledger.
-- ────────────────────────────────────────────────────────────────────────────


-- ── 1. Allow spin-wheel wallet-transaction types ────────────────────────────
-- Recreate the full enum with the two new spin types appended. The complete
-- list is reproduced verbatim so this is deterministic on a fresh deploy too.
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
      'roulette_bet','roulette_win','roulette_refund',
      'spin_wheel_bet','spin_wheel_reward'
    ])
  );


-- ── 2. Server-owned prize catalog ───────────────────────────────────────────
-- Labels MUST match the client's _kPrizes labels exactly — the client renders
-- the wheel from its local list and locates the winning segment by label.
create table if not exists public.spin_wheel_prizes (
  label         text primary key,
  weight        integer not null check (weight > 0),
  reward_kind   text    not null check (reward_kind in ('coins','diamonds','none')),
  reward_amount integer not null default 0 check (reward_amount >= 0),
  sort_order    integer not null,
  is_active     boolean not null default true
);

alter table public.spin_wheel_prizes enable row level security;
-- No client access: outcomes are server-decided; the client already has its own
-- display list. Only the SECURITY DEFINER RPC (as owner) reads this table.
revoke all on public.spin_wheel_prizes from anon, authenticated, public;

comment on table public.spin_wheel_prizes is
  'Server-authoritative Spin Wheel prize table (weights + rewards). Never '
  'client-readable; the winning segment and payout are decided here.';

insert into public.spin_wheel_prizes (label, weight, reward_kind, reward_amount, sort_order) values
  ('10 coins',   30, 'coins',      10, 1),
  ('50 coins',   25, 'coins',      50, 2),
  ('5 diamonds', 20, 'diamonds',    5, 3),
  ('100 coins',  12, 'coins',     100, 4),
  ('20 diamonds', 7, 'diamonds',   20, 5),
  ('500 coins',   4, 'coins',     500, 6),
  ('Try again',  15, 'none',        0, 7),
  ('1000 coins',  2, 'coins',    1000, 8)
on conflict (label) do nothing;


-- ── 3. Spin ledger (audit + idempotency) ────────────────────────────────────
create table if not exists public.spin_wheel_spins (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  client_spin_id text,                       -- caller-supplied idempotency key
  prize_label    text not null,
  cost           integer not null,
  coins_delta    integer not null default 0, -- net coins (reward - cost view: reward only here)
  diamonds_delta integer not null default 0,
  created_at     timestamptz not null default now(),
  -- One settled spin per (user, client_spin_id): the idempotency guard.
  constraint spin_wheel_spins_client_id_unique unique (user_id, client_spin_id)
);

create index if not exists spin_wheel_spins_user_idx
  on public.spin_wheel_spins (user_id, created_at desc);

alter table public.spin_wheel_spins enable row level security;
-- Users may read their own spin history; all writes go through the RPC only.
drop policy if exists "spin_wheel_spins_select_own" on public.spin_wheel_spins;
create policy "spin_wheel_spins_select_own"
  on public.spin_wheel_spins for select to authenticated
  using (user_id = auth.uid());
revoke all on public.spin_wheel_spins from anon, authenticated, public;
grant select on public.spin_wheel_spins to authenticated;

comment on table public.spin_wheel_spins is
  'Spin Wheel audit + idempotency ledger. Read-own-rows only; writes via the '
  'spin_wheel RPC (SECURITY DEFINER). Unique (user_id, client_spin_id) prevents '
  'double-charge / double-pay on a retried spin.';


-- ── 4. spin_wheel(client_spin_id) — the authoritative spin ──────────────────
-- Returns a single row (client calls `.rpc('spin_wheel').single()`), shaped so
-- the existing Flutter screen keeps working: prize_label + new_coins_balance,
-- plus the reward breakdown.
create or replace function public.spin_wheel(
  p_client_spin_id text default null
)
returns table (
  prize_label          text,
  coins_won            integer,
  diamonds_won         integer,
  new_coins_balance    integer,
  new_diamonds_balance integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  c_spin_cost  constant integer := 50;   -- authoritative cost (client _kSpinCost)
  v_existing   public.spin_wheel_spins;
  v_prize      public.spin_wheel_prizes;
  v_total      integer;
  v_roll       integer;
  v_coins_bal  integer;
  v_diamonds_bal integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- Serialize concurrent duplicates so the idempotency check below is race-free.
  -- Keyed on user + client id (or just the user when no id is supplied).
  perform pg_advisory_xact_lock(
    hashtext('spin_wheel:' || v_uid::text || ':' || coalesce(p_client_spin_id, ''))
  );

  -- Idempotent replay: same (user, client_spin_id) returns the original result
  -- with the CURRENT balances — no second debit, no second payout.
  if p_client_spin_id is not null then
    select * into v_existing
    from public.spin_wheel_spins
    where user_id = v_uid and client_spin_id = p_client_spin_id;

    if v_existing.id is not null then
      select coins_balance, diamonds_balance into v_coins_bal, v_diamonds_bal
      from public.wallets where user_id = v_uid;
      return query select
        v_existing.prize_label,
        greatest(v_existing.coins_delta, 0),
        greatest(v_existing.diamonds_delta, 0),
        coalesce(v_coins_bal, 0),
        coalesce(v_diamonds_bal, 0);
      return;
    end if;
  end if;

  -- ── Debit the spin cost atomically (only if the balance covers it) ─────────
  update public.wallets
  set coins_balance        = coins_balance - c_spin_cost,
      lifetime_coins_spent = lifetime_coins_spent + c_spin_cost,
      updated_at           = now()
  where user_id = v_uid
    and coins_balance >= c_spin_cost
  returning coins_balance, diamonds_balance into v_coins_bal, v_diamonds_bal;

  if not found then
    raise exception 'insufficient_coins';
  end if;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta,
     balance_coins_after, balance_diamonds_after, note, metadata)
  values
    (v_uid, 'spin_wheel_bet', 'debit', -c_spin_cost, 0,
     v_coins_bal, v_diamonds_bal, 'Spin Wheel spin',
     jsonb_build_object('cost', c_spin_cost, 'client_spin_id', p_client_spin_id));

  -- ── Pick the winning segment server-side (weighted random) ────────────────
  select coalesce(sum(weight), 0) into v_total
  from public.spin_wheel_prizes where is_active;
  if v_total <= 0 then
    raise exception 'no_active_prizes';
  end if;

  v_roll := floor(random() * v_total)::integer;  -- 0 .. v_total-1

  select p.* into v_prize
  from (
    select *, sum(weight) over (order by sort_order
                                rows between unbounded preceding and current row) as cum
    from public.spin_wheel_prizes
    where is_active
  ) p
  where v_roll < p.cum
  order by p.sort_order
  limit 1;

  if v_prize.label is null then
    raise exception 'prize_selection_failed';
  end if;

  -- ── Credit the reward server-side (server catalog amount, never client) ────
  if v_prize.reward_kind = 'coins' and v_prize.reward_amount > 0 then
    update public.wallets
    set coins_balance = coins_balance + v_prize.reward_amount,
        updated_at    = now()
    where user_id = v_uid
    returning coins_balance, diamonds_balance into v_coins_bal, v_diamonds_bal;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta,
       balance_coins_after, balance_diamonds_after, note, metadata)
    values
      (v_uid, 'spin_wheel_reward', 'credit', v_prize.reward_amount, 0,
       v_coins_bal, v_diamonds_bal, 'Spin Wheel reward: ' || v_prize.label,
       jsonb_build_object('prize', v_prize.label, 'client_spin_id', p_client_spin_id));

  elsif v_prize.reward_kind = 'diamonds' and v_prize.reward_amount > 0 then
    update public.wallets
    set diamonds_balance         = diamonds_balance + v_prize.reward_amount,
        lifetime_diamonds_earned = lifetime_diamonds_earned + v_prize.reward_amount,
        updated_at               = now()
    where user_id = v_uid
    returning coins_balance, diamonds_balance into v_coins_bal, v_diamonds_bal;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta,
       balance_coins_after, balance_diamonds_after, note, metadata)
    values
      (v_uid, 'spin_wheel_reward', 'credit', 0, v_prize.reward_amount,
       v_coins_bal, v_diamonds_bal, 'Spin Wheel reward: ' || v_prize.label,
       jsonb_build_object('prize', v_prize.label, 'client_spin_id', p_client_spin_id));
  end if;
  -- 'none' (Try again) credits nothing.

  -- ── Record the settled spin (audit + idempotency) ─────────────────────────
  insert into public.spin_wheel_spins
    (user_id, client_spin_id, prize_label, cost, coins_delta, diamonds_delta)
  values
    (v_uid, p_client_spin_id, v_prize.label, c_spin_cost,
     case when v_prize.reward_kind = 'coins'    then v_prize.reward_amount else 0 end,
     case when v_prize.reward_kind = 'diamonds' then v_prize.reward_amount else 0 end);

  return query select
    v_prize.label,
    case when v_prize.reward_kind = 'coins'    then v_prize.reward_amount else 0 end,
    case when v_prize.reward_kind = 'diamonds' then v_prize.reward_amount else 0 end,
    coalesce(v_coins_bal, 0),
    coalesce(v_diamonds_bal, 0);
end;
$$;

-- Client-callable; not exposed to anon.
revoke all on function public.spin_wheel(text) from public, anon;
grant execute on function public.spin_wheel(text) to authenticated;

comment on function public.spin_wheel(text) is
  'Server-authoritative Spin Wheel: debits the cost, picks the weighted winning '
  'segment, credits the reward, and records an idempotent audit row. The only '
  'path that mutates wallets for a spin; the client is never trusted for result '
  'or payout.';
