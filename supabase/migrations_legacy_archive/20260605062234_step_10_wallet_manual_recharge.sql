create table if not exists public.wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  coins_balance integer not null default 0,
  diamonds_balance integer not null default 0,
  lifetime_coins_charged integer not null default 0,
  lifetime_coins_spent integer not null default 0,
  lifetime_diamonds_earned integer not null default 0,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint wallets_coins_balance_non_negative check (coins_balance >= 0),
  constraint wallets_diamonds_balance_non_negative check (diamonds_balance >= 0),
  constraint wallets_lifetime_coins_charged_non_negative check (lifetime_coins_charged >= 0),
  constraint wallets_lifetime_coins_spent_non_negative check (lifetime_coins_spent >= 0),
  constraint wallets_lifetime_diamonds_earned_non_negative check (lifetime_diamonds_earned >= 0)
);

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  direction text not null,
  coins_delta integer not null default 0,
  diamonds_delta integer not null default 0,
  balance_coins_after integer null,
  balance_diamonds_after integer null,
  related_user_id uuid null references auth.users(id) on delete set null,
  related_room_id uuid null,
  related_gift_id uuid null,
  related_gift_transaction_id uuid null,
  related_recharge_request_id uuid null,
  agency_id uuid null,
  agent_id uuid null,
  note text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint wallet_transactions_type_check check (
    type in (
      'recharge_request',
      'admin_adjustment',
      'gift_sent',
      'gift_received',
      'agency_recharge',
      'refund',
      'system'
    )
  ),
  constraint wallet_transactions_direction_check check (
    direction in ('credit', 'debit', 'neutral')
  )
);

create table if not exists public.recharge_agencies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  owner_user_id uuid null references auth.users(id) on delete set null,
  country text null,
  phone text null,
  whatsapp text null,
  is_active boolean not null default true,
  commission_rate numeric(6,4) not null default 0,
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.recharge_agents (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid null references public.recharge_agencies(id) on delete set null,
  user_id uuid null references auth.users(id) on delete set null,
  name text not null,
  code text not null unique,
  phone text null,
  whatsapp text null,
  is_active boolean not null default true,
  commission_rate numeric(6,4) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.recharge_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  public_user_id text null,
  requested_coins integer not null,
  requested_amount_usd numeric(12,2) null,
  method text not null,
  status text not null default 'pending',
  reference_code text null,
  proof_url text null,
  agency_id uuid null references public.recharge_agencies(id) on delete set null,
  agent_id uuid null references public.recharge_agents(id) on delete set null,
  agent_code text null,
  admin_user_id uuid null references auth.users(id) on delete set null,
  admin_note text null,
  reject_reason text null,
  approved_at timestamptz null,
  rejected_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recharge_requests_requested_coins_positive check (requested_coins > 0),
  constraint recharge_requests_method_check check (
    method in ('omt', 'wish', 'usdt', 'agent', 'cash', 'admin_manual')
  ),
  constraint recharge_requests_status_check check (
    status in ('pending', 'approved', 'rejected', 'cancelled')
  )
);

create table if not exists public.app_user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, role),
  constraint app_user_roles_role_check check (
    role in ('super_admin', 'finance_admin', 'admin', 'support', 'moderator')
  )
);

create index if not exists wallet_transactions_user_created_idx
  on public.wallet_transactions (user_id, created_at desc);

create index if not exists recharge_requests_user_created_idx
  on public.recharge_requests (user_id, created_at desc);

create index if not exists recharge_requests_status_created_idx
  on public.recharge_requests (status, created_at desc);

create index if not exists recharge_agents_code_active_idx
  on public.recharge_agents (code)
  where is_active;

alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.recharge_agencies enable row level security;
alter table public.recharge_agents enable row level security;
alter table public.recharge_requests enable row level security;
alter table public.app_user_roles enable row level security;

create or replace function public.has_app_role(p_role text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_user_roles aur
    where aur.user_id = auth.uid()
      and aur.role = p_role
  );
$$;

create or replace function public.has_finance_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_app_role('super_admin')
      or public.has_app_role('finance_admin');
$$;

drop policy if exists "Users can view own wallet" on public.wallets;
create policy "Users can view own wallet"
on public.wallets
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "Users can view own wallet transactions" on public.wallet_transactions;
create policy "Users can view own wallet transactions"
on public.wallet_transactions
for select
to authenticated
using (user_id = auth.uid() or public.has_finance_access());

drop policy if exists "Users can view active recharge agencies" on public.recharge_agencies;
create policy "Users can view active recharge agencies"
on public.recharge_agencies
for select
to authenticated
using (is_active or public.has_finance_access());

drop policy if exists "Users can view active recharge agents" on public.recharge_agents;
create policy "Users can view active recharge agents"
on public.recharge_agents
for select
to authenticated
using (is_active or public.has_finance_access());

drop policy if exists "Users can view own recharge requests" on public.recharge_requests;
create policy "Users can view own recharge requests"
on public.recharge_requests
for select
to authenticated
using (user_id = auth.uid() or public.has_finance_access());

