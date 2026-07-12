-- LOCAL/STAGING ONLY. Explicit session opt-in prevents accidental execution.
do $$ begin
  if current_setting('app.agency_phase4_fixtures', true) <> 'enabled' then
    raise exception 'set app.agency_phase4_fixtures=enabled before loading fixtures';
  end if;
end $$;

create table if not exists agency_finance_v3.test_principals (
  fixture_role text primary key,
  user_id uuid not null unique,
  agency_id uuid
);
revoke all on agency_finance_v3.test_principals from public,anon,authenticated;

insert into agency_finance_v3.test_principals(fixture_role,user_id,agency_id) values
('normal_user','10000000-0000-0000-0000-000000000001',null),
('hostess','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001'),
('agency_owner','10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001'),
('recharge_agent','10000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000001'),
('admin','10000000-0000-0000-0000-000000000005',null),
('super_admin','10000000-0000-0000-0000-000000000006',null),
('service_role','10000000-0000-0000-0000-000000000007',null),
('other_agency_owner','10000000-0000-0000-0000-000000000008','20000000-0000-0000-0000-000000000002')
on conflict (fixture_role) do update set user_id=excluded.user_id,agency_id=excluded.agency_id;

insert into agency_finance_v3.agency_ledger_accounts
  (owner_type,owner_id,currency,account_code) values
('wallet','10000000-0000-0000-0000-000000000001','COIN','FIXTURE_WALLET'),
('agency','20000000-0000-0000-0000-000000000001','CREDIT','FIXTURE_AGENCY_CREDIT'),
('commission','20000000-0000-0000-0000-000000000001','USD','FIXTURE_COMMISSION'),
('settlement','20000000-0000-0000-0000-000000000001','USD','FIXTURE_SETTLEMENT')
on conflict (owner_type,owner_id,currency,account_code) do nothing;

-- Auth users, public Agency membership and request fixtures must be inserted by
-- the local test harness using the IDs above because their legacy schemas vary
-- across migration generations. No production identifiers are present here.
