-- Crash Rocket V3: deterministic fairness and atomic player wallet actions.

alter table public.wallet_transactions drop constraint if exists wallet_transactions_type_check;
alter table public.wallet_transactions add constraint wallet_transactions_type_check check (
  type = any (array[
    'recharge_request','admin_adjustment','gift_sent','gift_received',
    'agency_recharge','refund','system','withdrawal','withdrawal_refund',
    'agency_commission','red_envelope_sent','red_envelope_claimed',
    'hungry_cat_bet','hungry_cat_reward','hungry_cat_refund',
    'gold_ladder_entry','gold_ladder_win','gold_ladder_safe_payout',
    'crash_rocket_bet','crash_rocket_win','crash_rocket_refund',
    'room_game_bet','room_game_win','room_game_refund',
    'srood_loto_ticket','srood_treasure_entry','srood_treasure_win',
    'blocks_play','daily_reward','magic_srood_bet','magic_srood_reward',
    'magic_srood_refund','crash_v3_bet','crash_v3_win',
    'crash_v3_refund','crash_v3_adjustment'
  ])
);

create or replace function public.crash_v3_seed_hash(p_server_seed text)
returns text language sql immutable parallel safe
set search_path = '' as $$
  select encode(extensions.digest(convert_to(p_server_seed, 'UTF8'), 'sha256'), 'hex')
$$;

create or replace function public.crash_v3_result_hash(
  p_server_seed text, p_client_seed text, p_nonce bigint
) returns text language sql immutable parallel safe
set search_path = '' as $$
  select encode(extensions.hmac(
    convert_to(p_client_seed || ':' || p_nonce::text, 'UTF8'),
    convert_to(p_server_seed, 'UTF8'), 'sha256'), 'hex')
$$;

create or replace function public.crash_v3_multiplier_from_hash(
  p_result_hash text, p_house_edge_bps integer, p_maximum_multiplier numeric
) returns numeric language plpgsql immutable parallel safe
set search_path = '' as $$
declare
  v_integer numeric;
  v_u numeric;
  v_result numeric;
begin
  if p_result_hash !~ '^[0-9a-f]{64}$'
     or p_house_edge_bps not between 0 and 2500
     or p_maximum_multiplier < 1.01 then
    raise exception 'invalid_fairness_input';
  end if;
  -- First 52 bits are exactly representable. Dividing by 2^52 maps uniformly
  -- to [0,1) without modulo reduction or modulo bias.
  v_integer := ('x' || substr(p_result_hash, 1, 13))::bit(52)::bigint;
  v_u := v_integer / 4503599627370496::numeric;
  v_result := (1 - p_house_edge_bps / 10000.0) / (1 - v_u);
  return greatest(1.00, least(p_maximum_multiplier, floor(v_result * 100) / 100));
end $$;

create or replace function public.crash_v3_calculate_multiplier(
  p_flight_started_at timestamptz, p_growth_rate numeric,
  p_at timestamptz, p_maximum_multiplier numeric
) returns numeric language sql stable parallel safe
set search_path = '' as $$
  select greatest(1.00, least(p_maximum_multiplier,
    floor(exp(p_growth_rate * greatest(0, extract(epoch from p_at - p_flight_started_at))) * 100) / 100))
$$;

revoke all on function public.crash_v3_seed_hash(text) from public, anon, authenticated;
revoke all on function public.crash_v3_result_hash(text,text,bigint) from public, anon, authenticated;
revoke all on function public.crash_v3_multiplier_from_hash(text,integer,numeric) from public, anon, authenticated;
revoke all on function public.crash_v3_calculate_multiplier(timestamptz,numeric,timestamptz,numeric) from public, anon, authenticated;

create or replace function public.crash_v3_get_state()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_round public.crash_v3_rounds;
  v_settings public.crash_v3_settings;
