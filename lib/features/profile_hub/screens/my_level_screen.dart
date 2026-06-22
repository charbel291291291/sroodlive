import 'package:flutter/material.dart';

import '../../wealth/models/wealth_models.dart';
import '../../wealth/services/wealth_service.dart';
import '../services/charm_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

// ── XP formatter ─────────────────────────────────────────────────────────────
String _fmt(int v) {
  if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}B';
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return '$v';
}

Color _lighten(Color c, [double t = 0.45]) => Color.lerp(c, Colors.white, t)!;
Color _darken(Color c, [double t = 0.42]) => Color.lerp(c, Colors.black, t)!;

// ── Screen ────────────────────────────────────────────────────────────────────
class MyLevelScreen extends StatefulWidget {
  const MyLevelScreen({required this.isArabic, super.key});
  final bool isArabic;
  @override
  State<MyLevelScreen> createState() => _MyLevelScreenState();
}

enum _Track { charm, wealth }

class _MyLevelScreenState extends State<MyLevelScreen> {
  _Track _track = _Track.charm;
  late Future<UserCharm> _charmFuture;
  late Future<UserWealth> _wealthFuture;

  // Level range rows — index 9 fixed: '91–99' (level 90 belongs to royal tier).
  static const List<({String label, int badge, WealthTier tier})> _rows = [
    (label: '1–10', badge: 10, tier: WealthTier.bronze),
    (label: '11–20', badge: 20, tier: WealthTier.silver),
    (label: '21–30', badge: 30, tier: WealthTier.gold),
    (label: '31–40', badge: 40, tier: WealthTier.emerald),
    (label: '41–50', badge: 50, tier: WealthTier.sapphire),
    (label: '51–60', badge: 60, tier: WealthTier.ruby),
    (label: '61–70', badge: 70, tier: WealthTier.diamond),
    (label: '71–80', badge: 80, tier: WealthTier.master),
    (label: '81–90', badge: 90, tier: WealthTier.royal),
    (label: '91–99', badge: 99, tier: WealthTier.legend),
    (label: '100', badge: 100, tier: WealthTier.legend),
  ];

  @override
  void initState() {
    super.initState();
    _charmFuture = const CharmService().getMyCharm();
    _wealthFuture = const WealthService().getMyWealth();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    final isCharm = _track == _Track.charm;
    final accent = isCharm ? const Color(0xFFFF4ECD) : const Color(0xFFF0C15A);

    return Scaffold(
      backgroundColor: const Color(0xFF06020C),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            isArabic
                ? Icons.arrow_forward_ios_rounded
                : Icons.arrow_back_ios_rounded,
            color: accent,
            size: 20,
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          isArabic ? 'مستواي' : 'My Level',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: 0.4,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background radial glow — reactive to track accent colour.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 380),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.5),
                  radius: 1.0,
                  colors: [accent.withValues(alpha: 0.18), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 48),
              children: [
                _LuxuryTrackSwitch(
                  track: _track,
                  isArabic: isArabic,
                  onChanged: (t) => setState(() => _track = t),
                ),
                const SizedBox(height: 20),
                if (isCharm)
                  _CharmSection(
                    future: _charmFuture,
                    rows: _rows,
                    isArabic: isArabic,
                  )
                else
                  _WealthSection(
                    future: _wealthFuture,
                    rows: _rows,
                    isArabic: isArabic,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _LevelRow = ({String label, int badge, WealthTier tier});

// ── Track switch ──────────────────────────────────────────────────────────────
class _LuxuryTrackSwitch extends StatelessWidget {
  const _LuxuryTrackSwitch({
    required this.track,
    required this.isArabic,
    required this.onChanged,
  });
  final _Track track;
  final bool isArabic;
  final ValueChanged<_Track> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          _seg(
            label: isArabic ? 'السحر' : 'Charm',
            icon: Icons.favorite_rounded,
            selected: track == _Track.charm,
            color: const Color(0xFFFF4ECD),
            onTap: () => onChanged(_Track.charm),
          ),
          _seg(
            label: isArabic ? 'الثروة' : 'Wealth',
            icon: Icons.diamond_rounded,
            selected: track == _Track.wealth,
            color: const Color(0xFFF0C15A),
            onTap: () => onChanged(_Track.wealth),
          ),
        ],
      ),
    );
  }

  Widget _seg({
    required String label,
    required IconData icon,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.85),
                      color.withValues(alpha: 0.52),
                    ],
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.30),
                      blurRadius: 12,
                      spreadRadius: -1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : color.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.48),
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Loading / Error states ────────────────────────────────────────────────────
class _LevelLoadingCard extends StatelessWidget {
  const _LevelLoadingCard();
  @override
  Widget build(BuildContext context) => Container(
    height: 160,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: const Center(
      child: CircularProgressIndicator(
        color: Color(0xFFF0C15A),
        strokeWidth: 2.2,
      ),
    ),
  );
}

