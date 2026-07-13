-- ============================================================
-- Room Level Balancing — v2
-- ============================================================
-- Root cause: early-level thresholds were set at 2,000–35,000 XP,
-- causing single large gifts (10,000-coin × 1.5 = 15,000 XP) to
-- jump 3+ levels in one transaction.
--
-- Fix: multiply every threshold by 10.
--   Level 2: 2,000  → 20,000   (requires ~20 medium gifts)
--   Level 5: 35,000 → 350,000  (requires sustained multi-session activity)
--   Level 10: 600,000 → 6,000,000
--
-- After updating thresholds we recompute room_level for every room
-- so the stored value stays consistent with the new curve.
-- Rooms that reached level 2–3 purely from one or two big gifts
-- will correctly drop back to level 1; their XP is still kept.
-- ============================================================

-- ── 1. Update thresholds × 10 (level 1 stays at 0) ──────────────────────────

update public.room_level_thresholds
set xp_required = xp_required * 10
where level > 1;

-- ── 2. Recompute room_level for all rooms against new curve ──────────────────

update public.rooms r
set room_level = (
  select coalesce(max(t.level), 1)
  from public.room_level_thresholds t
  where t.xp_required <= r.room_xp
);
