import 'package:flutter/material.dart';

import '../models/profile_hub_models.dart';
import '../services/level_service.dart';
import '../widgets/profile_hub_widgets.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class LevelCenterScreen extends StatefulWidget {
  const LevelCenterScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<LevelCenterScreen> createState() => _LevelCenterScreenState();
}

class _LevelCenterScreenState extends State<LevelCenterScreen> {
  final _service = const LevelService();
  late Future<(UserLevel, List<LevelRule>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(UserLevel, List<LevelRule>)> _load() async {
    debugPrint('[LevelCenter] loading level + rules');
    final results = await Future.wait([
      _service.getMyLevel(),
      _service.getLevelRules(),
    ]);
    return (results[0] as UserLevel, results[1] as List<LevelRule>);
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

    return ProfileHubScaffold(
      title: isArabic ? 'سلّم المستويات' : 'Level Ladder',
      isArabic: isArabic,
      children: [
        FutureBuilder<(UserLevel, List<LevelRule>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return ProfileErrorState(
                message: snapshot.error?.toString() ?? 'Failed to load levels.',
                onRetry: _retry,
                isArabic: isArabic,
              );
            }
            final (myLevel, rules) = snapshot.data!;
            debugPrint(
              '[LevelCenter] current level=${myLevel.level} rules=${rules.length}',
            );
            return _LevelLadder(
              myLevel: myLevel,
              rules: rules,
              isArabic: isArabic,
            );
          },
        ),
      ],
    );
  }
}

// ── Tier group definition ──────────────────────────────────────────────────────

class _TierGroup {
  const _TierGroup({
    required this.start,
    required this.end,
    required this.nameEn,
    required this.nameAr,
    required this.primaryColor,
    required this.glowColor,
    required this.bgGradient,
    required this.icon,
  });

  final int start;
  final int end;
  final String nameEn;
  final String nameAr;
  final Color primaryColor;
  final Color glowColor;
  final List<Color> bgGradient;
  final IconData icon;

  bool contains(int level) => level >= start && level <= end;
}

const _tierGroups = [
  _TierGroup(
    start: 1,
    end: 10,
    nameEn: 'Bronze Spark',
    nameAr: 'شرارة البرونز',
    primaryColor: Color(0xFFCD7F32),
    glowColor: Color(0xFFCD7F32),
    bgGradient: [Color(0xFF2A1500), Color(0xFF1A0C00)],
    icon: Icons.local_fire_department_rounded,
  ),
  _TierGroup(
    start: 11,
    end: 20,
    nameEn: 'Silver Rise',
    nameAr: 'صعود الفضة',
    primaryColor: Color(0xFFC0C0C0),
    glowColor: Color(0xFFD8D8D8),
    bgGradient: [Color(0xFF1A1A2A), Color(0xFF0D0D1A)],
    icon: Icons.trending_up_rounded,
  ),
  _TierGroup(
    start: 21,
    end: 30,
    nameEn: 'Gold Flame',
    nameAr: 'لهب الذهب',
    primaryColor: Color(0xFFFFD700),
    glowColor: Color(0xFFFFD700),
    bgGradient: [Color(0xFF2A2000), Color(0xFF1A1400)],
    icon: Icons.star_rounded,
  ),
  _TierGroup(
    start: 31,
    end: 40,
    nameEn: 'Emerald Aura',
    nameAr: 'هالة الزمرد',
    primaryColor: Color(0xFF2ECC71),
    glowColor: Color(0xFF27AE60),
    bgGradient: [Color(0xFF002A10), Color(0xFF001A0A)],
    icon: Icons.eco_rounded,
  ),
  _TierGroup(
    start: 41,
    end: 50,
    nameEn: 'Sapphire Pulse',
    nameAr: 'نبضة الياقوت الأزرق',
    primaryColor: Color(0xFF2980B9),
    glowColor: Color(0xFF3498DB),
    bgGradient: [Color(0xFF00162A), Color(0xFF000E1A)],
    icon: Icons.water_drop_rounded,
  ),
  _TierGroup(
    start: 51,
    end: 60,
    nameEn: 'Ruby Crown',
    nameAr: 'تاج الياقوت',
    primaryColor: Color(0xFFE74C3C),
    glowColor: Color(0xFFC0392B),
    bgGradient: [Color(0xFF2A0000), Color(0xFF1A0000)],
    icon: Icons.workspace_premium_rounded,
  ),
  _TierGroup(
    start: 61,
    end: 70,
    nameEn: 'Diamond Halo',
    nameAr: 'هالة الألماس',
    primaryColor: Color(0xFF44D4FF),
    glowColor: Color(0xFF44D4FF),
    bgGradient: [Color(0xFF001A2A), Color(0xFF00111A)],
    icon: Icons.diamond_rounded,
  ),
  _TierGroup(
    start: 71,
    end: 80,
    nameEn: 'Master Eclipse',
    nameAr: 'كسوف الأسياد',
    primaryColor: Color(0xFF9B59F5),
    glowColor: Color(0xFF8E44AD),
    bgGradient: [Color(0xFF15002A), Color(0xFF0E001A)],
    icon: Icons.nights_stay_rounded,
  ),
  _TierGroup(
    start: 81,
    end: 90,
    nameEn: 'Royal Nebula',
    nameAr: 'سديم الملوك',
    primaryColor: Color(0xFFFF4ECD),
    glowColor: Color(0xFFE91E8C),
    bgGradient: [Color(0xFF2A0020), Color(0xFF1A0015)],
    icon: Icons.auto_awesome_rounded,
  ),
  _TierGroup(
    start: 91,
    end: 100,
    nameEn: 'Legendary Sun',
    nameAr: 'شمس الأساطير',
    primaryColor: Color(0xFFFF6B00),
    glowColor: Color(0xFFFFD700),
    bgGradient: [Color(0xFF2A1000), Color(0xFF1A0800)],
    icon: Icons.wb_sunny_rounded,
  ),
];

