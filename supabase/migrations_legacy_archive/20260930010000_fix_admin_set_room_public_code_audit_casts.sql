-- Local copy for remote-applied migration version 20260930010000.
-- Keeps Supabase migration history aligned.

create or replace function public.admin_set_room_public_code(
  p_room_id uuid,
  p_code    text
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

  if p_code !~ '^[1-9][0-9]{4}$' then
    raise exception 'invalid_room_code: must be a 5-digit number between 10000 and 99999';
  end if;

  if not exists (select 1 from public.rooms where id = p_room_id) then
    raise exception 'room_not_found';
  end if;

  update public.rooms
  set public_room_code = p_code,
      updated_at       = now()
  where id = p_room_id;

  perform public.admin_record_audit(
    'set_room_public_code'::text,
    'rooms'::text,
    p_room_id::text,
    auth.uid()::uuid,
    jsonb_build_object('public_room_code', p_code)::jsonb
  );
end;
$$;

grant execute on function public.admin_set_room_public_code(uuid, text) to authenticated;