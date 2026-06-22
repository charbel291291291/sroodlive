import 'package:flutter/material.dart';

import '../../wealth/models/wealth_models.dart';
import '../../wealth/services/wealth_service.dart';
import '../services/charm_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

/// "My level" — two official, independent tracks:
///   • Charm  — XP from gifts RECEIVED  (get_my_charm_level)
///   • Wealth — XP from gifts SENT       (get_my_wealth_level)
/// Both read real backend data; neither is mixed with VIP level/frames.
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

  @override
  void initState() {
    super.initState();
    _charmFuture = const CharmService().getMyCharm();
    _wealthFuture = const WealthService().getMyWealth();
  }

  // ── Table ranges (shared structure; per-track colour) ──────────────────────
  static const List<({String label, int badge, WealthTier tier})> _rows = [
    (label: '1-10',  badge: 10,  tier: WealthTier.bronze),
    (label: '11-20', badge: 20,  tier: WealthTier.silver),
    (label: '21-30', badge: 30,  tier: WealthTier.gold),
    (label: '31-40', badge: 40,  tier: WealthTier.emerald),
    (label: '41-50', badge: 50,  tier: WealthTier.sapphire),
    (label: '51-60', badge: 60,  tier: WealthTier.ruby),
    (label: '61-70', badge: 70,  tier: WealthTier.diamond),
    (label: '71-80', badge: 80,  tier: WealthTier.master),
    (label: '81-90', badge: 90,  tier: WealthTier.royal),
    (label: '90-99', badge: 99,  tier: WealthTier.legend),
    (label: '100',   badge: 100, tier: WealthTier.legend),
  ];

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    final charm = _track == _Track.charm;

    // Per-track premium background (purple for charm, gold/brown for wealth).
    final bg = charm
        ? const [Color(0xFF2A0E45), Color(0xFF12061F), Color(0xFF07030D)]
        : const [Color(0xFF3A2410), Color(0xFF1E1206), Color(0xFF0A0702)];

    return Scaffold(
      backgroundColor: const Color(0xFF07030D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          isArabic ? 'مستواي' : 'My level',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: bg,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _TrackSwitch(
                track: _track,
                isArabic: isArabic,
                onChanged: (t) => setState(() => _track = t),
              ),
              const SizedBox(height: 18),
              if (charm)
                _CharmSection(future: _charmFuture, rows: _rows, isArabic: isArabic)
              else
                _WealthSection(future: _wealthFuture, rows: _rows, isArabic: isArabic),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _LevelRow = ({String label, int badge, WealthTier tier});

// ── Segmented Charm / Wealth switch ──────────────────────────────────────────
class _TrackSwitch extends StatelessWidget {
  const _TrackSwitch({
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: selected
                ? LinearGradient(colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.55)])
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : color.withValues(alpha: 0.8)),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Charm section ────────────────────────────────────────────────────────────
class _CharmSection extends StatelessWidget {
  const _CharmSection({
    required this.future,
    required this.rows,
    required this.isArabic,
  });
  final Future<UserCharm> future;
  final List<_LevelRow> rows;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<UserCharm>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const _CurrentLevelSkeleton();
            }
            if (!snap.hasData) return const SizedBox.shrink();
            final c = snap.data!;
            return _CurrentLevelCard(
              level: c.charmLevel,
              tier: WealthTier.fromNumber(c.tierNumber),
              progress: c.levelProgress ?? 0,
              isMax: c.isMaxLevel,
              isArabic: isArabic,
              accent: const Color(0xFFFF4ECD),
            );
          },
        ),
        const SizedBox(height: 22),
        _DescriptionBlock(
          title: isArabic ? 'وصف مستوى السحر' : 'Charm level description',
          body: isArabic
              ? 'عند استلام هدايا بقيمة 10 عملات ذهبية تحصل على نقطة خبرة سحر واحدة. كلما ارتفع مستواك، يتغيّر لون أيقونة مستواك تبعاً لذلك.'
              : 'When you receive 10 gold coin gifts, you gain 1 charm experience point. As your level upgrades, the colour of your level icon changes accordingly.',
        ),
        const SizedBox(height: 16),
        _LevelTable(
          rows: rows,
          isArabic: isArabic,
          showEntryEffect: false,
        ),
      ],
    );
  }
}

// ── Wealth section ───────────────────────────────────────────────────────────
class _WealthSection extends StatelessWidget {
  const _WealthSection({
    required this.future,
    required this.rows,
    required this.isArabic,
  });
  final Future<UserWealth> future;
  final List<_LevelRow> rows;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<UserWealth>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const _CurrentLevelSkeleton();
            }
            if (!snap.hasData) return const SizedBox.shrink();
            final w = snap.data!;
            return _CurrentLevelCard(
              level: w.wealthLevel,
              tier: w.tier,
              progress: w.levelProgress ?? 0,
              isMax: w.isMaxLevel,
              isArabic: isArabic,
              accent: const Color(0xFFF0C15A),
            );
          },
        ),
        const SizedBox(height: 22),
        _DescriptionBlock(
          title: isArabic ? 'وصف مستوى الثروة' : 'Wealth level description',
          body: isArabic
              ? 'عند إرسال هدايا بقيمة 10 عملات ذهبية تحصل على نقطة خبرة ثروة واحدة. كلما ارتفع مستواك، تفتح أيقونات حصرية أكثر وتأثيرات دخول أكثر إبهاراً.'
              : 'When you send 10 gold coin gifts, you gain 1 wealth experience point. As you level up, you unlock more exclusive icons and more impressive entrance effects.',
        ),
        const SizedBox(height: 16),
        _LevelTable(
          rows: rows,
          isArabic: isArabic,
          showEntryEffect: true,
        ),
      ],
    );
  }
}

