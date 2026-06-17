-- =============================================================================
-- User Level System — Phase L2: Schema Extension (100 Levels)
--
-- Changes:
--   1. user_levels  — add 3 new tracking columns
--   2. level_rules  — upsert 100 levels across 6 color tiers
--   3. get_user_level(uuid) — public display RPC (safe, no XP exposed)
--   4. get_my_level()       — full own-user progress RPC
--
-- XP curve targets:
--   Level 10  =     180,000
--   Level 25  =   3,000,000
--   Level 50  =  25,000,000
--   Level 75  = 120,000,000
--   Level 100 = 500,000,000
--
-- Color tiers:
--   bronze    1–10    (entry / beginner identity)
--   silver    11–25   (active social user)
--   gold      26–45   (supporter)
--   purple    46–65   (elite supporter)
--   diamond   66–85   (star supporter)
--   legendary 86–100  (legendary Srood icon)
--
-- Strict scope:
--   No VIP logic touched | No wallet/gift logic touched | No Flutter changes
--   Fully idempotent (ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE, ON CONFLICT DO UPDATE)
--
-- Backward compatibility:
--   ensure_user_level() — unaffected (new columns have defaults)
--   add_user_xp()       — unaffected (reads level_rules; 100 levels handled correctly)
--   MyLevelScreen       — still works; UserLevel.fromJson ignores new columns
-- =============================================================================

-- ── 1. user_levels — new tracking columns ────────────────────────────────────

ALTER TABLE public.user_levels
  ADD COLUMN IF NOT EXISTS total_gifts_sent     bigint      NOT NULL DEFAULT 0
                           CHECK (total_gifts_sent >= 0),
  ADD COLUMN IF NOT EXISTS total_gifts_received bigint      NOT NULL DEFAULT 0
                           CHECK (total_gifts_received >= 0),
  ADD COLUMN IF NOT EXISTS last_xp_at           timestamptz;

-- ── 2. level_rules — upsert 100 levels ───────────────────────────────────────
--
-- XP values computed on a piecewise geometric curve with clean rounding:
--   L1–L10  : given fixed values
--   L11–L25 : geometric from 180 K → 3 M  (nearest 1 K)
--   L26–L50 : geometric from 3 M  → 25 M  (nearest 10 K)
--   L51–L75 : geometric from 25 M → 120 M (nearest 100 K)
--   L76–L100: geometric from 120 M→ 500 M (nearest 500 K)
--
-- badge_key is null for levels without a dedicated badge (Phase L7 assigns them).
-- ON CONFLICT DO UPDATE is safe — level is UNIQUE in level_rules.

INSERT INTO public.level_rules
  (level, title, required_xp, badge_key, color_name, benefits, is_active)
