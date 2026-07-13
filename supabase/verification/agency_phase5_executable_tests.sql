\set ON_ERROR_STOP 0
\pset pager off
\set QUIET on
-- clean slate (truncate bypasses the append-only row triggers)
truncate agency_finance_v3.agency_financial_operations,
         agency_finance_v3.agency_ledger_entries,
         agency_finance_v3.agency_audit_events,
         agency_finance_v3.agency_idempotency_keys,
         agency_finance_v3.agency_ledger_accounts cascade;
create temp table if not exists t(k text primary key, v uuid);
truncate t;

\set creator 11111111-1111-1111-1111-111111111111
\set agent   22222222-2222-2222-2222-222222222222
\set admin   33333333-3333-3333-3333-333333333333

-- T1
select set_config('request.jwt.claim.sub', :'creator', false);
insert into t values ('t1', (agency_finance_v3.create_recharge_request('t1',jsonb_build_object('coin_amount',1000,'exchange_rate',1))->>'operation_id')::uuid);
do $$ declare s text; n int; begin
  select status into s from agency_finance_v3.agency_financial_operations o join t on t.v=o.operation_id where t.k='t1';
  select count(*) into n from agency_finance_v3.agency_ledger_entries e join t on t.v=e.operation_id where t.k='t1';
  raise notice 'T1 %: status=% entries=% (want pending/0)', case when s='pending' and n=0 then 'PASS' else 'FAIL' end,s,n; end $$;

-- T2 idempotency
do $$ declare a uuid; b uuid; begin select v into a from t where k='t1';
  b := (agency_finance_v3.create_recharge_request('t1',jsonb_build_object('coin_amount',1000,'exchange_rate',1))->>'operation_id')::uuid;
  raise notice 'T2a %: cached op (equal=%)', case when a=b then 'PASS' else 'FAIL' end, (a=b); end $$;
do $$ begin perform agency_finance_v3.create_recharge_request('t1',jsonb_build_object('coin_amount',9,'exchange_rate',1));
  raise notice 'T2b FAIL'; exception when others then raise notice 'T2b %: %', case when sqlerrm like '%idempotency_conflict%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;

-- T3 approve
select set_config('request.jwt.claim.sub', :'admin', false);
do $$ declare src uuid; s text; n int; begin select v into src from t where k='t1';
  perform agency_finance_v3.approve_recharge_request('t3-app', src);
  select status into s from agency_finance_v3.agency_financial_operations where operation_id=src;
  select count(*) into n from agency_finance_v3.agency_ledger_entries e join agency_finance_v3.agency_financial_operations o on o.operation_id=e.operation_id where o.operation_type='recharge_approval' and o.request_id=src;
  raise notice 'T3 %: source=% approval_entries=% (want completed/0)', case when s='completed' and n=0 then 'PASS' else 'FAIL' end,s,n; end $$;
do $$ declare src uuid; begin select v into src from t where k='t1';
  perform agency_finance_v3.approve_recharge_request('t3-app2', src); raise notice 'T3-dup FAIL';
  exception when others then raise notice 'T3-dup %: %', case when sqlerrm like '%request_not_pending%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;

-- T4 self-approval (admin creates+approves)
insert into t values ('t4', (agency_finance_v3.create_recharge_request('t4',jsonb_build_object('coin_amount',200,'exchange_rate',1))->>'operation_id')::uuid);
do $$ declare src uuid; begin select v into src from t where k='t4';
  perform agency_finance_v3.approve_recharge_request('t4-app', src); raise notice 'T4 FAIL';
  exception when others then raise notice 'T4 %: %', case when sqlerrm like '%self_approval_forbidden%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;

-- T5 posting clearing->wallet
do $$ declare src uuid; posted uuid; d text; c text; amt numeric; cur text; coins bigint; begin
  select v into src from t where k='t1';
  posted := (agency_finance_v3.post_recharge_transaction('t5-post', src)->>'operation_id')::uuid;
  select entry_side,amount,e.currency,coin_amount into d,amt,cur,coins from agency_finance_v3.agency_ledger_entries e join agency_finance_v3.agency_ledger_accounts a using(account_id) where e.operation_id=posted and a.account_code='V3_CLEARING';
  select entry_side into c from agency_finance_v3.agency_ledger_entries e join agency_finance_v3.agency_ledger_accounts a using(account_id) where e.operation_id=posted and a.account_code='V3_WALLET';
  raise notice 'T5 %: clearing=% wallet=% amt=% cur=% coins=% (want debit/credit/1000/COIN/1000)', case when d='debit' and c='credit' and amt=1000 and cur='COIN' and coins=1000 then 'PASS' else 'FAIL' end,d,c,amt,cur,coins; end $$;
do $$ declare src uuid; begin select v into src from t where k='t1';
  perform agency_finance_v3.post_recharge_transaction('t5-p2', src); raise notice 'T5-dup FAIL';
  exception when others then raise notice 'T5-dup %: %', case when sqlerrm like '%request_already_posted%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;
