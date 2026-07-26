-- ═══════════════════════════════════════════════════════════════════════════
-- Frames v2 — admin role compatibility for role-gated frames
--
-- Problem this fixes
-- ------------------
-- public.frames_v2_user_can_use() resolves `frame_catalog.required_role` by
-- looking for a row in public.app_user_roles. Every other authorization path
-- in this app resolves admin membership through public.admin_users instead —
-- see public.has_app_role(text), which is what public.has_admin_access() (and
-- therefore every frames-v2 admin RPC and the new avatar-frames storage
-- policies) is built on. app_user_roles is described in
-- 20260615230000_admin_role_system_rebuild.sql as "kept for legacy backward
-- compat; new code uses admin_users".
--
-- Result today: the two role-gated rows in frame_catalog (required_role
-- 'admin' and 'super_admin') can never be worn, because a real admin has a row
-- in admin_users and no row in app_user_roles.
--
-- What this migration does
-- ------------------------
--   1. Adds public.frames_v2_user_has_admin_role(uuid, text) — an explicit,
--      closed mapping from an *active* admin_users membership to the role name
--      a frame may require. No loose string comparison, no wildcard.
--   2. Replaces public.frames_v2_user_can_use() so the required_role branch
--      passes when EITHER source says yes. The app_user_roles lookup is left
--      byte-for-byte intact, so existing behaviour can only widen, never
--      narrow.
--
-- Everything else about frames_v2_user_can_use is unchanged: same signature,
-- same volatility, same `search_path = public`, same VIP rules, same ownership
-- union, same privileges (create or replace preserves the existing grant set,
-- which is `postgres=EXECUTE` only — the function is called from other
-- security-definer functions, never directly by a client).
--
-- Additive and reversible. No table is altered, no row is written, no policy
-- is touched, no existing migration is edited.
--
-- Rollback: re-run the frames_v2_user_can_use body from
-- 20261112000000_frame_system_v2.sql (lines 186-269) and
-- `drop function if exists public.frames_v2_user_has_admin_role(uuid, text);`.
-- Dropping the helper alone is NOT a valid rollback — the replaced function
-- references it.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. admin_users → required_role mapping ─────────────────────────────────
-- The mapping mirrors the hierarchy already encoded in public.has_app_role
-- (text): owner passes everything, platform/normal super admin pass
-- super_admin and admin, admin passes admin. It is deliberately *narrower*
-- than has_app_role in one respect: has_app_role ends in an exact-match
-- fallback (`au.role = lower(p_role)`) for "older custom roles still stored in
-- admin_users". There is no such fallback here, because frame_catalog
-- .required_role is free text written by an admin in the Frame Management UI,
-- and an unrecognised value must fail closed rather than match whatever
-- happens to be sitting in admin_users.role.
--
-- admin_users has exactly one liveness column, `is_active boolean not null`
-- (there is no revoked_at / expires_at), so that is the only recency check
-- available and it is enforced here.

create or replace function public.frames_v2_user_has_admin_role(
  p_user_id uuid,
  p_role text
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_users au
    where au.user_id = p_user_id
      and au.is_active = true
      and case lower(coalesce(p_role, ''))
        when 'o_super_admin' then au.role = 'o_super_admin'
        when 'p_super_admin' then au.role in ('o_super_admin', 'p_super_admin')
        when 'super_admin'   then au.role in ('o_super_admin', 'p_super_admin', 'super_admin')
        when 'admin'         then au.role in ('o_super_admin', 'p_super_admin', 'super_admin', 'admin')
        else false
      end
  );
$$;

comment on function public.frames_v2_user_has_admin_role(uuid, text) is
  'Frames v2: does p_user_id hold an active admin_users membership that '
  'satisfies frame_catalog.required_role = p_role? Closed mapping over the '
  'four admin_users_role_check values; unknown roles return false.';

revoke all on function public.frames_v2_user_has_admin_role(uuid, text) from public;

-- ── 2. required_role now accepts either role source ────────────────────────
-- Copied verbatim from 20261112000000_frame_system_v2.sql. The only change is
-- the `if v_frame.required_role is not null then` block, marked below.

create or replace function public.frames_v2_user_can_use(
  p_user_id uuid,
  p_raw text
) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_code text := public.frames_v2_resolve_code(p_raw);
  v_frame public.frame_catalog%rowtype;
  v_legacy public.avatar_frames%rowtype;
begin
  if p_user_id is null then return false; end if;
  if p_raw is null or length(trim(p_raw)) = 0 then return true; end if;

  select * into v_frame from public.frame_catalog where code = v_code;

  if v_frame.id is null then
    -- Unknown to v2: fall back to legacy catalog semantics (normal/luxury
    -- frames are free today). Unknown everywhere → not allowed.
    select * into v_legacy from public.avatar_frames where frame_key = p_raw;
    if v_legacy.id is null then return false; end if;
    if v_legacy.category in ('normal','luxury') then return true; end if;
    return coalesce(v_legacy.required_vip_level, v_legacy.vip_level, 0)
      <= public.frames_v2_effective_vip(p_user_id);
  end if;

  if not v_frame.is_active then return false; end if;
  if v_frame.starts_at is not null and now() < v_frame.starts_at then
    return false;
  end if;
  if v_frame.expires_at is not null and now() >= v_frame.expires_at then
    return false;
  end if;

  -- Only vip_level-unlock frames are gated by required_vip_level. Role and
  -- admin_grant frames (custom_admin, custom_super_admin, custom_srood_live)
  -- inherit a non-null required_vip_level from their legacy avatar_frames
  -- vip_level column, but that column is not meaningful for their unlock
  -- semantics and must not block role/ownership-based access.
  if v_frame.unlock_type = 'vip_level'
     and v_frame.required_vip_level is not null
     and public.frames_v2_effective_vip(p_user_id) < v_frame.required_vip_level
  then
    return false;
  end if;

  -- ▼▼ CHANGED IN 20261202000000 ▼▼
  -- Legacy app_user_roles lookup unchanged; an active admin_users membership
  -- is now an additional, equally valid way to satisfy required_role.
  if v_frame.required_role is not null then
    if not exists (
      select 1 from public.app_user_roles r
      where r.user_id = p_user_id and r.role = v_frame.required_role
    ) and not public.frames_v2_user_has_admin_role(
      p_user_id, v_frame.required_role
    ) then
      return false;
    end if;
  end if;
  -- ▲▲ CHANGED IN 20261202000000 ▲▲

  return case v_frame.unlock_type
    when 'free' then true
    when 'vip_level' then true   -- gated by required_vip_level above
    when 'role' then true        -- gated by required_role above
    else exists (
      -- v2 ownership …
      select 1 from public.user_frames uf
      where uf.user_id = p_user_id
        and uf.frame_id = v_frame.id
        and uf.revoked_at is null
        and (uf.expires_at is null or uf.expires_at > now())
      union all
      -- … or legacy ownership (kept valid until cleanup approval) …
      select 1 from public.user_avatar_frames uaf
      where uaf.user_id = p_user_id
        and (uaf.frame_key = p_raw or uaf.frame_key = v_code
             or uaf.frame_key = v_frame.legacy_frame_key)
        and (uaf.expires_at is null or uaf.expires_at > now())
      union all
      -- … or a gamification-store frame sitting in the backpack
      select 1 from public.backpack_items b
      where b.user_id = p_user_id
        and b.item_type = 'avatar_frame'
        and b.metadata->>'frame_key' in (p_raw, v_code)
    )
  end;
end $$;

revoke all on function public.frames_v2_user_can_use(uuid, text) from public;
