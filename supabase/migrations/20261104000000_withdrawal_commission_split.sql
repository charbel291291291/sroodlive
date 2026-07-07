-- ────────────────────────────────────────────────────────────────────────────
-- Phase 3: wire agency commission_rate into the host withdrawal split.
--
-- Backend only. No games, no IAP, no client/screen changes. Withdrawals stay
-- diamond-based, row-locked, and derive the agency SERVER-SIDE from the
-- authoritative active agency_hosts membership (never from the client).
--
-- Model change (see comments below for exact formulas):
--   * Agency host: the agency share is now agencies.commission_rate × gross
--     (was a hardcoded 5%). Platform keeps a fixed 10% for agency hosts; the
--     host receives the remainder. Backward-compatible: at commission_rate = 0.05
--     the split is identical to the previous 85/5/10.
--   * Independent host: unchanged 88% / 12% (preserved separately).
--
-- admin_approve_withdrawal already credits the owner the STORED
-- agency_share_diamonds, so fixing the request-time computation flows through.
-- admin_reject_withdrawal already refunds held diamonds — left unchanged.
-- ────────────────────────────────────────────────────────────────────────────


-- ── request_withdrawal ──────────────────────────────────────────────────────
create or replace function public.request_withdrawal(
  p_diamonds integer, p_method text, p_account_details text, p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id       uuid := auth.uid();
  v_wallet        public.wallets;
  v_agency_id     uuid;
  v_agency_owner  uuid;
  v_rate          numeric;
  v_request_id    uuid;
  v_gross_usd     numeric(12,2);
  v_host_usd      numeric(12,2);
  v_agency_usd    numeric(12,2);
  v_platform_usd  numeric(12,2);
  v_agency_diamonds integer := 0;
  v_method        text := lower(trim(coalesce(p_method, '')));
  c_diamonds_per_usd constant integer := 20000;   -- 20,000 diamonds = 1 USD gross
  c_min_diamonds     constant integer := 100000;  -- min 100,000 diamonds = 5 USD
  c_platform_agency  constant numeric := 0.10;     -- platform share, agency host
  c_platform_solo    constant numeric := 0.12;     -- platform share, independent
  c_rate_cap         constant numeric := 0.80;     -- host always keeps >= 10%
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_diamonds is null or p_diamonds < c_min_diamonds then
    raise exception 'diamonds_below_minimum';
  end if;
  if v_method not in ('bank', 'paypal', 'wise') then
    raise exception 'invalid_withdrawal_method';
  end if;
  if nullif(trim(coalesce(p_account_details, '')), '') is null then
    raise exception 'account_details_required';
  end if;

  -- Row-lock the wallet FIRST so concurrent requests for this user serialize
  -- here; the duplicate-pending check below is then race-free.
  select * into v_wallet
  from public.wallets
  where user_id = v_user_id
  for update;
  if v_wallet is null or v_wallet.diamonds_balance < p_diamonds then
    raise exception 'insufficient_diamonds';
  end if;

  -- Duplicate-withdrawal safety: at most one pending request at a time.
  if exists (
    select 1 from public.withdrawal_requests
    where user_id = v_user_id and status = 'pending'
  ) then
    raise exception 'withdrawal_already_pending';
  end if;

  -- Agency derived SERVER-SIDE from the authoritative active agency_hosts
  -- membership. Only a DIFFERENT-owner, ACTIVE agency counts; an inactive
  -- agency (or none) => the host is treated as independent.
  select ah.agency_id, a.owner_user_id, a.commission_rate
  into v_agency_id, v_agency_owner, v_rate
  from public.agency_hosts ah
  join public.agencies a on a.id = ah.agency_id
  where ah.host_user_id = v_user_id
    and ah.status = 'active'
    and a.status = 'active'
    and a.owner_user_id is not null
    and a.owner_user_id <> v_user_id
  order by ah.joined_at desc
  limit 1;

  v_gross_usd := round(p_diamonds::numeric / c_diamonds_per_usd, 2);

  if v_agency_id is not null then
    -- Agency host: agency = commission_rate × gross, platform = 10% × gross,
    -- host = remainder. commission_rate is clamped to [0, 0.80].
    v_rate := least(greatest(coalesce(v_rate, 0), 0), c_rate_cap);
    v_agency_usd   := round(v_gross_usd * v_rate, 2);
    v_platform_usd := round(v_gross_usd * c_platform_agency, 2);
    v_host_usd     := v_gross_usd - v_agency_usd - v_platform_usd;
    v_agency_diamonds := floor(p_diamonds::numeric * v_rate)::integer;
  else
    -- Independent host: 88% / 12% (preserved separately, unchanged).
    v_host_usd     := round(v_gross_usd * (1 - c_platform_solo), 2);
    v_agency_usd   := 0;
    v_platform_usd := v_gross_usd - v_host_usd;
    v_agency_id    := null;
    v_agency_owner := null;
    v_agency_diamonds := 0;
  end if;

  -- Hold the diamonds immediately.
  update public.wallets
  set diamonds_balance = diamonds_balance - p_diamonds, updated_at = now()
  where user_id = v_user_id;

  insert into public.wallet_transactions (
    user_id, type, direction, coins_delta, diamonds_delta, note, metadata
  )
  values (
    v_user_id, 'withdrawal', 'debit', 0, -p_diamonds, 'Withdrawal request hold',
    jsonb_build_object(
      'gross_usd', v_gross_usd, 'host_usd', v_host_usd,
      'agency_usd', v_agency_usd, 'platform_usd', v_platform_usd,
      'agency_id', v_agency_id,
      'commission_rate', case when v_agency_id is not null then v_rate else null end)
  );

  insert into public.withdrawal_requests (
    user_id, diamonds, method, account_details, notes,
    gross_usd, host_share_usd, agency_share_usd, platform_share_usd,
    agency_id, agency_owner_user_id, agency_share_diamonds, estimated_usd, status
  )
  values (
    v_user_id, p_diamonds, v_method,
    trim(p_account_details), nullif(trim(coalesce(p_notes, '')), ''),
    v_gross_usd, v_host_usd, v_agency_usd, v_platform_usd,
    v_agency_id, v_agency_owner, v_agency_diamonds, v_host_usd, 'pending'
  )
  returning id into v_request_id;

  return v_request_id;
end;
$function$;


-- ── preview_withdrawal_split (mirror of the above, read-only) ────────────────
create or replace function public.preview_withdrawal_split(p_diamonds integer)
returns table (
  gross_usd numeric, host_share_usd numeric, agency_share_usd numeric,
  platform_share_usd numeric, has_agency boolean
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_rate    numeric;
  v_has     boolean := false;
  v_gross   numeric(12,2);
  c_diamonds_per_usd constant integer := 20000;
  c_platform_agency  constant numeric := 0.10;
  c_platform_solo    constant numeric := 0.12;
  c_rate_cap         constant numeric := 0.80;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select a.commission_rate into v_rate
  from public.agency_hosts ah
  join public.agencies a on a.id = ah.agency_id
  where ah.host_user_id = v_user_id
    and ah.status = 'active'
    and a.status = 'active'
    and a.owner_user_id is not null
    and a.owner_user_id <> v_user_id
  order by ah.joined_at desc
  limit 1;
  v_has := found;

  v_gross := round(coalesce(p_diamonds, 0)::numeric / c_diamonds_per_usd, 2);

  if v_has then
    v_rate := least(greatest(coalesce(v_rate, 0), 0), c_rate_cap);
    return query select
      v_gross,
      v_gross - round(v_gross * v_rate, 2) - round(v_gross * c_platform_agency, 2),
      round(v_gross * v_rate, 2),
      round(v_gross * c_platform_agency, 2),
      true;
  else
    return query select
      v_gross,
      round(v_gross * (1 - c_platform_solo), 2),
      0::numeric,
      v_gross - round(v_gross * (1 - c_platform_solo), 2),
      false;
  end if;
end;
$function$;


-- ── admin_approve_withdrawal: fix the now-variable commission note ───────────
-- Body byte-for-byte identical to the current definition except the ledger
-- note no longer hardcodes "5%" (the amount is the stored agency_share_diamonds,
-- which is now commission_rate-driven).
create or replace function public.admin_approve_withdrawal(
  p_request_id uuid, p_admin_note text default null
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
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

  if v_request is null then raise exception 'request_not_found'; end if;
  if v_request.status != 'pending' then raise exception 'request_not_pending'; end if;

  update public.withdrawal_requests
  set status = 'approved', admin_note = p_admin_note,
      processed_at = now(), processed_by = v_admin_id
  where id = p_request_id;

  -- Credit the agency owner their commission share in diamonds.
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
      'Agency commission share of host withdrawal'
    );
  end if;

  perform public.admin_record_audit(
    'withdrawal_approved', 'withdrawal_requests', p_request_id::text, v_request.user_id,
    jsonb_build_object(
      'diamonds', v_request.diamonds,
      'host_share_usd', v_request.host_share_usd,
      'agency_share_usd', v_request.agency_share_usd,
      'platform_share_usd', v_request.platform_share_usd));

  return true;
end;
$function$;
