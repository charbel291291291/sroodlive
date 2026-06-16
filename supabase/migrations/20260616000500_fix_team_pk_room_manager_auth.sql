create or replace function public.is_room_manager(
  p_room_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
  v_col text;
begin
  if p_room_id is null or p_user_id is null then
    return false;
  end if;

  -- App admins may manage Team PK in any room.
  if public.is_admin_staff(p_user_id) then
    return true;
  end if;

  -- Active room member with manager-like role.
  if exists (
    select 1
    from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = p_user_id
      and rm.left_at is null
      and lower(coalesce(rm.role, '')) in ('owner', 'host', 'manager', 'admin', 'moderator')
  ) then
    return true;
  end if;

  -- Compatibility with different rooms owner column names.
  foreach v_col in array array['owner_id', 'created_by', 'creator_id', 'user_id'] loop
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'rooms'
        and column_name = v_col
    ) then
      execute format(
        'select exists (select 1 from public.rooms where id = $1 and %I = $2)',
        v_col
      )
      into v_ok
      using p_room_id, p_user_id;

      if v_ok then
        return true;
      end if;
    end if;
  end loop;

  return false;
end;
$$;

grant execute on function public.is_room_manager(uuid, uuid) to authenticated;
