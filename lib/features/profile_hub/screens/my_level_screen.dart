import 'dart:ui';
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

/// My Level — Charm (gifts received) and Wealth (gifts sent) tracks.
/// Both read from live server RPCs. No fake values.
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

  // Fixed: index 9 was '90-99' (wrong — level 90 is royal). Corrected to '91-99'.
  static const List<({String label, int badge, WealthTier tier})> _rows = [
    (label: '1–10',  badge: 10,  tier: WealthTier.bronze),
    (label: '11–20', badge: 20,  tier: WealthTier.silver),
    (label: '21–30', badge: 30,  tier: WealthTier.gold),
    (label: '31–40', badge: 40,  tier: WealthTier.emerald),
    (label: '41–50', badge: 50,  tier: WealthTier.sapphire),
    (label: '51–60', badge: 60,  tier: WealthTier.ruby),
    (label: '61–70', badge: 70,  tier: WealthTier.diamond),
    (label: '71–80', badge: 80,  tier: WealthTier.master),
    (label: '81–90', badge: 90,  tier: WealthTier.royal),
    (label: '91–99', badge: 99,  tier: WealthTier.legend),
    (label: '100',   badge: 100, tier: WealthTier.legend),
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
          // Tier-reactive radial background glow
          Positioned(
            top: 0, left: 0, right: 0,
            height: 340,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.6),
                  radius: 1.0,
                  colors: [
                    accent.withValues(alpha: isCharm ? 0.20 : 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 44),
              children: [
                _LuxuryTrackSwitch(
                  track: _track,
                  isArabic: isArabic,
                  onChanged: (t) => setState(() => _track = t),
                ),
                const SizedBox(height: 24),
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
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(17),
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
          duration: const Duration(milliseconds: 220),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.88),
                      color.withValues(alpha: 0.54),
                    ],
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 14,
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
                size: 15,
                color: selected
                    ? Colors.white
                    : color.withValues(alpha: 0.60),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.50),
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
        height: 170,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(28),
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
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFFF5C7A), size: 36),
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
          return _LevelErrorCard(
            isArabic: isArabic,
            onRetry: () {},
          );
        }
        final c = snap.data!;
        // Derive tier from level (never stored tier_number which can drift).
        final tier = WealthTier.fromLevel(c.charmLevel);
        final nextXp = c.xpToNextLevel != null
            ? c.charmXp + c.xpToNextLevel!
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LuxuryHeroCard(
              level: c.charmLevel,
              tier: tier,
              progress: c.levelProgress ?? 0,
              currentXp: c.charmXp,
              nextLevelXp: nextXp,
              isMax: c.isMaxLevel,
              isArabic: isArabic,
              accent: _accent,
              trackLabel: isArabic ? 'مستوى السحر' : 'CHARM LEVEL',
            ),
            const SizedBox(height: 20),
            _TierProgressPath(
              currentTierNumber: tier.number,
              isArabic: isArabic,
            ),
            const SizedBox(height: 20),
            _LuxuryDescriptionCard(
              icon: Icons.favorite_rounded,
              color: _accent,
              title: isArabic ? 'كيف يعمل السحر؟' : 'How does Charm work?',
              body: isArabic
                  ? 'عند استلام هدايا بقيمة 10 عملات ذهبية تحصل على نقطة خبرة سحر واحدة. كلما ارتفع مستواك، يتغيّر لون أيقونتك ويتجدد ألق حضورك.'
                  : 'Every 10 coins worth of gifts received earns 1 Charm XP. As your level rises, your badge colour upgrades and your presence becomes more radiant.',
            ),
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
          return _LevelErrorCard(
            isArabic: isArabic,
            onRetry: () {},
          );
        }
        final w = snap.data!;
        final tier = WealthTier.fromLevel(w.wealthLevel);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LuxuryHeroCard(
              level: w.wealthLevel,
              tier: tier,
              progress: w.levelProgress ?? 0,
              currentXp: w.wealthXp,
              nextLevelXp: w.nextLevelRequiredXp,
              isMax: w.isMaxLevel,
              isArabic: isArabic,
              accent: _accent,
              trackLabel: isArabic ? 'مستوى الثروة' : 'WEALTH LEVEL',
            ),
            const SizedBox(height: 20),
            _TierProgressPath(
              currentTierNumber: tier.number,
              isArabic: isArabic,
            ),
            const SizedBox(height: 20),
            _LuxuryDescriptionCard(
              icon: Icons.diamond_rounded,
              color: _accent,
              title: isArabic ? 'كيف تعمل الثروة؟' : 'How does Wealth work?',
              body: isArabic
                  ? 'عند إرسال هدايا بقيمة 10 عملات ذهبية تحصل على نقطة خبرة ثروة واحدة. كلما ارتفع مستواك، تُفتح أيقونات حصرية وتأثيرات دخول أكثر إبهاراً.'
                  : 'Every 10 coins worth of gifts sent earns 1 Wealth XP. As you level up, you unlock exclusive icons and increasingly spectacular entrance effects.',
            ),
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

