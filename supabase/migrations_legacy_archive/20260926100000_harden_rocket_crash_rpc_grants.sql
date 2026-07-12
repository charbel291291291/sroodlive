-- ============================================================
-- Harden Rocket Crash RPC grants and refund safety
-- ============================================================
-- Revoke direct anon/authenticated access from legacy and
-- server-controlled Rocket Crash RPCs.
--
-- Keep refund_crash_bet callable by authenticated users only,
-- but make it refundable only while bet status is pending.
-- ============================================================

revoke execute on function public.arm_crash_bet(integer, integer) from public;
revoke execute on function public.arm_crash_bet(integer, integer) from anon;
revoke execute on function public.arm_crash_bet(integer, integer) from authenticated;

revoke execute on function public.cashout_crash_bet(uuid) from public;
revoke execute on function public.cashout_crash_bet(uuid) from anon;
revoke execute on function public.cashout_crash_bet(uuid) from authenticated;

revoke execute on function public.cashout_crash_bet_local(uuid, numeric) from public;
revoke execute on function public.cashout_crash_bet_local(uuid, numeric) from anon;
revoke execute on function public.cashout_crash_bet_local(uuid, numeric) from authenticated;

revoke execute on function public.settle_rocket_crash_round(uuid) from public;
revoke execute on function public.settle_rocket_crash_round(uuid) from anon;
revoke execute on function public.settle_rocket_crash_round(uuid) from authenticated;

revoke execute on function public.start_rocket_crash_flight(uuid) from public;
revoke execute on function public.start_rocket_crash_flight(uuid) from anon;
revoke execute on function public.start_rocket_crash_flight(uuid) from authenticated;

-- refund_crash_bet is still used by Flutter, so keep authenticated access only.
revoke execute on function public.refund_crash_bet(uuid) from public;
revoke execute on function public.refund_crash_bet(uuid) from anon;

create or replace function public.refund_crash_bet(p_bet_id uuid)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid         uuid := auth.uid();
  v_bet         crash_bets;
  v_new_balance integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_bet
  from public.crash_bets
  where id = p_bet_id
    and user_id = v_uid
  for update;

  if not found then
    raise exception 'bet_not_found';
  end if;

  -- Refund is only allowed before flight starts.
  -- The previous version allowed 'running', which could refund during flight.
  if v_bet.status <> 'pending' then
    raise exception 'not_refundable';
  end if;

  update public.wallets
  set coins_balance = coins_balance + v_bet.bet_amount
  where user_id = v_uid
  returning coins_balance into v_new_balance;

  update public.crash_bets
  set status = 'refunded'
  where id = p_bet_id;

  return json_build_object(
    'refunded_amount', v_bet.bet_amount,
    'new_balance', v_new_balance
  );
end;
$function$;

grant execute on function public.refund_crash_bet(uuid) to authenticated;