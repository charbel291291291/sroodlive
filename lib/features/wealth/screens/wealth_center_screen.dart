import 'package:flutter/material.dart';
import '../models/wealth_models.dart';
import '../services/wealth_service.dart';
import '../../profile_hub/services/charm_service.dart';

/// Luxury "My Level" screen.
///
/// Tabs:
///   - Contribution -> our REAL Wealth system (get_my_wealth_level). Wealth is
///     supporter/spender prestige = "contribution".
///   - Charisma     -> received-support prestige. Backend not built yet, so the
///     tab is shown but renders a placeholder (no fake values).
///
/// Server stays authoritative: the screen only reads the existing wealth
/// service/model. Hidden backend values are never displayed.
class WealthCenterScreen extends StatefulWidget {
  const WealthCenterScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<WealthCenterScreen> createState() => _WealthCenterScreenState();
}

class _WealthCenterScreenState extends State<WealthCenterScreen> {
  static const _service = WealthService();
  static const _charmService = CharmService();

  UserWealth? _wealth;
  bool _loading = true;
  late final Future<UserCharm> _charmFuture = _charmService.getMyCharm();

  // 0 = Charisma (placeholder), 1 = Contribution (real Wealth data).
  // Default to Contribution so the real data shows first.
  int _tab = 1;

  // Current tier derived from the REAL wealth level (never the stored
  // tier_number, which can drift). Falls back to level 1 only when there is no
  // data at all.
  WealthTier get _currentTier =>
      WealthTier.fromLevel((_wealth ?? UserWealth.empty).wealthLevel);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Degrade gracefully to a safe default if the wealth RPC/table is missing
    // (schema drift / undeployed migration) instead of failing the screen.
    UserWealth wealth;
    try {
      wealth = await _service.getMyWealth();
    } catch (e) {
      debugPrint('[WealthCenter] getMyWealth failed, using default: $e');
      wealth = UserWealth.empty; // Wealth Level 1 / Bronze
    }
    if (!mounted) return;
    setState(() {
      _wealth = wealth;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.isArabic;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0705),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              // Top glow derives from the user's actual tier color so that
              // Diamond, Royal, Legend users don't always see bronze tones.
              Color.lerp(_currentTier.color, Colors.black, 0.68)!,
              Color.lerp(_currentTier.color, Colors.black, 0.88)!,
              const Color(0xFF0A0705),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(ar),
              _LevelTabs(
                isArabic: ar,
                selected: _tab,
                onTap: (i) {
                  if (_tab != i) setState(() => _tab = i);
                },
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFF0C15A),
                          strokeWidth: 2.5,
                        ),
                      )
                    : _tab == 0
                    ? _buildCharisma(ar)
                    : _buildContribution(ar),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool ar) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: Color(0xFFF0C15A),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              ar ? 'مستواي' : 'My Level',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                shadows: [Shadow(color: Color(0x88F0C15A), blurRadius: 16)],
              ),
            ),
          ),
          const SizedBox(width: 48), // balances the back button
        ],
      ),
    );
  }

  // ── Contribution (real Wealth) ──────────────────────────────────────────────

  Widget _buildContribution(bool ar) {
    final w = _wealth ?? UserWealth.empty;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        children: [
          _LevelHeroCard(wealth: w, tier: _currentTier, isArabic: ar),
          const SizedBox(height: 18),
          _LevelRangeTable(
            currentTierNumber: _currentTier.number,
            isArabic: ar,
          ),
        ],
      ),
    );
  }

  // ── Charisma (real data from CharmService) ──────────────────────────────────

  Widget _buildCharisma(bool ar) {
    return FutureBuilder<UserCharm>(
      future: _charmFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFF4ECD),
              strokeWidth: 2.5,
            ),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
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
                    ar
                        ? 'تعذّر تحميل بيانات السحر'
                        : 'Could not load charm data',
                    style: const TextStyle(
                      color: Color(0xFFD8CFEA),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final c = snap.data!;
        // Derive tier from level to avoid stored-value drift.
        final tier = WealthTier.fromLevel(c.charmLevel);
        final progress = (c.levelProgress ?? 0).clamp(0.0, 1.0);
        final nextXp = c.xpToNextLevel != null
            ? c.charmXp + c.xpToNextLevel!
            : null;

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            children: [
              // Charm hero card (reuses the gold style but with pink accent)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                padding: const EdgeInsets.fromLTRB(16, 16, 18, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _lighten(tier.color, 0.35),
                      tier.color,
                      _darken(tier.color, 0.35),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: _lighten(tier.color, 0.55),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tier.color.withValues(alpha: 0.40),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _LaurelAvatar(tier: tier, level: c.charmLevel),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lv. ${c.charmLevel}',
                            style: const TextStyle(
                              color: Color(0xFF2D0A1A),
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: c.isMaxLevel ? 1.0 : progress,
                              minHeight: 9,
                              backgroundColor: const Color(0x33000000),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF8B26D9),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            c.isMaxLevel
                                ? (ar ? 'أعلى مستوى' : 'MAX LEVEL')
                                : nextXp != null
                                ? 'EXP ${_fmt(c.charmXp)}/${_fmt(nextXp)}'
                                : 'EXP ${_fmt(c.charmXp)}',
                            style: const TextStyle(
                              color: Color(0xFF5A1A3A),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _LevelRangeTable(currentTierNumber: tier.number, isArabic: ar),
            ],
          ),
        );
      },
    );
  }
}