drop policy if exists "Users can create own pending recharge requests" on public.recharge_requests;
create policy "Users can create own pending recharge requests"
on public.recharge_requests
for insert
to authenticated
with check (user_id = auth.uid() and status = 'pending');

drop policy if exists "Users can view own roles" on public.app_user_roles;
create policy "Users can view own roles"
on public.app_user_roles
for select
to authenticated
using (user_id = auth.uid());

create or replace function public.ensure_wallet(p_user_id uuid default auth.uid())
returns public.wallets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wallet public.wallets;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id is null then
    raise exception 'missing_user_id';
  end if;

  if p_user_id <> auth.uid() and not public.has_finance_access() then
    raise exception 'not_authorized';
  end if;

  insert into public.wallets (user_id)
  values (p_user_id)
  on conflict (user_id) do update
    set updated_at = public.wallets.updated_at
  returning * into v_wallet;

  return v_wallet;
end;
$$;

create or replace function public.request_recharge(
  p_requested_coins integer,
  p_method text,
  p_requested_amount_usd numeric default null,
  p_reference_code text default null,
  p_agent_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_public_user_id text;
  v_agent public.recharge_agents;
  v_request_id uuid;
  v_method text := lower(trim(coalesce(p_method, '')));
  v_agent_code text := nullif(trim(coalesce(p_agent_code, '')), '');
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_requested_coins is null or p_requested_coins <= 0 then
    raise exception 'invalid_requested_coins';
  end if;

  if v_method not in ('omt', 'wish', 'usdt', 'agent', 'cash', 'admin_manual') then
    raise exception 'invalid_recharge_method';
  end if;

  select p.public_user_id
  into v_public_user_id
  from public.profiles p
  where p.id = v_user_id;

  if v_agent_code is not null then
    select *
    into v_agent
    from public.recharge_agents ra
    where lower(ra.code) = lower(v_agent_code)
      and ra.is_active
    limit 1;
  end if;

  insert into public.recharge_requests (
    user_id,
    public_user_id,
    requested_coins,
    requested_amount_usd,
    method,
    reference_code,
    agent_code,
    agent_id,
    agency_id
  )
  values (
    v_user_id,
    v_public_user_id,
    p_requested_coins,
    p_requested_amount_usd,
    v_method,
    nullif(trim(coalesce(p_reference_code, '')), ''),
    v_agent_code,
    v_agent.id,
    v_agent.agency_id
  )
  returning id into v_request_id;

  return v_request_id;
end;
$$;

create or replace function public.approve_recharge_request(
  p_request_id uuid,
  p_admin_note text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_request public.recharge_requests;
  v_wallet public.wallets;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated';
  end if;

  if not public.has_finance_access() then
    raise exception 'not_authorized';
  end if;

  select *
  into v_request
  from public.recharge_requests rr
  where rr.id = p_request_id
  for update;

  if not found then
    raise exception 'recharge_request_not_found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'recharge_request_not_pending';
  end if;

  insert into public.wallets (user_id)
  values (v_request.user_id)
  on conflict (user_id) do nothing;

  update public.wallets
  set coins_balance = coins_balance + v_request.requested_coins,
      lifetime_coins_charged = lifetime_coins_charged + v_request.requested_coins,
      updated_at = now()
  where user_id = v_request.user_id
  returning * into v_wallet;

  update public.recharge_requests
  set status = 'approved',
      admin_user_id = v_admin_id,
      admin_note = nullif(trim(coalesce(p_admin_note, '')), ''),
      approved_at = now(),
      updated_at = now()
  where id = v_request.id;

  insert into public.wallet_transactions (
    user_id,
    type,
    direction,
    coins_delta,
    balance_coins_after,
    balance_diamonds_after,
    related_recharge_request_id,
    agency_id,
    agent_id,
    note
  )
  values (
    v_request.user_id,
    case when v_request.agent_id is null then 'recharge_request' else 'agency_recharge' end,
    'credit',
    v_request.requested_coins,
    v_wallet.coins_balance,
    v_wallet.diamonds_balance,
    v_request.id,
    v_request.agency_id,
    v_request.agent_id,
    p_admin_note
  );

  return true;
end;
$$;

create or replace function public.reject_recharge_request(
  p_request_id uuid,
  p_reject_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_request public.recharge_requests;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated';
  end if;

  if not public.has_finance_access() then
    raise exception 'not_authorized';
  end if;

  select *
  into v_request
  from public.recharge_requests rr
  where rr.id = p_request_id
  for update;

  if not found then
    raise exception 'recharge_request_not_found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'recharge_request_not_pending';
  end if;

  update public.recharge_requests
  set status = 'rejected',
      admin_user_id = v_admin_id,
      reject_reason = nullif(trim(coalesce(p_reject_reason, '')), ''),
      rejected_at = now(),
      updated_at = now()
  where id = v_request.id;

  return true;
end;
$$;

create or replace function public.send_gift_with_wallet(
  p_room_id uuid,
  p_receiver_id uuid,
  p_gift_id uuid,
  p_quantity integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_id uuid := auth.uid();
  v_quantity integer := greatest(coalesce(p_quantity, 1), 1);
  v_gift record;
  v_total_cost integer;
  v_diamonds_earned integer;
  v_sender_wallet public.wallets;
  v_receiver_wallet public.wallets;
  v_gift_transaction_id uuid;
begin
  if v_sender_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_receiver_id is null or p_receiver_id = v_sender_id then
    raise exception 'invalid_receiver';
  end if;

  if not exists (
    select 1
    from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = v_sender_id
      and rm.left_at is null
  ) then
    raise exception 'sender_not_in_room';
  end if;

  if not exists (
    select 1
    from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = p_receiver_id
      and rm.left_at is null
  ) then
    raise exception 'receiver_not_in_room';
  end if;

  select g.id, g.code, g.name, g.price_coins
  into v_gift
  from public.gifts g
  where g.id = p_gift_id
    and coalesce(g.is_active, true)
  limit 1;

  if not found then
    raise exception 'gift_not_found';
  end if;

  v_total_cost := (v_gift.price_coins::integer * v_quantity);
  v_diamonds_earned := v_total_cost;

  if v_total_cost <= 0 then
    raise exception 'invalid_gift_price';
  end if;

  insert into public.wallets (user_id)
  values (v_sender_id)
  on conflict (user_id) do nothing;

  insert into public.wallets (user_id)
  values (p_receiver_id)
  on conflict (user_id) do nothing;

  select *
  into v_sender_wallet
  from public.wallets
  where user_id = v_sender_id
  for update;

  if v_sender_wallet.coins_balance < v_total_cost then
    raise exception 'insufficient_coins';
  end if;

  update public.wallets
  set coins_balance = coins_balance - v_total_cost,
      lifetime_coins_spent = lifetime_coins_spent + v_total_cost,
      updated_at = now()
  where user_id = v_sender_id
  returning * into v_sender_wallet;

  update public.wallets
  set diamonds_balance = diamonds_balance + v_diamonds_earned,
      lifetime_diamonds_earned = lifetime_diamonds_earned + v_diamonds_earned,
      updated_at = now()
  where user_id = p_receiver_id
  returning * into v_receiver_wallet;

  insert into public.gift_transactions (
    room_id,
    sender_id,
    receiver_id,
    gift_id,
    gift_code,
    gift_name,
    gift_price_coins
  )
  values (
    p_room_id,
    v_sender_id,
    p_receiver_id,
    v_gift.id,
    v_gift.code,
    v_gift.name,
    v_total_cost
  )
  returning id into v_gift_transaction_id;

  insert into public.wallet_transactions (
    user_id,
    type,
    direction,
    coins_delta,
    balance_coins_after,
    balance_diamonds_after,
    related_user_id,
    related_room_id,
    related_gift_id,
    related_gift_transaction_id,
    note,
    metadata
  )
  values (
    v_sender_id,
    'gift_sent',
    'debit',
    -v_total_cost,
    v_sender_wallet.coins_balance,
    v_sender_wallet.diamonds_balance,
    p_receiver_id,
    p_room_id,
    v_gift.id,
    v_gift_transaction_id,
    'Gift sent',
    jsonb_build_object('quantity', v_quantity, 'gift_code', v_gift.code)
  );

  insert into public.wallet_transactions (
    user_id,
    type,
    direction,
    diamonds_delta,
    balance_coins_after,
    balance_diamonds_after,
    related_user_id,
    related_room_id,
    related_gift_id,
    related_gift_transaction_id,
    note,
    metadata
  )
  values (
    p_receiver_id,
    'gift_received',
    'credit',
    v_diamonds_earned,
    v_receiver_wallet.coins_balance,
    v_receiver_wallet.diamonds_balance,
    v_sender_id,
    p_room_id,
    v_gift.id,
    v_gift_transaction_id,
    'Gift received',
    jsonb_build_object('quantity', v_quantity, 'gift_code', v_gift.code)
  );

  return v_gift_transaction_id;
end;
$$;

grant usage on schema public to authenticated;
grant select on public.wallets to authenticated;
grant select on public.wallet_transactions to authenticated;
grant select on public.recharge_agencies to authenticated;
grant select on public.recharge_agents to authenticated;
grant select, insert on public.recharge_requests to authenticated;
grant select on public.app_user_roles to authenticated;

grant execute on function public.has_app_role(text) to authenticated;
grant execute on function public.has_finance_access() to authenticated;
grant execute on function public.ensure_wallet(uuid) to authenticated;
grant execute on function public.request_recharge(integer, text, numeric, text, text) to authenticated;
grant execute on function public.approve_recharge_request(uuid, text) to authenticated;
grant execute on function public.reject_recharge_request(uuid, text) to authenticated;
grant execute on function public.send_gift_with_wallet(uuid, uuid, uuid, integer) to authenticated;