class _LevelErrorCard extends StatelessWidget {
  const _LevelErrorCard({required this.isArabic, required this.onRetry});
  final bool isArabic;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF5C7A),
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            isArabic ? 'تعذّر تحميل البيانات' : 'Could not load data',
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onRetry,
            child: Text(
              isArabic ? 'إعادة المحاولة' : 'Retry',
              style: const TextStyle(color: Color(0xFFF0C15A)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Charm section ─────────────────────────────────────────────────────────────
class _CharmSection extends StatelessWidget {
  const _CharmSection({
    required this.future,
    required this.rows,
    required this.isArabic,
  });
  final Future<UserCharm> future;
  final List<_LevelRow> rows;
  final bool isArabic;

  static const _accent = Color(0xFFFF4ECD);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserCharm>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LevelLoadingCard();
        }
        if (snap.hasError || !snap.hasData) {
          return _LevelErrorCard(isArabic: isArabic, onRetry: () {});
        }
        final c = snap.data!;
        // Derive tier from level — never use stored tier_number (can drift).
        final tier = WealthTier.fromLevel(c.charmLevel);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LevelHeroCard(
              level: c.charmLevel,
              tier: tier,
              progress: c.levelProgress ?? 0,
              xpToNextLevel: c.xpToNextLevel,
              isMax: c.isMaxLevel,
              isArabic: isArabic,
              accent: _accent,
              isCharm: true,
            ),
            const SizedBox(height: 20),
            _LevelDescriptionCard(isArabic: isArabic, isCharm: true),
            const SizedBox(height: 20),
            _LuxuryLevelTable(
              rows: rows,
              currentTierNumber: tier.number,
              isArabic: isArabic,
              showEntryEffect: false,
            ),
          ],
        );
      },
    );
  }
}

// ── Wealth section ────────────────────────────────────────────────────────────
class _WealthSection extends StatelessWidget {
  const _WealthSection({
    required this.future,
    required this.rows,
    required this.isArabic,
  });
  final Future<UserWealth> future;
  final List<_LevelRow> rows;
  final bool isArabic;

  static const _accent = Color(0xFFF0C15A);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserWealth>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LevelLoadingCard();
        }
        if (snap.hasError || !snap.hasData) {
          return _LevelErrorCard(isArabic: isArabic, onRetry: () {});
        }
        final w = snap.data!;
        final tier = WealthTier.fromLevel(w.wealthLevel);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LevelHeroCard(
              level: w.wealthLevel,
              tier: tier,
              progress: w.levelProgress ?? 0,
              xpToNextLevel: w.xpToNextLevel,
              isMax: w.isMaxLevel,
              isArabic: isArabic,
              accent: _accent,
              isCharm: false,
            ),
            const SizedBox(height: 20),
            _LevelDescriptionCard(isArabic: isArabic, isCharm: false),
            const SizedBox(height: 20),
            _LuxuryLevelTable(
              rows: rows,
              currentTierNumber: tier.number,
              isArabic: isArabic,
              showEntryEffect: true,
            ),
          ],
        );
      },
    );
  }
}

