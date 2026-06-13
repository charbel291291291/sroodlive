-- Raise the request_recharge hard cap from 2,000,000 to 2,500,000 coins.
--
-- Reason: the $100 coin package includes a 20% bonus (2,400,000 total coins),
-- which exceeds the old cap of 2,000,000. The new cap gives headroom for the
-- current max package plus a small buffer.
--
-- The business rule remains "max $100 USD base cost". The cap is expressed in
-- coins to accommodate bonus tiers without requiring per-package exceptions.

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
  -- 2,500,000 coins = $100 base + 25% bonus headroom at 20,000 coins/USD
  c_max_coins constant integer := 2500000;
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

grant execute on function public.request_recharge(integer, text, numeric, text, text) to authenticated;
