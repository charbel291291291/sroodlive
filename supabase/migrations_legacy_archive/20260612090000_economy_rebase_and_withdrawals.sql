-- ────────────────────────────────────────────────────────────────────────────
-- Economy rebase: 1 USD = 20,000 coins  (was 500,000)
-- Withdrawal system with revenue split:
--   Host WITH agency:    host 85% / agency owner 5% / platform 10%
--   Host WITHOUT agency: host 88% / platform 12%
-- Diamonds are earned 1:1 with gift coin value, so 20,000 diamonds = 1 USD
-- gross; the split is applied at cashout time.
-- ────────────────────────────────────────────────────────────────────────────

-- ── 1. Recharge packages → new rate ─────────────────────────────────────────

update public.recharge_packages
set coins_amount = (price_usd * 20000)::bigint,
    updated_at = now()
where price_usd > 0;

-- ── 2. Rescale coin-priced catalogs (÷25: preserves USD price) ──────────────
-- Old rate 500,000/USD → new rate 20,000/USD. A 2,500,000-coin VIP package
-- ($5) becomes 100,000 coins (still $5).

update public.vip_packages
set price_coins = greatest(1, (price_coins / 25)::bigint),
    updated_at = now()
where price_coins > 25;

update public.gifts
set price_coins = greatest(1, (price_coins / 25)::int)
where price_coins > 25;

-- Store badges (profile hub) — only if the table exists with coin pricing
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'store_badges'
      and column_name = 'price_coins'
  ) then
    update public.store_badges
    set price_coins = greatest(1, (price_coins / 25)::bigint)
    where price_coins > 25;
  end if;
end $$;

-- ── 3. request_recharge: new maximum cap (100 USD = 2,000,000 coins) ────────

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
  -- 2,000,000 coins = 100 USD at the 20,000 coins/USD rate
  c_max_coins constant integer := 2000000;
  -- 20,000 coins = 1 USD minimum
  c_min_coins constant integer := 20000;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_requested_coins is null or p_requested_coins <= 0 then
    raise exception 'invalid_requested_coins';
  end if;

  if p_requested_coins < c_min_coins then
    raise exception 'requested_coins_below_minimum';
  end if;

  if p_requested_coins > c_max_coins then
    raise exception 'requested_coins_exceeds_maximum';
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

-- ── 4. Extend wallet_transactions types for withdrawals ─────────────────────

alter table public.wallet_transactions
drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
add constraint wallet_transactions_type_check check (
  type in (
    'recharge_request',
    'admin_adjustment',
    'gift_sent',
    'gift_received',
    'agency_recharge',
    'refund',
    'system',
    'withdrawal',
    'withdrawal_refund',
    'agency_commission'
  )
);

-- ── 5. withdrawal_requests table ─────────────────────────────────────────────

create table if not exists public.withdrawal_requests (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references auth.users(id) on delete cascade,
  diamonds              integer not null check (diamonds > 0),
  method                text not null check (method in ('bank', 'paypal', 'wise')),
  account_details       text not null,
  notes                 text,
  -- Split snapshot (computed in SQL at request time — never by the client)
  gross_usd             numeric(12,2) not null default 0,
  host_share_usd        numeric(12,2) not null default 0,
  agency_share_usd      numeric(12,2) not null default 0,
  platform_share_usd    numeric(12,2) not null default 0,
  agency_id             uuid references public.agencies(id) on delete set null,
  agency_owner_user_id  uuid references auth.users(id) on delete set null,
  agency_share_diamonds integer not null default 0,
  status                text not null default 'pending'
                          check (status in ('pending', 'approved', 'rejected', 'paid')),
  admin_note            text,
  estimated_usd         numeric(12,2),  -- legacy column kept for compatibility
  created_at            timestamptz not null default now(),
  processed_at          timestamptz,
  processed_by          uuid references auth.users(id) on delete set null
);

-- If the table pre-existed (created manually from the dashboard), make sure
-- all split columns are present — create table if not exists won't add them.
alter table public.withdrawal_requests add column if not exists gross_usd             numeric(12,2) not null default 0;
alter table public.withdrawal_requests add column if not exists host_share_usd        numeric(12,2) not null default 0;
alter table public.withdrawal_requests add column if not exists agency_share_usd      numeric(12,2) not null default 0;
alter table public.withdrawal_requests add column if not exists platform_share_usd    numeric(12,2) not null default 0;
alter table public.withdrawal_requests add column if not exists agency_id             uuid references public.agencies(id) on delete set null;
alter table public.withdrawal_requests add column if not exists agency_owner_user_id  uuid references auth.users(id) on delete set null;
alter table public.withdrawal_requests add column if not exists agency_share_diamonds integer not null default 0;
alter table public.withdrawal_requests add column if not exists admin_note            text;
alter table public.withdrawal_requests add column if not exists processed_at          timestamptz;
alter table public.withdrawal_requests add column if not exists processed_by          uuid references auth.users(id) on delete set null;

