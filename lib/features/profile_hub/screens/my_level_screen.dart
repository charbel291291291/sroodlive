import 'package:flutter/material.dart';

import '../models/profile_hub_models.dart';
import '../services/level_service.dart';
import '../widgets/profile_hub_widgets.dart';

class MyLevelScreen extends StatefulWidget {
  const MyLevelScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<MyLevelScreen> createState() => _MyLevelScreenState();
}

class _MyLevelScreenState extends State<MyLevelScreen> {
  final LevelService _service = const LevelService();
  late Future<({UserLevel level, List<LevelRule> rules})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({UserLevel level, List<LevelRule> rules})> _load() async {
    final level = await _service.getMyLevel();
    final rules = await _service.getLevelRules();
    return (level: level, rules: rules);
  }

  void _retry() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return ProfileHubScaffold(
      title: isArabic ? 'مستواي' : 'My level',
      isArabic: isArabic,
      children: [
        FutureBuilder<({UserLevel level, List<LevelRule> rules})>(
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

            final level = snapshot.data!.level;
            final rules = snapshot.data!.rules;
            LevelRule? currentRule;
            for (final rule in rules) {
              if (rule.level <= level.level) {
                currentRule = rule;
              }
            }
            final nextRule = _service.getNextLevel(level, rules);
            final startXp = currentRule?.requiredXp ?? 0;
            final targetXp = nextRule?.requiredXp ?? startXp;
            final progress = targetXp == startXp
                ? 1.0
                : ((level.xp - startXp) / (targetXp - startXp)).clamp(0.0, 1.0);

            return Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B105A), Color(0xFF160B26)],
                    ),
                    border: Border.all(
                      color: profileHubGold.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: isArabic
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.trending_up_rounded,
                        color: profileHubGold,
                        size: 34,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${isArabic ? 'المستوى' : 'Level'} ${level.level}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentRule?.title ??
                            (isArabic ? 'عضو جديد' : 'New Voice'),
                        style: const TextStyle(
                          color: profileHubMuted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 12,
                          backgroundColor: Colors.black.withValues(alpha: 0.34),
                          valueColor: const AlwaysStoppedAnimation(
                            profileHubGold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        nextRule == null
                            ? (isArabic
                                  ? 'وصلت لأعلى مستوى'
                                  : 'Top level reached')
                            : '${level.xp} / ${nextRule.requiredXp} XP',
                        style: const TextStyle(
                          color: profileHubMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                ProfileSectionTitle(
                  title: isArabic ? 'مصادر XP' : 'XP sources',
                  isArabic: isArabic,
                ),
                ProfileInfoCard(
                  icon: Icons.payments_rounded,
                  title: isArabic ? 'النشاط' : 'Activity',
                  body:
                      '${isArabic ? 'إنفاق العملات' : 'Coins spent'}: ${level.totalSpentCoins}\n'
                      '${isArabic ? 'الهدايا المستلمة' : 'Received gifts value'}: ${level.totalReceivedGiftsValue}\n'
                      '${isArabic ? 'دقائق الغرف' : 'Room minutes'}: ${level.totalRoomMinutes}',
                  isArabic: isArabic,
                ),
                ProfileSectionTitle(
                  title: isArabic ? 'المستوى التالي' : 'Next level benefits',
                  isArabic: isArabic,
                ),
                ProfileInfoCard(
                  icon: Icons.workspace_premium_rounded,
                  title:
                      nextRule?.title ??
                      (isArabic ? 'لا يوجد مستوى أعلى' : 'No higher level'),
                  body: nextRule == null
                      ? (isArabic
                            ? 'استمتع بمزاياك الحالية.'
                            : 'Enjoy your current benefits.')
                      : nextRule.benefits.join('\n'),
                  isArabic: isArabic,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
