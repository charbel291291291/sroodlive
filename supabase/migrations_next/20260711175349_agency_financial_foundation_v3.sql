-- Phase 3 isolated financial foundation. This schema is not exposed to the
-- current Flutter application and no legacy row is backfilled or cut over.

create schema if not exists agency_finance_v3;
revoke all on schema agency_finance_v3 from public, anon, authenticated;
grant usage on schema agency_finance_v3 to service_role;

create table agency_finance_v3.agency_financial_operations (
  operation_id uuid primary key default gen_random_uuid(),
  idempotency_key text not null,
  request_id uuid,
  transaction_id uuid,
  actor_user_id uuid not null references auth.users(id),
  beneficiary_user_id uuid references auth.users(id),
  agency_id uuid,
  agent_id uuid,
  currency text not null,
  coin_amount bigint not null default 0 check (coin_amount >= 0),
  diamond_amount bigint not null default 0 check (diamond_amount >= 0),
  fiat_amount numeric(20,6) not null default 0 check (fiat_amount >= 0),
  exchange_rate numeric(20,8) not null check (exchange_rate > 0),
  operation_type text not null check (operation_type in (
    'recharge_request','recharge_approval','recharge_rejection',
    'recharge_posting','withdrawal_request','withdrawal_approval',
    'withdrawal_rejection','agency_commission','agency_settlement',
    'reversal','administrative_correction')),
  status text not null default 'pending'
    check (status in ('pending','completed','rejected','reversed','failed')),
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  reversed_at timestamptz,
  reversal_of uuid references agency_finance_v3.agency_financial_operations(operation_id),
  metadata jsonb not null default '{}'::jsonb,
  correlation_id uuid not null default gen_random_uuid(),
  constraint agency_finance_v3_operation_idempotency_unique
    unique (operation_type, idempotency_key),
  constraint agency_finance_v3_completion_state check (
    (status = 'completed' and completed_at is not null) or status <> 'completed'),
  constraint agency_finance_v3_reversal_link check (
    (operation_type = 'reversal' and reversal_of is not null)
    or (operation_type <> 'reversal' and reversal_of is null))
);

create table agency_finance_v3.agency_ledger_accounts (
  account_id uuid primary key default gen_random_uuid(),
  owner_type text not null check (owner_type in
    ('agency','agent','host','wallet','platform','commission','settlement','clearing')),
  owner_id uuid,
  currency text not null,
  account_code text not null,
  status text not null default 'active' check (status in ('active','frozen','closed')),
  created_at timestamptz not null default clock_timestamp(),
  metadata jsonb not null default '{}'::jsonb,
  unique (owner_type, owner_id, currency, account_code)
);

create table agency_finance_v3.agency_ledger_entries (
  entry_id uuid primary key default gen_random_uuid(),
  operation_id uuid not null references
    agency_finance_v3.agency_financial_operations(operation_id),
  account_id uuid not null references agency_finance_v3.agency_ledger_accounts(account_id),
  request_id uuid,
  transaction_id uuid,
  entry_side text not null check (entry_side in ('debit','credit')),
  currency text not null,
  amount numeric(24,8) not null check (amount > 0),
  coin_amount bigint not null default 0 check (coin_amount >= 0),
  diamond_amount bigint not null default 0 check (diamond_amount >= 0),
  credit_amount numeric(24,8) not null default 0 check (credit_amount >= 0),
  commission_amount numeric(24,8) not null default 0 check (commission_amount >= 0),
  fiat_amount numeric(24,8) not null default 0 check (fiat_amount >= 0),
  posted_at timestamptz not null default clock_timestamp(),
  created_by uuid not null references auth.users(id),
  metadata jsonb not null default '{}'::jsonb,
  unique (operation_id, account_id, entry_side)
);

create table agency_finance_v3.agency_idempotency_keys (
  idempotency_id uuid primary key default gen_random_uuid(),
  operation_scope text not null,
  idempotency_key text not null,
  actor_user_id uuid not null references auth.users(id),
  operation_id uuid references agency_finance_v3.agency_financial_operations(operation_id),
  request_hash text not null,
  status text not null default 'claimed' check (status in ('claimed','completed','failed')),
  result jsonb,
  claimed_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  unique (operation_scope, idempotency_key)
);