alter table public.withdrawal_requests enable row level security;

drop policy if exists "withdrawal_requests_select_own" on public.withdrawal_requests;
create policy "withdrawal_requests_select_own"
  on public.withdrawal_requests for select to authenticated
  using (user_id = auth.uid() or public.has_finance_access());

-- Writes happen only through the security-definer RPCs below
grant select on public.withdrawal_requests to authenticated;

-- ── 6. request_withdrawal RPC ────────────────────────────────────────────────
-- Validates balance, computes the split SQL-side, holds the diamonds
-- immediately, and records the request. Frontend never decides amounts.

create or replace function public.request_withdrawal(
  p_diamonds integer,
  p_method text,
  p_account_details text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet public.wallets;
  v_agency_id uuid;
  v_agency_owner uuid;
  v_request_id uuid;
  v_gross_usd numeric(12,2);
  v_host_usd numeric(12,2);
  v_agency_usd numeric(12,2);
  v_platform_usd numeric(12,2);
  v_agency_diamonds integer := 0;
  v_method text := lower(trim(coalesce(p_method, '')));
  -- 20,000 diamonds = 1 USD gross
  c_diamonds_per_usd constant integer := 20000;
  -- Minimum withdrawal: 100,000 diamonds = 5 USD gross
  c_min_diamonds constant integer := 100000;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_diamonds is null or p_diamonds < c_min_diamonds then
    raise exception 'diamonds_below_minimum';
  end if;

  if v_method not in ('bank', 'paypal', 'wise') then
    raise exception 'invalid_withdrawal_method';
  end if;

  if nullif(trim(coalesce(p_account_details, '')), '') is null then
    raise exception 'account_details_required';
  end if;

  select * into v_wallet
  from public.wallets
  where user_id = v_user_id
  for update;

  if v_wallet is null or v_wallet.diamonds_balance < p_diamonds then
    raise exception 'insufficient_diamonds';
  end if;

  -- Active agency membership (not as the owner of their own agency)
  select am.agency_id, a.owner_user_id
  into v_agency_id, v_agency_owner
  from public.agency_members am
  join public.agencies a on a.id = am.agency_id
  where am.user_id = v_user_id
    and am.status = 'active'
    and a.status = 'active'
    and a.owner_user_id is not null
    and a.owner_user_id != v_user_id
  limit 1;

  v_gross_usd := round(p_diamonds::numeric / c_diamonds_per_usd, 2);

  if v_agency_id is not null then
    -- host 85% / agency 5% / platform 10%
    v_host_usd := round(v_gross_usd * 0.85, 2);
    v_agency_usd := round(v_gross_usd * 0.05, 2);
    v_platform_usd := v_gross_usd - v_host_usd - v_agency_usd;
    v_agency_diamonds := (p_diamonds * 5) / 100;
  else
    -- host 88% / platform 12%
    v_host_usd := round(v_gross_usd * 0.88, 2);
    v_agency_usd := 0;
    v_platform_usd := v_gross_usd - v_host_usd;
  end if;

  -- Hold the diamonds immediately
  update public.wallets
  set diamonds_balance = diamonds_balance - p_diamonds,
      updated_at = now()
  where user_id = v_user_id;

  insert into public.wallet_transactions (
    user_id, type, direction, coins_delta, diamonds_delta, note
  )
  values (
    v_user_id, 'withdrawal', 'debit', 0, -p_diamonds,
    'Withdrawal request hold'
  );

  insert into public.withdrawal_requests (
    user_id, diamonds, method, account_details, notes,
    gross_usd, host_share_usd, agency_share_usd, platform_share_usd,
    agency_id, agency_owner_user_id, agency_share_diamonds,
    estimated_usd, status
  )
  values (
    v_user_id, p_diamonds, v_method,
    trim(p_account_details), nullif(trim(coalesce(p_notes, '')), ''),
    v_gross_usd, v_host_usd, v_agency_usd, v_platform_usd,
    v_agency_id, v_agency_owner, v_agency_diamonds,
    v_host_usd, 'pending'
  )
  returning id into v_request_id;

  return v_request_id;
end;
$$;

grant execute on function public.request_withdrawal(integer, text, text, text) to authenticated;

-- ── 7. Withdrawal split preview (read-only, for the UI) ──────────────────────

create or replace function public.preview_withdrawal_split(p_diamonds integer)
returns table (
  gross_usd numeric,
  host_share_usd numeric,
  agency_share_usd numeric,
  platform_share_usd numeric,
  has_agency boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_has_agency boolean;
  v_gross numeric(12,2);
  c_diamonds_per_usd constant integer := 20000;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select exists (
    select 1
    from public.agency_members am
    join public.agencies a on a.id = am.agency_id
    where am.user_id = v_user_id
      and am.status = 'active'
      and a.status = 'active'
      and a.owner_user_id is not null
      and a.owner_user_id != v_user_id
  ) into v_has_agency;

  v_gross := round(coalesce(p_diamonds, 0)::numeric / c_diamonds_per_usd, 2);

  if v_has_agency then
    return query select
      v_gross,
      round(v_gross * 0.85, 2),
      round(v_gross * 0.05, 2),
      v_gross - round(v_gross * 0.85, 2) - round(v_gross * 0.05, 2),
      true;
  else
    return query select
      v_gross,
      round(v_gross * 0.88, 2),
      0::numeric,
      v_gross - round(v_gross * 0.88, 2),
      false;
  end if;
end;
$$;

grant execute on function public.preview_withdrawal_split(integer) to authenticated;

-- ── 8. Admin: approve withdrawal (credits agency owner share) ────────────────

create or replace function public.admin_approve_withdrawal(
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
  v_request public.withdrawal_requests;
begin
  if v_admin_id is null or not public.has_finance_access() then
    raise exception 'not_authorized';
  end if;

  select * into v_request
  from public.withdrawal_requests
  where id = p_request_id
  for update;

  if v_request is null then
    raise exception 'request_not_found';
  end if;

  if v_request.status != 'pending' then
    raise exception 'request_not_pending';
  end if;

  update public.withdrawal_requests
  set status = 'approved',
      admin_note = p_admin_note,
      processed_at = now(),
      processed_by = v_admin_id
  where id = p_request_id;

  -- Credit the agency owner their 5% share in diamonds
  if v_request.agency_owner_user_id is not null
     and v_request.agency_share_diamonds > 0 then
    insert into public.wallets (user_id, diamonds_balance, lifetime_diamonds_earned)
    values (v_request.agency_owner_user_id, v_request.agency_share_diamonds, v_request.agency_share_diamonds)
    on conflict (user_id) do update
      set diamonds_balance = public.wallets.diamonds_balance + v_request.agency_share_diamonds,
          lifetime_diamonds_earned = public.wallets.lifetime_diamonds_earned + v_request.agency_share_diamonds,
          updated_at = now();

    insert into public.wallet_transactions (
      user_id, type, direction, coins_delta, diamonds_delta, agency_id, note
    )
    values (
      v_request.agency_owner_user_id, 'agency_commission', 'credit',
      0, v_request.agency_share_diamonds, v_request.agency_id,
      'Agency 5% share of host withdrawal'
    );
  end if;

  perform public.admin_record_audit(
    'withdrawal_approved',
    'withdrawal_requests',
    p_request_id::text,
    v_request.user_id,
    jsonb_build_object(
      'diamonds', v_request.diamonds,
      'host_share_usd', v_request.host_share_usd,
      'agency_share_usd', v_request.agency_share_usd,
      'platform_share_usd', v_request.platform_share_usd
    )
  );

  return true;
end;
$$;

grant execute on function public.admin_approve_withdrawal(uuid, text) to authenticated;

-- ── 9. Admin: reject withdrawal (refunds the held diamonds) ──────────────────

create or replace function public.admin_reject_withdrawal(
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
  v_request public.withdrawal_requests;
begin
  if v_admin_id is null or not public.has_finance_access() then
    raise exception 'not_authorized';
  end if;

  select * into v_request
  from public.withdrawal_requests
  where id = p_request_id
  for update;

  if v_request is null then
    raise exception 'request_not_found';
  end if;

  if v_request.status != 'pending' then
    raise exception 'request_not_pending';
  end if;

  update public.withdrawal_requests
  set status = 'rejected',
      admin_note = p_admin_note,
      processed_at = now(),
      processed_by = v_admin_id
  where id = p_request_id;

  -- Refund the held diamonds
  update public.wallets
  set diamonds_balance = diamonds_balance + v_request.diamonds,
      updated_at = now()
  where user_id = v_request.user_id;

  insert into public.wallet_transactions (
    user_id, type, direction, coins_delta, diamonds_delta, note
  )
  values (
    v_request.user_id, 'withdrawal_refund', 'credit',
    0, v_request.diamonds, 'Withdrawal request rejected — diamonds refunded'
  );

  perform public.admin_record_audit(
    'withdrawal_rejected',
    'withdrawal_requests',
    p_request_id::text,
    v_request.user_id,
    jsonb_build_object('diamonds', v_request.diamonds, 'note', p_admin_note)
  );

  return true;
end;
$$;

grant execute on function public.admin_reject_withdrawal(uuid, text) to authenticated;
