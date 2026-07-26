-- ============================================================================
-- FRAMES V2 RENDERING FLAG.
--
-- Adds a single database-controlled feature flag, `frames_v2_rendering_enabled`,
-- reusing the Frame System v2 settings row (`frame_settings_v2`, id = 1) that
-- already carries `enforce_selection`. That table's RLS is admin-only
-- (`frames_v2 settings admin read`), which is correct for the settings row
-- itself but wrong for this flag: every client, not just admins, needs to
-- read it to decide which rendering path to use. Rather than loosen the
-- existing admin-only policy on the settings row (out of scope, and would
-- change already-shipped access to `enforce_selection`), this migration adds
-- a narrow SECURITY DEFINER accessor function — the same "central function +
-- revoke from public + grant execute" idiom already used throughout
-- 20261112000000_frame_system_v2.sql (see frames_v2_effective_vip,
-- frames_v2_user_can_use, etc.) — so the flag has its own minimal, explicit
-- read surface without widening access to the rest of the settings row.
--
-- Client contract: `frames_v2_rendering_flag()` never raises for a missing
-- row (the seeded id = 1 row always exists from 20261112000000) and always
-- returns a boolean, defaulting to `false` if the column is ever null.
-- Default `false` means: until an admin flips it, every client keeps using
-- the exact current legacy rendering path — this migration changes no
-- runtime behavior by itself.
-- ============================================================================

alter table public.frame_settings_v2
  add column if not exists frames_v2_rendering_enabled boolean not null default false;

-- Public accessor: readable by any client (including signed-out/anon, since
-- avatar rendering can happen on pre-auth screens), never exposes the rest
-- of the admin-only settings row.
create or replace function public.frames_v2_rendering_flag()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select frames_v2_rendering_enabled from public.frame_settings_v2 where id = 1),
    false
  );
$$;

revoke all on function public.frames_v2_rendering_flag() from public;
grant execute on function public.frames_v2_rendering_flag() to authenticated, anon;

-- Admin mutator, mirroring admin_set_frame_enforcement_v2 (same table, same
-- has_admin_access() authorization model, same audit log sink).
create or replace function public.admin_set_frames_v2_rendering_enabled(p_enabled boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.has_admin_access() then raise exception 'not_authorized'; end if;
  update public.frame_settings_v2
    set frames_v2_rendering_enabled = p_enabled, updated_at = now()
    where id = 1;
  insert into public.admin_audit_logs (admin_user_id, action, entity_type, metadata)
  values (auth.uid(), 'set_frames_v2_rendering_enabled', 'frame_settings_v2',
          jsonb_build_object('enabled', p_enabled));
  return true;
end $$;

revoke all on function public.admin_set_frames_v2_rendering_enabled(boolean) from public;
grant execute on function public.admin_set_frames_v2_rendering_enabled(boolean) to authenticated;
