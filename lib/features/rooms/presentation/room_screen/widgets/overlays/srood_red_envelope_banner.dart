/// Lucky Bag (red envelope) claim banner with live countdown, claim progress,
/// and super-bag styling. Claim/dismiss actions are owned by the screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/srood_room_theme.dart';

class SroodRedEnvelopeBanner extends StatefulWidget {
  const SroodRedEnvelopeBanner({
    required this.envelope,
    required this.isArabic,
    required this.loading,
    required this.isSender,
    required this.onClaim,
    required this.onDismiss,
    super.key,
  });

  final Map<String, dynamic> envelope;
  final bool isArabic;
  final bool loading;
  final bool isSender;
  final VoidCallback onClaim;
  final VoidCallback onDismiss;

  @override
  State<SroodRedEnvelopeBanner> createState() => _SroodRedEnvelopeBannerState();
}

class _SroodRedEnvelopeBannerState extends State<SroodRedEnvelopeBanner> {
  Timer? _countdownTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _initCountdown();
  }

  @override
  void didUpdateWidget(SroodRedEnvelopeBanner old) {
    super.didUpdateWidget(old);
    if (old.envelope['id'] != widget.envelope['id'] ||
        old.envelope['expires_at'] != widget.envelope['expires_at']) {
      _initCountdown();
    }
  }

  void _initCountdown() {
    _countdownTimer?.cancel();
    final expiresAtStr = widget.envelope['expires_at'] as String?;
    if (expiresAtStr == null) return;
    final expiresAt = DateTime.tryParse(expiresAtStr);
    if (expiresAt == null) return;
    _secondsLeft = expiresAt
        .difference(DateTime.now().toUtc())
        .inSeconds
        .clamp(0, 9999);
    if (_secondsLeft <= 0) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, 9999));
      if (_secondsLeft <= 0) _countdownTimer?.cancel();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final envelope = widget.envelope;
    final isArabic = widget.isArabic;
    final total = envelope['total_coins'] as int? ?? 0;
    final count = envelope['envelope_count'] as int? ?? 1;
    final claimed = envelope['claimed_count'] as int? ?? 0;
    final isSuper = envelope['is_super'] == true;
    final remaining = count - claimed;
    final progress = count > 0 ? claimed / count : 0.0;

    final mins = _secondsLeft ~/ 60;
    final secs = _secondsLeft % 60;
    final countdownStr = _secondsLeft > 0
        ? (mins > 0 ? '$mins:${secs.toString().padLeft(2, '0')}' : '${secs}s')
        : '';

    final titleText = isSuper
        ? (isArabic ? '🔥 حقيبة الحظ الكبرى!' : '🔥 Super Lucky Bag!')
        : (isArabic ? '🎁 حقيبة الحظ!' : '🎁 Lucky Bag!');

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSuper
                ? const [
                    Color(0xFF7A0000),
                    Color(0xFFBF3510),
                    Color(0xFF7A0000),
                  ]
                : const [
                    Color(0xFF7A0000),
                    Color(0xFFBF1B0B),
                    Color(0xFF7A0000),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(SroodRoomDims.radiusXl - 2),
          border: Border.all(
            color: const Color(
              0xFFFFD700,
            ).withValues(alpha: isSuper ? 0.65 : 0.45),
            width: isSuper ? 2.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  (isSuper ? const Color(0xFFFF6B00) : const Color(0xFFE63946))
                      .withValues(alpha: 0.5),
              blurRadius: 24,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(alpha: 0.18),
              blurRadius: 10,
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SroodRoomDims.radiusXl - 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main row
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    _BannerBagIcon(isSuper: isSuper),
                    const SizedBox(width: 10),

                    // Text block
                    Expanded(
                      child: Column(
                        crossAxisAlignment: isArabic
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleText,
                            style: TextStyle(
                              color: isSuper
                                  ? const Color(0xFFFFBB40)
                                  : const Color(0xFFFFD700),
                              fontWeight: FontWeight.w900,
                              fontSize: SroodRoomDims.textMd,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isArabic
                                    ? '$total عملة · $remaining متبقية'
                                    : '$total coins · $remaining left',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: SroodRoomDims.textSm,
                                ),
                              ),
                              if (countdownStr.isNotEmpty) ...[
                                const SizedBox(width: SroodRoomDims.space6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '⏱ $countdownStr',
                                    style: TextStyle(
                                      color: _secondsLeft <= 10
                                          ? const Color(0xFFFF6B6B)
                                          : Colors.white.withValues(
                                              alpha: 0.75,
                                            ),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: SroodRoomDims.space8),

                    // Claim button (everyone can tap — including sender)
                    if (widget.loading)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFFFFD700),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: widget.onClaim,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isSuper
                                  ? const [
                                      Color(0xFFFF8C00),
                                      Color(0xFFD4380D),
                                    ]
                                  : const [
                                      Color(0xFFFFE066),
                                      Color(0xFFC8850A),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(
                              SroodRoomDims.radiusMd,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFFFD700,
                                ).withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            isArabic ? 'افتح' : 'Open',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: SroodRoomDims.textMd,
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(width: SroodRoomDims.space8),
                    // Dismiss
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),

              // Progress bar (claims consumed)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isSuper
                              ? const Color(0xFFFF8C00)
                              : const Color(0xFFFFD700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isArabic
                          ? '$claimed / $count فتحة'
                          : '$claimed / $count claimed',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: SroodRoomDims.textXs,
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

// Animated pulsing bag icon for the banner.
class _BannerBagIcon extends StatefulWidget {
  const _BannerBagIcon({required this.isSuper});

  final bool isSuper;

  @override
  State<_BannerBagIcon> createState() => _BannerBagIconState();
}

class _BannerBagIconState extends State<_BannerBagIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween(
      begin: 0.88,
      end: 1.0,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Transform.scale(
        scale: _pulse.value,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: widget.isSuper
                  ? const [Color(0xFFFF8C00), Color(0xFF8B2500)]
                  : const [Color(0xFFFFE066), Color(0xFFC8850A)],
              radius: 0.72,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (widget.isSuper
                            ? const Color(0xFFFF6B00)
                            : const Color(0xFFFFD700))
                        .withValues(alpha: 0.5 * _pulse.value),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.card_giftcard_rounded,
              size: 26,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
