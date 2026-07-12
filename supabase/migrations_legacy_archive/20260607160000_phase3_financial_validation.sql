-- Phase 3: Financial validation hardening
-- Adds upper-bound caps and audit logging to coin operations.
-- All functions use SECURITY DEFINER set search_path = public.

-- â”€â”€â”€ 1. request_recharge: add maximum coin cap â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
  -- 50,000,000 coins = 100 USD at the 500,000 coins/USD rate
  c_max_coins constant integer := 50000000;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_requested_coins is null or p_requested_coins <= 0 then
    raise exception 'invalid_requested_coins';
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

-- â”€â”€â”€ 2. approve_recharge_request: add admin_record_audit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  perform public.admin_record_audit(
    'approve_recharge',
    'recharge_requests',
    v_request.id::text,
    v_request.user_id,
    jsonb_build_object(
      'coins', v_request.requested_coins,
      'method', v_request.method,
      'balance_after', v_wallet.coins_balance
    )
  );

  return true;
end;
$$;

-- â”€â”€â”€ 3. admin_manual_wallet_adjustment: add cap + admin_record_audit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

create or replace function public.admin_manual_wallet_adjustment(
  p_user_id uuid,
  p_coins_delta integer default 0,
  p_diamonds_delta integer default 0,
  p_note text default null
)
returns public.wallets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_wallet public.wallets;
  v_coins_delta integer := coalesce(p_coins_delta, 0);
  v_diamonds_delta integer := coalesce(p_diamonds_delta, 0);
  -- 1 billion coins absolute cap per single admin operation
  c_max_abs_delta constant integer := 1000000000;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated';
  end if;

  if not (public.has_app_role('super_admin') or public.has_app_role('finance_admin')) then
    raise exception 'not_authorized';
  end if;

  if p_user_id is null then
    raise exception 'missing_user_id';
  end if;

  if v_coins_delta = 0 and v_diamonds_delta = 0 then
    raise exception 'empty_adjustment';
  end if;

  if abs(v_coins_delta) > c_max_abs_delta then
    raise exception 'coins_delta_exceeds_maximum';
  end if;

  if abs(v_diamonds_delta) > c_max_abs_delta then
    raise exception 'diamonds_delta_exceeds_maximum';
  end if;

  insert into public.wallets (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select *
  into v_wallet
  from public.wallets
  where user_id = p_user_id
  for update;

  if v_wallet.coins_balance + v_coins_delta < 0
     or v_wallet.diamonds_balance + v_diamonds_delta < 0 then
    raise exception 'negative_balance_not_allowed';
  end if;

  update public.wallets
  set coins_balance = coins_balance + v_coins_delta,
      diamonds_balance = diamonds_balance + v_diamonds_delta,
      lifetime_coins_charged = lifetime_coins_charged + greatest(v_coins_delta, 0),
      lifetime_diamonds_earned = lifetime_diamonds_earned + greatest(v_diamonds_delta, 0),
      updated_at = now()
  where user_id = p_user_id
  returning * into v_wallet;

  insert into public.wallet_transactions (
    user_id,
    type,
    direction,
    coins_delta,
    diamonds_delta,
    balance_coins_after,
    balance_diamonds_after,
    note,
    metadata
  )
  values (
    p_user_id,
    'admin_adjustment',
    case
      when v_coins_delta > 0 or v_diamonds_delta > 0 then 'credit'
      when v_coins_delta < 0 or v_diamonds_delta < 0 then 'debit'
      else 'neutral'
    end,
    v_coins_delta,
    v_diamonds_delta,
    v_wallet.coins_balance,
    v_wallet.diamonds_balance,
    nullif(trim(coalesce(p_note, '')), ''),
    jsonb_build_object('admin_user_id', v_admin_id)
  );

  perform public.admin_record_audit(
    'admin_wallet_adjustment',
    'wallets',
    p_user_id::text,
    p_user_id,
    jsonb_build_object(
      'coins_delta', v_coins_delta,
      'diamonds_delta', v_diamonds_delta,
      'balance_coins_after', v_wallet.coins_balance,
      'balance_diamonds_after', v_wallet.diamonds_balance,
      'note', p_note
    )
  );

  return v_wallet;
end;
$$;

-- Grants (unchanged from original â€” functions already existed and were granted)
grant execute on function public.request_recharge(integer, text, numeric, text, text) to authenticated;
grant execute on function public.approve_recharge_request(uuid, text) to authenticated;
grant execute on function public.admin_manual_wallet_adjustment(uuid, integer, integer, text) to authenticated;
