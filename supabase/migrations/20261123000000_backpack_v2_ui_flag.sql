-- ============================================================================
-- BACKPACK V2 UI FLAG (M5).
--
-- Adds a single database-controlled feature flag, `backpack_v2_ui_enabled`,
-- gating the new flag-gated Backpack V2 inventory screen added in M5. This
-- is a distinct flag instance from `frames_v2_rendering_enabled`
-- (20261114000000_frames_v2_rendering_enabled_flag.sql) — Backpack V2 UI
-- reachability and Frame V2 rendering are different domains and must be
-- switchable independently. No new feature-flag framework is introduced;
-- this mirrors that migration's own accessor/mutator/audit shape.
--
-- Deliberate divergences from the frames_v2 template, to match the
-- conventions this Backpack V2 module already established in
-- 20261120000001_backpack_v2_rpcs.sql / 20261120000002_backpack_v2_hardening.sql:
--   * `set search_path = ''` with fully-qualified `public.` references,
--     rather than `set search_path = public`.
--   * A new minimal single-row settings table instead of reusing an
--     unrelated existing settings row — `frame_settings_v2` is Frame V2's
--     own table and has no natural connection to Backpack V2.
--   * Grants execute only to `authenticated` (no `anon`) — every approved
--     Backpack V2 RPC already requires an authenticated caller, so the UI
--     flag itself never needs to be readable pre-auth.
--
-- Client contract: `backpack_v2_ui_enabled()` never raises for a missing
-- row (the row is seeded below) and always returns a boolean, defaulting to
-- `false` if the column is ever null. Default `false` means the new M5
-- screen is unreachable until an admin explicitly flips this flag — this
-- migration changes no runtime behavior by itself.
-- ============================================================================

create table if not exists public.backpack_v2_settings (
  id int primary key default 1,
  ui_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint backpack_v2_settings_singleton check (id = 1)
);

insert into public.backpack_v2_settings (id, ui_enabled)
values (1, false)
on conflict (id) do nothing;

alter table public.backpack_v2_settings enable row level security;

-- No SELECT/INSERT/UPDATE/DELETE policy at all — matches the rest of the
-- Backpack V2 module's convention (see backpack_v2_repository.dart doc
-- comment): all access goes through SECURITY DEFINER functions below, never
-- direct table reads/writes.

create or replace function public.backpack_v2_ui_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select ui_enabled from public.backpack_v2_settings where id = 1),
    false
  );
$$;

revoke all on function public.backpack_v2_ui_enabled() from public;
grant execute on function public.backpack_v2_ui_enabled() to authenticated;

create or replace function public.admin_set_backpack_v2_ui_enabled(p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_admin_access() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  update public.backpack_v2_settings
    set ui_enabled = p_enabled, updated_at = now()
    where id = 1;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, metadata)
  values (auth.uid(), 'set_backpack_v2_ui_enabled', 'backpack_v2_settings',
          jsonb_build_object('enabled', p_enabled));

  return true;
end;
$$;

revoke all on function public.admin_set_backpack_v2_ui_enabled(boolean) from public;
grant execute on function public.admin_set_backpack_v2_ui_enabled(boolean) to authenticated;