// ── Luxury hero card ──────────────────────────────────────────────────────────

class _LuxuryHeroCard extends StatelessWidget {
  const _LuxuryHeroCard({
    required this.level,
    required this.tier,
    required this.progress,
    required this.currentXp,
    required this.nextLevelXp,
    required this.isMax,
    required this.isArabic,
    required this.accent,
    required this.trackLabel,
  });

  final int level;
  final WealthTier tier;
  final double progress;
  final int currentXp;
  final int? nextLevelXp;
  final bool isMax;
  final bool isArabic;
  final Color accent;
  final String trackLabel;

  @override
  Widget build(BuildContext context) {
    final c = tier.color;
    final clamped = progress.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                c.withValues(alpha: 0.26),
                const Color(0xFF07020E).withValues(alpha: 0.80),
              ],
            ),
            border: Border.all(
              color: c.withValues(alpha: 0.52),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: c.withValues(alpha: 0.30),
                blurRadius: 38,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tier emblem
                  _TierEmblem(tier: tier, size: 74),
                  const SizedBox(width: 18),
                  // Level text info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trackLabel,
                          style: TextStyle(
                            color: c.withValues(alpha: 0.75),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isArabic ? 'المستوى $level' : 'Level $level',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          tier.displayName.toUpperCase(),
                          style: TextStyle(
                            color: c,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Progress section
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isArabic ? 'نقاط الخبرة' : 'Experience',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.50),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        isMax
                            ? (isArabic ? '✦ أعلى مستوى' : '✦ Max Level')
                            : nextLevelXp != null
                                ? '${_fmt(currentXp)} / ${_fmt(nextLevelXp!)} XP'
                                : '${_fmt(currentXp)} XP',
                        style: TextStyle(
                          color: c,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  _LuxuryProgressBar(
                    progress: isMax ? 1.0 : clamped,
                    color: accent,
                    tierColor: c,
                  ),
                  const SizedBox(height: 8),
                  if (!isMax && nextLevelXp != null)
                    Align(
                      alignment: isArabic
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(
                        isArabic
                            ? '${_fmt(nextLevelXp! - currentXp)} XP للمستوى ${level + 1}'
                            : '${_fmt(nextLevelXp! - currentXp)} XP to Level ${level + 1}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Luxury progress bar ───────────────────────────────────────────────────────

class _LuxuryProgressBar extends StatelessWidget {
  const _LuxuryProgressBar({
    required this.progress,
    required this.color,
    required this.tierColor,
  });
  final double progress;
  final Color color;
  final Color tierColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final fillWidth =
            (constraints.maxWidth * progress).clamp(0.0, constraints.maxWidth);
        return Stack(
          children: [
            // Track
            Container(
              height: 11,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            // Fill
            AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              height: 11,
              width: fillWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [
                    _lighten(color, 0.38),
                    color,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.60),
                    blurRadius: 10,
                    spreadRadius: -1,
                  ),
                ],
              ),
            ),
            // Shimmer end-glow dot
            if (progress > 0.04)
              Positioned(
                left: (fillWidth - 5).clamp(0, constraints.maxWidth - 5),
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.85),
                      boxShadow: [
                        BoxShadow(
                          color: color,
                          blurRadius: 6,
                        ),
                      ],
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

// ── Tier emblem ───────────────────────────────────────────────────────────────

class _TierEmblem extends StatelessWidget {
  const _TierEmblem({required this.tier, required this.size});
  final WealthTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = tier.color;
    final light = _lighten(c, 0.50);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: c.withValues(alpha: 0.55),
                    blurRadius: size * 0.36,
                    spreadRadius: 1),
                BoxShadow(
                    color: c.withValues(alpha: 0.22),
                    blurRadius: size * 0.65,
                    spreadRadius: 4),
              ],
            ),
          ),
          // Outer metallic ring
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [light, c, Colors.white, c, light],
              ),
            ),
            padding: const EdgeInsets.all(2.5),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.45),
                  radius: 0.80,
                  colors: [
                    c.withValues(alpha: 0.30),
                    const Color(0xFF0C0715),
                  ],
                ),
                border: Border.all(
                  color: c.withValues(alpha: 0.55),
                  width: 1.2,
                ),
              ),
              child: Center(
                child: Text(
                  tier.icon,
                  style: TextStyle(fontSize: size * 0.40),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tier progress path (horizontal scroll) ────────────────────────────────────

class _TierProgressPath extends StatelessWidget {
  const _TierProgressPath({
    required this.currentTierNumber,
    required this.isArabic,
  });
  final int currentTierNumber;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isArabic ? 'مسار الترقي' : 'Tier Progression',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: WealthTier.values.length,
            separatorBuilder: (context, i) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final tier = WealthTier.values[i];
              final isCurrent = tier.number == currentTierNumber;
              final isUnlocked = tier.number <= currentTierNumber;
              return _TierMiniCard(
                tier: tier,
                isCurrent: isCurrent,
                isUnlocked: isUnlocked,
                isArabic: isArabic,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TierMiniCard extends StatelessWidget {
  const _TierMiniCard({
    required this.tier,
    required this.isCurrent,
    required this.isUnlocked,
    required this.isArabic,
  });
  final WealthTier tier;
  final bool isCurrent;
  final bool isUnlocked;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final c = tier.color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: isCurrent ? 92 : 82,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.withValues(
                alpha: isCurrent
                    ? 0.30
                    : isUnlocked
                        ? 0.15
                        : 0.06),
            Colors.black.withValues(alpha: 0.45),
          ],
        ),
        border: Border.all(
          color: isCurrent
              ? c.withValues(alpha: 0.88)
              : isUnlocked
                  ? c.withValues(alpha: 0.38)
                  : c.withValues(alpha: 0.14),
          width: isCurrent ? 1.8 : 1.0,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: c.withValues(alpha: 0.38),
                  blurRadius: 16,
                  spreadRadius: -1,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tier.icon,
              style: TextStyle(fontSize: isCurrent ? 26 : 22),
            ),
            const SizedBox(height: 6),
            Text(
              tier.displayName,
              style: TextStyle(
                color: isCurrent
                    ? c
                    : isUnlocked
                        ? c.withValues(alpha: 0.72)
                        : Colors.white.withValues(alpha: 0.28),
                fontSize: 10.5,
                fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${tier.minLevel}–${tier.maxLevel}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: isCurrent ? 0.60 : 0.30),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(height: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.withValues(alpha: 0.65)),
                ),
                child: Text(
                  isArabic ? 'أنت' : 'You',
                  style: TextStyle(
                    color: c,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Description card ──────────────────────────────────────────────────────────

class _LuxuryDescriptionCard extends StatelessWidget {
  const _LuxuryDescriptionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
              border: Border.all(
                  color: color.withValues(alpha: 0.48), width: 1.2),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.28), blurRadius: 8),
              ],
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 12.5,
                    height: 1.58,
                    fontWeight: FontWeight.w500,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Header
              Container(
                color: Colors.white.withValues(alpha: 0.05),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  textDirection:
                      isArabic ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        isArabic ? 'المستوى' : 'Level',
                        style: _hStyle,
                        textAlign:
                            isArabic ? TextAlign.right : TextAlign.left,
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
                Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.05)),
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

  static const _hStyle = TextStyle(
    color: Color(0xFF9E91B8),
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
  );
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
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
                            alpha: isUnlocked ? 0.82 : 0.35),
                    fontSize: 14,
                    fontWeight: isCurrent
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
                if (isCurrent)
                  Text(
                    isArabic ? '← أنت هنا' : 'You →',
                    style: TextStyle(
                      color: c,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: Opacity(
                opacity: isUnlocked ? 1.0 : 0.32,
                child: _TierLevelBadge(
                  number: row.badge,
                  tier: row.tier,
                  size: 40,
                ),
              ),
            ),
          ),
          if (showEntryEffect)
            Expanded(
              flex: 5,
              child: row.badge <= 10
                  ? Text(
                      '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.22),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    )
                  : _EntrancePreview(
                      tier: row.tier, isArabic: isArabic),
            ),
        ],
      ),
    );
  }
}

