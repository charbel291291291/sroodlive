-- Fix: admin roles table is named admin_users, not admin_roles.
-- Corrects _admin_assert_banners_role and admin_check_golden_id_available
-- which were deployed in 20261020000000 with the wrong table reference.

CREATE OR REPLACE FUNCTION public._admin_assert_banners_role()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = auth.uid()
      AND is_active = true
      AND role IN ('o_super_admin', 'p_super_admin', 'super_admin')
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._admin_assert_banners_role() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_check_golden_id_available(
  p_public_user_id  text,
  p_exclude_user_id uuid DEFAULT NULL
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = auth.uid() AND is_active = true
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
  RETURN NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE public_user_id = p_public_user_id
      AND (p_exclude_user_id IS NULL OR id != p_exclude_user_id)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_check_golden_id_available(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_check_golden_id_available(text, uuid) TO authenticated;