begin
  if v_user is null then raise exception 'authentication_required'; end if;
  select * into v_settings from public.crash_v3_settings where singleton;
  select * into v_round from public.crash_v3_rounds
   where status <> 'settled' and status <> 'cancelled'
   order by created_at desc limit 1;
  if not found then
    select * into v_round from public.crash_v3_rounds order by created_at desc limit 1;
  end if;
  return jsonb_build_object(
    'server_time', clock_timestamp(),
    'settings', jsonb_build_object(
      'game_enabled', v_settings.game_enabled,
      'maintenance_mode', v_settings.maintenance_mode,
      'emergency_stop', v_settings.emergency_stop,
      'minimum_bet', v_settings.minimum_bet,
      'maximum_bet', v_settings.maximum_bet,
      'maximum_payout_per_bet', v_settings.maximum_payout_per_bet,
      'betting_duration_ms', v_settings.betting_duration_ms,
      'maximum_multiplier', v_settings.maximum_multiplier,
      'default_growth_rate', v_settings.default_growth_rate
    ),
    'current_round', case when v_round.id is null then null else jsonb_build_object(
      'id', v_round.id, 'public_round_id', v_round.public_round_id,
      'status', v_round.status, 'starts_at', v_round.starts_at,
      'betting_opens_at', v_round.betting_opens_at,
      'betting_closes_at', v_round.betting_closes_at,
      'flight_started_at', v_round.flight_started_at,
      'crashed_at', v_round.crashed_at,
      'settled_at', v_round.settled_at,
      'crash_multiplier', case when v_round.status in ('crashed','settling','settled','cancelled') then v_round.crash_multiplier end,
      'server_seed_hash', v_round.server_seed_hash,
      'revealed_server_seed', case when v_round.status in ('settled','cancelled') then v_round.revealed_server_seed end,
      'client_seed', v_round.client_seed, 'nonce', v_round.nonce,
      'result_hash', case when v_round.status in ('settled','cancelled') then v_round.result_hash end,
      'growth_rate', v_round.growth_rate,
      'event_sequence', coalesce((select max(event_sequence) from public.crash_v3_round_events where round_id=v_round.id),0)
    ) end,
    'my_bets', coalesce((select jsonb_agg(to_jsonb(b) - 'user_id' order by b.slot_number)
      from public.crash_v3_bets b where b.round_id=v_round.id and b.user_id=v_user), '[]'::jsonb),
    'recent_history', coalesce((select jsonb_agg(x.item order by x.created_at desc) from (
      select r.created_at, jsonb_build_object('id',r.id,'public_round_id',r.public_round_id,
        'crash_multiplier',r.crash_multiplier,'settled_at',r.settled_at,
        'server_seed_hash',r.server_seed_hash) item
      from public.crash_v3_rounds r where r.status='settled'
      order by r.created_at desc limit 20) x), '[]'::jsonb)
  );
end $$;

