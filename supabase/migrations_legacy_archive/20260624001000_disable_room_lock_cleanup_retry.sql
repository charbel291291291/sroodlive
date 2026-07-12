do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'rooms'
      and column_name = 'is_locked'
  ) then
    execute 'update public.rooms set is_locked = false where is_locked = true';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'rooms'
      and column_name = 'room_pin_enabled'
  ) then
    execute 'update public.rooms set room_pin_enabled = false where room_pin_enabled = true';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'rooms'
      and column_name = 'room_pin_hash'
  ) then
    execute 'update public.rooms set room_pin_hash = null';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'rooms'
      and column_name = 'password_hash'
  ) then
    execute 'update public.rooms set password_hash = null';
  end if;
end $$;
