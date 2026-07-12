-- ────────────────────────────────────────────────────────────────────────────
-- Room Owner Management
-- Tables: room_moderators, room_bans, room_announcements,
--         room_schedules, room_schedule_rsvps
-- RPCs:   owner_mute_member, ban_room_member, unban_room_member
-- ────────────────────────────────────────────────────────────────────────────

-- ── 1. room_moderators ────────────────────────────────────────────────────
create table if not exists public.room_moderators (
  id               uuid primary key default gen_random_uuid(),
  room_id          uuid not null references public.rooms(id)     on delete cascade,
  user_id          uuid not null references auth.users(id)       on delete cascade,
  created_by       uuid not null references auth.users(id)       on delete cascade,
  can_manage_mics  boolean not null default true,
  can_mute         boolean not null default true,
  can_kick         boolean not null default false,
  can_manage_schedule boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique(room_id, user_id)
);

alter table public.room_moderators enable row level security;

drop policy if exists "room_moderators_select" on public.room_moderators;
create policy "room_moderators_select"
  on public.room_moderators for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.rooms r
      where r.id = room_id and r.owner_id = auth.uid()
    )
  );

drop policy if exists "room_moderators_insert" on public.room_moderators;
create policy "room_moderators_insert"
  on public.room_moderators for insert to authenticated
  with check (
    exists (
      select 1 from public.rooms r
      where r.id = room_id and r.owner_id = auth.uid()
    )
  );

drop policy if exists "room_moderators_update" on public.room_moderators;
create policy "room_moderators_update"
  on public.room_moderators for update to authenticated
  using (
    exists (
      select 1 from public.rooms r
      where r.id = room_id and r.owner_id = auth.uid()
    )
  );

drop policy if exists "room_moderators_delete" on public.room_moderators;
create policy "room_moderators_delete"
  on public.room_moderators for delete to authenticated
  using (
    exists (
      select 1 from public.rooms r
      where r.id = room_id and r.owner_id = auth.uid()
    )
  );

grant select, insert, update, delete on public.room_moderators to authenticated;

-- ── 2. room_bans ─────────────────────────────────────────────────────────
create table if not exists public.room_bans (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms(id)   on delete cascade,
  user_id     uuid not null references auth.users(id)     on delete cascade,
  banned_by   uuid not null references auth.users(id)     on delete cascade,
  reason      text,
  expires_at  timestamptz,
  created_at  timestamptz not null default now(),
  unique(room_id, user_id)
);

alter table public.room_bans enable row level security;

-- Room owner can read all bans for their room; banned user can read their own ban
drop policy if exists "room_bans_select" on public.room_bans;
create policy "room_bans_select"
  on public.room_bans for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.rooms r
      where r.id = room_id and r.owner_id = auth.uid()
    )
  );

-- Bans are written only via security-definer RPCs below — no direct insert policy needed
grant select on public.room_bans to authenticated;

