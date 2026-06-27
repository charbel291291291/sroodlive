-- Fix admin_set_room_public_code audit call ambiguity.
-- Root cause: public.admin_record_audit has multiple overloads, so literals must be explicitly cast.

create or replace function public.admin_set_room_public_code(
  p_room_id uuid,
  p_code text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := trim(coalesce(p_code, ''));
  v_admin uuid := auth.uid();
begin
  if v_admin is null then
    raise exception 'not_authenticated';
  end if;

  if not public.has_admin_access() then
    raise exception 'not_authorized';
  end if;

  if v_code !~ '^[1-9][0-9]{4}$' then
    raise exception 'invalid_room_code: must be a 5-digit number between 10000 and 99999';
  end if;

  update public.rooms
  set public_room_code = v_code,
      updated_at = now()
  where id = p_room_id;

  if not found then
    raise exception 'room_not_found';
  end if;

  perform public.admin_record_audit(
    'set_room_public_code'::text,
    'rooms'::text,
    p_room_id::text,
    v_admin::uuid,
    jsonb_build_object(
      'room_id', p_room_id,
      'public_room_code', v_code
    )::jsonb
  );
end;
$$;

grant execute on function public.admin_set_room_public_code(uuid, text) to authenticated;