VALUES
  -- ── Bronze 1–10: Entry / Beginner identity ──────────────────────────────────
  ( 1, 'New Voice',           0,          'new_member',  'bronze',    '["Welcome badge"]'::jsonb,               true),
  ( 2, 'Rising Voice',        1000,       'gift_sender', 'bronze',    '["Gift sender badge"]'::jsonb,           true),
  ( 3, 'Known Voice',         3000,       null,          'bronze',    '["Bronze identity"]'::jsonb,             true),
  ( 4, 'Room Voice',          7000,       null,          'bronze',    '["Room presence"]'::jsonb,               true),
  ( 5, 'Room Regular',        15000,      'room_host',   'bronze',    '["Room host badge"]'::jsonb,             true),
  ( 6, 'Active Voice',        30000,      null,          'bronze',    '["Active member"]'::jsonb,               true),
  ( 7, 'Active Regular',      50000,      null,          'bronze',    '["Active regular"]'::jsonb,              true),
  ( 8, 'Social Voice',        80000,      null,          'bronze',    '["Social presence"]'::jsonb,             true),
  ( 9, 'Social Regular',      120000,     null,          'bronze',    '["Social regular"]'::jsonb,              true),
  (10, 'Community Voice',     180000,     null,          'bronze',    '["Community member"]'::jsonb,            true),
  -- ── Silver 11–25: Active social user ────────────────────────────────────────
  (11, 'Gift Sender',         217000,     null,          'silver',    '["Silver identity"]'::jsonb,             true),
  (12, 'Gift Supporter',      262000,     null,          'silver',    '["Silver presence"]'::jsonb,             true),
  (13, 'Room Supporter',      316000,     null,          'silver',    '["Silver room"]'::jsonb,                 true),
  (14, 'Active Supporter',    381000,     null,          'silver',    '["Silver supporter"]'::jsonb,            true),
  (15, 'Loyal Supporter',     460000,     null,          'silver',    '["Silver loyalty"]'::jsonb,              true),
  (16, 'Silver Voice',        555000,     null,          'silver',    '["Silver voice"]'::jsonb,                true),
  (17, 'Silver Regular',      669000,     null,          'silver',    '["Silver regular"]'::jsonb,              true),
  (18, 'Silver Member',       807000,     null,          'silver',    '["Silver member"]'::jsonb,               true),
  (19, 'Silver Supporter',    974000,     null,          'silver',    '["Silver support"]'::jsonb,              true),
  (20, 'Silver Star',         1170000,    null,          'silver',    '["Silver star"]'::jsonb,                 true),
  (21, 'Community Supporter', 1420000,    null,          'silver',    '["Community support"]'::jsonb,           true),
  (22, 'Community Regular',   1710000,    null,          'silver',    '["Community regular"]'::jsonb,           true),
  (23, 'Community Member',    2060000,    null,          'silver',    '["Community member"]'::jsonb,            true),
  (24, 'Community Star',      2490000,    null,          'silver',    '["Community star"]'::jsonb,              true),
  (25, 'Community Champion',  3000000,    null,          'silver',    '["Silver champion"]'::jsonb,             true),
  -- ── Gold 26–45: Supporter ───────────────────────────────────────────────────
  (26, 'Golden Voice',        3270000,    null,          'gold',      '["Gold identity"]'::jsonb,               true),
  (27, 'Golden Regular',      3550000,    null,          'gold',      '["Gold regular"]'::jsonb,                true),
  (28, 'Golden Member',       3870000,    null,          'gold',      '["Gold member"]'::jsonb,                 true),
  (29, 'Golden Supporter',    4210000,    null,          'gold',      '["Gold supporter"]'::jsonb,              true),
  (30, 'Golden Star',         4580000,    null,          'gold',      '["Gold star"]'::jsonb,                   true),
  (31, 'Gift Champion',       4990000,    null,          'gold',      '["Gift champion"]'::jsonb,               true),
  (32, 'Room Champion',       5430000,    null,          'gold',      '["Room champion"]'::jsonb,               true),
  (33, 'Social Champion',     5910000,    null,          'gold',      '["Social champion"]'::jsonb,             true),
  (34, 'Rising Champion',     6440000,    null,          'gold',      '["Rising champion"]'::jsonb,             true),
  (35, 'Golden Champion',     7010000,    null,          'gold',      '["Gold champion"]'::jsonb,               true),
  (36, 'Gifted Voice',        7630000,    null,          'gold',      '["Gifted voice"]'::jsonb,                true),
  (37, 'Gifted Regular',      8300000,    null,          'gold',      '["Gifted regular"]'::jsonb,              true),
  (38, 'Gifted Member',       9040000,    null,          'gold',      '["Gifted member"]'::jsonb,               true),
  (39, 'Gifted Supporter',    9840000,    null,          'gold',      '["Gifted supporter"]'::jsonb,            true),
  (40, 'Gifted Champion',     10700000,   null,          'gold',      '["Gifted champion"]'::jsonb,             true),
  (41, 'Golden Flame',        11700000,   null,          'gold',      '["Gold flame"]'::jsonb,                  true),
  (42, 'Golden Spark',        12700000,   null,          'gold',      '["Gold spark"]'::jsonb,                  true),
  (43, 'Golden Spirit',       13800000,   null,          'gold',      '["Gold spirit"]'::jsonb,                 true),
  (44, 'Golden Soul',         15000000,   null,          'gold',      '["Gold soul"]'::jsonb,                   true),
  (45, 'Golden Legend',       16400000,   null,          'gold',      '["Gold legend"]'::jsonb,                 true),
  -- ── Purple 46–65: Elite supporter ───────────────────────────────────────────
  (46, 'Purple Voice',        17800000,   null,          'purple',    '["Purple identity"]'::jsonb,             true),
  (47, 'Purple Regular',      19400000,   null,          'purple',    '["Purple regular"]'::jsonb,              true),
  (48, 'Purple Member',       21100000,   null,          'purple',    '["Purple member"]'::jsonb,               true),
  (49, 'Purple Supporter',    23000000,   null,          'purple',    '["Purple supporter"]'::jsonb,            true),
  (50, 'Purple Star',         25000000,   null,          'purple',    '["Purple star"]'::jsonb,                 true),
  (51, 'Elite Voice',         26600000,   null,          'purple',    '["Elite voice"]'::jsonb,                 true),
  (52, 'Elite Regular',       28300000,   null,          'purple',    '["Elite regular"]'::jsonb,               true),
  (53, 'Elite Member',        30200000,   null,          'purple',    '["Elite member"]'::jsonb,                true),
  (54, 'Elite Supporter',     32100000,   null,          'purple',    '["Elite supporter"]'::jsonb,             true),
  (55, 'Elite Star',          34200000,   null,          'purple',    '["Elite star"]'::jsonb,                  true),
  (56, 'Purple Flame',        36400000,   null,          'purple',    '["Purple flame"]'::jsonb,                true),
  (57, 'Purple Spirit',       38800000,   null,          'purple',    '["Purple spirit"]'::jsonb,               true),
  (58, 'Purple Soul',         41300000,   null,          'purple',    '["Purple soul"]'::jsonb,                 true),
  (59, 'Elite Flame',         44000000,   null,          'purple',    '["Elite flame"]'::jsonb,                 true),
  (60, 'Elite Spirit',        46800000,   null,          'purple',    '["Elite spirit"]'::jsonb,                true),
  (61, 'Elite Soul',          49900000,   null,          'purple',    '["Elite soul"]'::jsonb,                  true),
  (62, 'Purple Crown',        53100000,   null,          'purple',    '["Purple crown"]'::jsonb,                true),
  (63, 'Elite Crown',         56500000,   null,          'purple',    '["Elite crown"]'::jsonb,                 true),
  (64, 'Royal Voice',         60200000,   null,          'purple',    '["Royal voice"]'::jsonb,                 true),
  (65, 'Royal Supporter',     64100000,   null,          'purple',    '["Royal supporter"]'::jsonb,             true),
  -- ── Diamond 66–85: Star supporter ───────────────────────────────────────────
  (66, 'Diamond Voice',       68200000,   null,          'diamond',   '["Diamond identity"]'::jsonb,            true),
  (67, 'Diamond Regular',     72600000,   null,          'diamond',   '["Diamond regular"]'::jsonb,             true),
  (68, 'Diamond Member',      77300000,   null,          'diamond',   '["Diamond member"]'::jsonb,              true),
  (69, 'Diamond Supporter',   82400000,   null,          'diamond',   '["Diamond supporter"]'::jsonb,           true),
  (70, 'Diamond Star',        87700000,   null,          'diamond',   '["Diamond star"]'::jsonb,                true),
  (71, 'Star Voice',          93400000,   null,          'diamond',   '["Star voice"]'::jsonb,                  true),
  (72, 'Star Regular',        99400000,   null,          'diamond',   '["Star regular"]'::jsonb,                true),
  (73, 'Star Member',         106000000,  null,          'diamond',   '["Star member"]'::jsonb,                 true),
  (74, 'Star Supporter',      112500000,  null,          'diamond',   '["Star supporter"]'::jsonb,              true),
  (75, 'Star Champion',       120000000,  null,          'diamond',   '["Star champion"]'::jsonb,               true),
  (76, 'Diamond Flame',       127000000,  null,          'diamond',   '["Diamond flame"]'::jsonb,               true),
  (77, 'Diamond Spirit',      134500000,  null,          'diamond',   '["Diamond spirit"]'::jsonb,              true),
  (78, 'Diamond Soul',        142500000,  null,          'diamond',   '["Diamond soul"]'::jsonb,                true),
  (79, 'Star Flame',          151000000,  null,          'diamond',   '["Star flame"]'::jsonb,                  true),
  (80, 'Star Spirit',         159500000,  null,          'diamond',   '["Star spirit"]'::jsonb,                 true),
  (81, 'Star Soul',           169000000,  null,          'diamond',   '["Star soul"]'::jsonb,                   true),
  (82, 'Diamond Crown',       179000000,  null,          'diamond',   '["Diamond crown"]'::jsonb,               true),
  (83, 'Star Crown',          189500000,  null,          'diamond',   '["Star crown"]'::jsonb,                  true),
  (84, 'Rising Star',         200500000,  null,          'diamond',   '["Rising star"]'::jsonb,                 true),
  (85, 'Star Legend',         212500000,  null,          'diamond',   '["Star legend"]'::jsonb,                 true),
  -- ── Legendary 86–100: Legendary Srood icon ──────────────────────────────────
  (86, 'Srood Voice',         225000000,  null,          'legendary', '["Legendary identity"]'::jsonb,          true),
  (87, 'Srood Regular',       238000000,  null,          'legendary', '["Legendary regular"]'::jsonb,           true),
  (88, 'Srood Member',        252000000,  null,          'legendary', '["Legendary member"]'::jsonb,            true),
  (89, 'Srood Supporter',     267000000,  null,          'legendary', '["Legendary supporter"]'::jsonb,         true),
  (90, 'Srood Star',          282500000,  null,          'legendary', '["Legendary star"]'::jsonb,              true),
  (91, 'Srood Champion',      299000000,  null,          'legendary', '["Legendary champion"]'::jsonb,          true),
  (92, 'Srood Flame',         316500000,  null,          'legendary', '["Legendary flame"]'::jsonb,             true),
  (93, 'Srood Spirit',        335500000,  null,          'legendary', '["Legendary spirit"]'::jsonb,            true),
  (94, 'Srood Soul',          355000000,  null,          'legendary', '["Legendary soul"]'::jsonb,              true),
  (95, 'Srood Crown',         376000000,  null,          'legendary', '["Legendary crown"]'::jsonb,             true),
  (96, 'Srood Legend',        398000000,  null,          'legendary', '["Srood legend"]'::jsonb,                true),
  (97, 'Grand Legend',        421500000,  null,          'legendary', '["Grand legend"]'::jsonb,                true),
  (98, 'Supreme Legend',      446000000,  null,          'legendary', '["Supreme legend"]'::jsonb,              true),
  (99, 'Ultimate Legend',     472500000,  null,          'legendary', '["Ultimate legend"]'::jsonb,             true),
 (100, 'Srood Icon',          500000000,  null,          'legendary', '["Srood Icon — highest title"]'::jsonb,  true)
