create or replace function public.apply_vip_recharge_exp(
  p_user_id uuid,
  p_recharged_coins bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_now timestamptz := statement_timestamp();
  v_profile public.profiles%rowtype;
  v_new_lifetime bigint;
  v_new_monthly bigint;
  v_monthly_before bigint;
  v_earned_tier integer;
  v_maintain_exp bigint;
  v_new_expires timestamptz;
begin
  if p_user_id is null then
    raise exception 'vip_user_required' using errcode = '22023';
  end if;
  if p_recharged_coins is null or p_recharged_coins <= 0 then
    raise exception 'vip_recharge_must_be_positive' using errcode = '22023';
  end if;

  select * into v_profile
  from public.profiles
  where id = p_user_id
  for update;
  if not found then
    raise exception 'vip_profile_not_found' using errcode = 'P0002';
  end if;

  update public.profiles
  set vip_recharge_exp = coalesce(vip_recharge_exp, 0) + p_recharged_coins,
      vip_monthly_exp = coalesce(vip_monthly_exp, 0) + p_recharged_coins,
      vip_last_recharge_at = v_now,
      vip_cycle_started_at = coalesce(vip_cycle_started_at, v_now),
      updated_at = v_now
  where id = p_user_id
  returning vip_recharge_exp, vip_monthly_exp
    into v_new_lifetime, v_new_monthly;

  v_monthly_before := v_new_monthly - p_recharged_coins;
  select coalesce(max(level), 0) into v_earned_tier
  from public.vip_levels
  where is_active = true
    and required_recharge_exp is not null
    and required_recharge_exp <= v_new_lifetime;

  if v_earned_tier = 0 then return; end if;

  if v_earned_tier > coalesce(v_profile.vip_level, 0) then
    v_new_expires := v_now + interval '30 days';
  elsif v_earned_tier = coalesce(v_profile.vip_level, 0) then
    select coalesce(monthly_maintain_exp, required_recharge_exp, 0)
      into v_maintain_exp
    from public.vip_levels
    where level = v_earned_tier and is_active = true;
    if not found or v_monthly_before >= v_maintain_exp
      or v_new_monthly < v_maintain_exp then
      return;
    end if;
    v_new_expires := greatest(coalesce(v_profile.vip_expires_at, v_now), v_now)
      + interval '30 days';
  else
    return;
  end if;

  update public.user_vip_subscriptions
  set is_active = false, updated_at = v_now
  where user_id = p_user_id
    and is_active = true
    and payment_source = 'recharge_exp';

  insert into public.user_vip_subscriptions (
    user_id, vip_level, starts_at, ends_at, is_active, payment_source,
    created_at, updated_at
  ) values (
    p_user_id, v_earned_tier, v_now, v_new_expires, true, 'recharge_exp',
    v_now, v_now
  );

  update public.profiles
  set vip_level = v_earned_tier,
      vip_started_at = case
        when v_earned_tier > coalesce(v_profile.vip_level, 0) then v_now
        else coalesce(vip_started_at, v_now)
      end,
      vip_expires_at = v_new_expires,
      updated_at = v_now
  where id = p_user_id;
end;
$$;

revoke execute on function public.apply_vip_recharge_exp(uuid, bigint)
  from public, anon, authenticated;
grant execute on function public.apply_vip_recharge_exp(uuid, bigint)
  to service_role;
