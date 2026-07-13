-- =============================================================================
-- VIP Phase 4: backend enforcement and admin utilities
-- All changes are additive (CREATE OR REPLACE / ADD COLUMN IF NOT EXISTS).
-- No tables or columns are dropped. No existing data is modified.
-- =============================================================================

-- ── 1. RPC: set_my_vip_setting ───────────────────────────────────────────────
--
-- Server-side enforcement for user_vip_settings.
-- Validates that the caller's current VIP level meets the minimum requirement
-- for the requested key before writing. Expired VIP is treated as level 0.
--
-- Supported user-settable keys and minimum levels (must match Flutter VipPrivileges):
--   not_being_followed : 5
--   anti_entering_room : 6
--   private_browsing   : 6
--   do_not_disturb     : 7
--   anti_kick          : 8
--   invisibility       : 8
--
-- TODO Phase 5: revoke direct UPDATE on user_vip_settings from authenticated
--              role once this RPC is verified stable in production, so that
--              the only write path goes through this function.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_my_vip_setting(
  p_key     text,
  p_enabled boolean
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid        := auth.uid();
  v_level      int;
  v_expires_at timestamptz;
  v_min_level  int;
  v_now        timestamptz := now();
BEGIN
  -- ── Auth check ────────────────────────────────────────────────────────────
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- ── Read caller VIP status ────────────────────────────────────────────────
  SELECT p.vip_level, p.vip_expires_at
  INTO   v_level, v_expires_at
  FROM   public.profiles p
  WHERE  p.id = v_uid;

  -- Treat expired VIP as level 0
  IF v_expires_at IS NOT NULL AND v_expires_at < v_now THEN
    v_level := 0;
  END IF;
  v_level := COALESCE(v_level, 0);

  -- ── Validate key + resolve min level ──────────────────────────────────────
  v_min_level := CASE p_key
    WHEN 'not_being_followed' THEN 5
    WHEN 'anti_entering_room' THEN 6
    WHEN 'private_browsing'   THEN 6
    WHEN 'do_not_disturb'     THEN 7
    WHEN 'anti_kick'          THEN 8
    WHEN 'invisibility'       THEN 8
    ELSE NULL
  END;

  IF v_min_level IS NULL THEN
    RAISE EXCEPTION 'invalid_key: %', p_key
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- ── Enforce level requirement ──────────────────────────────────────────────
  IF v_level < v_min_level THEN
    RAISE EXCEPTION 'vip_level_required: % requires VIP % (caller is VIP %)',
      p_key, v_min_level, v_level
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Upsert row then set the column ────────────────────────────────────────
  -- Ensure the row exists first (no-op if it already does).
  INSERT INTO public.user_vip_settings (user_id, updated_at)
  VALUES (v_uid, v_now)
  ON CONFLICT (user_id) DO NOTHING;

  -- Dynamic column update — safe because p_key is validated against the
  -- fixed CASE above; no user-supplied column name reaches format().
  EXECUTE format(
    'UPDATE public.user_vip_settings SET %I = $1, updated_at = $2 WHERE user_id = $3',
    p_key
  ) USING p_enabled, v_now, v_uid;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_my_vip_setting(text, boolean) TO authenticated;

-- ── 2. RPC: set_golden_id ────────────────────────────────────────────────────
--
-- Admin-only. Sets or clears the Golden ID flag on a user's profile.
-- Wraps the existing is_golden_id / golden_id_expires_at columns.
--
-- p_enabled = true  → sets is_golden_id = true
--                      sets golden_id_expires_at = now() + p_duration_days days
--                      if p_duration_days is null → permanent (no expiry)
-- p_enabled = false → clears both columns
--
-- Returns jsonb with {user_id, is_golden_id, golden_id_expires_at}.
--
-- Note: admin_set_user_golden_id() still exists for the admin panel
-- (it also updates public_user_id). This RPC is the simpler privilege-only
-- surface used by the VIP service layer.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_golden_id(
  p_user_id       uuid,
  p_enabled       boolean,
  p_duration_days int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expires_at timestamptz;
BEGIN
  -- Admin check reuses the existing helper from centralized_vip_system migration.
  IF NOT public._vip_caller_is_admin() THEN
    RAISE EXCEPTION 'permission_denied: admin role required'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_enabled THEN
    v_expires_at := CASE
      WHEN p_duration_days IS NOT NULL AND p_duration_days > 0
        THEN now() + (p_duration_days * interval '1 day')
      ELSE NULL
    END;

    UPDATE public.profiles
    SET
      is_golden_id         = true,
      golden_id_expires_at = v_expires_at
    WHERE id = p_user_id;
  ELSE
    UPDATE public.profiles
    SET
      is_golden_id         = false,
      golden_id_expires_at = NULL
    WHERE id = p_user_id;
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'user_id',             p.id,
      'is_golden_id',        p.is_golden_id,
      'golden_id_expires_at', p.golden_id_expires_at
    )
    FROM public.profiles p
    WHERE p.id = p_user_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_golden_id(uuid, boolean, int) TO authenticated;

-- ── 3. Expiry maintenance documentation ──────────────────────────────────────
--
-- expire_old_vips() already exists (centralized_vip_system migration).
-- It marks user_vip_subscriptions rows inactive and clears vip_level from
-- profiles for users whose subscription has ended.
--
-- CALLING OPTIONS (choose one based on your infra):
--
-- a) pg_cron (if enabled on your Supabase project):
--      SELECT cron.schedule(
--        'expire-old-vips-daily',
--        '0 3 * * *',        -- 03:00 UTC every day
--        $$ SELECT public.expire_old_vips() $$
--      );
--
-- b) Supabase Edge Function (HTTP cron trigger):
--      Deploy an edge function that calls `rpc('expire_old_vips')` and
--      schedule it via the Supabase Dashboard → Edge Functions → Schedule.
--
-- c) External cron (server, GitHub Actions, etc.):
--      POST to https://<project>.supabase.co/rest/v1/rpc/expire_old_vips
--      with service-role key.
--
-- pg_cron is NOT enabled in this project's migrations; do not add it here
-- unless the extension has been verified active in the Supabase project.
-- TODO Phase 5: enable pg_cron if Supabase project supports it, then apply
--              the schedule above.
-- =============================================================================

-- (No SQL needed for this section — documentation only.)

-- ── 4. Ensure set_my_vip_setting is not callable by anon ─────────────────────

REVOKE EXECUTE ON FUNCTION public.set_my_vip_setting(text, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_golden_id(uuid, boolean, int)  FROM anon;
