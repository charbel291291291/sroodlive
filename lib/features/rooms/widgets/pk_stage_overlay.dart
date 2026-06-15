import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pk_session.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PK colours.
// ─────────────────────────────────────────────────────────────────────────────

const kPkRed = Color(0xFFE63946);
const kPkBlue = Color(0xFF3D8EF0);

Color pkTeamColor(String? team) =>
    team == 'a' ? kPkRed : team == 'b' ? kPkBlue : Colors.transparent;

// ─────────────────────────────────────────────────────────────────────────────
// PkBanner — replaces the "Voice Stage" header row during an active PK.
// Shows: [Team A score] [countdown] [Team B score]
// ─────────────────────────────────────────────────────────────────────────────

class PkBanner extends StatefulWidget {
  const PkBanner({
    required this.session,
    required this.isArabic,
    required this.onFinish,
    required this.isHost,
    super.key,
  });

  final PkSession session;
  final bool isArabic;
  final VoidCallback onFinish;
  final bool isHost;

  @override
  State<PkBanner> createState() => _PkBannerState();
}

class _PkBannerState extends State<PkBanner> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  bool _hasAutoFinished = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now().toUtc();
    final diff = widget.session.endsAt.toUtc().difference(now);
    setState(() => _remaining = diff.isNegative ? Duration.zero : diff);

    if (!_hasAutoFinished && diff.isNegative) {
      _hasAutoFinished = true;
      widget.onFinish();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final urgent = _remaining.inSeconds < 30 && _remaining.inSeconds > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Scores + timer row
        Row(
          children: [
            // Team A
            _TeamScoreChip(
              label: widget.isArabic ? 'فريق أ' : 'Team A',
              score: session.teamAScore,
              color: kPkRed,
              leading: session.leadingTeam == 'a',
            ),
            const Spacer(),
            // Countdown
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: urgent
                    ? kPkRed.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: urgent
                      ? kPkRed.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                _fmt(_remaining),
                style: TextStyle(
                  color: urgent ? kPkRed : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
            // Team B
            _TeamScoreChip(
              label: widget.isArabic ? 'فريق ب' : 'Team B',
              score: session.teamBScore,
              color: kPkBlue,
              leading: session.leadingTeam == 'b',
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Battle bar
        PkBattleBar(
          teamAFraction: session.teamAFraction,
          isArabic: widget.isArabic,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PkBattleBar — animated tug-of-war progress bar.
// ─────────────────────────────────────────────────────────────────────────────

class PkBattleBar extends StatelessWidget {
  const PkBattleBar({
    required this.teamAFraction,
    required this.isArabic,
    super.key,
  });

  final double teamAFraction;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return SizedBox(
        height: 22,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background track
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Row(
                children: [
                  // Red fill (Team A)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOut,
                    width: width * teamAFraction,
                    height: 22,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF6B7A), kPkRed],
                      ),
                    ),
                  ),
                  // Blue fill (Team B)
                  Expanded(
                    child: Container(
                      height: 22,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [kPkBlue, Color(0xFF6BAEFF)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // VS center knob
            AnimatedPositioned(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
              left: (width * teamAFraction) - 14,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A0A33),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PkResultBanner — shown when PK finishes.
// ─────────────────────────────────────────────────────────────────────────────

class PkResultBanner extends StatefulWidget {
  const PkResultBanner({
    required this.session,
    required this.isArabic,
    required this.onClose,
    super.key,
  });

  final PkSession session;
  final bool isArabic;
  final VoidCallback onClose;

  @override
  State<PkResultBanner> createState() => _PkResultBannerState();
}

class _PkResultBannerState extends State<PkResultBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
    // Auto-close after 6 seconds.
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) widget.onClose();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final winner = session.winnerTeam;
    final winColor = winner == 'a'
        ? kPkRed
        : winner == 'b'
            ? kPkBlue
            : const Color(0xFFF0C15A);
    final winLabel = winner == 'a'
        ? _t('الفريق أ يفوز!', 'Team A Wins!')
        : winner == 'b'
            ? _t('الفريق ب يفوز!', 'Team B Wins!')
            : _t('تعادل!', 'Draw!');

    // Top scorer.
    PkMember? mvp;
    if (session.members.isNotEmpty) {
      mvp = session.members.reduce(
          (a, b) => a.pkScore >= b.pkScore ? a : b);
      if (mvp.pkScore == 0) mvp = null;
    }

    return ScaleTransition(
      scale: _scale,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              winColor.withValues(alpha: 0.18),
              const Color(0xFF0C051E).withValues(alpha: 0.9),
            ],
          ),
          border: Border.all(color: winColor.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: winColor.withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Winner crown
            Icon(Icons.emoji_events_rounded, color: winColor, size: 36),
            const SizedBox(height: 6),
            Text(
              winLabel,
              style: TextStyle(
                color: winColor,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 12),
            // Final scores
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _FinalScore(
                  label: _t('فريق أ', 'Team A'),
                  score: session.teamAScore,
                  color: kPkRed,
                  isWinner: winner == 'a',
                ),
                Container(
                  width: 1,
                  height: 32,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                _FinalScore(
                  label: _t('فريق ب', 'Team B'),
                  score: session.teamBScore,
                  color: kPkBlue,
                  isWinner: winner == 'b',
                ),
              ],
            ),
            if (mvp != null) ...[
              const SizedBox(height: 10),
              Divider(color: Colors.white.withValues(alpha: 0.08)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_rounded,
                      color: Color(0xFFF0C15A), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${_t('أفضل لاعب', 'MVP')}: ${mvp.displayName ?? '—'}  •  ${mvp.pkScore} ${_t('نقطة', 'pts')}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            GestureDetector(
              onTap: widget.onClose,
              child: Text(
                _t('إغلاق', 'Close'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TeamScoreChip extends StatelessWidget {
  const _TeamScoreChip({
    required this.label,
    required this.score,
    required this.color,
    required this.leading,
  });

  final String label;
  final int score;
  final Color color;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: leading ? 0.20 : 0.08),
        border: Border.all(
          color: color.withValues(alpha: leading ? 0.60 : 0.25),
          width: leading ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading)
            Icon(Icons.local_fire_department_rounded,
                color: color, size: 12),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            score.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinalScore extends StatelessWidget {
  const _FinalScore({
    required this.label,
    required this.score,
    required this.color,
    required this.isWinner,
  });

  final String label;
  final int score;
  final Color color;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$score',
          style: TextStyle(
            color: isWinner ? color : Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (isWinner)
          Icon(Icons.check_circle_rounded, color: color, size: 14),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seat glow helper — used by _LiveSeatBubble to tint PK team seats.
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the team color for [userId] in [session], or null if not assigned.
Color? pkSeatTeamColor(String userId, PkSession? session) {
  if (session == null || !session.isActive) return null;
  final member = session.members
      .where((m) => m.userId == userId)
      .firstOrNull;
  if (member == null) return null;
  return pkTeamColor(member.team);
}

// Spinner widget used in PK loading states.
class PkSpinner extends StatelessWidget {
  const PkSpinner({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF8B26D9),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing ring animation for the leading team indicator on seat.
// ─────────────────────────────────────────────────────────────────────────────

class PkPulseRing extends StatefulWidget {
  const PkPulseRing({required this.color, required this.radius, super.key});
  final Color color;
  final double radius;

  @override
  State<PkPulseRing> createState() => _PkPulseRingState();
}

class _PkPulseRingState extends State<PkPulseRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _scale = Tween<double>(begin: 1.0, end: 1.5)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 0.6, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (context2, child) => Container(
          width: widget.radius * 2 * _scale.value,
          height: widget.radius * 2 * _scale.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withValues(alpha: _opacity.value),
              width: 2,
            ),
          ),
        ),
      );
}

// ignore: unused_element
double _clamp(double v, double lo, double hi) => math.min(math.max(v, lo), hi);
