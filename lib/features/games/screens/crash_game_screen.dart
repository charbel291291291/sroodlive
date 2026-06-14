import 'package:flutter/material.dart';

import 'gold_ladder_quiz_screen.dart';
import 'hungry_cat_webview_screen.dart';
import 'rocket_crash_webview_screen.dart';
import 'spin_wheel_screen.dart';

class CrashGameScreen extends StatelessWidget {
  const CrashGameScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final title = isArabic ? 'الألعاب' : 'Games';

    return Scaffold(
      backgroundColor: const Color(0xFF08030F),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFF4C1D95)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.sports_esports_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 110),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  _GameCard(
                    icon: '🎡',
                    title: isArabic ? 'عجلة الحظ' : 'Spin Wheel',
                    subtitle: isArabic
                        ? 'اختار رهانك ولف العجلة.'
                        : 'Pick your bet and spin the wheel.',
                    colors: const [Color(0xFFF97316), Color(0xFF7C2D12)],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SpinWheelScreen(isArabic: isArabic),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _GameCard(
                    icon: '🐱',
                    title: isArabic ? 'القط الجائع' : 'Hungry Cat',
                    subtitle: isArabic
                        ? 'لعبة أكل وجوائز مع القط.'
                        : 'Food, coins, and cute cat rewards.',
                    colors: const [Color(0xFFF0C15A), Color(0xFF92400E)],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HungryCatWebviewScreen(isArabic: isArabic),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _GameCard(
                    icon: '🚀',
                    title: isArabic ? 'صاروخ الانهيار' : 'Rocket Crash',
                    subtitle: isArabic
                        ? 'راهن واكسب قبل أن يسقط الصاروخ!'
                        : 'Bet and cash out before the rocket crashes!',
                    colors: const [Color(0xFF1A6FFF), Color(0xFF030e2a)],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RocketCrashWebviewScreen(isArabic: isArabic),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _GameCard(
                    icon: '🏆',
                    title: isArabic ? 'سلم الذهب' : 'Gold Ladder',
                    subtitle: isArabic
                        ? 'جاوب واربح واطلع على السلم.'
                        : 'Answer, climb, and win rewards.',
                    colors: const [Color(0xFF22C55E), Color(0xFF064E3B)],
                    badge: isArabic ? 'جديد' : 'NEW',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => GoldLadderQuizScreen(isArabic: isArabic),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
    this.badge,
  });

  final String icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                bottom: -22,
                child: Text(
                  icon,
                  style: TextStyle(
                    fontSize: 108,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        icon,
                        style: const TextStyle(fontSize: 34),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (badge != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    badge!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