// ── Glossy tier badge capsule (original design, preserved) ───────────────────

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
            color: Colors.white.withValues(alpha: 0.65), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: c.withValues(alpha: 0.55), blurRadius: size * 0.30),
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
                    BoxShadow(
                        color: c.withValues(alpha: 0.7), blurRadius: 4),
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
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 2)
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Entrance effect preview (original design, preserved) ─────────────────────

class _EntrancePreview extends StatelessWidget {
  const _EntrancePreview({required this.tier, required this.isArabic});
  final WealthTier tier;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final c = tier.color;
    final light = _lighten(c, 0.5);

    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            c.withValues(alpha: 0.70),
            c.withValues(alpha: 0.28),
            c.withValues(alpha: 0.04),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border:
            Border.all(color: light.withValues(alpha: 0.7), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: c.withValues(alpha: 0.50), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [light, c, Colors.white, c, light],
              ),
              boxShadow: [
                BoxShadow(
                    color: c.withValues(alpha: 0.8), blurRadius: 6)
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
                size: 16,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              isArabic ? 'دخل المستخدم الغرفة' : 'User enters the room',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
              ),
            ),
          ),
          Icon(
            Icons.auto_awesome_rounded,
            size: 13,
            color: light.withValues(alpha: 0.9),
          ),
        ],
      ),
    );
  }
}