create or replace function public.crash_v3_place_bet(
  p_round_id uuid, p_slot_number integer, p_bet_amount bigint,
  p_auto_cashout_multiplier numeric, p_idempotency_key text
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_now timestamptz := clock_timestamp();
  v_settings public.crash_v3_settings; v_round public.crash_v3_rounds;
  v_bet public.crash_v3_bets; v_wallet public.wallets;
  v_tx uuid := extensions.gen_random_uuid();
begin
  if v_user is null then raise exception 'authentication_required'; end if;
  if p_slot_number not in (1,2) or p_idempotency_key is null or length(p_idempotency_key) not between 16 and 128 then
    raise exception 'invalid_request'; end if;
  select * into v_bet from public.crash_v3_bets where user_id=v_user and idempotency_key=p_idempotency_key;
  if found then return jsonb_build_object('bet',to_jsonb(v_bet)-'user_id','idempotent',true); end if;
  if (select count(*) from public.crash_v3_audit_logs where actor_user_id=v_user and action='place_bet'
      and created_at > v_now - interval '1 second') >= 5 then raise exception 'rate_limited'; end if;
  select * into v_settings from public.crash_v3_settings where singleton for update;
  if not v_settings.game_enabled or v_settings.maintenance_mode or v_settings.emergency_stop then raise exception 'game_unavailable'; end if;
  if p_bet_amount < v_settings.minimum_bet or p_bet_amount > v_settings.maximum_bet then raise exception 'bet_out_of_range'; end if;
  if p_auto_cashout_multiplier is not null and (p_auto_cashout_multiplier < 1.01 or p_auto_cashout_multiplier > v_settings.maximum_multiplier) then raise exception 'auto_cashout_out_of_range'; end if;
  select * into v_round from public.crash_v3_rounds where id=p_round_id for update;
  if not found or v_round.status <> 'betting' or v_now < v_round.betting_opens_at or v_now >= v_round.betting_closes_at then raise exception 'betting_closed'; end if;
  if v_round.total_wagered + p_bet_amount > v_settings.maximum_total_round_exposure then raise exception 'round_exposure_limit'; end if;
  insert into public.crash_v3_daily_user_limits(user_id,limit_date) values(v_user,(v_now at time zone 'UTC')::date)
    on conflict do nothing;
  perform 1 from public.crash_v3_daily_user_limits where user_id=v_user and limit_date=(v_now at time zone 'UTC')::date for update;
  if (select wagered_amount+p_bet_amount from public.crash_v3_daily_user_limits where user_id=v_user and limit_date=(v_now at time zone 'UTC')::date) > v_settings.daily_user_wager_limit then raise exception 'daily_wager_limit'; end if;
  if (select lost_amount+p_bet_amount from public.crash_v3_daily_user_limits where user_id=v_user and limit_date=(v_now at time zone 'UTC')::date) > v_settings.daily_user_loss_limit then raise exception 'daily_loss_limit'; end if;
  select * into v_wallet from public.wallets where user_id=v_user for update;
  if not found or v_wallet.coins_balance < p_bet_amount then raise exception 'insufficient_balance'; end if;
  update public.wallets set coins_balance=coins_balance-p_bet_amount,
    lifetime_coins_spent=lifetime_coins_spent+p_bet_amount,updated_at=v_now where user_id=v_user;
  insert into public.wallet_transactions(id,user_id,type,direction,coins_delta,balance_coins_after,note,metadata)
  values(v_tx,v_user,'crash_v3_bet','debit',-p_bet_amount,v_wallet.coins_balance-p_bet_amount,
    'Crash V3 bet',jsonb_build_object('round_id',p_round_id,'slot_number',p_slot_number,'idempotency_key',p_idempotency_key));
  insert into public.crash_v3_bets(round_id,user_id,slot_number,bet_amount,auto_cashout_multiplier,status,
    accepted_at,idempotency_key,client_request_id,wallet_transaction_id)
  values(p_round_id,v_user,p_slot_number,p_bet_amount,p_auto_cashout_multiplier,'accepted',v_now,
    p_idempotency_key,p_idempotency_key,v_tx) returning * into v_bet;
  update public.crash_v3_rounds set total_wagered=total_wagered+p_bet_amount,bet_count=bet_count+1,updated_at=v_now where id=p_round_id;
  update public.crash_v3_daily_user_limits set wagered_amount=wagered_amount+p_bet_amount,
    bet_count=bet_count+1,updated_at=v_now where user_id=v_user and limit_date=(v_now at time zone 'UTC')::date;
  insert into public.crash_v3_audit_logs(actor_user_id,actor_role,action,round_id,bet_id,after_data,request_id)
    values(v_user,'authenticated','place_bet',p_round_id,v_bet.id,jsonb_build_object('amount',p_bet_amount,'wallet_transaction_id',v_tx),p_idempotency_key);
  return jsonb_build_object('bet',to_jsonb(v_bet)-'user_id','wallet_balance',v_wallet.coins_balance-p_bet_amount,'idempotent',false);
exception when unique_violation then
  select * into v_bet from public.crash_v3_bets where user_id=v_user and idempotency_key=p_idempotency_key;
  if found then return jsonb_build_object('bet',to_jsonb(v_bet)-'user_id','idempotent',true); end if;
  raise exception 'bet_slot_already_used';
end $$;

create or replace function public.crash_v3_cashout(p_bet_id uuid,p_idempotency_key text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_user uuid:=auth.uid(); v_now timestamptz:=clock_timestamp(); v_bet public.crash_v3_bets;
  v_round public.crash_v3_rounds; v_settings public.crash_v3_settings;
  v_multiplier numeric; v_payout bigint; v_balance integer; v_tx uuid:=extensions.gen_random_uuid(); v_sequence bigint;
begin
  if v_user is null then raise exception 'authentication_required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 16 and 128 then raise exception 'invalid_request'; end if;
  select * into v_bet from public.crash_v3_bets where id=p_bet_id and user_id=v_user for update;
  if not found then raise exception 'bet_not_found'; end if;
  if v_bet.status='won' and v_bet.cashout_idempotency_key=p_idempotency_key then
    return jsonb_build_object('bet',to_jsonb(v_bet)-'user_id','idempotent',true); end if;
  if v_bet.status<>'accepted' then raise exception 'bet_not_cashout_eligible'; end if;
  select * into v_round from public.crash_v3_rounds where id=v_bet.round_id for update;
  if v_round.status<>'flying' or v_round.flight_started_at is null then raise exception 'round_not_flying'; end if;
  select * into v_settings from public.crash_v3_settings where singleton;
  v_multiplier:=public.crash_v3_calculate_multiplier(v_round.flight_started_at,v_round.growth_rate,v_now,v_round.maximum_multiplier);
  if v_multiplier>=v_round.crash_multiplier then raise exception 'too_late'; end if;
  v_payout:=least(v_settings.maximum_payout_per_bet,floor(v_bet.bet_amount*v_multiplier))::bigint;
  if v_payout>2000000000 then raise exception 'payout_overflow'; end if;
  select coins_balance into v_balance from public.wallets where user_id=v_user for update;
  if v_balance::bigint+v_payout>2147483647 then raise exception 'wallet_balance_limit'; end if;
  update public.wallets set coins_balance=coins_balance+v_payout,updated_at=v_now where user_id=v_user;
  insert into public.wallet_transactions(id,user_id,type,direction,coins_delta,balance_coins_after,note,metadata)
    values(v_tx,v_user,'crash_v3_win','credit',v_payout,v_balance+v_payout,'Crash V3 cash-out',
      jsonb_build_object('round_id',v_round.id,'bet_id',v_bet.id,'multiplier',v_multiplier,'idempotency_key',p_idempotency_key));
  update public.crash_v3_bets set status='won',cashout_requested_at=v_now,cashed_out_at=v_now,
    cashout_multiplier=v_multiplier,payout_amount=v_payout,payout_transaction_id=v_tx,
    cashout_idempotency_key=p_idempotency_key,updated_at=v_now where id=v_bet.id returning * into v_bet;
  update public.crash_v3_rounds set total_paid=total_paid+v_payout,cashout_count=cashout_count+1,updated_at=v_now where id=v_round.id;
  update public.crash_v3_daily_user_limits set paid_amount=paid_amount+v_payout,updated_at=v_now
    where user_id=v_user and limit_date=(v_now at time zone 'UTC')::date;
  select coalesce(max(event_sequence),0)+1 into v_sequence from public.crash_v3_round_events where round_id=v_round.id;
  insert into public.crash_v3_round_events(round_id,event_type,event_sequence,event_payload,engine_instance_id)
    values(v_round.id,'cashout_confirmed',v_sequence,
      jsonb_build_object('multiplier',v_multiplier),v_round.engine_instance_id);
  insert into public.crash_v3_audit_logs(actor_user_id,actor_role,action,round_id,bet_id,after_data,request_id)
    values(v_user,'authenticated','cashout',v_round.id,v_bet.id,jsonb_build_object('payout',v_payout,'multiplier',v_multiplier,'wallet_transaction_id',v_tx),p_idempotency_key);
  return jsonb_build_object('bet',to_jsonb(v_bet)-'user_id','wallet_balance',v_balance+v_payout,'idempotent',false);
end $$;

create or replace function public.crash_v3_get_my_history(p_limit integer default 20,p_cursor timestamptz default null)
returns jsonb language sql security definer stable set search_path=public,pg_temp as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (
    select b.id,b.round_id,r.public_round_id,b.slot_number,b.bet_amount,b.auto_cashout_multiplier,
      b.cashout_multiplier,b.payout_amount,b.status,b.created_at
    from public.crash_v3_bets b join public.crash_v3_rounds r on r.id=b.round_id
    where b.user_id=auth.uid() and (p_cursor is null or b.created_at<p_cursor)
    order by b.created_at desc limit least(greatest(p_limit,1),100)) x
$$;

create or replace function public.crash_v3_get_round_history(p_limit integer default 20,p_cursor timestamptz default null)
returns jsonb language sql security definer stable set search_path=public,pg_temp as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (
    select id,public_round_id,status,crash_multiplier,server_seed_hash,revealed_server_seed,
      client_seed,nonce,result_hash,settled_at,created_at
    from public.crash_v3_rounds where status in ('settled','cancelled')
      and (p_cursor is null or created_at<p_cursor)
    order by created_at desc limit least(greatest(p_limit,1),100)) x
$$;

create or replace function public.crash_v3_verify_round(p_round_id uuid)
returns jsonb language plpgsql security definer stable set search_path=public,pg_temp as $$
declare v_round public.crash_v3_rounds; v_hash text; v_multiplier numeric;
begin
  select * into v_round from public.crash_v3_rounds where id=p_round_id and status in ('settled','cancelled');
  if not found then raise exception 'round_not_revealed'; end if;
  v_hash:=public.crash_v3_result_hash(v_round.revealed_server_seed,v_round.client_seed,v_round.nonce);
  v_multiplier:=public.crash_v3_multiplier_from_hash(v_hash,v_round.house_edge_bps,v_round.maximum_multiplier);
  return jsonb_build_object('round_id',v_round.id,'public_round_id',v_round.public_round_id,
    'server_seed',v_round.revealed_server_seed,'server_seed_hash',v_round.server_seed_hash,
    'calculated_seed_hash',public.crash_v3_seed_hash(v_round.revealed_server_seed),
    'client_seed',v_round.client_seed,'nonce',v_round.nonce,'result_hash',v_round.result_hash,
    'calculated_result_hash',v_hash,'crash_multiplier',v_round.crash_multiplier,
    'calculated_crash_multiplier',v_multiplier,
    'verified',v_hash=v_round.result_hash and v_multiplier=v_round.crash_multiplier
      and public.crash_v3_seed_hash(v_round.revealed_server_seed)=v_round.server_seed_hash);
end $$;

revoke all on function public.crash_v3_get_state() from public,anon;
revoke all on function public.crash_v3_place_bet(uuid,integer,bigint,numeric,text) from public,anon;
revoke all on function public.crash_v3_cashout(uuid,text) from public,anon;
revoke all on function public.crash_v3_get_my_history(integer,timestamptz) from public,anon;
revoke all on function public.crash_v3_get_round_history(integer,timestamptz) from public,anon;
revoke all on function public.crash_v3_verify_round(uuid) from public,anon;
grant execute on function public.crash_v3_get_state() to authenticated;
grant execute on function public.crash_v3_place_bet(uuid,integer,bigint,numeric,text) to authenticated;
grant execute on function public.crash_v3_cashout(uuid,text) to authenticated;
grant execute on function public.crash_v3_get_my_history(integer,timestamptz) to authenticated;
grant execute on function public.crash_v3_get_round_history(integer,timestamptz) to authenticated;
grant execute on function public.crash_v3_verify_round(uuid) to authenticated;

comment on function public.crash_v3_multiplier_from_hash(text,integer,numeric) is
  'Crash formula: floor(min(cap,max(1,(1-edge)/(1-u)))*100)/100; u is the unbiased first 52 HMAC bits divided by 2^52.';
