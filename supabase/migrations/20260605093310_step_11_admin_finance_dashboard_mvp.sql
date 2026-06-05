create or replace function public.has_admin_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_app_role('super_admin')
      or public.has_app_role('finance_admin')
      or public.has_app_role('admin');
$$;

create or replace function public.admin_dashboard_overview()
returns table (
  pending_recharge_count bigint,
  approved_recharge_count_today bigint,
  total_coins_charged_today bigint,
  total_gift_coins_spent_today bigint,
  total_diamonds_earned_today bigint,
  total_gift_transactions_today bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from public.recharge_requests where status = 'pending'),
    (select count(*) from public.recharge_requests where status = 'approved' and approved_at >= date_trunc('day', now())),
    coalesce((select sum(requested_coins)::bigint from public.recharge_requests where status = 'approved' and approved_at >= date_trunc('day', now())), 0),
    coalesce((select abs(sum(coins_delta))::bigint from public.wallet_transactions where type = 'gift_sent' and created_at >= date_trunc('day', now())), 0),
    coalesce((select sum(diamonds_delta)::bigint from public.wallet_transactions where type = 'gift_received' and created_at >= date_trunc('day', now())), 0),
    (select count(*) from public.gift_transactions where created_at >= date_trunc('day', now()))
  where public.has_admin_access();
$$;

