-- Crash Rocket V3: trusted engine transitions, recovery, settlement and owner controls.

create or replace function public.crash_v3_append_event(
  p_round_id uuid,p_event_type text,p_payload jsonb,p_engine_instance_id text
) returns bigint language plpgsql security definer
set search_path=public,pg_temp as $$
declare v_sequence bigint;
begin
  perform 1 from public.crash_v3_rounds where id=p_round_id for update;
  select coalesce(max(event_sequence),0)+1 into v_sequence
    from public.crash_v3_round_events where round_id=p_round_id;
  insert into public.crash_v3_round_events(round_id,event_type,event_sequence,event_payload,engine_instance_id)
    values(p_round_id,p_event_type,v_sequence,coalesce(p_payload,'{}'::jsonb),p_engine_instance_id);
  return v_sequence;
end $$;

create or replace function public.crash_v3_engine_get_work(p_engine_instance_id text)
returns jsonb language plpgsql security definer
set search_path=public,pg_temp as $$
declare v_round public.crash_v3_rounds; v_lease public.crash_v3_engine_leases;
begin
  if auth.role()<>'service_role' then raise exception 'service_role_required'; end if;
  select * into v_lease from public.crash_v3_engine_leases where lease_key='primary';
  if found and v_lease.engine_instance_id<>p_engine_instance_id and v_lease.expires_at>clock_timestamp() then
    raise exception 'engine_lease_owned';
  end if;
  select * into v_round from public.crash_v3_rounds where status not in ('settled','cancelled') order by created_at desc limit 1;
  return jsonb_build_object('server_time',clock_timestamp(),'round',case when v_round.id is null then null else
    jsonb_build_object('id',v_round.id,'status',v_round.status,'encrypted_server_seed',v_round.encrypted_server_seed,
      'server_seed_hash',v_round.server_seed_hash,'client_seed',v_round.client_seed,'nonce',v_round.nonce) end);
end $$;

create or replace function public.crash_v3_refund_round_internal(
  p_round_id uuid,p_reason text,p_actor_role text,p_engine_instance_id text
) returns bigint language plpgsql security definer
set search_path=public,pg_temp as $$
declare v_bet public.crash_v3_bets; v_balance integer; v_tx uuid; v_total bigint:=0; v_now timestamptz:=clock_timestamp();
begin
  perform 1 from public.crash_v3_rounds where id=p_round_id for update;
  for v_bet in select * from public.crash_v3_bets where round_id=p_round_id and status='accepted' order by id for update loop
    select coins_balance into v_balance from public.wallets where user_id=v_bet.user_id for update;
    if v_balance::bigint+v_bet.bet_amount>2147483647 then raise exception 'wallet_balance_limit'; end if;
    v_tx:=extensions.gen_random_uuid();
    update public.wallets set coins_balance=coins_balance+v_bet.bet_amount,
      lifetime_coins_spent=greatest(0,lifetime_coins_spent-v_bet.bet_amount),updated_at=v_now where user_id=v_bet.user_id;
    insert into public.wallet_transactions(id,user_id,type,direction,coins_delta,balance_coins_after,note,metadata)
      values(v_tx,v_bet.user_id,'crash_v3_refund','credit',v_bet.bet_amount,v_balance+v_bet.bet_amount,
        'Crash V3 round refund',jsonb_build_object('round_id',p_round_id,'bet_id',v_bet.id,'reason',p_reason));
    update public.crash_v3_bets set status='refunded',refunded_at=v_now,payout_amount=v_bet.bet_amount,
      payout_transaction_id=v_tx,failure_reason=p_reason,updated_at=v_now where id=v_bet.id;
    v_total:=v_total+v_bet.bet_amount;
  end loop;
  update public.crash_v3_rounds set total_refunded=total_refunded+v_total,updated_at=v_now where id=p_round_id;
  insert into public.crash_v3_audit_logs(actor_user_id,actor_role,action,round_id,after_data)
    values(auth.uid(),p_actor_role,'refund_round',p_round_id,jsonb_build_object(
      'amount',v_total,'reason',p_reason,'engine_instance_id',p_engine_instance_id));
  return v_total;
end $$;

