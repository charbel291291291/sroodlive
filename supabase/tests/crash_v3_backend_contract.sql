\set ON_ERROR_STOP on
begin;

do $$ begin
  if public.crash_v3_result_hash('key','The quick brown fox jumps over the lazy dog',0)
     <> 'c6e6def3e6baecc215e7fb4df33c1186f42a3e51e48fd8f9f35f23d8f4747c06' then
    raise exception 'known HMAC-SHA256 vector failed';
  end if;
  if public.crash_v3_seed_hash('abc') <> 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' then
    raise exception 'known SHA-256 vector failed';
  end if;
  if public.crash_v3_multiplier_from_hash(repeat('0',64),300,1000) <> 1.00 then
    raise exception 'minimum multiplier rounding failed';
  end if;
  if public.crash_v3_multiplier_from_hash(repeat('f',64),300,10) <> 10.00 then
    raise exception 'maximum multiplier cap failed';
  end if;
end $$;

insert into auth.users(id,instance_id,aud,role,email) values
 ('c3000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','crash-v3-test@example.com')
on conflict(id) do nothing;
insert into public.wallets(user_id,coins_balance) values('c3000000-0000-0000-0000-000000000001',100000)
on conflict(user_id) do update set coins_balance=excluded.coins_balance;
select set_config('request.jwt.claims','{"sub":"c3000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
update public.crash_v3_settings set game_enabled=true,maintenance_mode=false,emergency_stop=false,
 minimum_bet=100,maximum_bet=10000,daily_user_wager_limit=100000,daily_user_loss_limit=100000;

insert into public.crash_v3_rounds(id,status,starts_at,betting_opens_at,betting_closes_at,
 crash_multiplier,server_seed_hash,encrypted_server_seed,client_seed,result_hash,growth_rate,house_edge_bps,maximum_multiplier)
values('c3000000-0000-0000-0000-000000000010','betting',clock_timestamp()-interval '2 seconds',
 clock_timestamp()-interval '1 second',clock_timestamp()+interval '10 seconds',10,
 public.crash_v3_seed_hash(repeat('a',64)),'test-ciphertext','srood-live-crash-v3',
 public.crash_v3_result_hash(repeat('a',64),'srood-live-crash-v3',currval('public.crash_v3_nonce_seq')),
 0.065,300,1000);

select public.crash_v3_place_bet('c3000000-0000-0000-0000-000000000010',1,1000,2.00,'bet-idempotency-00000001');
select public.crash_v3_place_bet('c3000000-0000-0000-0000-000000000010',1,1000,2.00,'bet-idempotency-00000001');
do $$ begin
  if (select coins_balance from public.wallets where user_id='c3000000-0000-0000-0000-000000000001')<>99000 then raise exception 'duplicate bet debited twice'; end if;
  if (select count(*) from public.crash_v3_bets where round_id='c3000000-0000-0000-0000-000000000010')<>1 then raise exception 'duplicate bet row'; end if;
  if (select count(*) from public.wallet_transactions where type='crash_v3_bet' and metadata->>'round_id'='c3000000-0000-0000-0000-000000000010')<>1 then raise exception 'duplicate debit ledger'; end if;
end $$;

update public.crash_v3_rounds set status='flying',flight_started_at=clock_timestamp()-interval '1 second' where id='c3000000-0000-0000-0000-000000000010';
select public.crash_v3_cashout((select id from public.crash_v3_bets where round_id='c3000000-0000-0000-0000-000000000010'),'cashout-idempotency-0001');
select public.crash_v3_cashout((select id from public.crash_v3_bets where round_id='c3000000-0000-0000-0000-000000000010'),'cashout-idempotency-0001');
do $$ declare v_bet public.crash_v3_bets; begin
  select * into v_bet from public.crash_v3_bets where round_id='c3000000-0000-0000-0000-000000000010';
  if v_bet.status<>'won' or v_bet.payout_transaction_id is null then raise exception 'cashout not settled'; end if;
  if (select count(*) from public.wallet_transactions where type='crash_v3_win' and metadata->>'round_id'='c3000000-0000-0000-0000-000000000010')<>1 then raise exception 'duplicate payout ledger'; end if;
  if exists(select 1 from public.wallets where coins_balance<0) then raise exception 'negative wallet'; end if;
end $$;

do $$ begin
  if has_table_privilege('authenticated','public.crash_v3_rounds','INSERT')
    or has_table_privilege('authenticated','public.crash_v3_bets','UPDATE')
    or has_table_privilege('anon','public.crash_v3_round_events','SELECT') then
    raise exception 'direct privilege boundary failed';
  end if;
end $$;

rollback;
