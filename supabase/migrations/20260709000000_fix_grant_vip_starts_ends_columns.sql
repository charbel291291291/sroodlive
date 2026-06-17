create or replace function public.grant_vip(
  p_user_id uuid,
  p_vip_level integer,
  p_duration_days integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_caller uuid := auth.uid();
  v_now timestamptz := now();
  v_expires_at timestamptz;
  v_sub_id uuid;
begin
  if not public._vip_caller_is_admin() then
    raise exception 'permission_denied: admin role required'
      using errcode = 'insufficient_privilege';
  end if;

  if p_vip_level < 0 or p_vip_level > 9 then
    raise exception 'invalid_vip_level: must be 0-9'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_vip_level = 0 then
    update public.user_vip_subscriptions
    set is_active = false,
        updated_at = now()
    where user_id = p_user_id
      and is_active = true;

    update public.profiles
    set vip_level = 0,
        vip_expires_at = null,
        vip_started_at = null,
        updated_at = now()
    where id = p_user_id;

    return jsonb_build_object(
      'user_id', p_user_id,
      'vip_level', 0,
      'action', 'revoked'
    );
  end if;

  v_expires_at := v_now + (greatest(coalesce(p_duration_days, 30), 1) * interval '1 day');

  update public.user_vip_subscriptions
  set is_active = false,
      updated_at = now()
  where user_id = p_user_id
    and is_active = true;

  insert into public.user_vip_subscriptions (
    user_id,
    vip_level,
    starts_at,
    ends_at,
    is_active,
    payment_source,
    created_by_admin
  )
  values (
    p_user_id,
    p_vip_level,
    v_now,
    v_expires_at,
    true,
    'admin_grant',
    v_caller
  )
  returning id into v_sub_id;

  update public.profiles
  set vip_level = p_vip_level,
      vip_started_at = v_now,
      vip_expires_at = v_expires_at,
      updated_at = now()
  where id = p_user_id;

  return jsonb_build_object(
    'user_id', p_user_id,
    'vip_level', p_vip_level,
    'expires_at', v_expires_at,
    'subscription_id', v_sub_id,
    'action', 'granted'
  );
end;
$function$;