// ── Level hero card (reference style) ────────────────────────────────────────
class _LevelHeroCard extends StatelessWidget {
  const _LevelHeroCard({
    required this.level,
    required this.tier,
    required this.progress,
    required this.xpToNextLevel,
    required this.isMax,
    required this.isArabic,
    required this.accent,
    required this.isCharm,
  });

  final int level;
  final WealthTier tier;
  final double progress;
  final int? xpToNextLevel; // delta XP to next level
  final bool isMax;
  final bool isArabic;
  final Color accent;
  final bool isCharm;

  @override
  Widget build(BuildContext context) {
    final c = tier.color;
    final clamped = progress.clamp(0.0, 1.0);
    final nextLevel = isMax ? level : level + 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _darken(c, 0.60).withValues(alpha: 0.98),
            const Color(0xFF0C0612),
          ],
        ),
        border: Border.all(color: c.withValues(alpha: 0.48), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: c.withValues(alpha: 0.26),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row: tier icon / labels + journey dots ─────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Tier icon circle
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.withValues(alpha: 0.18),
                  border: Border.all(
                    color: c.withValues(alpha: 0.55),
                    width: 1.3,
                  ),
                  boxShadow: [
                    BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 8),
                  ],
                ),
                child: Center(
                  child: Text(tier.icon, style: const TextStyle(fontSize: 19)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isCharm
                          ? (isArabic ? 'مستوى السحر' : 'Charm Level')
                          : (isArabic ? 'مستوى الثروة' : 'Wealth Level'),
                      style: TextStyle(
                        color: c.withValues(alpha: 0.72),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      tier.displayName.toUpperCase(),
                      style: TextStyle(
                        color: c,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
              // Compact 10-dot tier journey — max ~160px wide, never overflows.
              _TierJourneyDots(currentTierNumber: tier.number),
            ],
          ),

          const SizedBox(height: 14),

          // ── Large level number ─────────────────────────────────────────────
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: isArabic ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              isArabic ? 'المستوى $level' : 'Level $level',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 46,
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: -0.5,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── LV labels ─────────────────────────────────────────────────────
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _LvLabel(label: 'LV $level', color: c),
              _LvLabel(
                label: isMax ? '—' : 'LV $nextLevel',
                color: Colors.white.withValues(alpha: 0.38),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Progress bar ───────────────────────────────────────────────────
          _LuxuryProgressBar(progress: isMax ? 1.0 : clamped, color: accent),
          const SizedBox(height: 10),

          // ── "Need X Exp to upgrade" ────────────────────────────────────────
          Center(
            child: Text(
              isMax
                  ? (isArabic ? '✦ وصلت إلى أعلى مستوى' : '✦ Max level reached')
                  : xpToNextLevel != null
                  ? (isArabic
                        ? 'تحتاج ${_fmt(xpToNextLevel!)} خبرة للترقية'
                        : 'Need ${_fmt(xpToNextLevel!)} Exp to upgrade')
                  : '',
              style: TextStyle(
                color: isMax ? c : Colors.white.withValues(alpha: 0.62),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Tiny "LV X" label used in the hero card.
class _LvLabel extends StatelessWidget {
  const _LvLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    );
  }
}

// ── Compact tier journey dots ─────────────────────────────────────────────────
// 10 pill segments; current is wider. Total width ≤ 160px on any device.
class _TierJourneyDots extends StatelessWidget {
  const _TierJourneyDots({required this.currentTierNumber});
  final int currentTierNumber;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(10, (i) {
        final tierNum = i + 1;
        final tier = WealthTier.fromNumber(tierNum);
        final isCurrent = tierNum == currentTierNumber;
        final isUnlocked = tierNum <= currentTierNumber;
        final c = tier.color;

        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: isCurrent ? 16 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: isCurrent
                  ? c
                  : isUnlocked
                  ? c.withValues(alpha: 0.50)
                  : Colors.white.withValues(alpha: 0.10),
              boxShadow: isCurrent
                  ? [BoxShadow(color: c.withValues(alpha: 0.65), blurRadius: 6)]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}

// ── Progress bar ──────────────────────────────────────────────────────────────
class _LuxuryProgressBar extends StatelessWidget {
  const _LuxuryProgressBar({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final fillWidth = (constraints.maxWidth * progress).clamp(
          0.0,
          constraints.maxWidth,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Track
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.40),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            // Fill
            AnimatedContainer(
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOut,
              height: 10,
              width: fillWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [_lighten(color, 0.35), color],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: -1,
                  ),
                ],
              ),
            ),
            // End-glow dot
            if (progress > 0.04)
              Positioned(
                left: (fillWidth - 5).clamp(0.0, constraints.maxWidth - 5),
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.85),
                      boxShadow: [BoxShadow(color: color, blurRadius: 6)],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Level description card ────────────────────────────────────────────────────
class _LevelDescriptionCard extends StatelessWidget {
  const _LevelDescriptionCard({required this.isArabic, required this.isCharm});
  final bool isArabic;
  final bool isCharm;

  @override
  Widget build(BuildContext context) {
    final color = isCharm ? const Color(0xFFFF4ECD) : const Color(0xFFF0C15A);
    final title = isArabic ? 'وصف المستوى' : 'Level description';
    final desc = isCharm
        ? (isArabic
              ? 'استلام هدايا العملات الذهبية يزيد من خبرة مستوى السحر.'
              : 'Receiving gold coin gifts increases Charm Level EXP.')
        : (isArabic
              ? 'إرسال هدايا العملات الذهبية يزيد من خبرة مستوى الثروة.'
              : 'Sending gold coin gifts increases Wealth Level EXP.');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section title
          Row(
            children: [
              Icon(
                isCharm ? Icons.favorite_rounded : Icons.diamond_rounded,
                color: color,
                size: 15,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            desc,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          _RuleRow(
            isArabic: isArabic,
            label: isArabic ? 'هدايا عادية:' : 'Non-Lucky Gifts:',
            value: isArabic ? '1 عملة = 1 خبرة' : '1 coin = 1 EXP',
            color: color,
          ),
          const SizedBox(height: 6),
          _RuleRow(
            isArabic: isArabic,
            label: isArabic ? 'هدايا محظوظة:' : 'Lucky Gifts:',
            value: isArabic ? '1 عملة = 0.1 خبرة' : '1 coin = 0.1 EXP',
            color: color,
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.isArabic,
    required this.label,
    required this.value,
    required this.color,
  });
  final bool isArabic;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.70),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.52),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ── Level table ───────────────────────────────────────────────────────────────
class _LuxuryLevelTable extends StatelessWidget {
  const _LuxuryLevelTable({
    required this.rows,
    required this.currentTierNumber,
    required this.isArabic,
    required this.showEntryEffect,
  });
  final List<_LevelRow> rows;
  final int currentTierNumber;
  final bool isArabic;
  final bool showEntryEffect;

  static const _hStyle = TextStyle(
    color: Color(0xFF9E91B8),
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isArabic ? 'جدول المستويات' : 'Level Table',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                color: Colors.white.withValues(alpha: 0.05),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        isArabic ? 'المستوى' : 'Level',
                        style: _hStyle,
                        textAlign: isArabic ? TextAlign.right : TextAlign.left,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        isArabic ? 'الأيقونة' : 'Badge',
                        style: _hStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (showEntryEffect)
                      Expanded(
                        flex: 5,
                        child: Text(
                          isArabic ? 'تأثير الدخول' : 'Entry Effect',
                          style: _hStyle,
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              for (var i = 0; i < rows.length; i++) ...[
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
                _LevelTableRow(
                  row: rows[i],
                  isCurrent: rows[i].tier.number == currentTierNumber,
                  isUnlocked: rows[i].tier.number <= currentTierNumber,
                  isArabic: isArabic,
                  showEntryEffect: showEntryEffect,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LevelTableRow extends StatelessWidget {
  const _LevelTableRow({
    required this.row,
    required this.isCurrent,
    required this.isUnlocked,
    required this.isArabic,
    required this.showEntryEffect,
  });
  final _LevelRow row;
  final bool isCurrent;
  final bool isUnlocked;
  final bool isArabic;
  final bool showEntryEffect;

  @override
  Widget build(BuildContext context) {
    final c = row.tier.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      color: isCurrent ? c.withValues(alpha: 0.10) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          // Level range
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.label,
                  style: TextStyle(
                    color: isCurrent
                        ? Colors.white
                        : Colors.white.withValues(
                            alpha: isUnlocked ? 0.80 : 0.32,
                          ),
                    fontSize: 13.5,
                    fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                if (isCurrent)
                  Text(
                    isArabic ? '← أنت هنا' : 'You →',
                    style: TextStyle(
                      color: c,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
          // Badge
          Expanded(
            flex: 3,
            child: Center(
              child: Opacity(
                opacity: isUnlocked ? 1.0 : 0.30,
                child: _TierLevelBadge(
                  number: row.badge,
                  tier: row.tier,
                  size: 38,
                ),
              ),
            ),
          ),
          // Entry effect
          if (showEntryEffect)
            Expanded(
              flex: 5,
              child: row.badge <= 10
                  ? Text(
                      '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.20),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    )
                  : _EntrancePreview(tier: row.tier, isArabic: isArabic),
            ),
        ],
      ),
    );
  }
}

// ── Glossy tier badge capsule ─────────────────────────────────────────────────
class _TierLevelBadge extends StatelessWidget {
  const _TierLevelBadge({
    required this.number,
    required this.tier,
    required this.size,
  });
  final int number;
  final WealthTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = tier.color;
    final light = _lighten(c, 0.55);
    final dark = _darken(c, 0.42);

    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size * 1.55),
      padding: EdgeInsets.fromLTRB(size * 0.12, 0, size * 0.26, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, c, dark],
          stops: const [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.65),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.55), blurRadius: size * 0.30),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: size * 0.12,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Shine highlight
          Positioned(
            top: size * 0.06,
            left: size * 0.18,
            right: size * 0.18,
            child: Container(
              height: size * 0.28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.55),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: size * 0.62,
                height: size * 0.62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.white, light, dark],
                    stops: const [0.0, 0.45, 1.0],
                    center: const Alignment(-0.3, -0.4),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 4),
                  ],
                ),
              ),
              SizedBox(width: size * 0.12),
              Text(
                '$number',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.42,
                  height: 1.0,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 2)],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Entrance effect preview ───────────────────────────────────────────────────
class _EntrancePreview extends StatelessWidget {
  const _EntrancePreview({required this.tier, required this.isArabic});
  final WealthTier tier;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final c = tier.color;
    final light = _lighten(c, 0.5);

    return Container(
      height: 40,
      padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            c.withValues(alpha: 0.68),
            c.withValues(alpha: 0.26),
            c.withValues(alpha: 0.04),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: light.withValues(alpha: 0.65), width: 1.1),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [light, c, Colors.white, c, light],
              ),
              boxShadow: [
                BoxShadow(color: c.withValues(alpha: 0.8), blurRadius: 6),
              ],
            ),
            padding: const EdgeInsets.all(2.5),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.person_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isArabic ? 'دخل المستخدم الغرفة' : 'User enters the room',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
              ),
            ),
          ),
          Icon(
            Icons.auto_awesome_rounded,
            size: 11,
            color: light.withValues(alpha: 0.85),
          ),
        ],
      ),
    );
  }
}
