-- ── Admin promo banners SECURITY DEFINER RPCs ────────────────────────────────
-- Replaces direct promo_banners table access from the Flutter admin client.
-- Each RPC verifies the caller holds at least super_admin role.

-- ── Helper: assert caller has banners.manage permission (≥ super_admin) ───────

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

-- ── admin_list_promo_banners ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_list_promo_banners(
  p_limit int DEFAULT 200
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._admin_assert_banners_role();
  p_limit := LEAST(GREATEST(COALESCE(p_limit, 200), 1), 500);
  RETURN COALESCE(
    (
      SELECT jsonb_agg(
        row_to_json(b.*)::jsonb
        ORDER BY b.sort_order ASC NULLS LAST
      )
      FROM (SELECT * FROM public.promo_banners LIMIT p_limit) b
    ),
    '[]'::jsonb
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_promo_banners(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_promo_banners(int) TO authenticated;

-- ── admin_upsert_promo_banner ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_upsert_promo_banner(
  p_id             uuid,
  p_slide_key      text,
  p_sort_order     int,
  p_is_active      boolean,
  p_label_en       text,
  p_label_ar       text,
  p_title_en       text,
  p_title_ar       text,
  p_subtitle_en    text,
  p_subtitle_ar    text,
  p_cta_en         text,
  p_cta_ar         text,
  p_icon_name      text,
  p_gradient_start text DEFAULT NULL,
  p_gradient_mid   text DEFAULT NULL,
  p_gradient_end   text DEFAULT NULL,
  p_icon_bg_color  text DEFAULT NULL,
  p_image_url      text DEFAULT NULL,
  p_target_route   text DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._admin_assert_banners_role();
  INSERT INTO public.promo_banners (
    id, slide_key, sort_order, is_active,
    label_en, label_ar, title_en, title_ar,
    subtitle_en, subtitle_ar, cta_en, cta_ar,
    icon_name, gradient_start, gradient_mid, gradient_end,
    icon_bg_color, image_url, target_route, updated_at
  )
  VALUES (
    COALESCE(p_id, gen_random_uuid()),
    p_slide_key, p_sort_order, p_is_active,
    p_label_en, p_label_ar, p_title_en, p_title_ar,
    p_subtitle_en, p_subtitle_ar, p_cta_en, p_cta_ar,
    p_icon_name, p_gradient_start, p_gradient_mid, p_gradient_end,
    p_icon_bg_color, p_image_url, p_target_route, now()
  )
  ON CONFLICT (slide_key) DO UPDATE SET
    sort_order     = EXCLUDED.sort_order,
    is_active      = EXCLUDED.is_active,
    label_en       = EXCLUDED.label_en,
    label_ar       = EXCLUDED.label_ar,
    title_en       = EXCLUDED.title_en,
    title_ar       = EXCLUDED.title_ar,
    subtitle_en    = EXCLUDED.subtitle_en,
    subtitle_ar    = EXCLUDED.subtitle_ar,
    cta_en         = EXCLUDED.cta_en,
    cta_ar         = EXCLUDED.cta_ar,
    icon_name      = EXCLUDED.icon_name,
    gradient_start = EXCLUDED.gradient_start,
    gradient_mid   = EXCLUDED.gradient_mid,
    gradient_end   = EXCLUDED.gradient_end,
    icon_bg_color  = EXCLUDED.icon_bg_color,
    image_url      = EXCLUDED.image_url,
    target_route   = EXCLUDED.target_route,
    updated_at     = now();
END;
$$;
REVOKE ALL ON FUNCTION public.admin_upsert_promo_banner(
  uuid, text, int, boolean, text, text, text, text,
  text, text, text, text, text, text, text, text, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_upsert_promo_banner(
  uuid, text, int, boolean, text, text, text, text,
  text, text, text, text, text, text, text, text, text, text, text
) TO authenticated;

-- ── admin_delete_promo_banner ─────────────────────────────────────────────────
-- Requires typed confirmation: p_confirm_key must equal 'DELETE BANNER ' || slide_key

CREATE OR REPLACE FUNCTION public.admin_delete_promo_banner(
  p_banner_id   uuid,
  p_confirm_key text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_slide_key    text;
  v_expected_key text;
BEGIN
  PERFORM public._admin_assert_banners_role();

  SELECT slide_key INTO v_slide_key
  FROM public.promo_banners WHERE id = p_banner_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'banner_not_found';
  END IF;

  v_expected_key := 'DELETE BANNER ' || v_slide_key;
  IF p_confirm_key IS DISTINCT FROM v_expected_key THEN
    RAISE EXCEPTION 'confirmation_mismatch';
  END IF;

  DELETE FROM public.promo_banners WHERE id = p_banner_id;
  RETURN jsonb_build_object('success', true, 'slide_key', v_slide_key);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_delete_promo_banner(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_promo_banner(uuid, text) TO authenticated;

-- ── admin_check_golden_id_available ──────────────────────────────────────────
-- Returns true when the public_user_id is NOT taken by anyone except p_exclude_user_id.

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