-- ── 3. room_announcements ─────────────────────────────────────────────────
create table if not exists public.room_announcements (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms(id)   on delete cascade,
  created_by  uuid not null references auth.users(id)     on delete cascade,
  message     text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.room_announcements enable row level security;

-- Any authenticated user can read active announcements (for in-room display)
drop policy if exists "room_announcements_select" on public.room_announcements;
create policy "room_announcements_select"
  on public.room_announcements for select to authenticated
  using (true);

drop policy if exists "room_announcements_insert" on public.room_announcements;
create policy "room_announcements_insert"
  on public.room_announcements for insert to authenticated
  with check (
    exists (
      select 1 from public.rooms r
      where r.id = room_id and r.owner_id = auth.uid()
    )
  );

drop policy if exists "room_announcements_update" on public.room_announcements;
create policy "room_announcements_update"
  on public.room_announcements for update to authenticated
  using (
    exists (
      select 1 from public.rooms r
      where r.id = room_id and r.owner_id = auth.uid()
    )
  );

grant select, insert, update on public.room_announcements to authenticated;

-- ── 4. room_schedules ────────────────────────────────────────────────────
-- (Also used by the existing RoomScheduleScreen)
create table if not exists public.room_schedules (
  id            uuid primary key default gen_random_uuid(),
  host_id       uuid not null references auth.users(id) on delete cascade,
  room_id       uuid references public.rooms(id)        on delete set null,
  title         text not null,
  description   text,
  cover_url     text,
  scheduled_at  timestamptz not null,
  rsvp_count    integer not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.room_schedules enable row level security;

drop policy if exists "room_schedules_select" on public.room_schedules;
create policy "room_schedules_select"
  on public.room_schedules for select to authenticated
  using (true);

drop policy if exists "room_schedules_insert" on public.room_schedules;
create policy "room_schedules_insert"
  on public.room_schedules for insert to authenticated
  with check (auth.uid() = host_id);

drop policy if exists "room_schedules_update_own" on public.room_schedules;
create policy "room_schedules_update_own"
  on public.room_schedules for update to authenticated
  using (auth.uid() = host_id);

drop policy if exists "room_schedules_delete_own" on public.room_schedules;
create policy "room_schedules_delete_own"
  on public.room_schedules for delete to authenticated
  using (auth.uid() = host_id);

grant select, insert, update, delete on public.room_schedules to authenticated;

-- ── 5. room_schedule_rsvps ───────────────────────────────────────────────
create table if not exists public.room_schedule_rsvps (
  schedule_id  uuid not null references public.room_schedules(id) on delete cascade,
  user_id      uuid not null references auth.users(id)            on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (schedule_id, user_id)
);

alter table public.room_schedule_rsvps enable row level security;

drop policy if exists "room_schedule_rsvps_select" on public.room_schedule_rsvps;
create policy "room_schedule_rsvps_select"
  on public.room_schedule_rsvps for select to authenticated
  using (true);

drop policy if exists "room_schedule_rsvps_insert" on public.room_schedule_rsvps;
create policy "room_schedule_rsvps_insert"
  on public.room_schedule_rsvps for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "room_schedule_rsvps_delete_own" on public.room_schedule_rsvps;
create policy "room_schedule_rsvps_delete_own"
  on public.room_schedule_rsvps for delete to authenticated
  using (auth.uid() = user_id);

grant select, insert, delete on public.room_schedule_rsvps to authenticated;

-- ── 6. RPC: owner_mute_member ────────────────────────────────────────────
create or replace function public.owner_mute_member(
  p_room_id  uuid,
  p_user_id  uuid,
  p_is_muted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_owner  uuid;
begin
  if v_caller is null then
    raise exception 'not_authenticated';
  end if;

  select owner_id into v_owner from public.rooms where id = p_room_id;

  if v_owner is null then
    raise exception 'room_not_found';
  end if;

  if v_owner != v_caller then
    raise exception 'not_room_owner';
  end if;

  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = p_user_id and left_at is null
  ) then
    raise exception 'member_not_in_room';
  end if;

  update public.room_members
  set is_muted = p_is_muted, updated_at = now()
  where room_id = p_room_id and user_id = p_user_id and left_at is null;
end;
$$;

grant execute on function public.owner_mute_member(uuid, uuid, boolean) to authenticated;

comment on function public.owner_mute_member(uuid, uuid, boolean) is
  'Room owner mutes or unmutes a member. Verifies ownership before writing.';

-- ── 7. RPC: ban_room_member ──────────────────────────────────────────────
create or replace function public.ban_room_member(
  p_room_id   uuid,
  p_user_id   uuid,
  p_reason    text          default null,
  p_expires_at timestamptz  default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_owner  uuid;
begin
  if v_caller is null then
    raise exception 'not_authenticated';
  end if;

  select owner_id into v_owner from public.rooms where id = p_room_id;

  if v_owner is null then
    raise exception 'room_not_found';
  end if;

  if v_owner != v_caller then
    raise exception 'not_room_owner';
  end if;

  if p_user_id = v_caller then
    raise exception 'cannot_ban_self';
  end if;

  insert into public.room_bans (room_id, user_id, banned_by, reason, expires_at)
  values (p_room_id, p_user_id, v_caller, p_reason, p_expires_at)
  on conflict (room_id, user_id) do update
    set reason     = excluded.reason,
        expires_at = excluded.expires_at,
        banned_by  = excluded.banned_by,
        created_at = now();

  -- Kick from room if currently present
  update public.room_members
  set is_muted = true, seat_number = null,
      left_at = now(), last_seen_at = now(), updated_at = now()
  where room_id = p_room_id and user_id = p_user_id and left_at is null;
end;
$$;

grant execute on function public.ban_room_member(uuid, uuid, text, timestamptz) to authenticated;

comment on function public.ban_room_member(uuid, uuid, text, timestamptz) is
  'Room owner bans a user. Auto-kicks them if present. Verifies ownership.';

-- ── 8. RPC: unban_room_member ────────────────────────────────────────────
create or replace function public.unban_room_member(
  p_room_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_owner  uuid;
begin
  if v_caller is null then
    raise exception 'not_authenticated';
  end if;

  select owner_id into v_owner from public.rooms where id = p_room_id;

  if v_owner is null then
    raise exception 'room_not_found';
  end if;

  if v_owner != v_caller then
    raise exception 'not_room_owner';
  end if;

  delete from public.room_bans
  where room_id = p_room_id and user_id = p_user_id;
end;
$$;

grant execute on function public.unban_room_member(uuid, uuid) to authenticated;

comment on function public.unban_room_member(uuid, uuid) is
  'Room owner removes a ban. Verifies ownership before deleting.';
