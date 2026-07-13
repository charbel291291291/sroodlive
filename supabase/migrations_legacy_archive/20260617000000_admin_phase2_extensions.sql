-- =============================================================================
-- Admin Phase 2 Extensions
-- Implements:
--   1. expire_user_restrictions()  — auto-expire timed restrictions
--   2. admin_search_audit_logs()   — filtered audit log search
--   3. admin_update_recharge_agency() — update agency including commission_rate
--   4. user_reports table + 3 RPCs (submit, list, update_status)
--
-- Safety rules:
--   - admin_audit_logs is immutable: no DELETE policy added
--   - commission_rate changes gated to has_finance_access()
--   - o_super_admin-only actions are enforced inside each RPC
--   - No tables dropped, no data deleted
-- =============================================================================

-- ── 1. expire_user_restrictions() ────────────────────────────────────────────
--
-- Call this from a Supabase Scheduled Edge Function (recommended) or pg_cron.
-- Finds active rows where expires_at <= now(), marks is_active = false,
-- writes one audit log entry per expired restriction, returns total count.
--
-- Scheduling option A — Supabase Dashboard > Edge Functions > Schedules:
--   Deploy an Edge Function that calls: supabase.rpc('expire_user_restrictions')
--   Set schedule: 0 * * * * (every hour) or 0 3 * * * (daily 03:00 UTC)
--
-- Scheduling option B — pg_cron (only if enabled on the project):
--   SELECT cron.schedule('expire-restrictions-hourly','0 * * * *',
--     $$ SELECT public.expire_user_restrictions() $$);

CREATE OR REPLACE FUNCTION public.expire_user_restrictions()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row   record;
  v_count int := 0;
BEGIN
  FOR v_row IN
    SELECT id, user_id, restriction_type
    FROM   public.admin_user_restrictions
    WHERE  is_active   = true
      AND  expires_at IS NOT NULL
      AND  expires_at <= now()
  LOOP
    UPDATE public.admin_user_restrictions
    SET    is_active  = false,
           updated_at = now()
    WHERE  id = v_row.id;

    INSERT INTO public.admin_audit_logs
      (admin_user_id, target_user_id, action, entity_type, entity_id, metadata)
    VALUES
      (NULL,
       v_row.user_id,
       'restriction_expired',
       'admin_user_restrictions',
       v_row.id::text,
       jsonb_build_object(
         'restriction_type', v_row.restriction_type,
         'expired_at',       now()
       ));

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- No public GRANT — called only by the service role / cron scheduler.
-- Admins cannot call this directly from the app (no authenticated grant).

-- ── 2. admin_search_audit_logs() ─────────────────────────────────────────────
--
-- Filtered search for the Audit Log module.
-- Requires any admin role (has_admin_access()).
-- No DELETE policy is added — audit logs are immutable.

CREATE OR REPLACE FUNCTION public.admin_search_audit_logs(
  p_actor_id      uuid    DEFAULT NULL,
  p_action        text    DEFAULT NULL,
  p_target_type   text    DEFAULT NULL,
  p_from          timestamptz DEFAULT NULL,
  p_to            timestamptz DEFAULT NULL,
  p_limit         int     DEFAULT 100
)
RETURNS TABLE (
  id                   uuid,
  admin_user_id        uuid,
  admin_public_user_id text,
  admin_name           text,
  target_user_id       uuid,
  target_public_user_id text,
  target_name          text,
  action               text,
  entity_type          text,
  entity_id            text,
  metadata             jsonb,
  created_at           timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    al.id,
    al.admin_user_id,
    ap.public_user_id  AS admin_public_user_id,
    ap.display_name    AS admin_name,
    al.target_user_id,
    tp.public_user_id  AS target_public_user_id,
    tp.display_name    AS target_name,
    al.action,
    al.entity_type,
    al.entity_id,
    al.metadata,
    al.created_at
  FROM  public.admin_audit_logs al
  LEFT  JOIN public.profiles ap ON ap.id = al.admin_user_id
  LEFT  JOIN public.profiles tp ON tp.id = al.target_user_id
  WHERE public.has_admin_access()
    AND (p_actor_id    IS NULL OR al.admin_user_id  = p_actor_id)
    AND (p_action      IS NULL OR al.action         ILIKE '%' || p_action || '%')
    AND (p_target_type IS NULL OR al.entity_type    = p_target_type)
    AND (p_from        IS NULL OR al.created_at    >= p_from)
    AND (p_to          IS NULL OR al.created_at    <= p_to)
  ORDER BY al.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500));