create table agency_finance_v3.agency_audit_events (
  audit_id uuid primary key default gen_random_uuid(),
  operation_id uuid references agency_finance_v3.agency_financial_operations(operation_id),
  actor_user_id uuid not null references auth.users(id),
  event_type text not null,
  agency_id uuid,
  target_user_id uuid,
  correlation_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);

create index agency_finance_v3_operations_request_idx
  on agency_finance_v3.agency_financial_operations(request_id);
create index agency_finance_v3_operations_transaction_idx
  on agency_finance_v3.agency_financial_operations(transaction_id);
create index agency_finance_v3_operations_agency_created_idx
  on agency_finance_v3.agency_financial_operations(agency_id, created_at desc);
create index agency_finance_v3_entries_operation_idx
  on agency_finance_v3.agency_ledger_entries(operation_id);
create index agency_finance_v3_entries_account_posted_idx
  on agency_finance_v3.agency_ledger_entries(account_id, posted_at desc);

alter table agency_finance_v3.agency_financial_operations enable row level security;
alter table agency_finance_v3.agency_ledger_accounts enable row level security;
alter table agency_finance_v3.agency_ledger_entries enable row level security;
alter table agency_finance_v3.agency_idempotency_keys enable row level security;
alter table agency_finance_v3.agency_audit_events enable row level security;

revoke all on all tables in schema agency_finance_v3 from public, anon, authenticated;
grant select, insert, update on agency_finance_v3.agency_financial_operations to service_role;
grant select, insert on agency_finance_v3.agency_ledger_accounts to service_role;
grant select, insert on agency_finance_v3.agency_ledger_entries to service_role;
grant select, insert, update on agency_finance_v3.agency_idempotency_keys to service_role;
grant select, insert on agency_finance_v3.agency_audit_events to service_role;

create or replace function agency_finance_v3.reject_mutation()
returns trigger language plpgsql security definer
set search_path = pg_catalog, agency_finance_v3
as $$ begin raise exception 'append_only_record'; end $$;

create trigger agency_finance_v3_ledger_entries_append_only
before update or delete on agency_finance_v3.agency_ledger_entries
for each row execute function agency_finance_v3.reject_mutation();
create trigger agency_finance_v3_audit_events_append_only
before update or delete on agency_finance_v3.agency_audit_events
for each row execute function agency_finance_v3.reject_mutation();
create trigger agency_finance_v3_posted_operations_immutable
before delete on agency_finance_v3.agency_financial_operations
for each row execute function agency_finance_v3.reject_mutation();

-- Updates to operations may only perform legal lifecycle transitions and may
-- never rewrite financial fields. Without this, any UPDATE-capable role could
-- silently mutate completed amounts/status.
create or replace function agency_finance_v3.guard_operation_update()
returns trigger language plpgsql security definer
set search_path = pg_catalog, agency_finance_v3
as $$
begin
  if new.operation_id is distinct from old.operation_id
     or new.idempotency_key is distinct from old.idempotency_key
     or new.operation_type is distinct from old.operation_type
     or new.actor_user_id is distinct from old.actor_user_id
     or new.beneficiary_user_id is distinct from old.beneficiary_user_id
     or new.currency is distinct from old.currency
     or new.coin_amount is distinct from old.coin_amount
     or new.diamond_amount is distinct from old.diamond_amount
     or new.fiat_amount is distinct from old.fiat_amount
     or new.exchange_rate is distinct from old.exchange_rate
     or new.reversal_of is distinct from old.reversal_of
     or new.created_at is distinct from old.created_at then
    raise exception 'operation_financial_fields_immutable';
  end if;
  if not (
       (old.status = 'pending'   and new.status in ('pending','completed','rejected','failed'))
    or (old.status = 'completed' and new.status in ('completed','reversed'))
  ) then
    raise exception 'invalid_operation_status_transition';
  end if;
  if new.status = 'completed' and new.completed_at is null then
    raise exception 'completed_requires_timestamp';
  end if;
  if new.status = 'reversed' and new.reversed_at is null then
    raise exception 'reversed_requires_timestamp';
  end if;
  return new;
