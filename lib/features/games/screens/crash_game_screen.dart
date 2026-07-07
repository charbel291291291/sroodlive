import 'package:flutter/material.dart';

import 'crash_rocket_screen.dart';
import 'gold_ladder_quiz_screen.dart';
import 'hungry_cat_webview_screen.dart';
import 'magic_srood_screen.dart';
import 'spin_wheel_screen.dart';
import 'srood_blocks_screen.dart';
import 'srood_loto_screen.dart';
import 'srood_treasure_screen.dart';

class GameCenterScreen extends StatelessWidget {
  const GameCenterScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final title = isArabic ? 'الألعاب' : 'Games';

    final games = _gamesData(context, isArabic);

    return Scaffold(
      backgroundColor: const Color(0xFF08030F),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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
                            color: const Color(
                              0xFF8B5CF6,
                            ).withValues(alpha: 0.35),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: const Color(0xFF6D28D9).withValues(alpha: 0.3),
                        border: Border.all(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '${games.length} ${isArabic ? 'لعبة' : 'Games'}',
                        style: const TextStyle(
                          color: Color(0xFFA78BFA),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 2-column grid ─────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 120),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.95,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _GameGridCard(data: games[i]),
                  childCount: games.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_GameData> _gamesData(BuildContext context, bool ar) => [
    _GameData(
      emoji: '🎡',
      assetPath: 'assets/images/games/spin_wheel.webp',
      title: ar ? 'عجلة الحظ' : 'Spin Wheel',
      subtitle: ar ? 'لف العجلة واربح' : 'Spin & win',
      colors: const [Color(0xFFF97316), Color(0xFF7C2D12)],
      glowColor: const Color(0xFFF97316),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SpinWheelScreen(isArabic: ar)),
      ),
    ),
    _GameData(
      emoji: '🐱',
      assetPath: 'assets/images/games/hungry_cat.webp',
      title: ar ? 'القط الجائع' : 'Hungry Cat',
      subtitle: ar ? 'أطعم القط واكسب' : 'Feed & earn',
      colors: const [Color(0xFFF0C15A), Color(0xFF92400E)],
      glowColor: const Color(0xFFF0C15A),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HungryCatWebviewScreen(isArabic: ar),
        ),
      ),
    ),
    _GameData(
      emoji: '🚀',
      assetPath: null,
      title: ar ? 'صاروخ سرود' : 'Srood Rocket',
      subtitle: ar ? 'اسحب قبل الانفجار' : 'Cash out before the crash',
      colors: const [Color(0xFF28C7FA), Color(0xFF102B52)],
      glowColor: const Color(0xFFF4C95D),
      badge: ar ? 'مباشر' : 'LIVE',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CrashRocketScreen(isArabic: ar),
        ),
      ),
    ),
    _GameData(
      emoji: '🏆',
      assetPath: 'assets/images/games/gold_ladder.webp',
      title: ar ? 'سلم الذهب' : 'Gold Ladder',
      subtitle: ar ? 'جاوب واطلع فوق' : 'Answer & climb',
      colors: const [Color(0xFF22C55E), Color(0xFF064E3B)],
      glowColor: const Color(0xFF22C55E),
      badge: ar ? 'تحدي' : 'QUIZ',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GoldLadderQuizScreen(isArabic: ar),
        ),
      ),
    ),
    _GameData(
      emoji: '🎰',
      assetPath: 'assets/images/games/srood_draw.webp',
      title: ar ? 'سرود درو' : 'Srood Draw',
      subtitle: ar ? 'اشتري تذكرة واكسب' : 'Buy a ticket & win',
      colors: const [Color(0xFFEC4899), Color(0xFF831843)],
      glowColor: const Color(0xFFEC4899),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SroodLotoScreen(isArabic: ar)),
      ),
    ),
    _GameData(
      emoji: '💎',
      assetPath: 'assets/images/games/srood_treasure.webp',
      title: ar ? 'سرود تريجر' : 'Srood Treasure',
      subtitle: ar ? 'اختار صندوقك' : 'Pick your box',
      colors: const [Color(0xFF06B6D4), Color(0xFF164E63)],
      glowColor: const Color(0xFF06B6D4),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SroodTreasureScreen(isArabic: ar),
        ),
      ),
    ),
    _GameData(
      emoji: '⚽',
      assetPath: null,
      title: ar ? 'ماجيك سرود' : 'Magic Srood',
      subtitle: ar ? 'اختر الفريق واكسب' : 'Pick & win',
      colors: const [Color(0xFFFFCC00), Color(0xFF4A3000)],
      glowColor: const Color(0xFFFFCC00),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => MagicSroodScreen(isArabic: ar)),
      ),
    ),
    _GameData(
      emoji: '🟪',
      assetPath: 'assets/images/games/srood_blocks.webp',
      title: ar ? 'سرود بلوكس' : 'Srood Blocks',
      subtitle: ar ? 'رتّب البلوكس واكسب XP' : 'Stack & earn XP',
      colors: const [Color(0xFF8B5CF6), Color(0xFF2E1065)],
      glowColor: const Color(0xFF8B5CF6),
      badge: ar ? 'جديد' : 'NEW',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SroodBlocksScreen(isArabic: ar),
        ),
      ),
    ),
  ];
}

@Deprecated('Use GameCenterScreen.')
class CrashGameScreen extends GameCenterScreen {
  const CrashGameScreen({required super.isArabic, super.key});
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _GameData {
  const _GameData({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.glowColor,
    required this.onTap,
    this.badge,
    this.assetPath,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final Color glowColor;
  final VoidCallback onTap;
  final String? badge;
  final String? assetPath;
}

// ── Grid card ─────────────────────────────────────────────────────────────────

class _GameGridCard extends StatelessWidget {
  const _GameGridCard({required this.data});

  final _GameData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: data.onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                data.colors[0].withValues(alpha: 0.18),
                data.colors[1].withValues(alpha: 0.35),
              ],
            ),
            border: Border.all(color: data.colors[0].withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: data.glowColor.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // ghost emoji background
              Positioned(
                right: -12,
                bottom: -14,
                child: Text(
                  data.emoji,
                  style: TextStyle(
                    fontSize: 72,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),

              // content
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // icon container
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: data.colors,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: data.glowColor.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: data.assetPath != null
                          ? Image.asset(
                              data.assetPath!,
                              fit: BoxFit.contain,
                              errorBuilder: (context2, err, st) => Text(
                                data.emoji,
                                style: const TextStyle(fontSize: 26),
                              ),
                            )
                          : Center(
                              child: Text(
                                data.emoji,
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                    ),

                    const Spacer(),

                    // badge
                    if (data.badge != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          color: data.colors[0].withValues(alpha: 0.3),
                          border: Border.all(
                            color: data.colors[0].withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          data.badge!,
                          style: TextStyle(
                            color: data.colors[0],
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),

                    // title
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),

                    // subtitle
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // arrow chip
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white54,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