// ── Main ladder widget ─────────────────────────────────────────────────────────

class _LevelLadder extends StatelessWidget {
  const _LevelLadder({
    required this.myLevel,
    required this.rules,
    required this.isArabic,
  });

  final UserLevel myLevel;
  final List<LevelRule> rules;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final ruleMap = {for (final r in rules) r.level: r};

    return Column(
      children: [
        // My current level summary chip
        _CurrentLevelBadge(myLevel: myLevel, isArabic: isArabic),
        const SizedBox(height: 20),
        // All tier groups
        for (final group in _tierGroups) ...[
          _TierGroupCard(
            group: group,
            rules: ruleMap,
            currentLevel: myLevel.level,
            isArabic: isArabic,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Current level hero badge ───────────────────────────────────────────────────

class _CurrentLevelBadge extends StatelessWidget {
  const _CurrentLevelBadge({required this.myLevel, required this.isArabic});

  final UserLevel myLevel;
  final bool isArabic;

  Color get _color {
    return switch (myLevel.currentLevelColor) {
      'bronze' => const Color(0xFFCD7F32),
      'silver' => const Color(0xFFC0C0C0),
      'gold' => const Color(0xFFFFD700),
      'emerald' => const Color(0xFF2ECC71),
      'sapphire' => const Color(0xFF2E86DE),
      'ruby' => const Color(0xFFE74C3C),
      'diamond' => const Color(0xFF44D4FF),
      'master' => const Color(0xFF9B59F5),
      'royal' => const Color(0xFFFF4ECD),
      'legendary' => const Color(0xFFFF6B00),
      _ => const Color(0xFFCD7F32), // bronze default
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.18), const Color(0xFF12091D)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Icon(Icons.military_tech_rounded, color: color, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'مستواك الحالي' : 'Your Current Level',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${isArabic ? 'المستوى' : 'Level'} ${myLevel.level}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (myLevel.currentLevelTitle != null)
                  Text(
                    myLevel.currentLevelTitle!,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (myLevel.levelProgress != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: myLevel.levelProgress!.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  if (!myLevel.isMaxLevel && myLevel.xpToNextLevel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        isArabic
                            ? '${_fmtXp(myLevel.xpToNextLevel!)} XP للمستوى التالي'
                            : '${_fmtXp(myLevel.xpToNextLevel!)} XP to next level',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.48),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: color.withValues(alpha: 0.7),
                width: 1.2,
              ),
            ),
            child: Text(
              '${_fmtXp(myLevel.xp)} XP',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tier group card ────────────────────────────────────────────────────────────

class _TierGroupCard extends StatefulWidget {
  const _TierGroupCard({
    required this.group,
    required this.rules,
    required this.currentLevel,
    required this.isArabic,
  });

  final _TierGroup group;
  final Map<int, LevelRule> rules;
  final int currentLevel;
  final bool isArabic;

  @override
  State<_TierGroupCard> createState() => _TierGroupCardState();
}

class _TierGroupCardState extends State<_TierGroupCard> {
  bool _expanded = false;

  bool get _isCurrentTier => widget.group.contains(widget.currentLevel);
  bool get _isCompleted => widget.currentLevel > widget.group.end;

  @override
  void initState() {
    super.initState();
    // Auto-expand the tier containing the user's current level
    _expanded = _isCurrentTier;
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final color = group.primaryColor;
    final isCurrent = _isCurrentTier;
    final isCompleted = _isCompleted;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: group.bgGradient,
        ),
        border: Border.all(
          color: isCurrent
              ? color.withValues(alpha: 0.75)
              : color.withValues(alpha: 0.25),
          width: isCurrent ? 1.6 : 1.0,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: group.glowColor.withValues(alpha: 0.30),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: Column(
        children: [
          // Header row — always visible
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                textDirection: widget.isArabic
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                children: [
                  // Tier icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.15),
                      border: Border.all(
                        color: color.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(group.icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: widget.isArabic
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Row(
                          textDirection: widget.isArabic
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          children: [
                            Text(
                              widget.isArabic ? group.nameAr : group.nameEn,
                              style: TextStyle(
                                color: color,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.8),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  widget.isArabic ? 'أنت هنا' : 'You',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.isArabic ? 'المستويات' : 'Levels'} ${group.start}–${group.end}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status icon
                  if (isCompleted)
                    Icon(Icons.check_circle_rounded, color: color, size: 22)
                  else
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: Colors.white.withValues(alpha: 0.45),
                      size: 22,
                    ),
                ],
              ),
            ),
          ),
          // Expanded level chips
          if (_expanded) ...[
            Divider(
              height: 1,
              color: color.withValues(alpha: 0.20),
              indent: 16,
              endIndent: 16,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                textDirection: widget.isArabic
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                children: [
                  for (int lvl = group.start; lvl <= group.end; lvl++)
                    _LevelChip(
                      level: lvl,
                      rule: widget.rules[lvl],
                      color: color,
                      isCurrent: lvl == widget.currentLevel,
                      isUnlocked: lvl <= widget.currentLevel,
                      isArabic: widget.isArabic,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Level chip ─────────────────────────────────────────────────────────────────

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.level,
    required this.rule,
    required this.color,
    required this.isCurrent,
    required this.isUnlocked,
    required this.isArabic,
  });

  final int level;
  final LevelRule? rule;
  final Color color;
  final bool isCurrent;
  final bool isUnlocked;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isCurrent
            ? color.withValues(alpha: 0.28)
            : isUnlocked
            ? color.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: isCurrent
              ? color.withValues(alpha: 0.90)
              : isUnlocked
              ? color.withValues(alpha: 0.40)
              : Colors.white.withValues(alpha: 0.12),
          width: isCurrent ? 1.5 : 1.0,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.40),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ]
            : [],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$level',
            style: TextStyle(
              color: isCurrent
                  ? color
                  : isUnlocked
                  ? color.withValues(alpha: 0.80)
                  : Colors.white.withValues(alpha: 0.35),
              fontSize: 15,
              fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
          if (isCurrent)
            Text(
              isArabic ? 'أنت' : 'You',
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
        ],
      ),
    );
  }
}

String _fmtXp(int v) {
  if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}B';
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return '$v';
}
