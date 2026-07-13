/// Room level progression sheet: tier badge, XP progress, daily/weekly
/// stats, streak multiplier, XP sources guide, and upcoming/unlocked
/// rewards. The threshold table mirrors the DB and is presentation-only.
library;

import 'package:flutter/material.dart';

import '../../../theme/srood_room_theme.dart';

class SroodLevelData {
  const SroodLevelData(this.level, this.xpRequired, this.tier, this.unlock);

  final int level;
  final int xpRequired;
  final String tier;
  final String unlock;
}

/// Static threshold table (mirrors DB) + tier styling helpers.
class SroodRoomLevelInfo {
  SroodRoomLevelInfo._();

  static const List<SroodLevelData> thresholds = [
    SroodLevelData(1, 0, 'Starter', 'Violet Glass Mic Pods'),
    SroodLevelData(2, 2000, 'Starter', 'Stronger Mic Glow'),
    SroodLevelData(3, 6000, 'Starter', 'Silver Glass Border'),
    SroodLevelData(4, 15000, 'Starter', 'Animated Seat Border Pulse'),
    SroodLevelData(5, 35000, 'Starter', 'Blue Prestige Seat Style'),
    SroodLevelData(6, 75000, 'Rising', 'Blue Aura Room Glow'),
    SroodLevelData(7, 140000, 'Rising', 'Gold Accent Ring'),
    SroodLevelData(8, 240000, 'Rising', 'Purple Crown Room'),
    SroodLevelData(9, 380000, 'Rising', 'Advanced PK Mode Access'),
    SroodLevelData(10, 600000, 'Rising', 'Gold Room Frame'),
    SroodLevelData(11, 800000, 'Prestige', 'Premium Entrance Effect'),
    SroodLevelData(12, 1065000, 'Prestige', 'Enhanced Room Badge Glow'),
    SroodLevelData(13, 1415000, 'Prestige', 'Extended Welcome Message'),
    SroodLevelData(14, 1880000, 'Prestige', 'Ruby Seat Theme'),
    SroodLevelData(15, 2500000, 'Prestige', 'Premium Room Background'),
    SroodLevelData(16, 3155000, 'Elite', 'Animated Room Intro'),
    SroodLevelData(17, 3980000, 'Elite', 'Dual-Color Seat Ring'),
    SroodLevelData(18, 5020000, 'Elite', 'Enhanced Gift Effects'),
    SroodLevelData(19, 6335000, 'Elite', 'Elite Room Banner'),
    SroodLevelData(20, 8000000, 'Elite', 'Royal Mic Seats'),
    SroodLevelData(21, 9610000, 'Grand', 'Extended Host Controls'),
    SroodLevelData(22, 11540000, 'Grand', 'Custom Intro Music Slot'),
    SroodLevelData(23, 13860000, 'Grand', 'Premium Seat Numbering'),
    SroodLevelData(24, 16640000, 'Grand', 'Diamond Border Effects'),
    SroodLevelData(25, 20000000, 'Grand', 'Room Entrance Animation'),
    SroodLevelData(26, 23520000, 'Royal', 'Priority Room Discovery'),
    SroodLevelData(27, 27660000, 'Royal', 'Custom Room Badge Shape'),
    SroodLevelData(28, 32530000, 'Royal', 'Exclusive Gift Reactions'),
    SroodLevelData(29, 38260000, 'Royal', 'Extended PK Battle Time'),
    SroodLevelData(30, 45000000, 'Royal', 'Crown Room Badge'),
    SroodLevelData(31, 51700000, 'Legend', 'Elite Tier Priority Listing'),
    SroodLevelData(32, 59400000, 'Legend', 'Sapphire Seat Theme'),
    SroodLevelData(33, 68250000, 'Legend', 'Custom Announcement Style'),
    SroodLevelData(34, 78420000, 'Legend', 'Golden Room Aura'),
    SroodLevelData(35, 90000000, 'Legend', 'Diamond Seat Glow'),
    SroodLevelData(36, 102240000, 'Mythic', 'Enhanced Leaderboard Rank'),
    SroodLevelData(37, 116140000, 'Mythic', 'Cosmic Seat Pulse'),
    SroodLevelData(38, 131935000, 'Mythic', 'Private Room Analytics'),
    SroodLevelData(39, 149878000, 'Mythic', 'Platinum Room Frame'),
    SroodLevelData(40, 170000000, 'Mythic', 'Palace Room Theme'),
    SroodLevelData(41, 190400000, 'Immortal', 'Mythic Room Entrance'),
    SroodLevelData(42, 213248000, 'Immortal', 'Galaxy Seat Effects'),
    SroodLevelData(43, 238838000, 'Immortal', 'Rainbow Gift Reactions'),
    SroodLevelData(44, 267499000, 'Immortal', 'Legendary Room Banner'),
    SroodLevelData(45, 300000000, 'Immortal', 'Elite Ranking Priority'),
    SroodLevelData(46, 332100000, 'Throne', 'Eternal Aura'),
    SroodLevelData(47, 367734000, 'Throne', 'Shadow Throne Effects'),
    SroodLevelData(48, 407082000, 'Throne', 'Eclipse Seat Theme'),
    SroodLevelData(49, 450638000, 'Throne', 'Immortal Room Badge'),
    SroodLevelData(50, 500000000, 'Throne', 'Legend Throne Room Theme'),
  ];