create or replace function public.crash_v3_engine_tick(
  p_engine_instance_id text,p_new_server_seed text default null,
  p_new_encrypted_server_seed text default null,p_current_server_seed text default null
) returns jsonb language plpgsql security definer
set search_path=public,pg_temp as $$
declare
  v_now timestamptz:=clock_timestamp(); v_settings public.crash_v3_settings;
  v_round public.crash_v3_rounds; v_bet public.crash_v3_bets; v_hash text; v_crash numeric;
  v_current numeric; v_payout bigint; v_balance integer; v_tx uuid; v_refunded bigint:=0;
  v_expected_debit bigint; v_actual_debit bigint; v_actual_credit bigint; v_actual_refund bigint;
  v_reconciliation_status text;
begin
  if auth.role()<>'service_role' then raise exception 'service_role_required'; end if;
  if p_engine_instance_id is null or length(p_engine_instance_id) not between 8 and 128 then raise exception 'invalid_engine_instance'; end if;
  if not pg_try_advisory_xact_lock(hashtextextended('crash-v3-engine',0)) then raise exception 'engine_busy'; end if;
  insert into public.crash_v3_engine_leases(lease_key,engine_instance_id,acquired_at,heartbeat_at,expires_at)
    values('primary',p_engine_instance_id,v_now,v_now,v_now+interval '15 seconds')
  on conflict(lease_key) do update set engine_instance_id=excluded.engine_instance_id,
    acquired_at=case when crash_v3_engine_leases.engine_instance_id=excluded.engine_instance_id then crash_v3_engine_leases.acquired_at else excluded.acquired_at end,
    heartbeat_at=excluded.heartbeat_at,expires_at=excluded.expires_at
  where crash_v3_engine_leases.engine_instance_id=excluded.engine_instance_id or crash_v3_engine_leases.expires_at<=v_now;
  if not exists(select 1 from public.crash_v3_engine_leases where lease_key='primary' and engine_instance_id=p_engine_instance_id) then raise exception 'engine_lease_owned'; end if;
  select * into v_settings from public.crash_v3_settings where singleton;
  select * into v_round from public.crash_v3_rounds where status not in ('settled','cancelled') order by created_at desc limit 1 for update;

  if not found then
    if not v_settings.game_enabled or v_settings.maintenance_mode or v_settings.emergency_stop then
      return jsonb_build_object('server_time',v_now,'status','disabled');
    end if;
    if p_new_server_seed is null or length(p_new_server_seed)<32 or p_new_encrypted_server_seed is null then raise exception 'new_seed_required'; end if;
    v_hash:=public.crash_v3_result_hash(p_new_server_seed,'srood-live-crash-v3',nextval('public.crash_v3_nonce_seq'));
    -- currval is used because nonce was consumed above exactly once in this session.
    v_crash:=public.crash_v3_multiplier_from_hash(v_hash,v_settings.house_edge_bps,v_settings.maximum_multiplier);
    insert into public.crash_v3_rounds(nonce,status,starts_at,betting_opens_at,betting_closes_at,
      crash_multiplier,server_seed_hash,encrypted_server_seed,client_seed,result_hash,growth_rate,
      house_edge_bps,maximum_multiplier,engine_instance_id)
    values(currval('public.crash_v3_nonce_seq'),'waiting',v_now,
      v_now+make_interval(secs=>v_settings.waiting_duration_ms/1000.0),
      v_now+make_interval(secs=>(v_settings.waiting_duration_ms+v_settings.betting_duration_ms)/1000.0),
      v_crash,public.crash_v3_seed_hash(p_new_server_seed),p_new_encrypted_server_seed,
      'srood-live-crash-v3',v_hash,v_settings.default_growth_rate,v_settings.house_edge_bps,
      v_settings.maximum_multiplier,p_engine_instance_id) returning * into v_round;
    perform public.crash_v3_append_event(v_round.id,'round_created',jsonb_build_object(
      'round_id',v_round.id,'public_round_id',v_round.public_round_id,'status','waiting',
      'starts_at',v_round.starts_at,'betting_opens_at',v_round.betting_opens_at,
      'betting_closes_at',v_round.betting_closes_at,'server_seed_hash',v_round.server_seed_hash),p_engine_instance_id);
    return jsonb_build_object('server_time',v_now,'round_id',v_round.id,'status',v_round.status);
  end if;

  if v_settings.emergency_stop or not v_settings.game_enabled then
    if v_round.status in ('waiting','betting','locked','flying','crashed','settling') then
      v_refunded:=public.crash_v3_refund_round_internal(v_round.id,'emergency_stop','service_role',p_engine_instance_id);
      if p_current_server_seed is not null and public.crash_v3_seed_hash(p_current_server_seed)=v_round.server_seed_hash then
        update public.crash_v3_rounds set revealed_server_seed=p_current_server_seed where id=v_round.id;
      end if;
      update public.crash_v3_rounds set status='cancelled',cancelled_at=v_now,failure_reason='emergency_stop',updated_at=v_now where id=v_round.id;
      perform public.crash_v3_append_event(v_round.id,'round_cancelled',jsonb_build_object('reason','emergency_stop','refunded',v_refunded),p_engine_instance_id);
    end if;
    return jsonb_build_object('server_time',v_now,'round_id',v_round.id,'status','cancelled');
  end if;

  if v_round.status='waiting' and v_now>=v_round.betting_opens_at then
    update public.crash_v3_rounds set status='betting',updated_at=v_now where id=v_round.id returning * into v_round;
    perform public.crash_v3_append_event(v_round.id,'betting_opened',jsonb_build_object('betting_closes_at',v_round.betting_closes_at),p_engine_instance_id);
  end if;
  if v_round.status='betting' and v_now>=v_round.betting_closes_at then
    update public.crash_v3_rounds set status='locked',updated_at=v_now where id=v_round.id returning * into v_round;
    perform public.crash_v3_append_event(v_round.id,'betting_locked','{}',p_engine_instance_id);
  end if;
  if v_round.status='locked' and v_now>=v_round.betting_closes_at+make_interval(secs=>v_settings.locked_duration_ms/1000.0) then
    update public.crash_v3_rounds set status='flying',flight_started_at=v_now,updated_at=v_now where id=v_round.id returning * into v_round;
    perform public.crash_v3_append_event(v_round.id,'flight_started',jsonb_build_object('flight_started_at',v_now,'growth_rate',v_round.growth_rate),p_engine_instance_id);
  end if;
  if v_round.status='flying' then
    v_current:=public.crash_v3_calculate_multiplier(v_round.flight_started_at,v_round.growth_rate,v_now,v_round.maximum_multiplier);
    for v_bet in select * from public.crash_v3_bets where round_id=v_round.id and status='accepted'
      and auto_cashout_multiplier is not null and auto_cashout_multiplier<=v_current
      and auto_cashout_multiplier<v_round.crash_multiplier order by id for update loop
      select coins_balance into v_balance from public.wallets where user_id=v_bet.user_id for update;
      v_payout:=least(v_settings.maximum_payout_per_bet,floor(v_bet.bet_amount*v_bet.auto_cashout_multiplier))::bigint;
      if v_balance::bigint+v_payout>2147483647 then raise exception 'wallet_balance_limit'; end if;
      v_tx:=extensions.gen_random_uuid();
      update public.wallets set coins_balance=coins_balance+v_payout,updated_at=v_now where user_id=v_bet.user_id;
      insert into public.wallet_transactions(id,user_id,type,direction,coins_delta,balance_coins_after,note,metadata)
        values(v_tx,v_bet.user_id,'crash_v3_win','credit',v_payout,v_balance+v_payout,'Crash V3 auto cash-out',
          jsonb_build_object('round_id',v_round.id,'bet_id',v_bet.id,'multiplier',v_bet.auto_cashout_multiplier));
      update public.crash_v3_bets set status='won',cashed_out_at=v_now,cashout_multiplier=auto_cashout_multiplier,
        payout_amount=v_payout,payout_transaction_id=v_tx,updated_at=v_now where id=v_bet.id;
      update public.crash_v3_rounds set total_paid=total_paid+v_payout,cashout_count=cashout_count+1,updated_at=v_now where id=v_round.id;
      update public.crash_v3_daily_user_limits set paid_amount=paid_amount+v_payout,updated_at=v_now
        where user_id=v_bet.user_id and limit_date=(v_now at time zone 'UTC')::date;
      perform public.crash_v3_append_event(v_round.id,'auto_cashout_confirmed',
        jsonb_build_object('multiplier',v_bet.auto_cashout_multiplier),p_engine_instance_id);
    end loop;
    if v_current>=v_round.crash_multiplier then
      update public.crash_v3_rounds set status='crashed',crashed_at=v_now,updated_at=v_now where id=v_round.id returning * into v_round;
      perform public.crash_v3_append_event(v_round.id,'round_crashed',jsonb_build_object('crash_multiplier',v_round.crash_multiplier,'crashed_at',v_now),p_engine_instance_id);
    end if;
  end if;
  if v_round.status='crashed' then
    update public.crash_v3_rounds set status='settling',settlement_started_at=v_now,updated_at=v_now where id=v_round.id returning * into v_round;
    perform public.crash_v3_append_event(v_round.id,'round_settling','{}',p_engine_instance_id);
  end if;
  if v_round.status='settling' then
    update public.crash_v3_bets set status='lost',updated_at=v_now where round_id=v_round.id and status='accepted';
    update public.crash_v3_daily_user_limits l set lost_amount=l.lost_amount+x.amount,updated_at=v_now
      from (select user_id,sum(bet_amount)::bigint amount from public.crash_v3_bets where round_id=v_round.id and status='lost' group by user_id) x
      where l.user_id=x.user_id and l.limit_date=(v_now at time zone 'UTC')::date;
    if p_current_server_seed is null or public.crash_v3_seed_hash(p_current_server_seed)<>v_round.server_seed_hash then
      raise exception 'seed_reveal_verification_failed'; end if;
    select coalesce(sum(bet_amount),0) into v_expected_debit from public.crash_v3_bets where round_id=v_round.id;
    select coalesce(-sum(coins_delta),0) into v_actual_debit from public.wallet_transactions
      where type='crash_v3_bet' and metadata->>'round_id'=v_round.id::text;
    select coalesce(sum(coins_delta),0) into v_actual_credit from public.wallet_transactions
      where type='crash_v3_win' and metadata->>'round_id'=v_round.id::text;
    select coalesce(sum(coins_delta),0) into v_actual_refund from public.wallet_transactions
      where type='crash_v3_refund' and metadata->>'round_id'=v_round.id::text;
    v_reconciliation_status:=case when v_expected_debit=v_actual_debit and v_round.total_paid=v_actual_credit
      and v_round.total_refunded=v_actual_refund then 'matched' else 'mismatch' end;
    insert into public.crash_v3_financial_reconciliation(round_id,expected_total_wagered,actual_total_debited,
      expected_total_paid,actual_total_credited,expected_total_refunded,actual_total_refunded,reconciliation_status,mismatch_details)
    values(v_round.id,v_expected_debit,v_actual_debit,v_round.total_paid,v_actual_credit,v_round.total_refunded,v_actual_refund,
      v_reconciliation_status,case when v_reconciliation_status='matched' then '{}'::jsonb else jsonb_build_object(
        'wager_delta',v_expected_debit-v_actual_debit,'paid_delta',v_round.total_paid-v_actual_credit,
        'refund_delta',v_round.total_refunded-v_actual_refund) end)
    on conflict(round_id) do nothing;
    update public.crash_v3_rounds set status='settled',settled_at=v_now,revealed_server_seed=p_current_server_seed,updated_at=v_now where id=v_round.id returning * into v_round;
    perform public.crash_v3_append_event(v_round.id,'round_settled',jsonb_build_object('crash_multiplier',v_round.crash_multiplier,
      'revealed_server_seed',p_current_server_seed,'result_hash',v_round.result_hash,'reconciliation_status',v_reconciliation_status),p_engine_instance_id);
  end if;
  return jsonb_build_object('server_time',v_now,'round_id',v_round.id,'status',v_round.status);