$$;

GRANT EXECUTE ON FUNCTION public.admin_search_audit_logs(uuid,text,text,timestamptz,timestamptz,int)
  TO authenticated;

-- ── 3. admin_update_recharge_agency() ────────────────────────────────────────
--
-- Lets admins update agency metadata and commission rate.
-- commission_rate changes require has_finance_access()
-- (p_super_admin or o_super_admin).
-- Other field changes require has_bd_access().

CREATE OR REPLACE FUNCTION public.admin_update_recharge_agency(
  p_agency_id       uuid,
  p_name            text    DEFAULT NULL,
  p_whatsapp        text    DEFAULT NULL,
  p_country         text    DEFAULT NULL,
  p_commission_rate numeric DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_old    record;
BEGIN
  IF NOT public.has_bd_access() THEN
    RAISE EXCEPTION 'permission_denied: bd_access required';
  END IF;

  IF p_commission_rate IS NOT NULL AND NOT public.has_finance_access() THEN
    RAISE EXCEPTION 'permission_denied: finance_access required to change commission_rate';
  END IF;

  SELECT name, whatsapp, country, commission_rate
  INTO   v_old
  FROM   public.recharge_agencies
  WHERE  id = p_agency_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: agency % does not exist', p_agency_id;
  END IF;

  UPDATE public.recharge_agencies
  SET
    name            = COALESCE(p_name,            name),
    whatsapp        = COALESCE(p_whatsapp,         whatsapp),
    country         = COALESCE(p_country,          country),
    commission_rate = COALESCE(p_commission_rate,  commission_rate),
    updated_at      = now()
  WHERE id = p_agency_id;

  INSERT INTO public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  VALUES
    (v_caller,
     'agency_updated',
     'recharge_agencies',
     p_agency_id::text,
     jsonb_build_object(
       'old', jsonb_build_object(
         'name',            v_old.name,
         'whatsapp',        v_old.whatsapp,
         'country',         v_old.country,
         'commission_rate', v_old.commission_rate
       ),
       'new', jsonb_build_object(
         'name',            COALESCE(p_name,           v_old.name),
         'whatsapp',        COALESCE(p_whatsapp,        v_old.whatsapp),
         'country',         COALESCE(p_country,         v_old.country),
         'commission_rate', COALESCE(p_commission_rate, v_old.commission_rate)
       )
     ));
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_recharge_agency(uuid,text,text,text,numeric)
  TO authenticated;

-- ── 4a. user_reports table ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.user_reports (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target_type     text        NOT NULL CHECK (target_type IN (
                                'user','room','message','profile_image',
                                'room_cover','bio','gift','other'
                              )),
  target_id       text        NOT NULL,
  reason          text        NOT NULL,
  details         text        NULL,
  status          text        NOT NULL DEFAULT 'pending'
                              CHECK (status IN (
                                'pending','reviewing','resolved',
                                'rejected','needs_more_info'
                              )),
  created_at      timestamptz NOT NULL DEFAULT now(),
  resolved_by     uuid        NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  resolved_at     timestamptz NULL,
  resolution_note text        NULL
);

CREATE INDEX IF NOT EXISTS user_reports_status_idx
  ON public.user_reports (status, created_at DESC);

CREATE INDEX IF NOT EXISTS user_reports_reporter_idx
  ON public.user_reports (reporter_id);

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

-- Users can see only their own reports
DROP POLICY IF EXISTS "Users can view own reports" ON public.user_reports;
CREATE POLICY "Users can view own reports"
  ON public.user_reports FOR SELECT
  TO authenticated
  USING (reporter_id = auth.uid() OR public.has_admin_access());

-- Users can insert their own reports
DROP POLICY IF EXISTS "Users can submit reports" ON public.user_reports;
CREATE POLICY "Users can submit reports"
  ON public.user_reports FOR INSERT
  TO authenticated
  WITH CHECK (reporter_id = auth.uid());

GRANT SELECT, INSERT ON public.user_reports TO authenticated;

-- ── 4b. submit_user_report() ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.submit_user_report(
  p_target_type text,
  p_target_id   text,
  p_reason      text,
  p_details     text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller  uuid := auth.uid();
  v_report_id uuid;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  -- Rate-limit: max 5 reports per user per hour
  IF (
    SELECT count(*) FROM public.user_reports
    WHERE  reporter_id = v_caller
      AND  created_at >= now() - interval '1 hour'
  ) >= 5 THEN
    RAISE EXCEPTION 'rate_limited: max 5 reports per hour';
  END IF;

  INSERT INTO public.user_reports
    (reporter_id, target_type, target_id, reason, details)
  VALUES
    (v_caller, p_target_type, p_target_id, p_reason, p_details)
  RETURNING id INTO v_report_id;

  RETURN v_report_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_user_report(text,text,text,text)
  TO authenticated;

-- ── 4c. admin_list_reports() ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_list_reports(
  p_status      text DEFAULT NULL,
  p_target_type text DEFAULT NULL,
  p_limit       int  DEFAULT 100
)
RETURNS TABLE (
  id              uuid,
  reporter_id     uuid,
  reporter_public_user_id text,
  reporter_name   text,
  target_type     text,
  target_id       text,
  reason          text,
  details         text,
  status          text,
  created_at      timestamptz,
  resolved_by     uuid,
  resolved_by_name text,
  resolved_at     timestamptz,
  resolution_note text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    r.id,
    r.reporter_id,
    rp.public_user_id  AS reporter_public_user_id,
    rp.display_name    AS reporter_name,
    r.target_type,
    r.target_id,
    r.reason,
    r.details,
    r.status,
    r.created_at,
    r.resolved_by,
    ap.display_name    AS resolved_by_name,
    r.resolved_at,
    r.resolution_note
  FROM  public.user_reports r
  LEFT  JOIN public.profiles rp ON rp.id = r.reporter_id
  LEFT  JOIN public.profiles ap ON ap.id = r.resolved_by
  WHERE public.has_admin_access()
    AND (p_status      IS NULL OR r.status      = p_status)
    AND (p_target_type IS NULL OR r.target_type = p_target_type)
  ORDER BY
    CASE r.status WHEN 'pending' THEN 0 WHEN 'reviewing' THEN 1 ELSE 2 END,
    r.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500));
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_reports(text,text,int)
  TO authenticated;

-- ── 4d. admin_update_report_status() ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_update_report_status(
  p_report_id     uuid,
  p_status        text,
  p_resolution_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
BEGIN
  IF NOT public.has_admin_access() THEN
    RAISE EXCEPTION 'permission_denied: admin access required';
  END IF;

  IF p_status NOT IN ('pending','reviewing','resolved','rejected','needs_more_info') THEN
    RAISE EXCEPTION 'invalid_status: %', p_status;
  END IF;

  UPDATE public.user_reports
  SET
    status          = p_status,
    resolved_by     = CASE WHEN p_status IN ('resolved','rejected') THEN v_caller ELSE resolved_by END,
    resolved_at     = CASE WHEN p_status IN ('resolved','rejected') THEN now()      ELSE resolved_at END,
    resolution_note = COALESCE(p_resolution_note, resolution_note)
  WHERE id = p_report_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: report % does not exist', p_report_id;
  END IF;

  INSERT INTO public.admin_audit_logs
    (admin_user_id, action, entity_type, entity_id, metadata)
  VALUES
    (v_caller,
     'report_status_updated',
     'user_reports',
     p_report_id::text,
     jsonb_build_object(
       'status',          p_status,
       'resolution_note', p_resolution_note
     ));
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_report_status(uuid,text,text)
  TO authenticated;

-- =============================================================================
-- End of admin_phase2_extensions.sql
-- =============================================================================