ON CONFLICT (level) DO UPDATE SET
  title       = EXCLUDED.title,
  required_xp = EXCLUDED.required_xp,
  badge_key   = EXCLUDED.badge_key,
  color_name  = EXCLUDED.color_name,
  benefits    = EXCLUDED.benefits,
  is_active   = EXCLUDED.is_active,
  updated_at  = now();

-- ── 3. get_user_level(p_user_id) — public display RPC ────────────────────────
--
-- Returns public display fields only:  user_id, level, title, color_name, badge_key
-- Does NOT expose xp, totals, or any financial data.
-- Callable by any authenticated user for any other user_id.
-- Returns NULL if the user has no user_levels row yet.
-- SECURITY DEFINER bypasses user_levels RLS (own-user only) safely.

CREATE OR REPLACE FUNCTION public.get_user_level(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level  int;
  v_rule   record;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT ul.level
  INTO   v_level
  FROM   public.user_levels ul
  WHERE  ul.user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT lr.title, lr.color_name, lr.badge_key
  INTO   v_rule
  FROM   public.level_rules lr
  WHERE  lr.level     = v_level
    AND  lr.is_active = true
  LIMIT 1;

  RETURN jsonb_build_object(
    'user_id',    p_user_id,
    'level',      v_level,
    'title',      COALESCE(v_rule.title,      'Level ' || v_level),
    'color_name', COALESCE(v_rule.color_name, 'bronze'),
    'badge_key',  v_rule.badge_key
  );
END;
$$;

GRANT  EXECUTE ON FUNCTION public.get_user_level(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_user_level(uuid) FROM anon;

-- ── 4. get_my_level() — full own-user progress RPC ───────────────────────────
--
-- Returns full progress snapshot for the calling user including:
--   all accumulator totals, current + next rule, progress fraction, XP to next level.
-- Creates the user_levels row on first call (same as ensure_user_level).
-- Never exposes another user's data (enforced by auth.uid() binding).
-- SECURITY DEFINER allows it to write on first call.

CREATE OR REPLACE FUNCTION public.get_my_level()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid          uuid := auth.uid();
  v_ul           record;
  v_cur_rule     record;
  v_next_rule    record;
  v_xp_in_tier   bigint;
  v_xp_tier_span bigint;
  v_progress     numeric;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.user_levels (user_id)
  VALUES (v_uid)
  ON CONFLICT (user_id) DO UPDATE SET updated_at = public.user_levels.updated_at;

  SELECT * INTO v_ul
  FROM   public.user_levels
  WHERE  user_id = v_uid;

  SELECT * INTO v_cur_rule
  FROM   public.level_rules
  WHERE  level = v_ul.level AND is_active = true
  LIMIT  1;

  SELECT * INTO v_next_rule
  FROM   public.level_rules
  WHERE  level > v_ul.level AND is_active = true
  ORDER  BY level ASC
  LIMIT  1;

  IF v_next_rule IS NOT NULL THEN
    v_xp_in_tier   := v_ul.xp - COALESCE(v_cur_rule.required_xp, 0);
    v_xp_tier_span := v_next_rule.required_xp - COALESCE(v_cur_rule.required_xp, 0);
    v_progress := CASE
      WHEN v_xp_tier_span <= 0 THEN 1.0
      ELSE LEAST(1.0, GREATEST(0.0, v_xp_in_tier::numeric / v_xp_tier_span::numeric))
    END;
  ELSE
    v_progress := 1.0;  -- max level
  END IF;

  RETURN jsonb_build_object(
    'user_id',                    v_uid,
    'level',                      v_ul.level,
    'xp',                         v_ul.xp,
    'total_spent_coins',          v_ul.total_spent_coins,
    'total_received_gifts_value', v_ul.total_received_gifts_value,
    'total_room_minutes',         v_ul.total_room_minutes,
    'total_gifts_sent',           v_ul.total_gifts_sent,
    'total_gifts_received',       v_ul.total_gifts_received,
    'last_xp_at',                 v_ul.last_xp_at,
    'current_level_title',        COALESCE(v_cur_rule.title,      'Level ' || v_ul.level),
    'current_level_color',        COALESCE(v_cur_rule.color_name, 'bronze'),
    'current_level_badge_key',    v_cur_rule.badge_key,
    'current_level_required_xp',  COALESCE(v_cur_rule.required_xp, 0),
    'next_level',                 v_next_rule.level,
    'next_level_title',           v_next_rule.title,
    'next_level_required_xp',     v_next_rule.required_xp,
    'xp_to_next_level',           CASE
                                    WHEN v_next_rule IS NOT NULL
                                    THEN GREATEST(0, v_next_rule.required_xp - v_ul.xp)
                                    ELSE 0
                                  END,
    'level_progress',             v_progress
  );
END;
$$;

GRANT  EXECUTE ON FUNCTION public.get_my_level() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_my_level() FROM anon;

-- ── 5. add_user_xp — update last_xp_at when XP is awarded ───────────────────
--
-- The existing add_user_xp() function does not set last_xp_at (column is new).
-- Replace it to also stamp the timestamp. Logic is otherwise identical.

CREATE OR REPLACE FUNCTION public.add_user_xp(
  p_user_id uuid,
  p_xp      bigint,
  p_source  text DEFAULT NULL
)
RETURNS public.user_levels
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level     public.user_levels;
  v_new_level integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_user_id <> auth.uid() AND NOT public.profile_hub_admin_access() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  INSERT INTO public.user_levels (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE public.user_levels
  SET
    xp          = xp + GREATEST(COALESCE(p_xp, 0), 0),
    last_xp_at  = now(),
    updated_at  = now()
  WHERE user_id = p_user_id
  RETURNING * INTO v_level;

  SELECT COALESCE(MAX(level), 1)
  INTO   v_new_level
  FROM   public.level_rules
  WHERE  is_active
    AND  required_xp <= v_level.xp;

  UPDATE public.user_levels
  SET
    level      = GREATEST(level, v_new_level),
    updated_at = now()
  WHERE user_id = p_user_id
  RETURNING * INTO v_level;

  RETURN v_level;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_user_xp(uuid, bigint, text) TO authenticated;

-- =============================================================================
-- Phase L2 complete.
--
-- Tables altered:
--   user_levels   ← +total_gifts_sent, +total_gifts_received, +last_xp_at
--
-- level_rules data:
--   100 levels upserted
--   Bronze 1–10   | XP 0 → 180,000
--   Silver 11–25  | XP 217,000 → 3,000,000
--   Gold 26–45    | XP 3,270,000 → 16,400,000
--   Purple 46–65  | XP 17,800,000 → 64,100,000
--   Diamond 66–85 | XP 68,200,000 → 212,500,000
--   Legendary 86–100 | XP 225,000,000 → 500,000,000
--
-- RPCs:
--   get_user_level(uuid) ← public display (level + title + color + badge_key only)
--   get_my_level()       ← full own-user progress snapshot
--   add_user_xp()        ← updated to stamp last_xp_at (logic otherwise unchanged)
--
-- Unchanged:
--   ensure_user_level()  All VIP migrations  Wallet/gift logic  Flutter
--
-- Next:
--   Phase L3 — hook send_gift_with_wallet → apply_gift_level_xp
--   Phase L4 — Flutter model + LevelService.getMyLevel() → get_my_level()
-- =============================================================================