// ── Tabs ──────────────────────────────────────────────────────────────────────

class _LevelTabs extends StatelessWidget {
  const _LevelTabs({
    required this.isArabic,
    required this.selected,
    required this.onTap,
  });

  final bool isArabic;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
      child: Row(
        children: [
          _tab(isArabic ? 'الجاذبية' : 'Charisma', 0),
          _tab(isArabic ? 'المساهمة' : 'Contribution', 1),
        ],
      ),
    );
  }

  Widget _tab(String label, int index) {
    final on = selected == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: on
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                  fontWeight: on ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: on ? 36 : 0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFE9A8), Color(0xFFE3B25E)],
                ),
                boxShadow: on
                    ? const [
                        BoxShadow(color: Color(0xAAF0C15A), blurRadius: 10),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero card ───────────────────────────────────────────────────────────────

class _LevelHeroCard extends StatelessWidget {
  const _LevelHeroCard({
    required this.wealth,
    required this.tier,
    required this.isArabic,
  });

  final UserWealth wealth;
  final WealthTier tier;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final progress = (wealth.levelProgress ?? 0).clamp(0.0, 1.0);
    final isMax = wealth.isMaxLevel;
    final nextXp = wealth.nextLevelRequiredXp ?? wealth.wealthXp;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6E2AE), Color(0xFFE6B968), Color(0xFFCB9540)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFF0C8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE3B25E).withValues(alpha: 0.4),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _LaurelAvatar(tier: tier, level: wealth.wealthLevel),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lv. ${wealth.wealthLevel}',
                  style: const TextStyle(
                    color: Color(0xFF6B4A14),
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: isMax ? 1.0 : progress,
                    minHeight: 9,
                    backgroundColor: const Color(0x33000000),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF9A00),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isMax
                      ? (isArabic ? 'أعلى مستوى' : 'MAX LEVEL')
                      : 'EXP ${_fmt(wealth.wealthXp)}/${_fmt(nextXp)}',
                  style: const TextStyle(
                    color: Color(0xFF7A5A24),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

// Avatar inside a gold laurel ring with a level badge under it.
class _LaurelAvatar extends StatelessWidget {
  const _LaurelAvatar({required this.tier, required this.level});
  final WealthTier tier;
  final int level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 96,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Gold laurel ring.
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF1C4), Color(0xFFD9A84E)],
              ),
              boxShadow: [BoxShadow(color: Color(0x66FFFFFF), blurRadius: 8)],
            ),
            padding: const EdgeInsets.all(4),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A1208),
                border: Border.all(
                  color: tier.color.withValues(alpha: 0.7),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(tier.icon, style: const TextStyle(fontSize: 30)),
              ),
            ),
          ),
          // Level badge under the avatar.
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _lighten(tier.color, 0.25),
                    _darken(tier.color, 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0xFFFFF0C8), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: tier.color.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shield, color: Colors.white, size: 11),
                  const SizedBox(width: 3),
                  Text(
                    '$level',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Level range table ─────────────────────────────────────────────────────────

class _LevelRangeTable extends StatelessWidget {
  const _LevelRangeTable({
    required this.currentTierNumber,
    required this.isArabic,
  });

  final int currentTierNumber;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final tiers = WealthTier.values;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          // Column headers.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isArabic ? 'نطاق المستوى' : 'Level Range',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  isArabic ? 'حد المستوى' : 'Tier Cap',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < tiers.length; i++)
            _LevelRangeRow(
              tier: tiers[i],
              isCurrent: tiers[i].number == currentTierNumber,
              isFirst: i == 0,
              isLast: i == tiers.length - 1,
              isArabic: isArabic,
            ),
        ],
      ),
    );
  }
}