create or replace function public.admin_list_recharge_requests(
  p_status text default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  user_id uuid,
  public_user_id text,
  nickname text,
  requested_coins integer,
  requested_amount_usd numeric,
  method text,
  reference_code text,
  agent_code text,
  status text,
  created_at timestamptz,
  agency_name text,
  agent_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    rr.id,
    rr.user_id,
    rr.public_user_id,
    coalesce(nullif(p.display_name, ''), nullif(p.username, '')) as nickname,
    rr.requested_coins,
    rr.requested_amount_usd,
    rr.method,
    rr.reference_code,
    rr.agent_code,
    rr.status,
    rr.created_at,
    ra.name as agency_name,
    rag.name as agent_name
  from public.recharge_requests rr
  left join public.profiles p on p.id = rr.user_id
  left join public.recharge_agencies ra on ra.id = rr.agency_id
  left join public.recharge_agents rag on rag.id = rr.agent_id
  where public.has_admin_access()
    and (p_status is null or rr.status = p_status)
  order by rr.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

create or replace function public.admin_wallet_lookup_by_public_id(
  p_public_user_id text
)
returns table (
  user_id uuid,
  public_user_id text,
  nickname text,
  avatar_url text,
  coins_balance integer,
  diamonds_balance integer,
  lifetime_coins_charged integer,
  lifetime_coins_spent integer,
  lifetime_diamonds_earned integer,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.public_user_id,
    coalesce(nullif(p.display_name, ''), nullif(p.username, '')) as nickname,
    p.avatar_url,
    coalesce(w.coins_balance, 0),
    coalesce(w.diamonds_balance, 0),
    coalesce(w.lifetime_coins_charged, 0),
    coalesce(w.lifetime_coins_spent, 0),
    coalesce(w.lifetime_diamonds_earned, 0),
    w.created_at,
    w.updated_at
  from public.profiles p
  left join public.wallets w on w.user_id = p.id
  where public.has_admin_access()
    and lower(p.public_user_id) = lower(trim(p_public_user_id))
  limit 1;
$$;

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

  return v_wallet;
end;
$$;

create or replace function public.admin_list_wallet_transactions(
  p_limit integer default 50
)
returns table (
  id uuid,
  user_id uuid,
  public_user_id text,
  nickname text,
  type text,
  direction text,
  coins_delta integer,
  diamonds_delta integer,
  note text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    wt.id,
    wt.user_id,
    p.public_user_id,
    coalesce(nullif(p.display_name, ''), nullif(p.username, '')) as nickname,
    wt.type,
    wt.direction,
    wt.coins_delta,
    wt.diamonds_delta,
    wt.note,
    wt.created_at
  from public.wallet_transactions wt
  left join public.profiles p on p.id = wt.user_id
  where public.has_admin_access()
  order by wt.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

create or replace function public.admin_list_gift_transactions(
  p_limit integer default 50
)
returns table (
  id uuid,
  room_id uuid,
  sender_id uuid,
  sender_public_user_id text,
  receiver_id uuid,
  receiver_public_user_id text,
  gift_name text,
  gift_code text,
  gift_price_coins integer,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    gt.id,
    gt.room_id,
    gt.sender_id,
    sp.public_user_id,
    gt.receiver_id,
    rp.public_user_id,
    gt.gift_name,
    gt.gift_code,
    gt.gift_price_coins,
    gt.created_at
  from public.gift_transactions gt
  left join public.profiles sp on sp.id = gt.sender_id
  left join public.profiles rp on rp.id = gt.receiver_id
  where public.has_admin_access()
  order by gt.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

create or replace function public.admin_list_recharge_agencies()
returns table (
  id uuid,
  name text,
  code text,
  country text,
  whatsapp text,
  is_active boolean,
  commission_rate numeric,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select id, name, code, country, whatsapp, is_active, commission_rate, created_at
  from public.recharge_agencies
  where public.has_admin_access()
  order by created_at desc;
$$;

create or replace function public.admin_list_recharge_agents()
returns table (
  id uuid,
  agency_id uuid,
  agency_code text,
  agency_name text,
  name text,
  code text,
  whatsapp text,
  is_active boolean,
  commission_rate numeric,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    rag.id,
    rag.agency_id,
    ra.code,
    ra.name,
    rag.name,
    rag.code,
    rag.whatsapp,
    rag.is_active,
    rag.commission_rate,
    rag.created_at
  from public.recharge_agents rag
  left join public.recharge_agencies ra on ra.id = rag.agency_id
  where public.has_admin_access()
  order by rag.created_at desc;
$$;

create or replace function public.admin_create_recharge_agency(
  p_name text,
  p_code text,
  p_country text default null,
  p_whatsapp text default null,
  p_commission_rate numeric default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  insert into public.recharge_agencies (name, code, country, whatsapp, commission_rate)
  values (
    trim(p_name),
    upper(trim(p_code)),
    nullif(trim(coalesce(p_country, '')), ''),
    nullif(trim(coalesce(p_whatsapp, '')), ''),
    coalesce(p_commission_rate, 0)
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.admin_create_recharge_agent(
  p_agency_code text,
  p_name text,
  p_code text,
  p_whatsapp text default null,
  p_commission_rate numeric default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agency_id uuid;
  v_id uuid;
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  select id into v_agency_id
  from public.recharge_agencies
  where upper(code) = upper(trim(p_agency_code))
  limit 1;

  if v_agency_id is null then
    raise exception 'agency_not_found';
  end if;

  insert into public.recharge_agents (agency_id, name, code, whatsapp, commission_rate)
  values (
    v_agency_id,
    trim(p_name),
    upper(trim(p_code)),
    nullif(trim(coalesce(p_whatsapp, '')), ''),
    coalesce(p_commission_rate, 0)
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.has_admin_access() to authenticated;
grant execute on function public.admin_dashboard_overview() to authenticated;
grant execute on function public.admin_list_recharge_requests(text, integer) to authenticated;
grant execute on function public.admin_wallet_lookup_by_public_id(text) to authenticated;
grant execute on function public.admin_manual_wallet_adjustment(uuid, integer, integer, text) to authenticated;
grant execute on function public.admin_list_wallet_transactions(integer) to authenticated;
grant execute on function public.admin_list_gift_transactions(integer) to authenticated;
grant execute on function public.admin_list_recharge_agencies() to authenticated;
grant execute on function public.admin_list_recharge_agents() to authenticated;
grant execute on function public.admin_create_recharge_agency(text, text, text, text, numeric) to authenticated;
grant execute on function public.admin_create_recharge_agent(text, text, text, text, numeric) to authenticated;
