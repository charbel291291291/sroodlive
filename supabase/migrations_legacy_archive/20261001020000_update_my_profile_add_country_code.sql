-- Add p_country_code parameter to update_my_profile so the ISO-2 code is
-- saved alongside the display name, enabling server-side country filtering.

CREATE OR REPLACE FUNCTION public.update_my_profile(
  p_username      text,
  p_display_name  text,
  p_date_of_birth text,
  p_bio           text,
  p_country       text,
  p_gender        text,
  p_country_code  text default null
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_uid         uuid := auth.uid();
  v_row         public.profiles;
  v_new_country text := nullif(trim(coalesce(p_country, '')), '');
  v_new_country_code text := nullif(trim(upper(coalesce(p_country_code, ''))), '');
  v_new_gender  text := nullif(trim(coalesce(p_gender,  '')), '');
  v_dob         date;
  v_set_country boolean := false;
  v_set_gender  boolean := false;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_row from public.profiles where id = v_uid for update;
  if not found then raise exception 'profile_not_found'; end if;

  begin
    v_dob := nullif(trim(coalesce(p_date_of_birth, '')), '')::date;
  exception when others then
    v_dob := v_row.date_of_birth;
  end;

  if v_new_gender is distinct from v_row.gender then
    if v_row.gender_changed_once then
      raise exception 'gender_locked';
    end if;
    v_set_gender := true;
  end if;

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
    country       = case when v_set_country then v_new_country      else country      end,
    country_code  = case when v_set_country then v_new_country_code else country_code end,
    gender        = case when v_set_gender  then v_new_gender        else gender       end,
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
    'country_code',         v_row.country_code,
    'gender_changed_once',  v_row.gender_changed_once,
    'country_changed_once', v_row.country_changed_once
  );
end;
$function$;
