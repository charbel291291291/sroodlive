-- user_vip_settings: stores per-user VIP privilege toggles.
-- Each row is owned by the user; privileges are only usable when the user
-- holds the required VIP level (enforced in-app and via RLS on profiles).

create table if not exists public.user_vip_settings (
  user_id              uuid primary key references auth.users(id) on delete cascade,
  not_being_followed   boolean not null default false,
  anti_entering_room   boolean not null default false,
  private_browsing     boolean not null default false,
  do_not_disturb       boolean not null default false,
  invisibility         boolean not null default false,
  anti_kick            boolean not null default false,
  updated_at           timestamptz not null default now()
);

-- Index for quick lookup by user.
create index if not exists idx_user_vip_settings_user_id
  on public.user_vip_settings (user_id);

-- RLS: users manage only their own row.
alter table public.user_vip_settings enable row level security;

create policy "user_vip_settings_select_own"
  on public.user_vip_settings for select
  using (auth.uid() = user_id);

create policy "user_vip_settings_insert_own"
  on public.user_vip_settings for insert
  with check (auth.uid() = user_id);

create policy "user_vip_settings_update_own"
  on public.user_vip_settings for update
  using (auth.uid() = user_id);

-- Service-role can read (for server-side privilege enforcement).
create policy "user_vip_settings_service_read"
  on public.user_vip_settings for select
  using (true);

-- Helper function: check if a target user has a specific privilege active.
-- Returns false when the user doesn't exist or hasn't enabled the setting.
create or replace function public.vip_privilege_active(
  p_user_id   uuid,
  p_privilege text   -- column name: not_being_followed | anti_kick | …
) returns boolean
language plpgsql stable security definer
as $$
declare
  v_result boolean;
begin
  execute format(
    'select coalesce(s.%I, false) from public.user_vip_settings s where s.user_id = $1',
    p_privilege
  )
  into v_result
  using p_user_id;
  return coalesce(v_result, false);
end;
$$;