do $$ declare src uuid; begin select v into src from t where k='t4';
  perform agency_finance_v3.post_recharge_transaction('t5-un', src); raise notice 'T5-unapp FAIL';
  exception when others then raise notice 'T5-unapp %: %', case when sqlerrm like '%request_not_approved%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;

-- T6 reject
select set_config('request.jwt.claim.sub', :'creator', false);
insert into t values ('t6', (agency_finance_v3.create_recharge_request('t6',jsonb_build_object('coin_amount',300,'exchange_rate',1))->>'operation_id')::uuid);
select set_config('request.jwt.claim.sub', :'admin', false);
do $$ declare src uuid; s text; n int; begin select v into src from t where k='t6';
  perform agency_finance_v3.reject_recharge_request('t6-rej', src, 'x');
  select status into s from agency_finance_v3.agency_financial_operations where operation_id=src;
  select count(*) into n from agency_finance_v3.agency_ledger_entries e join agency_finance_v3.agency_financial_operations o on o.operation_id=e.operation_id where o.operation_type='recharge_rejection' and o.request_id=src;
  raise notice 'T6 %: status=% rej_entries=% (want rejected/0)', case when s='rejected' and n=0 then 'PASS' else 'FAIL' end,s,n; end $$;
do $$ declare src uuid; begin select v into src from t where k='t6';
  perform agency_finance_v3.approve_recharge_request('t6-app', src); raise notice 'T6-postrej FAIL';
  exception when others then raise notice 'T6-postrej %: %', case when sqlerrm like '%request_not_pending%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;

-- T7 withdrawal wallet->clearing
select set_config('request.jwt.claim.sub', :'creator', false);
insert into t values ('t7', (agency_finance_v3.create_withdrawal_request('t7',jsonb_build_object('diamond_amount',500,'exchange_rate',1))->>'operation_id')::uuid);
select set_config('request.jwt.claim.sub', :'admin', false);
do $$ declare src uuid; w text; c text; cur text; dia bigint; app uuid; begin select v into src from t where k='t7';
  app := (agency_finance_v3.approve_withdrawal_request('t7-app', src)->>'operation_id')::uuid;
  select entry_side,e.currency,diamond_amount into w,cur,dia from agency_finance_v3.agency_ledger_entries e join agency_finance_v3.agency_ledger_accounts a using(account_id) where e.operation_id=app and a.account_code='V3_WALLET';
  select entry_side into c from agency_finance_v3.agency_ledger_entries e join agency_finance_v3.agency_ledger_accounts a using(account_id) where e.operation_id=app and a.account_code='V3_CLEARING';
  raise notice 'T7 %: wallet=% clearing=% cur=% dia=% (want debit/credit/DIAMOND/500)', case when w='debit' and c='credit' and cur='DIAMOND' and dia=500 then 'PASS' else 'FAIL' end,w,c,cur,dia; end $$;

-- T8 reversal
do $$ declare posted uuid; rev uuid; w text; c text; amt numeric; s text; begin
  select operation_id into posted from agency_finance_v3.agency_financial_operations where idempotency_key='t5-post';
  rev := (agency_finance_v3.reverse_financial_operation('t8-rev', posted, 'x')->>'operation_id')::uuid;
  select entry_side into w from agency_finance_v3.agency_ledger_entries e join agency_finance_v3.agency_ledger_accounts a using(account_id) where e.operation_id=rev and a.account_code='V3_WALLET';
  select entry_side,amount into c,amt from agency_finance_v3.agency_ledger_entries e join agency_finance_v3.agency_ledger_accounts a using(account_id) where e.operation_id=rev and a.account_code='V3_CLEARING';
  select status into s from agency_finance_v3.agency_financial_operations where operation_id=posted;
  raise notice 'T8 %: wallet=% clearing=% amt=% source=% (want debit/credit/1000/reversed)', case when w='debit' and c='credit' and amt=1000 and s='reversed' then 'PASS' else 'FAIL' end,w,c,amt,s; end $$;
do $$ declare posted uuid; begin select operation_id into posted from agency_finance_v3.agency_financial_operations where idempotency_key='t5-post';
  perform agency_finance_v3.reverse_financial_operation('t8-r2', posted, 'x'); raise notice 'T8-dup FAIL';
  exception when others then raise notice 'T8-dup %: %', case when sqlerrm like '%reversal_source_not_completed%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;
do $$ declare appr uuid; begin select operation_id into appr from agency_finance_v3.agency_financial_operations where idempotency_key='t3-app';
  perform agency_finance_v3.reverse_financial_operation('t8-r3', appr, 'x'); raise notice 'T8-nonmov FAIL';
  exception when others then raise notice 'T8-nonmov %: %', case when sqlerrm like '%source_operation_not_reversible%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;

-- T9 currency derivation
select set_config('request.jwt.claim.sub', :'creator', false);
do $$ begin perform agency_finance_v3.create_recharge_request('t9-f', jsonb_build_object('fiat_amount',10,'exchange_rate',1)); raise notice 'T9-fiat FAIL';
  exception when others then raise notice 'T9-fiat %: %', case when sqlerrm like '%fiat_currency_required%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;