// ── Current level header card (real data) ────────────────────────────────────
class _CurrentLevelCard extends StatelessWidget {
  const _CurrentLevelCard({
    required this.level,
    required this.tier,
    required this.progress,
    required this.isMax,
    required this.isArabic,
    required this.accent,
  });
  final int level;
  final WealthTier tier;
  final double progress;
  final bool isMax;
  final bool isArabic;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tier.color.withValues(alpha: 0.22), Colors.black.withValues(alpha: 0.30)],
        ),
        border: Border.all(color: tier.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          _TierLevelBadge(number: level, tier: tier, size: 58),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isArabic ? 'المستوى' : 'Level'} $level · ${tier.displayName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: isMax ? 1.0 : progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isMax
                      ? (isArabic ? 'أعلى مستوى' : 'Max level reached')
                      : (isArabic
                          ? 'التقدم ${(progress.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%'
                          : '${(progress.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}% to next level'),
                  style: const TextStyle(
                    color: Color(0xFFBCAED6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _CurrentLevelSkeleton extends StatelessWidget {
  const _CurrentLevelSkeleton();
  @override
  Widget build(BuildContext context) => Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.black.withValues(alpha: 0.25),
        ),
        child: const Center(
          child: SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFFF0C15A)),
          ),
        ),
      );
}

// ── Description block (centered) ─────────────────────────────────────────────
class _DescriptionBlock extends StatelessWidget {
  const _DescriptionBlock({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFCBBEE6),
            fontSize: 13.5,
            height: 1.55,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Level table ──────────────────────────────────────────────────────────────
class _LevelTable extends StatelessWidget {
  const _LevelTable({
    required this.rows,
    required this.isArabic,
    required this.showEntryEffect,
  });
  final List<_LevelRow> rows;
  final bool isArabic;
  final bool showEntryEffect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            color: Colors.white.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(isArabic ? 'المستوى' : 'Level',
                      style: _hStyle),
                ),
                Expanded(
                  flex: 3,
                  child: Text(isArabic ? 'الأيقونة' : 'Level icon',
                      style: _hStyle, textAlign: TextAlign.center),
                ),
                if (showEntryEffect)
                  Expanded(
                    flex: 5,
                    child: Text(isArabic ? 'تأثير الدخول' : 'Entry Effect',
                        style: _hStyle, textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            Container(
              color: i.isEven
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.03),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      rows[i].label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: _TierLevelBadge(
                        number: rows[i].badge,
                        tier: rows[i].tier,
                        size: 40,
                      ),
                    ),
                  ),
                  if (showEntryEffect)
                    Expanded(
                      flex: 5,
                      child: rows[i].badge <= 10
                          ? const Text('--',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Color(0xFF9C8FCB),
                                  fontWeight: FontWeight.w800))
                          : _EntrancePreview(
                              tier: rows[i].tier, isArabic: isArabic),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const _hStyle = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.w900,
  );
}

// ── Glossy tier level badge (programmatic, original) ─────────────────────────
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
    final light = Color.lerp(c, Colors.white, 0.55)!;
    final dark = Color.lerp(c, Colors.black, 0.42)!;

    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size * 1.55),
      padding: EdgeInsets.fromLTRB(size * 0.12, 0, size * 0.26, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        // Glossy tier capsule.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, c, dark],
          stops: const [0.0, 0.5, 1.0],
        ),
        // Metallic double rim.
        border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 1.2),
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
          // Top gloss highlight.
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
              // Metallic gem disc (per-tier color).
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

// ── Entrance effect preview (programmatic, original) ─────────────────────────
class _EntrancePreview extends StatelessWidget {
  const _EntrancePreview({required this.tier, required this.isArabic});
  final WealthTier tier;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final c = tier.color;
    final light = Color.lerp(c, Colors.white, 0.5)!;
    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        // Glowing horizontal banner that fades to the right.
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
        border: Border.all(color: light.withValues(alpha: 0.7), width: 1.2),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 10)],
      ),
      child: Row(
        children: [
          // Circular avatar slot with a shiny double frame ring.
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [light, c, Colors.white, c, light],
              ),
              boxShadow: [BoxShadow(color: c.withValues(alpha: 0.8), blurRadius: 6)],
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
              child: Icon(Icons.person_rounded,
                  size: 16, color: Colors.white.withValues(alpha: 0.9)),
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
          Icon(Icons.auto_awesome_rounded,
              size: 13, color: light.withValues(alpha: 0.9)),
        ],
      ),
    );
  }
}
