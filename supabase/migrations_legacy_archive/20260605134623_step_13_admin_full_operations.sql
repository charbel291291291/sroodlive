alter table public.gifts
add column if not exists category text not null default 'hot';

drop function if exists public.admin_list_gifts(integer);

create or replace function public.admin_list_gifts(
  p_limit integer default 100
)
returns table (
  id uuid,
  code text,
  name text,
  arabic_name text,
  price_coins integer,
  icon text,
  category text,
  is_active boolean,
  sort_order integer,
  sent_count bigint,
  coins_spent bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    g.id,
    g.code,
    g.name,
    g.arabic_name,
    g.price_coins,
    g.icon,
    g.category,
    g.is_active,
    g.sort_order,
    coalesce(count(gt.id), 0),
    coalesce(sum(gt.gift_price_coins), 0)::bigint
  from public.gifts g
  left join public.gift_transactions gt on gt.gift_id = g.id
  where public.has_admin_access()
  group by
    g.id,
    g.code,
    g.name,
    g.arabic_name,
    g.price_coins,
    g.icon,
    g.category,
    g.is_active,
    g.sort_order
  order by g.sort_order asc, g.price_coins asc
  limit greatest(1, least(coalesce(p_limit, 100), 200));
$$;

create table if not exists public.admin_user_restrictions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  restriction_type text not null check (
    restriction_type in ('account_ban', 'room_ban', 'chat_mute', 'gift_block')
  ),
  reason text null,
  is_active boolean not null default true,
  expires_at timestamptz null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists admin_user_restrictions_user_idx
on public.admin_user_restrictions (user_id, is_active, restriction_type);

alter table public.admin_user_restrictions enable row level security;

drop policy if exists "Admins can view user restrictions" on public.admin_user_restrictions;
create policy "Admins can view user restrictions"
on public.admin_user_restrictions
for select
to authenticated
using (public.has_admin_access());

grant select on public.admin_user_restrictions to authenticated;

create or replace function public.admin_user_detail(
  p_user_id uuid
)
returns table (
  user_id uuid,
  email text,
  public_user_id text,
  display_name text,
  username text,
  avatar_url text,
  bio text,
  date_of_birth date,
  vip_level integer,
  vip_title text,
  vip_started_at timestamptz,
  vip_expires_at timestamptz,
  selected_avatar_frame_key text,
  coins_balance integer,
  diamonds_balance integer,
  lifetime_coins_charged integer,
  lifetime_coins_spent integer,
  lifetime_diamonds_earned integer,
  roles text[],
  active_restrictions jsonb,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    u.email::text,
    p.public_user_id,
    p.display_name,
    p.username,
    p.avatar_url,
    p.bio,
    p.date_of_birth,
    coalesce(p.vip_level, 0),
    p.vip_title,
    p.vip_started_at,
    p.vip_expires_at,
    p.selected_avatar_frame_key,
    coalesce(w.coins_balance, 0),
    coalesce(w.diamonds_balance, 0),
    coalesce(w.lifetime_coins_charged, 0),
    coalesce(w.lifetime_coins_spent, 0),
    coalesce(w.lifetime_diamonds_earned, 0),
    coalesce(array_remove(array_agg(distinct aur.role), null), array[]::text[]),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'type', r.restriction_type,
            'reason', r.reason,
            'expires_at', r.expires_at,
            'created_at', r.created_at
          )
          order by r.created_at desc
        )
        from public.admin_user_restrictions r
        where r.user_id = p.id
          and r.is_active
          and (r.expires_at is null or r.expires_at > now())
      ),
      '[]'::jsonb
    ),
    p.created_at
  from public.profiles p
  left join auth.users u on u.id = p.id
  left join public.wallets w on w.user_id = p.id
  left join public.app_user_roles aur on aur.user_id = p.id
  where public.has_admin_access()
    and p.id = p_user_id
  group by
    p.id,
    u.email,
    p.public_user_id,
    p.display_name,
    p.username,
    p.avatar_url,
    p.bio,
    p.date_of_birth,
    p.vip_level,
    p.vip_title,
    p.vip_started_at,
    p.vip_expires_at,
    p.selected_avatar_frame_key,
    w.coins_balance,
    w.diamonds_balance,
    w.lifetime_coins_charged,
    w.lifetime_coins_spent,
    w.lifetime_diamonds_earned,
    p.created_at
  limit 1;
$$;

create or replace function public.admin_update_user_profile(
  p_user_id uuid,
  p_display_name text default null,
  p_username text default null,
  p_avatar_url text default null,
  p_bio text default null,
  p_vip_level integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    public.has_app_role('super_admin')
    or public.has_app_role('support_admin')
  ) then
    raise exception 'not_authorized';
  end if;

  update public.profiles
  set display_name = p_display_name,
      username = p_username,
      avatar_url = p_avatar_url,
      bio = p_bio,
      vip_level = coalesce(p_vip_level, vip_level),
      vip_started_at = case
        when p_vip_level is null then vip_started_at
        when p_vip_level > 0 and vip_level <> p_vip_level then now()
        when p_vip_level = 0 then null
        else vip_started_at
      end,
      vip_expires_at = case
        when p_vip_level is null then vip_expires_at
        when p_vip_level = 0 then null
        else vip_expires_at
      end
  where id = p_user_id;

  perform public.admin_record_audit(
    'update_user_profile',
    'profiles',
    p_user_id::text,
    p_user_id,
    jsonb_build_object('vip_level', p_vip_level)
  );