end $$;

create trigger agency_finance_v3_operations_update_guard
before update on agency_finance_v3.agency_financial_operations
for each row execute function agency_finance_v3.guard_operation_update();

-- Postgres UNIQUE treats NULLs as distinct, so the table constraint alone
-- allows duplicate accounts for ownerless owner types (platform/clearing).
create unique index agency_finance_v3_accounts_null_owner_unique
  on agency_finance_v3.agency_ledger_accounts (owner_type, currency, account_code)
  where owner_id is null;

revoke execute on all functions in schema agency_finance_v3 from public, anon, authenticated;
grant execute on function agency_finance_v3.reject_mutation() to service_role;

-- Prototype RPCs deliberately fail closed until staging supplies the specific
-- account map and authorization adapter. Their signatures reserve secure,
-- non-public endpoints without changing live behavior.
create or replace function agency_finance_v3.prototype_not_enabled()
returns jsonb language plpgsql security definer
set search_path = pg_catalog, agency_finance_v3
as $$ begin raise exception 'agency_finance_v3_not_enabled'; end $$;

create or replace function agency_finance_v3.create_recharge_request(p_idempotency_key text, p_payload jsonb)
returns jsonb language sql security definer set search_path = pg_catalog, agency_finance_v3
as $$ select agency_finance_v3.prototype_not_enabled() $$;
create or replace function agency_finance_v3.approve_recharge_request(p_idempotency_key text, p_request_id uuid)
returns jsonb language sql security definer set search_path = pg_catalog, agency_finance_v3
as $$ select agency_finance_v3.prototype_not_enabled() $$;
create or replace function agency_finance_v3.reject_recharge_request(p_idempotency_key text, p_request_id uuid, p_reason text)
returns jsonb language sql security definer set search_path = pg_catalog, agency_finance_v3
as $$ select agency_finance_v3.prototype_not_enabled() $$;
create or replace function agency_finance_v3.post_recharge_transaction(p_idempotency_key text, p_request_id uuid)
returns jsonb language sql security definer set search_path = pg_catalog, agency_finance_v3
as $$ select agency_finance_v3.prototype_not_enabled() $$;
create or replace function agency_finance_v3.create_withdrawal_request(p_idempotency_key text, p_payload jsonb)
returns jsonb language sql security definer set search_path = pg_catalog, agency_finance_v3
as $$ select agency_finance_v3.prototype_not_enabled() $$;
create or replace function agency_finance_v3.approve_withdrawal_request(p_idempotency_key text, p_request_id uuid)
returns jsonb language sql security definer set search_path = pg_catalog, agency_finance_v3
as $$ select agency_finance_v3.prototype_not_enabled() $$;
create or replace function agency_finance_v3.reject_withdrawal_request(p_idempotency_key text, p_request_id uuid, p_reason text)
returns jsonb language sql security definer set search_path = pg_catalog, agency_finance_v3
as $$ select agency_finance_v3.prototype_not_enabled() $$;
create or replace function agency_finance_v3.reverse_financial_operation(p_idempotency_key text, p_operation_id uuid, p_reason text)
returns jsonb language sql security definer set search_path = pg_catalog, agency_finance_v3
as $$ select agency_finance_v3.prototype_not_enabled() $$;
create or replace function agency_finance_v3.post_agency_commission(p_idempotency_key text, p_payload jsonb)
returns jsonb language sql security definer set search_path = pg_catalog, agency_finance_v3
as $$ select agency_finance_v3.prototype_not_enabled() $$;
create or replace function agency_finance_v3.post_agency_settlement(p_idempotency_key text, p_payload jsonb)
returns jsonb language sql security definer set search_path = pg_catalog, agency_finance_v3
as $$ select agency_finance_v3.prototype_not_enabled() $$;

revoke execute on all functions in schema agency_finance_v3 from public, anon, authenticated;
grant execute on all functions in schema agency_finance_v3 to service_role;