class _LevelRangeRow extends StatelessWidget {
  const _LevelRangeRow({
    required this.tier,
    required this.isCurrent,
    required this.isFirst,
    required this.isLast,
    required this.isArabic,
  });

  final WealthTier tier;
  final bool isCurrent;
  final bool isFirst;
  final bool isLast;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimelineMarker(active: isCurrent, isFirst: isFirst, isLast: isLast),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10, left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: isCurrent
                    ? LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          tier.color.withValues(alpha: 0.26),
                          const Color(0xFF1A0E06),
                        ],
                      )
                    : null,
                color: isCurrent ? null : const Color(0xFF160D06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCurrent
                      ? tier.color.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.06),
                  width: isCurrent ? 1.6 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${tier.minLevel} - ${tier.maxLevel}',
                          style: const TextStyle(
                            color: Color(0xFFF3E3C0),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${tier.displayName} · ${isArabic ? 'أنت هنا' : 'You'}',
                            style: TextStyle(
                              color: tier.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _LevelBadgePill(tier: tier, glow: isCurrent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Timeline marker ─────────────────────────────────────────────────────────

class _TimelineMarker extends StatelessWidget {
  const _TimelineMarker({
    required this.active,
    required this.isFirst,
    required this.isLast,
  });

  final bool active;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE3B25E);
    return SizedBox(
      width: 26,
      child: Column(
        children: [
          // top line segment
          Expanded(
            child: Container(
              width: 1.4,
              color: isFirst
                  ? Colors.transparent
                  : gold.withValues(alpha: 0.35),
            ),
          ),
          // diamond marker
          Transform.rotate(
            angle: 0.785398, // 45 degrees
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: active ? gold : Colors.transparent,
                border: Border.all(color: gold, width: 1.5),
                boxShadow: active
                    ? const [BoxShadow(color: Color(0xAAF0C15A), blurRadius: 8)]
                    : null,
              ),
            ),
          ),
          // bottom line segment
          Expanded(
            child: Container(
              width: 1.4,
              color: isLast ? Colors.transparent : gold.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Badge pill ──────────────────────────────────────────────────────────────

class _LevelBadgePill extends StatelessWidget {
  const _LevelBadgePill({required this.tier, required this.glow});
  final WealthTier tier;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _lighten(tier.color, 0.28),
            tier.color,
            _darken(tier.color, 0.28),
          ],
        ),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFFFF0C8), width: 1),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: tier.color.withValues(alpha: 0.6),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_rounded, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          Text(
            '${tier.maxLevel}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Color(0x66000000), blurRadius: 2)],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _lighten(Color c, [double amount = 0.3]) =>
    Color.lerp(c, Colors.white, amount)!;

Color _darken(Color c, [double amount = 0.3]) =>
    Color.lerp(c, Colors.black, amount)!;

String _fmt(int xp) {
  if (xp >= 1000000000) return '${(xp / 1000000000).toStringAsFixed(1)}B';
  if (xp >= 1000000) return '${(xp / 1000000).toStringAsFixed(1)}M';
  if (xp >= 1000) return '${(xp / 1000).toStringAsFixed(1)}K';
  return '$xp';
}
