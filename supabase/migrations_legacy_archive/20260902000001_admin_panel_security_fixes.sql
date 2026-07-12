-- =============================================================================
-- Admin panel security fixes (2026-09-02)
--
-- 1. Confirm set_hungry_cat_forced_next_result has super_admin check   [no-op]
-- 2. Confirm set_rocket_crash_forced_next_multiplier has super_admin   [no-op]
-- 3. Confirm RLS on withdrawal_requests / promo_banners / hungry_cat_config [no-op]
-- 4. Patch get_current_loto_draw to return jackpot_contribution_pct
--    so the admin panel can display and save the correct value rather than
--    mistakenly loading jackpot_pool_coins as the contribution percentage.
-- =============================================================================

-- ── 4. Patch get_current_loto_draw — add jackpot_contribution_pct to settings
-- Uses CREATE OR REPLACE to remain idempotent.

CREATE OR REPLACE FUNCTION public.get_current_loto_draw()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_draw     public.loto_draws;
  v_s        public.loto_settings;
  v_balance  integer;
  v_tickets  jsonb;
BEGIN
  -- Load active or most-recent draw
  SELECT * INTO v_draw
  FROM public.loto_draws
  WHERE status IN ('open', 'closed', 'drawing')
  ORDER BY draw_at DESC
  LIMIT 1;

  -- Load settings
  SELECT * INTO v_s FROM public.loto_settings LIMIT 1;

  -- User balance
  SELECT coins_balance INTO v_balance
  FROM public.wallets WHERE user_id = v_user_id;

  -- User tickets for this draw
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',            t.id,
    'numbers',       t.numbers,
    'status',        t.status,
    'matched_count', t.matched_count,
    'prize_coins',   t.prize_coins,
    'created_at',    t.created_at
  ) ORDER BY t.created_at DESC), '[]'::jsonb)
  INTO v_tickets
  FROM public.loto_tickets t
  WHERE t.draw_id = v_draw.id AND t.user_id = v_user_id;

  RETURN jsonb_build_object(
    'draw', CASE WHEN v_draw.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',                  v_draw.id,
      'draw_number',         v_draw.draw_number,
      'status',              v_draw.status,
      'opens_at',            v_draw.opens_at,
      'closes_at',           v_draw.closes_at,
      'draw_at',             v_draw.draw_at,
      'total_tickets',       v_draw.total_tickets,
      'total_sales_coins',   v_draw.total_sales_coins,
      'jackpot_pool_before', v_draw.jackpot_pool_before
    ) END,
    'settings', jsonb_build_object(
      'is_enabled',                  v_s.is_enabled,
      'ticket_price_coins',          v_s.ticket_price_coins,
      'number_min',                  v_s.number_min,
      'number_max',                  v_s.number_max,
      'numbers_per_ticket',          v_s.numbers_per_ticket,
      'match_3_prize',               v_s.match_3_prize,
      'match_4_prize',               v_s.match_4_prize,
      'match_5_prize',               v_s.match_5_prize,
      'match_6_prize',               v_s.match_6_prize,
      'progressive_jackpot_enabled', v_s.progressive_jackpot_enabled,
      'jackpot_pool_coins',          v_s.jackpot_pool_coins,
      'jackpot_contribution_pct',    v_s.jackpot_contribution_pct,
      'responsible_notice_ar',       v_s.responsible_notice_ar,
      'responsible_notice_en',       v_s.responsible_notice_en
    ),
    'my_tickets',          v_tickets,
    'user_balance',        coalesce(v_balance, 0),
    'seconds_until_draw',  greatest(0, extract(epoch from (v_draw.draw_at - now()))::integer),
    'seconds_until_close', greatest(0, extract(epoch from (v_draw.closes_at - now()))::integer)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_current_loto_draw() TO authenticated;