end;
$$;

create or replace function public.admin_set_user_restriction(
  p_user_id uuid,
  p_restriction_type text,
  p_is_active boolean,
  p_reason text default null,
  p_expires_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text := lower(trim(coalesce(p_restriction_type, '')));
begin
  if not (
    public.has_app_role('super_admin')
    or public.has_app_role('support_admin')
    or public.has_app_role('room_admin')
    or public.has_app_role('moderator')
  ) then
    raise exception 'not_authorized';
  end if;

  if v_type not in ('account_ban', 'room_ban', 'chat_mute', 'gift_block') then
    raise exception 'invalid_restriction_type';
  end if;

  if coalesce(p_is_active, false) then
    insert into public.admin_user_restrictions (
      user_id,
      restriction_type,
      reason,
      is_active,
      expires_at,
      created_by,
      updated_at
    )
    values (
      p_user_id,
      v_type,
      nullif(trim(coalesce(p_reason, '')), ''),
      true,
      p_expires_at,
      auth.uid(),
      now()
    );
  else
    update public.admin_user_restrictions
    set is_active = false,
        updated_at = now()
    where user_id = p_user_id
      and restriction_type = v_type
      and is_active;
  end if;

  perform public.admin_record_audit(
    case when coalesce(p_is_active, false) then 'add_restriction' else 'remove_restriction' end,
    'admin_user_restrictions',
    p_user_id::text,
    p_user_id,
    jsonb_build_object('restriction_type', v_type, 'reason', p_reason)
  );
end;
$$;

create or replace function public.admin_user_wallet_transactions(
  p_user_id uuid,
  p_limit integer default 50
)
returns table (
  id uuid,
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
  select id, type, direction, coins_delta, diamonds_delta, note, created_at
  from public.wallet_transactions
  where public.has_admin_access()
    and user_id = p_user_id
  order by created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

create or replace function public.admin_user_recharge_requests(
  p_user_id uuid,
  p_limit integer default 50
)
returns table (
  id uuid,
  requested_coins integer,
  requested_amount_usd numeric,
  method text,
  status text,
  reference_code text,
  agent_code text,
  created_at timestamptz,
  approved_at timestamptz,
  rejected_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    id,
    requested_coins,
    requested_amount_usd,
    method,
    status,
    reference_code,
    agent_code,
    created_at,
    approved_at,
    rejected_at
  from public.recharge_requests
  where public.has_admin_access()
    and user_id = p_user_id
  order by created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

create or replace function public.admin_user_gift_transactions(
  p_user_id uuid,
  p_limit integer default 50
)
returns table (
  id uuid,
  direction text,
  room_id uuid,
  other_user_id uuid,
  other_public_user_id text,
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
    case when gt.sender_id = p_user_id then 'sent' else 'received' end,
    gt.room_id,
    case when gt.sender_id = p_user_id then gt.receiver_id else gt.sender_id end,
    op.public_user_id,
    gt.gift_name,
    gt.gift_code,
    gt.gift_price_coins,
    gt.created_at
  from public.gift_transactions gt
  left join public.profiles op
    on op.id = case when gt.sender_id = p_user_id then gt.receiver_id else gt.sender_id end
  where public.has_admin_access()
    and (gt.sender_id = p_user_id or gt.receiver_id = p_user_id)
  order by gt.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

create or replace function public.admin_close_room(
  p_room_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  if not public.has_room_admin_access() then
    raise exception 'not_authorized';
  end if;

  update public.room_members
  set is_muted = true,
      seat_number = null,
      left_at = v_now,
      last_seen_at = v_now
  where room_id = p_room_id
    and left_at is null;

  perform public.admin_record_audit(
    'close_room',
    'rooms',
    p_room_id::text,
    null,
    jsonb_build_object('reason', p_reason)
  );
end;
$$;

create or replace function public.admin_kick_room_member(
  p_room_id uuid,
  p_user_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  if not public.has_room_admin_access() then
    raise exception 'not_authorized';
  end if;

  update public.room_members
  set is_muted = true,
      seat_number = null,
      left_at = v_now,
      last_seen_at = v_now
  where room_id = p_room_id
    and user_id = p_user_id
    and left_at is null;

  perform public.admin_record_audit(
    'kick_room_member',
    'room_members',
    p_room_id::text,
    p_user_id,
    jsonb_build_object('reason', p_reason)
  );
end;
$$;

create or replace function public.admin_update_gift(
  p_gift_id uuid default null,
  p_code text default null,
  p_name text default null,
  p_arabic_name text default null,
  p_price_coins integer default null,
  p_icon text default null,
  p_category text default 'hot',
  p_is_active boolean default true,
  p_sort_order integer default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.has_content_admin_access() then
    raise exception 'not_authorized';
  end if;

  if p_gift_id is null then
    insert into public.gifts (
      code,
      name,
      arabic_name,
      price_coins,
      icon,
      category,
      is_active,
      sort_order
    )
    values (
      lower(trim(coalesce(p_code, ''))),
      trim(coalesce(p_name, 'Gift')),
      nullif(trim(coalesce(p_arabic_name, '')), ''),
      greatest(coalesce(p_price_coins, 1), 1),
      nullif(trim(coalesce(p_icon, '')), ''),
      lower(trim(coalesce(p_category, 'hot'))),
      coalesce(p_is_active, true),
      coalesce(p_sort_order, 0)
    )
    on conflict (code) do update set
      name = excluded.name,
      arabic_name = excluded.arabic_name,
      price_coins = excluded.price_coins,
      icon = excluded.icon,
      category = excluded.category,
      is_active = excluded.is_active,
      sort_order = excluded.sort_order
    returning id into v_id;
  else
    update public.gifts
    set code = lower(trim(coalesce(p_code, code))),
        name = trim(coalesce(p_name, name)),
        arabic_name = nullif(trim(coalesce(p_arabic_name, arabic_name, '')), ''),
        price_coins = greatest(coalesce(p_price_coins, price_coins), 1),
        icon = nullif(trim(coalesce(p_icon, icon, '')), ''),
        category = lower(trim(coalesce(p_category, category, 'hot'))),
        is_active = coalesce(p_is_active, is_active),
        sort_order = coalesce(p_sort_order, sort_order)
    where id = p_gift_id
    returning id into v_id;
  end if;

  perform public.admin_record_audit(
    'update_gift',
    'gifts',
    v_id::text,
    null,
    jsonb_build_object('code', p_code, 'name', p_name, 'price_coins', p_price_coins)
  );

  return v_id;
end;
$$;

create or replace function public.admin_finance_report(
  p_from timestamptz default date_trunc('day', now()),
  p_to timestamptz default now()
)
returns table (
  approved_recharges bigint,
  rejected_recharges bigint,
  pending_recharges bigint,
  coins_charged bigint,
  gift_transactions bigint,
  gift_coins_spent bigint,
  diamonds_earned bigint,
  manual_adjustment_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from public.recharge_requests where status = 'approved' and approved_at >= p_from and approved_at < p_to),
    (select count(*) from public.recharge_requests where status = 'rejected' and rejected_at >= p_from and rejected_at < p_to),
    (select count(*) from public.recharge_requests where status = 'pending'),
    coalesce((select sum(requested_coins)::bigint from public.recharge_requests where status = 'approved' and approved_at >= p_from and approved_at < p_to), 0),
    (select count(*) from public.gift_transactions where created_at >= p_from and created_at < p_to),
    coalesce((select sum(gift_price_coins)::bigint from public.gift_transactions where created_at >= p_from and created_at < p_to), 0),
    coalesce((select sum(diamonds_delta)::bigint from public.wallet_transactions where type = 'gift_received' and created_at >= p_from and created_at < p_to), 0),
    (select count(*) from public.wallet_transactions where type = 'admin_adjustment' and created_at >= p_from and created_at < p_to)
  where public.has_admin_access();
$$;

create or replace function public.admin_bd_report(
  p_from timestamptz default date_trunc('day', now()),
  p_to timestamptz default now()
)
returns table (
  agency_id uuid,
  agency_name text,
  agency_code text,
  agent_id uuid,
  agent_name text,
  agent_code text,
  approved_count bigint,
  coins_charged bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    ra.id,
    ra.name,
    ra.code,
    rag.id,
    rag.name,
    rag.code,
    count(rr.id),
    coalesce(sum(rr.requested_coins), 0)::bigint
  from public.recharge_requests rr
  left join public.recharge_agencies ra on ra.id = rr.agency_id
  left join public.recharge_agents rag on rag.id = rr.agent_id
  where public.has_admin_access()
    and rr.status = 'approved'
    and rr.approved_at >= p_from
    and rr.approved_at < p_to
  group by ra.id, ra.name, ra.code, rag.id, rag.name, rag.code
  order by coalesce(sum(rr.requested_coins), 0) desc;
$$;

grant execute on function public.admin_user_detail(uuid) to authenticated;
grant execute on function public.admin_update_user_profile(uuid, text, text, text, text, integer) to authenticated;
grant execute on function public.admin_set_user_restriction(uuid, text, boolean, text, timestamptz) to authenticated;
grant execute on function public.admin_user_wallet_transactions(uuid, integer) to authenticated;
grant execute on function public.admin_user_recharge_requests(uuid, integer) to authenticated;
grant execute on function public.admin_user_gift_transactions(uuid, integer) to authenticated;
grant execute on function public.admin_close_room(uuid, text) to authenticated;
grant execute on function public.admin_kick_room_member(uuid, uuid, text) to authenticated;
grant execute on function public.admin_update_gift(uuid, text, text, text, integer, text, text, boolean, integer) to authenticated;
grant execute on function public.admin_finance_report(timestamptz, timestamptz) to authenticated;
grant execute on function public.admin_bd_report(timestamptz, timestamptz) to authenticated;