  static SroodLevelData dataForLevel(int lvl) =>
      thresholds[(lvl.clamp(1, 50)) - 1];

  static SroodLevelData? nextLevel(int lvl) =>
      lvl >= 50 ? null : thresholds[lvl.clamp(1, 49)];

  static Color tierColor(String tier) {
    switch (tier) {
      case 'Rising':
        return const Color(0xFF60A5FA);
      case 'Prestige':
        return const Color(0xFFE879F9);
      case 'Elite':
        return const Color(0xFFFFD700);
      case 'Grand':
        return const Color(0xFF34D399);
      case 'Royal':
        return const Color(0xFFFF6B6B);
      case 'Legend':
        return const Color(0xFFFF9500);
      case 'Mythic':
        return const Color(0xFFE040FB);
      case 'Immortal':
        return const Color(0xFF00E5FF);
      case 'Throne':
        return const Color(0xFFFFD700);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  static String _fmt(int xp) {
    if (xp >= 1000000) return '${(xp / 1000000).toStringAsFixed(1)}M';
    if (xp >= 1000) return '${(xp / 1000).toStringAsFixed(1)}K';
    return xp.toString();
  }

  static String motivationalText({
    required int level,
    required int remainingXp,
    required int dailyStreak,
    required double streakMultiplier,
  }) {
    final next = nextLevel(level);
    if (next == null) {
      return '🏆 Maximum level reached. Your room is legendary.';
    }
    final fmtRemaining = _fmt(remainingXp);
    if (streakMultiplier < 1.25 && dailyStreak < 7) {
      final daysLeft = 7 - dailyStreak;
      return 'Keep your streak for $daysLeft more day${daysLeft == 1 ? '' : 's'} to activate ×1.25 XP';
    }
    return 'Only $fmtRemaining XP left to unlock ${next.unlock}';
  }
}

class SroodRoomLevelSheet extends StatelessWidget {
  const SroodRoomLevelSheet({
    required this.roomId,
    required this.level,
    required this.roomXp,
    required this.xpToday,
    required this.xpWeek,
    required this.dailyStreak,
    required this.streakMultiplier,
    super.key,
  });

  final String roomId;
  final int level;
  final int roomXp;
  final int xpToday;
  final int xpWeek;
  final int dailyStreak;
  final double streakMultiplier;

  String _fmt(int xp) {
    if (xp >= 1000000) return '${(xp / 1000000).toStringAsFixed(2)}M';
    if (xp >= 1000) return '${(xp / 1000).toStringAsFixed(1)}K';
    return xp.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cur = SroodRoomLevelInfo.dataForLevel(level);
    final next = SroodRoomLevelInfo.nextLevel(level);
    final tier = cur.tier;
    final tc = SroodRoomLevelInfo.tierColor(tier);

    final prevXp = cur.xpRequired;
    final nextXp = next?.xpRequired ?? prevXp;
    final span = nextXp - prevXp;
    final progress = span > 0
        ? ((roomXp - prevXp) / span).clamp(0.0, 1.0)
        : 1.0;
    final remaining = next != null ? (nextXp - roomXp).clamp(0, nextXp) : 0;
    final pct = (progress * 100).toStringAsFixed(1);

    final motivText = SroodRoomLevelInfo.motivationalText(
      level: level,
      remainingXp: remaining,
      dailyStreak: dailyStreak,
      streakMultiplier: streakMultiplier,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(
                const Color(0xFF0D0720),
                tc.withValues(alpha: 0.18),
                0.4,
              )!,
              const Color(0xFF08040F),
            ],
          ),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(SroodRoomDims.radiusSheet),
          ),
          border: Border(
            top: BorderSide(color: tc.withValues(alpha: 0.35), width: 1.2),
          ),
        ),
        child: Column(
          children: [
            // drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  // ── Tier badge + level headline ──────────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              tc.withValues(alpha: 0.25),
                              tc.withValues(alpha: 0.10),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: tc.withValues(alpha: 0.55),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          tier.toUpperCase(),
                          style: TextStyle(
                            fontSize: SroodRoomDims.textSm,
                            fontWeight: FontWeight.w900,
                            color: tc,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'LV $level',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: tc,
                          shadows: [
                            Shadow(
                              color: tc.withValues(alpha: 0.6),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SroodRoomDims.space4),
                  Text(
                    cur.unlock,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── XP progress bar ──────────────────────────────────────
                  if (next != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_fmt(roomXp)} XP',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: TextStyle(
                            fontSize: 12,
                            color: tc,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${_fmt(nextXp)} XP',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SroodRoomDims.space6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        children: [
                          Container(
                            height: 10,
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              height: 10,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [tc, tc.withValues(alpha: 0.6)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: tc.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SroodRoomDims.space6),
                    Text(
                      '${_fmt(remaining)} XP remaining to LV ${level + 1}',
                      style: const TextStyle(
                        fontSize: SroodRoomDims.textSm,
                        color: Colors.white38,
                      ),
                    ),
                  ] else
                    Container(
                      padding: const EdgeInsets.all(SroodRoomDims.space12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            tc.withValues(alpha: 0.15),
                            tc.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(
                          SroodRoomDims.radiusMd,
                        ),
                        border: Border.all(color: tc.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.emoji_events_rounded, color: tc, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'Maximum Level — Legend Status Achieved',
                            style: TextStyle(
                              fontSize: SroodRoomDims.textMd,
                              fontWeight: FontWeight.w700,
                              color: tc,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: SroodRoomDims.space20),

                  // ── Stats row ────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _XpStatCard(
                          label: 'Today',
                          value: _fmt(xpToday),
                          icon: Icons.today_rounded,
                          color: tc,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _XpStatCard(
                          label: 'This Week',
                          value: _fmt(xpWeek),
                          icon: Icons.calendar_view_week_rounded,
                          color: const Color(0xFF60A5FA),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _XpStatCard(
                          label: 'Streak',
                          value:
                              '$dailyStreak day${dailyStreak == 1 ? '' : 's'}',
                          icon: Icons.local_fire_department_rounded,
                          color: dailyStreak >= 7
                              ? const Color(0xFFFF9500)
                              : const Color(0xFFFF6B6B),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _XpStatCard(
                          label: 'Multiplier',
                          value: '×${streakMultiplier.toStringAsFixed(2)}',
                          icon: Icons.bolt_rounded,
                          color: streakMultiplier > 1.0
                              ? const Color(0xFFFFD700)
                              : Colors.white38,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: SroodRoomDims.space20),

                  // ── Motivational challenge ───────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A0A30), Color(0xFF0D0520)],
                      ),
                      borderRadius: BorderRadius.circular(
                        SroodRoomDims.radiusMd + 2,
                      ),
                      border: Border.all(color: tc.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.emoji_flags_rounded, color: tc, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            motivText,
                            style: TextStyle(
                              fontSize: SroodRoomDims.textMd,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // ── XP sources guide ─────────────────────────────────────
                  Text(
                    'How to earn XP',
                    style: TextStyle(
                      fontSize: SroodRoomDims.textMd,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.55),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._xpSources.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(
                        bottom: SroodRoomDims.space8,
                      ),
                      child: Row(
                        children: [
                          Icon(s.$1, size: 16, color: s.$3),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.$2,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // ── Upcoming unlocks ─────────────────────────────────────
                  Text(
                    'Upcoming Unlocks',
                    style: TextStyle(
                      fontSize: SroodRoomDims.textMd,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.55),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate((level + 5).clamp(0, 50) - level, (i) {
                    final upcoming = SroodRoomLevelInfo.nextLevel(level + i);
                    if (upcoming == null) return const SizedBox.shrink();
                    final uc = SroodRoomLevelInfo.tierColor(upcoming.tier);
                    final isNext = i == 0;
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: SroodRoomDims.space8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  uc.withValues(alpha: isNext ? 0.30 : 0.12),
                                  uc.withValues(alpha: isNext ? 0.12 : 0.04),
                                ],
                              ),
                              border: Border.all(
                                color: uc.withValues(
                                  alpha: isNext ? 0.7 : 0.25,
                                ),
                                width: isNext ? 1.2 : 0.8,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${upcoming.level}',
                                style: TextStyle(
                                  fontSize: SroodRoomDims.textXs,
                                  fontWeight: FontWeight.w900,
                                  color: uc,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  upcoming.unlock,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isNext
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : Colors.white54,
                                  ),
                                ),
                                Text(
                                  '${_fmt(upcoming.xpRequired)} XP required · ${upcoming.tier}',
                                  style: TextStyle(
                                    fontSize: SroodRoomDims.textXs,
                                    color: uc.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isNext)
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 12,
                              color: uc.withValues(alpha: 0.5),
                            ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 22),

                  // ── Previous unlocks ─────────────────────────────────────
                  if (level > 1) ...[
                    Text(
                      'Unlocked',
                      style: TextStyle(
                        fontSize: SroodRoomDims.textMd,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.55),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(level - 1, (i) {
                      final d = SroodRoomLevelInfo.thresholds[i];
                      final uc = SroodRoomLevelInfo.tierColor(d.tier);
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: SroodRoomDims.space6,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: uc.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: SroodRoomDims.space8),
                            Text(
                              'LV ${d.level}: ${d.unlock}',
                              style: const TextStyle(
                                fontSize: SroodRoomDims.textSm,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const List<(IconData, String, Color)> _xpSources = [
    (
      Icons.card_giftcard_rounded,
      'Gifts: 1 coin = 1 XP (big gifts get +20–50% bonus)',
      Color(0xFFFFD700),
    ),
    (
      Icons.people_alt_rounded,
      'Active listeners: small XP every 5 min (capped daily)',
      Color(0xFF60A5FA),
    ),
    (
      Icons.access_time_rounded,
      'Hosting: XP while room is live with real users',
      Color(0xFF34D399),
    ),
    (
      Icons.sports_kabaddi_rounded,
      'PK battles: XP bonus for winning or close battles',
      Color(0xFFFF6B6B),
    ),
    (
      Icons.local_fire_department_rounded,
      'Daily streak: keeps room active for multiplier rewards',
      Color(0xFFFF9500),
    ),
    (
      Icons.event_rounded,
      'Events: admin-created XP boost periods (e.g. ×1.5)',
      Color(0xFFE879F9),
    ),
  ];
}

class _XpStatCard extends StatelessWidget {
  const _XpStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd + 2),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: SroodRoomDims.textXs,
                    color: color.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: SroodRoomDims.textLg,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
