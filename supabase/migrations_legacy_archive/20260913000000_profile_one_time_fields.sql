-- =============================================================================
-- One-time gender/country profile edits (additive)
--
-- Adds lock columns + a SECURITY DEFINER RPC that performs profile updates and
-- enforces "gender and country may each be changed only once" SERVER-SIDE
-- (the Flutter UI also disables the fields, but the backend is the real gate).
--
-- Additive + idempotent. No destructive changes. Does not touch wallet, VIP,
-- levels, rooms, gifts, follow, moderation, daily rewards, or admin logic.
-- =============================================================================

alter table public.profiles
  add column if not exists gender_changed_once  boolean not null default false,
  add column if not exists country_changed_once boolean not null default false,
  add column if not exists gender_changed_at    timestamptz,
  add column if not exists country_changed_at   timestamptz;

create or replace function public.update_my_profile(
  p_username      text,
  p_display_name  text,
  p_date_of_birth text,   -- 'YYYY-MM-DD' or null/empty
  p_bio           text,
  p_country       text,
  p_gender        text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.profiles;
  v_new_country text := nullif(trim(coalesce(p_country, '')), '');
  v_new_gender  text := nullif(trim(coalesce(p_gender,  '')), '');
  v_dob         date;
  v_set_country boolean := false;
  v_set_gender  boolean := false;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_row from public.profiles where id = v_uid for update;
  if not found then raise exception 'profile_not_found'; end if;

  -- Parse optional date of birth.
  begin
    v_dob := nullif(trim(coalesce(p_date_of_birth, '')), '')::date;
  exception when others then
    v_dob := v_row.date_of_birth; -- keep existing on bad input
  end;

  -- Gender: consume the one allowed change only when it actually differs.
  if v_new_gender is distinct from v_row.gender then
    if v_row.gender_changed_once then
      raise exception 'gender_locked';
    end if;
    v_set_gender := true;
  end if;

  -- Country: same rule.
  if v_new_country is distinct from v_row.country then
    if v_row.country_changed_once then
      raise exception 'country_locked';
    end if;
    v_set_country := true;
  end if;

  update public.profiles set
    username      = coalesce(nullif(trim(coalesce(p_username, '')), ''),
                             nullif(trim(coalesce(p_display_name, '')), ''),
                             username),
    display_name  = coalesce(nullif(trim(coalesce(p_display_name, '')), ''), display_name),
    date_of_birth = v_dob,
    bio           = nullif(trim(coalesce(p_bio, '')), ''),
    country       = case when v_set_country then v_new_country else country end,
    gender        = case when v_set_gender  then v_new_gender  else gender  end,
    country_changed_once = case when v_set_country then true  else country_changed_once end,
    country_changed_at   = case when v_set_country then now() else country_changed_at end,
    gender_changed_once  = case when v_set_gender  then true  else gender_changed_once end,
    gender_changed_at    = case when v_set_gender  then now() else gender_changed_at end,
    updated_at = now()
  where id = v_uid
  returning * into v_row;

  return jsonb_build_object(
    'gender',               v_row.gender,
    'country',              v_row.country,
    'gender_changed_once',  v_row.gender_changed_once,
    'country_changed_once', v_row.country_changed_once
  );
end;
$$;

revoke all on function public.update_my_profile(text,text,text,text,text,text) from public;
grant execute on function public.update_my_profile(text,text,text,text,text,text) to authenticated;

-- =============================================================================
-- End of 20260913000000_profile_one_time_fields.sql
-- =============================================================================
