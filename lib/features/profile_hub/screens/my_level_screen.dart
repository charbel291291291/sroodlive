import 'package:flutter/material.dart';

import '../models/profile_hub_models.dart';
import '../services/level_service.dart';
import '../widgets/profile_hub_widgets.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class MyLevelScreen extends StatefulWidget {
  const MyLevelScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<MyLevelScreen> createState() => _MyLevelScreenState();
}

class _MyLevelScreenState extends State<MyLevelScreen> {
  final LevelService _service = const LevelService();
  late Future<UserLevel> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.getMyLevel();
  }

  void _retry() => setState(() => _future = _service.getMyLevel());

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

    return ProfileHubScaffold(
      title: isArabic ? 'مستواي' : 'My level',
      isArabic: isArabic,
      children: [
        FutureBuilder<UserLevel>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return ProfileErrorState(
                message: snapshot.error?.toString() ?? 'Failed to load level.',
                onRetry: _retry,
                isArabic: isArabic,
              );
            }

            final lvl = snapshot.data!;
            return _LevelBody(level: lvl, isArabic: isArabic);
          },
        ),
      ],
    );
  }
}

class _LevelBody extends StatelessWidget {
  const _LevelBody({required this.level, required this.isArabic});

  final UserLevel level;
  final bool isArabic;

  Color get _tierColor {
    return switch (level.currentLevelColor) {
      'bronze'    => const Color(0xFFCD7F32),
      'silver'    => const Color(0xFFC0C0C0),
      'gold'      => const Color(0xFFFFD700),
      'emerald'   => const Color(0xFF2ECC71),
      'sapphire'  => const Color(0xFF2E86DE),
      'ruby'      => const Color(0xFFE74C3C),
      'diamond'   => const Color(0xFF44D4FF),
      'master'    => const Color(0xFF9B59F5),
      'royal'     => const Color(0xFFFF4ECD),
      'legendary' => const Color(0xFFFF6B00),
      _           => const Color(0xFFCD7F32), // bronze default
    };
  }

  String _fmtNumber(int n) {
    if (n >= 1000000) {
      final v = n / 1000000;
      return '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)}M';
    }
    if (n >= 1000) {
      final v = n / 1000;
      return '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)}k';
    }
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierColor;
    final progress = (level.levelProgress ?? 0.0).clamp(0.0, 1.0);
    final progressPct = (progress * 100).toStringAsFixed(0);
    final title = level.currentLevelTitle ??
        (isArabic ? 'عضو جديد' : 'New Voice');

    return Column(
      crossAxisAlignment:
          isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // ── Hero card ─────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3B105A), Color(0xFF160B26)],
            ),
            border: Border.all(
              color: profileHubGold.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.trending_up_rounded, color: tierColor, size: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: tierColor.withValues(alpha: 0.55), width: 0.8),
                    ),
                    child: Text(
                      level.currentLevelColor?.toUpperCase() ?? 'BRONZE',
                      style: TextStyle(
                        color: tierColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${isArabic ? 'المستوى' : 'Level'} ${level.level}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: tierColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),

              // ── Progress bar ─────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 12,
                  backgroundColor: Colors.black.withValues(alpha: 0.34),
                  valueColor: AlwaysStoppedAnimation(tierColor),
                ),
              ),
              const SizedBox(height: 8),

              if (level.isMaxLevel)
                Text(
                  isArabic
                      ? 'وصلت لأعلى مستوى — Srood Icon'
                      : 'Max level reached — Srood Icon',
                  style: const TextStyle(
                    color: profileHubMuted,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$progressPct%',
                      style: TextStyle(
                        color: tierColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      isArabic
                          ? '${_fmtNumber(level.xpToNextLevel ?? 0)} XP للمستوى ${level.nextLevel}'
                          : '${_fmtNumber(level.xpToNextLevel ?? 0)} XP to level ${level.nextLevel}',
                      style: const TextStyle(
                        color: profileHubMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // ── Stats ──────────────────────────────────────────────────────
        ProfileSectionTitle(
          title: isArabic ? 'الإحصائيات' : 'Stats',
          isArabic: isArabic,
        ),
        _StatsGrid(level: level, isArabic: isArabic),

        // ── Next level ────────────────────────────────────────────────
        ProfileSectionTitle(
          title: isArabic ? 'المستوى التالي' : 'Next level',
          isArabic: isArabic,
        ),
        ProfileInfoCard(
          icon: Icons.workspace_premium_rounded,
          title: level.isMaxLevel
              ? (isArabic ? 'لا يوجد مستوى أعلى' : 'No higher level')
              : '${isArabic ? 'المستوى' : 'Level'} ${level.nextLevel}'
                '${level.nextLevelTitle != null ? ' — ${level.nextLevelTitle}' : ''}',
          body: level.isMaxLevel
              ? (isArabic
                  ? 'استمتع بمزاياك كأيقونة Srood.'
                  : 'Enjoy your status as a Srood Icon.')
              : (isArabic
                  ? 'تحتاج ${_fmtNumber(level.xpToNextLevel ?? 0)} XP إضافية.'
                  : '${_fmtNumber(level.xpToNextLevel ?? 0)} more XP needed.'),
          isArabic: isArabic,
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.level, required this.isArabic});

  final UserLevel level;
  final bool isArabic;

  String _fmt(int n) {
    if (n >= 1000000) {
      final v = n / 1000000;
      return '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)}M';
    }
    if (n >= 1000) {
      final v = n / 1000;
      return '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)}k';
    }
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.bolt_rounded,        isArabic ? 'XP الكلي' : 'Total XP',         _fmt(level.xp)),
      (Icons.payments_rounded,    isArabic ? 'عملات منفقة' : 'Coins spent',   _fmt(level.totalSpentCoins)),
      (Icons.send_rounded,        isArabic ? 'هدايا أُرسلت' : 'Gifts sent',   _fmt(level.totalGiftsSent)),
      (Icons.redeem_rounded,      isArabic ? 'هدايا استُلمت' : 'Gifts rcv\'d', _fmt(level.totalGiftsReceived)),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: [
        for (final (icon, label, value) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.black.withValues(alpha: 0.28),
              border: Border.all(
                  color: profileHubGold.withValues(alpha: 0.18), width: 0.7),
            ),
            child: Row(
              children: [
                Icon(icon, color: profileHubGold, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          color: profileHubMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
