-- ============================================================
-- Room Public Code, 5-digit numeric display ID
-- ============================================================
-- Adds public_room_code to rooms for clean display and sharing.
-- Internal UUID id is unchanged and still used for all foreign keys.
-- Existing rooms are backfilled with unique 5-digit codes.
-- New rooms get a code through the column default.
-- ============================================================

-- 1. Add the column as nullable first so backfill can run
alter table public.rooms
  add column if not exists public_room_code text;

-- 2. Generator function. Retries up to 100 times on collision.
create or replace function public.generate_5digit_room_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_candidate text;
  v_attempts  int := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    if v_attempts > 100 then
      raise exception 'generate_5digit_room_code: no unique code found after 100 attempts';
    end if;

    -- 10000 to 99999, no leading zero
    v_candidate := (floor(random() * 90000) + 10000)::bigint::text;

    exit when not exists (
      select 1 from public.rooms where public_room_code = v_candidate
    );
  end loop;

  return v_candidate;
end;
$$;

grant execute on function public.generate_5digit_room_code() to authenticated, service_role;

-- 3. Backfill existing rooms one by one so each gets a unique code
do $$
declare
  r record;
begin
  for r in select id from public.rooms where public_room_code is null loop
    update public.rooms
    set public_room_code = public.generate_5digit_room_code()
    where id = r.id;
  end loop;
end $$;

-- 4. Make column not null after backfill
alter table public.rooms
  alter column public_room_code set not null;

-- 5. Set default for new rooms
alter table public.rooms
  alter column public_room_code
  set default public.generate_5digit_room_code();

-- 6. Unique constraint
alter table public.rooms
  drop constraint if exists rooms_public_room_code_key;

alter table public.rooms
  add constraint rooms_public_room_code_key unique (public_room_code);

-- 7. Format check, exactly 5 digits, no leading zero
alter table public.rooms
  drop constraint if exists rooms_public_room_code_format;

alter table public.rooms
  add constraint rooms_public_room_code_format
  check (public_room_code ~ '^[1-9][0-9]{4}$');

-- 8. Index for fast lookup by code
create index if not exists idx_rooms_public_room_code
  on public.rooms (public_room_code);
