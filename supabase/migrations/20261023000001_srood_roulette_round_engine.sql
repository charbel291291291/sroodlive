-- =============================================================================
-- Srood Roulette round engine.
--
-- The foundation migration (20261023000000) created tables, RLS, and the
-- read/bet RPCs, but nothing ever opened a round, closed betting, spun a
-- number, or settled bets. This adds:
--   - public.roulette_is_red(int) — European roulette red-number lookup.
--   - public.settle_roulette_round(uuid) — resolves every active bet for a
--     round against the winning number and pays out via public.wallets.
--   - public.advance_roulette_round() — state machine driving
--     betting_open -> locked -> spinning -> settled, then opens the next
--     round. Scheduled via pg_cron, mirroring the Fish Hunt / Rocket Crash
--     auto-advance pattern.
-- All wallet-affecting work stays inside SECURITY DEFINER functions with
-- set search_path = '' and fully-qualified public.* references.
-- =============================================================================

create or replace function public.roulette_is_red(p_number int)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_number = any (array[
    1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36
  ]);
$$;

revoke all on function public.roulette_is_red(int)
  from public, anon, authenticated;
grant execute on function public.roulette_is_red(int) to authenticated;

-- ── Settlement ───────────────────────────────────────────────────────────────

create or replace function public.settle_roulette_round(p_round_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round   public.roulette_rounds;
  v_bet     record;
  v_is_win  boolean;
  v_payout  bigint;
  v_new_bal bigint;
begin
  select *
  into v_round
  from public.roulette_rounds
  where id = p_round_id
  for update;

  if not found or v_round.status <> 'spinning' or v_round.winning_number is null then
    return;
  end if;

  for v_bet in
    select *
    from public.roulette_bets
    where round_id = p_round_id
      and status = 'active'
    for update
  loop
    v_is_win := case v_bet.bet_zone
      when 'straight_zero' then v_round.winning_number = 0
      when 'low'           then v_round.winning_number between 1 and 12
      when 'mid'           then v_round.winning_number between 13 and 24
      when 'high'          then v_round.winning_number between 25 and 36
      when 'red'           then public.roulette_is_red(v_round.winning_number)
      when 'black'         then v_round.winning_number <> 0
                                 and not public.roulette_is_red(v_round.winning_number)
      when 'even'          then v_round.winning_number <> 0
                                 and v_round.winning_number % 2 = 0
      when 'odd'           then v_round.winning_number <> 0
                                 and v_round.winning_number % 2 = 1
      else false
    end;

    if v_is_win then
      v_payout := floor(v_bet.bet_amount * v_bet.payout_multiplier)::bigint;

      update public.wallets
      set coins_balance = coins_balance + v_payout,
          updated_at = now()
      where user_id = v_bet.user_id
      returning coins_balance into v_new_bal;

      insert into public.wallet_transactions (
        user_id, type, direction, coins_delta, diamonds_delta,
        balance_coins_after, note, metadata
      )
      values (
        v_bet.user_id, 'roulette_win', 'credit', v_payout, 0,
        v_new_bal, 'Srood Roulette win',
        jsonb_build_object(
          'round_id', p_round_id, 'bet_id', v_bet.id,
          'bet_zone', v_bet.bet_zone, 'winning_number', v_round.winning_number
        )
      );

      update public.roulette_bets
      set status = 'won',
          payout_amount = v_payout
      where id = v_bet.id;
    else
      update public.roulette_bets
      set status = 'lost',
          payout_amount = 0
      where id = v_bet.id;
    end if;
  end loop;

  update public.roulette_rounds
  set status = 'settled',
      settled_at = now()
  where id = p_round_id;
end;
$$;

revoke all on function public.settle_roulette_round(uuid)
  from public, anon, authenticated;

-- ── Advance / state machine ──────────────────────────────────────────────────

create or replace function public.advance_roulette_round()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round             public.roulette_rounds;
  v_betting_duration   constant interval := interval '15 seconds';
  v_spin_duration      constant interval := interval '4 seconds';
begin
  select *
  into v_round
  from public.roulette_rounds
  where status <> 'settled'
  order by created_at desc
  limit 1
  for update;

  if not found then
    insert into public.roulette_rounds (room_id, status, betting_closes_at)
    values (null, 'betting_open', now() + v_betting_duration);
    return;
  end if;

  if v_round.status = 'betting_open' and v_round.betting_closes_at <= now() then
    update public.roulette_rounds
    set status = 'locked'
    where id = v_round.id;
    return;
  end if;

  if v_round.status = 'locked' then
    update public.roulette_rounds
    set status = 'spinning',
        winning_number = floor(random() * 37)::int,
        server_seed_hash = encode(
          extensions.digest(extensions.gen_random_bytes(32), 'sha256'), 'hex'
        )
    where id = v_round.id;
    return;
  end if;

  if v_round.status = 'spinning'
     and v_round.started_at + v_betting_duration + v_spin_duration <= now() then
    perform public.settle_roulette_round(v_round.id);
    return;
  end if;
end;
$$;

revoke all on function public.advance_roulette_round()
  from public, anon, authenticated;

-- ── pg_cron auto-advance job ─────────────────────────────────────────────────
-- Mirrors fish_hunt_auto_advance / rocket_crash_auto_advance.

do $$
declare
  v_job_name text := 'roulette_auto_advance';
begin
  if not exists (
    select 1 from pg_catalog.pg_extension where extname = 'pg_cron'
  ) then
    raise notice 'pg_cron not available — Roulette auto-advance will need manual/cron setup';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = v_job_name) then
    perform cron.unschedule(v_job_name);
  end if;

  begin
    perform cron.schedule(
      v_job_name,
      '3 seconds',
      $cron$ select public.advance_roulette_round(); $cron$
    );
    raise notice 'Roulette auto-advance cron job scheduled (every 3 seconds)';
  exception when others then
    perform cron.schedule(
      v_job_name,
      '* * * * *',
      $cron$ select public.advance_roulette_round(); $cron$
    );
    raise notice 'Roulette auto-advance cron job scheduled (every minute — seconds syntax unavailable)';
  end;
end;
$$;
