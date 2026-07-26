-- ═══════════════════════════════════════════════════════════════════════════
-- Frame Management v2 — artwork storage + guarded create RPC
--
-- Additive only. This migration does not touch frame_catalog, avatar_frames,
-- user_avatar_frames, user_frames, frames_v2_user_can_use, or any of the
-- 29 existing catalog rows. It adds:
--
--   1. the `avatar-frames` storage bucket that the admin Frame Management
--      screen uploads artwork into (no such bucket existed before);
--   2. read/write policies on storage.objects for that bucket, gated on the
--      same public.has_admin_access() predicate that already gates every
--      frames-v2 admin RPC;
--   3. public.admin_create_frame_v2(...) — an INSERT-only sibling of
--      admin_upsert_frame_v2. The existing upsert ends in
--      `on conflict (code) do update`, which silently overwrites a different
--      admin's frame when two codes collide. The create path must fail loudly
--      instead, so the editor can say "that frame code is already taken".
--      admin_upsert_frame_v2 is left exactly as-is and continues to serve
--      updates.
--
-- Client contract: the editor calls admin_create_frame_v2 for new frames and
-- admin_upsert_frame_v2 for edits of an existing row.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Storage bucket ──────────────────────────────────────────────────────
-- Public read: avatar frames render on pre-auth and public surfaces, same as
-- the `avatars` bucket. 2 MB is the outer ceiling (the animated-WebP limit);
-- the client enforces tighter per-format caps (1 MB static, 400 KB target).

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'avatar-frames',
  'avatar-frames',
  true,
  2097152,
  array['image/webp', 'image/png']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ── 2. Storage policies ────────────────────────────────────────────────────
-- Reads are open (public bucket, rendered by every client incl. anon).
-- Writes require has_admin_access() = app role 'admin' or 'super_admin',
-- matching the gate on admin_create_frame_v2 / admin_upsert_frame_v2 so an
-- account can never upload artwork it cannot also register in the catalog.

drop policy if exists "avatar_frames_select" on storage.objects;
create policy "avatar_frames_select"
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'avatar-frames');

drop policy if exists "avatar_frames_insert" on storage.objects;
create policy "avatar_frames_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatar-frames'
    and public.has_admin_access()
  );

drop policy if exists "avatar_frames_update" on storage.objects;
create policy "avatar_frames_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatar-frames'
    and public.has_admin_access()
  );

drop policy if exists "avatar_frames_delete" on storage.objects;
create policy "avatar_frames_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatar-frames'
    and public.has_admin_access()
  );

-- ── 3. Guarded create RPC ──────────────────────────────────────────────────
-- Same 20 parameters, in the same order, as admin_upsert_frame_v2 so the
-- Flutter payload builder is shared between create and update. Differences:
--   • plain insert — no `on conflict (code) do update`, so an existing frame
--     is never overwritten; the collision raises 'frame_code_exists';
--   • validates the VIP / role unlock combinations the editor also blocks,
--     so an out-of-date client cannot persist a contradictory rule.

create or replace function public.admin_create_frame_v2(
  p_code text, p_name text, p_category text,
  p_vip_level int default null,
  p_rarity text default 'common',
  p_asset_type text default 'painter',
  p_asset_url text default null,
  p_thumbnail_url text default null,
  p_animation_url text default null,
  p_is_animated boolean default false,
  p_is_active boolean default true,
  p_sort_order int default 0,
  p_unlock_type text default 'free',
  p_unlock_value text default null,
  p_required_role text default null,
  p_required_level int default null,
  p_required_vip_level int default null,
  p_starts_at timestamptz default null,
  p_expires_at timestamptz default null,
  p_localized_names jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not public.has_admin_access() then raise exception 'not_authorized'; end if;

  -- VIP / role coherence (mirrors the client-side editor rules exactly).
  if p_unlock_type = 'vip_level'
     and coalesce(p_required_vip_level, p_vip_level) is null then
    raise exception 'invalid_vip_config';
  end if;

  if p_vip_level is not null
     and p_required_vip_level is not null
     and p_vip_level <> p_required_vip_level then
    raise exception 'invalid_vip_config';
  end if;

  if p_unlock_type = 'role'
     and coalesce(nullif(btrim(p_required_role), ''), '') = '' then
    raise exception 'invalid_role_config';
  end if;

  -- Fast, deterministic duplicate error. The exception handler below is the
  -- race backstop if a concurrent insert wins between this check and ours.
  if exists (select 1 from public.frame_catalog where code = p_code) then
    raise exception 'frame_code_exists';
  end if;

  insert into public.frame_catalog (
    code, name, localized_names, category, vip_level, rarity, asset_type,
    asset_url, thumbnail_url, animation_url, is_animated, is_active,
    sort_order, unlock_type, unlock_value, required_role, required_level,
    required_vip_level, starts_at, expires_at
  ) values (
    p_code, p_name, coalesce(p_localized_names, '{}'::jsonb), p_category,
    p_vip_level, p_rarity, p_asset_type, p_asset_url, p_thumbnail_url,
    p_animation_url, p_is_animated, p_is_active, p_sort_order, p_unlock_type,
    p_unlock_value, p_required_role, p_required_level, p_required_vip_level,
    p_starts_at, p_expires_at
  )
  returning id into v_id;

  -- Legacy FK compatibility: every selectable v2 code needs a row in
  -- avatar_frames (profiles.selected_avatar_frame_key FK). Additive upsert;
  -- the legacy check constraint only allows normal/luxury/vip categories.
  insert into public.avatar_frames
    (frame_key, name, category, vip_level, required_vip_level, asset_url, is_active, sort_order)
  values (
    p_code, p_name,
    case when p_category in ('normal','luxury','vip') then p_category else 'luxury' end,
    p_vip_level, p_required_vip_level, p_asset_url, p_is_active, p_sort_order
  )
  on conflict (frame_key) do update set
    name = excluded.name,
    is_active = excluded.is_active,
    required_vip_level = excluded.required_vip_level,
    sort_order = excluded.sort_order;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'create_frame_v2', 'frame_catalog', p_code,
          jsonb_build_object('category', p_category, 'active', p_is_active));
  return v_id;
exception
  when unique_violation then
    raise exception 'frame_code_exists';
end $$;

revoke all on function public.admin_create_frame_v2(
  text, text, text, int, text, text, text, text, text, boolean, boolean, int,
  text, text, text, int, int, timestamptz, timestamptz, jsonb
) from public;

grant execute on function public.admin_create_frame_v2(
  text, text, text, int, text, text, text, text, text, boolean, boolean, int,
  text, text, text, int, int, timestamptz, timestamptz, jsonb
) to authenticated;

comment on function public.admin_create_frame_v2(
  text, text, text, int, text, text, text, text, text, boolean, boolean, int,
  text, text, text, int, int, timestamptz, timestamptz, jsonb
) is
  'Frames v2: insert-only frame creation. Raises frame_code_exists instead of '
  'overwriting, unlike admin_upsert_frame_v2 which is kept for updates.';