end $$;

create or replace function public.crash_v3_admin_get_settings() returns jsonb language plpgsql security definer stable set search_path=public,pg_temp as $$
begin if not public.is_owner_control_user() then raise exception 'not_owner'; end if;
return (select to_jsonb(s)-'singleton' from public.crash_v3_settings s where singleton); end $$;

create or replace function public.crash_v3_admin_update_settings(p_patch jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_before jsonb;v_after jsonb;begin
if not public.is_owner_control_user() then raise exception 'not_owner'; end if;
if p_patch ?| array['singleton','updated_by','updated_at'] then raise exception 'immutable_setting'; end if;
if coalesce((p_patch->>'game_enabled')::boolean,false) and not exists(
  select 1 from public.crash_v3_engine_leases where lease_key='primary' and expires_at>clock_timestamp()
) then raise exception 'engine_unavailable'; end if;
select to_jsonb(s) into v_before from public.crash_v3_settings s where singleton for update;
update public.crash_v3_settings set
 game_enabled=coalesce((p_patch->>'game_enabled')::boolean,game_enabled),maintenance_mode=coalesce((p_patch->>'maintenance_mode')::boolean,maintenance_mode),
 minimum_bet=coalesce((p_patch->>'minimum_bet')::bigint,minimum_bet),maximum_bet=coalesce((p_patch->>'maximum_bet')::bigint,maximum_bet),
 maximum_payout_per_bet=coalesce((p_patch->>'maximum_payout_per_bet')::bigint,maximum_payout_per_bet),
 maximum_total_round_exposure=coalesce((p_patch->>'maximum_total_round_exposure')::bigint,maximum_total_round_exposure),
 betting_duration_ms=coalesce((p_patch->>'betting_duration_ms')::integer,betting_duration_ms),
 locked_duration_ms=coalesce((p_patch->>'locked_duration_ms')::integer,locked_duration_ms),waiting_duration_ms=coalesce((p_patch->>'waiting_duration_ms')::integer,waiting_duration_ms),
 settlement_timeout_ms=coalesce((p_patch->>'settlement_timeout_ms')::integer,settlement_timeout_ms),inter_round_delay_ms=coalesce((p_patch->>'inter_round_delay_ms')::integer,inter_round_delay_ms),
 house_edge_bps=coalesce((p_patch->>'house_edge_bps')::integer,house_edge_bps),maximum_multiplier=coalesce((p_patch->>'maximum_multiplier')::numeric,maximum_multiplier),
 default_growth_rate=coalesce((p_patch->>'default_growth_rate')::numeric,default_growth_rate),auto_refund_on_engine_failure=coalesce((p_patch->>'auto_refund_on_engine_failure')::boolean,auto_refund_on_engine_failure),
 daily_user_loss_limit=coalesce((p_patch->>'daily_user_loss_limit')::bigint,daily_user_loss_limit),daily_user_wager_limit=coalesce((p_patch->>'daily_user_wager_limit')::bigint,daily_user_wager_limit),
 updated_by=auth.uid(),updated_at=clock_timestamp() where singleton returning to_jsonb(crash_v3_settings.*) into v_after;
insert into public.crash_v3_audit_logs(actor_user_id,actor_role,action,before_data,after_data) values(auth.uid(),'owner','update_settings',v_before,v_after);
insert into public.owner_game_control_audit_logs(owner_user_id,action,game_type,old_value,new_value) values(auth.uid(),'update_settings','crash_v3',v_before,v_after);
return v_after-'singleton';end $$;

create or replace function public.crash_v3_admin_emergency_stop() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin if not public.is_owner_control_user() then raise exception 'not_owner'; end if;
update public.crash_v3_settings set emergency_stop=true,game_enabled=false,updated_by=auth.uid(),updated_at=clock_timestamp() where singleton;
insert into public.crash_v3_audit_logs(actor_user_id,actor_role,action) values(auth.uid(),'owner','emergency_stop');
return jsonb_build_object('emergency_stop',true,'game_enabled',false);end $$;

create or replace function public.crash_v3_admin_resume() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin if not public.is_owner_control_user() then raise exception 'not_owner'; end if;
if not exists(select 1 from public.crash_v3_engine_leases where lease_key='primary' and expires_at>clock_timestamp()) then
  raise exception 'engine_unavailable'; end if;
update public.crash_v3_settings set emergency_stop=false,game_enabled=true,updated_by=auth.uid(),updated_at=clock_timestamp() where singleton;
insert into public.crash_v3_audit_logs(actor_user_id,actor_role,action) values(auth.uid(),'owner','resume');
return jsonb_build_object('emergency_stop',false,'game_enabled',true);end $$;

create or replace function public.crash_v3_admin_get_live_risk() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_round public.crash_v3_rounds;begin if not public.is_owner_control_user() then raise exception 'not_owner'; end if;
select * into v_round from public.crash_v3_rounds order by created_at desc limit 1;
return jsonb_build_object('server_time',clock_timestamp(),'round',to_jsonb(v_round)-'encrypted_server_seed'-'revealed_server_seed'-'result_hash'-'crash_multiplier',
 'active_bets',(select count(*) from public.crash_v3_bets where round_id=v_round.id and status='accepted'),
 'estimated_worst_case_payout',(select coalesce(sum(least(s.maximum_payout_per_bet,floor(b.bet_amount*coalesce(b.auto_cashout_multiplier,s.maximum_multiplier)))::bigint),0)
 from public.crash_v3_bets b cross join public.crash_v3_settings s where b.round_id=v_round.id and b.status='accepted'),
 'engine',(select to_jsonb(l) from public.crash_v3_engine_leases l where lease_key='primary'),
 'reconciliation_alerts',(select count(*) from public.crash_v3_financial_reconciliation where reconciliation_status='mismatch'));end $$;

create or replace function public.crash_v3_admin_get_round_details(p_round_id uuid) returns jsonb language plpgsql security definer stable set search_path=public,pg_temp as $$
begin if not public.is_owner_control_user() then raise exception 'not_owner'; end if;return jsonb_build_object(
'round',(select to_jsonb(r)-'encrypted_server_seed' from public.crash_v3_rounds r where id=p_round_id),
'bets',(select coalesce(jsonb_agg(to_jsonb(b)),'[]') from public.crash_v3_bets b where round_id=p_round_id),
'events',(select coalesce(jsonb_agg(to_jsonb(e) order by event_sequence),'[]') from public.crash_v3_round_events e where round_id=p_round_id));end $$;

create or replace function public.crash_v3_admin_get_reconciliation(p_limit integer default 50) returns jsonb language plpgsql security definer stable set search_path=public,pg_temp as $$
begin if not public.is_owner_control_user() then raise exception 'not_owner'; end if;return(select coalesce(jsonb_agg(to_jsonb(x) order by created_at desc),'[]') from(select * from public.crash_v3_financial_reconciliation order by created_at desc limit least(greatest(p_limit,1),200))x);end $$;
create or replace function public.crash_v3_admin_get_audit_logs(p_limit integer default 100) returns jsonb language plpgsql security definer stable set search_path=public,pg_temp as $$
begin if not public.is_owner_control_user() then raise exception 'not_owner'; end if;return(select coalesce(jsonb_agg(to_jsonb(x) order by created_at desc),'[]') from(select * from public.crash_v3_audit_logs order by created_at desc limit least(greatest(p_limit,1),500))x);end $$;
create or replace function public.crash_v3_admin_refund_cancelled_round(p_round_id uuid,p_reason text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_status text;v_total bigint;begin if not public.is_owner_control_user() then raise exception 'not_owner'; end if;
select status into v_status from public.crash_v3_rounds where id=p_round_id for update;if v_status<>'cancelled' then raise exception 'round_not_cancelled';end if;
v_total:=public.crash_v3_refund_round_internal(p_round_id,coalesce(p_reason,'owner_refund'),'owner',null);return jsonb_build_object('round_id',p_round_id,'refunded',v_total);end $$;

revoke all on function public.crash_v3_append_event(uuid,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.crash_v3_engine_get_work(text) from public,anon,authenticated;
revoke all on function public.crash_v3_refund_round_internal(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.crash_v3_engine_tick(text,text,text,text) from public,anon,authenticated;
grant execute on function public.crash_v3_engine_get_work(text) to service_role;
grant execute on function public.crash_v3_engine_tick(text,text,text,text) to service_role;

revoke all on function public.crash_v3_admin_get_settings() from public,anon;
revoke all on function public.crash_v3_admin_update_settings(jsonb) from public,anon;
revoke all on function public.crash_v3_admin_emergency_stop() from public,anon;
revoke all on function public.crash_v3_admin_resume() from public,anon;
revoke all on function public.crash_v3_admin_get_live_risk() from public,anon;
revoke all on function public.crash_v3_admin_get_round_details(uuid) from public,anon;
revoke all on function public.crash_v3_admin_get_reconciliation(integer) from public,anon;
revoke all on function public.crash_v3_admin_get_audit_logs(integer) from public,anon;
revoke all on function public.crash_v3_admin_refund_cancelled_round(uuid,text) from public,anon;
grant execute on function public.crash_v3_admin_get_settings(),public.crash_v3_admin_update_settings(jsonb),
 public.crash_v3_admin_emergency_stop(),public.crash_v3_admin_resume(),public.crash_v3_admin_get_live_risk(),
 public.crash_v3_admin_get_round_details(uuid),public.crash_v3_admin_get_reconciliation(integer),
 public.crash_v3_admin_get_audit_logs(integer),public.crash_v3_admin_refund_cancelled_round(uuid,text) to authenticated;