do $$ declare c text; begin perform agency_finance_v3.create_recharge_request('t9-c', jsonb_build_object('coin_amount',5,'exchange_rate',1));
  select currency into c from agency_finance_v3.agency_financial_operations where idempotency_key='t9-c'; raise notice 'T9-coin %: %', case when c='COIN' then 'PASS' else 'FAIL' end, c; end $$;
do $$ declare c text; begin perform agency_finance_v3.create_recharge_request('t9-d', jsonb_build_object('diamond_amount',5,'exchange_rate',1));
  select currency into c from agency_finance_v3.agency_financial_operations where idempotency_key='t9-d'; raise notice 'T9-dia %: %', case when c='DIAMOND' then 'PASS' else 'FAIL' end, c; end $$;

-- T10 immutability (t5-post now reversed=completed movement; t1 request reversed? use completed posting op which is now 'reversed')
do $$ declare op uuid; begin select operation_id into op from agency_finance_v3.agency_financial_operations where idempotency_key='t5-post';
  update agency_finance_v3.agency_financial_operations set coin_amount=coin_amount+1 where operation_id=op; raise notice 'T10a FAIL';
  exception when others then raise notice 'T10a %: %', case when sqlerrm like '%operation_financial_fields_immutable%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;
do $$ declare op uuid; begin select operation_id into op from agency_finance_v3.agency_financial_operations where idempotency_key='t5-post';
  update agency_finance_v3.agency_financial_operations set status='pending' where operation_id=op; raise notice 'T10b FAIL';
  exception when others then raise notice 'T10b %: %', case when sqlerrm like '%invalid_operation_status_transition%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;
do $$ begin delete from agency_finance_v3.agency_ledger_entries where entry_id in (select entry_id from agency_finance_v3.agency_ledger_entries limit 1); raise notice 'T10c FAIL';
  exception when others then raise notice 'T10c %: %', case when sqlerrm like '%append_only_record%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;

-- T11 isolation
do $$ begin set local role authenticated;
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
  perform agency_finance_v3.create_recharge_request('t11', jsonb_build_object('coin_amount',1,'exchange_rate',1)); raise notice 'T11 FAIL';
  exception when insufficient_privilege then raise notice 'T11 PASS: %', sqlerrm;
           when others then raise notice 'T11 %: %', case when sqlerrm like '%permission denied%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;

-- T12 invariant
do $$ declare bad int; begin select count(*) into bad from (select operation_id,currency,sum(case entry_side when 'debit' then amount else -amount end) net from agency_finance_v3.agency_ledger_entries group by 1,2) x where net<>0;
  raise notice 'T12 %: unbalanced=% (want 0)', case when bad=0 then 'PASS' else 'FAIL' end, bad; end $$;

-- Failure injection
select set_config('request.jwt.claim.sub', :'admin', false);
do $$ begin perform agency_finance_v3.approve_recharge_request('fi1','99999999-9999-9999-9999-999999999999'); raise notice 'FI-notfound FAIL';
  exception when others then raise notice 'FI-notfound %: %', case when sqlerrm like '%source_request_not_found%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;
select set_config('request.jwt.claim.sub', :'creator', false);
do $$ begin perform agency_finance_v3.create_recharge_request('fi2', jsonb_build_object('coin_amount',0,'exchange_rate',1)); raise notice 'FI-zero FAIL';
  exception when others then raise notice 'FI-zero %: %', case when sqlerrm like '%positive_amount_required%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;
do $$ declare src uuid; begin select v into src from t where k='t7';
  perform agency_finance_v3.approve_recharge_request('fi3', src); raise notice 'FI-nonadmin FAIL';
  exception when others then raise notice 'FI-nonadmin %: %', case when sqlerrm like '%not_authorized%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;
select set_config('request.jwt.claim.sub', '', false);
do $$ begin perform agency_finance_v3.create_recharge_request('fi4', jsonb_build_object('coin_amount',1,'exchange_rate',1)); raise notice 'FI-noauth FAIL';
  exception when others then raise notice 'FI-noauth %: %', case when sqlerrm like '%not_authenticated%' then 'PASS' else 'FAIL' end, sqlerrm; end $$;

-- Rollback: failed op leaves no idempotency claim; key reusable
select set_config('request.jwt.claim.sub', :'admin', false);
do $$ declare after int; begin
  begin perform agency_finance_v3.approve_recharge_request('RBK', (select v from t where k='t6')); exception when others then null; end;
  select count(*) into after from agency_finance_v3.agency_idempotency_keys where idempotency_key='RBK';
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
  perform agency_finance_v3.create_recharge_request('RBK', jsonb_build_object('coin_amount',7,'exchange_rate',1));
  raise notice 'RB %: claim_after_fail=% reuse=ok', case when after=0 then 'PASS' else 'FAIL' end, after;
  exception when others then raise notice 'RB FAIL: reuse blocked -> %', sqlerrm; end $$;
