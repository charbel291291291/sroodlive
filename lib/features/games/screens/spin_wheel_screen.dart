import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';

class SpinWheelScreen extends StatefulWidget {
  const SpinWheelScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<SpinWheelScreen> createState() => _SpinWheelScreenState();
}

class _SpinPrize {
  final String label;
  final String emoji;
  final Color color;
  final int weight; // relative probability weight

  const _SpinPrize({
    required this.label,
    required this.emoji,
    required this.color,
    required this.weight,
  });
}

const _kSpinCost = 50; // coins per spin

final _kPrizes = <_SpinPrize>[
  _SpinPrize(
    label: '10 coins',
    emoji: '🪙',
    color: Color(0xFF4A3470),
    weight: 30,
  ),
  _SpinPrize(
    label: '50 coins',
    emoji: '🪙',
    color: Color(0xFF6B3A9E),
    weight: 25,
  ),
  _SpinPrize(
    label: '5 diamonds',
    emoji: '💎',
    color: Color(0xFF1A3A55),
    weight: 20,
  ),
  _SpinPrize(
    label: '100 coins',
    emoji: '🪙',
    color: Color(0xFF8B26D9),
    weight: 12,
  ),
  _SpinPrize(
    label: '20 diamonds',
    emoji: '💎',
    color: Color(0xFF1A4A6A),
    weight: 7,
  ),
  _SpinPrize(
    label: '500 coins',
    emoji: '🎉',
    color: Color(0xFF3A1250),
    weight: 4,
  ),
  _SpinPrize(
    label: 'Try again',
    emoji: '🔄',
    color: Color(0xFF2A1A40),
    weight: 15,
  ),
  _SpinPrize(
    label: '1000 coins',
    emoji: '👑',
    color: Color(0xFFF0C15A),
    weight: 2,
  ),
];

class _SpinWheelScreenState extends State<SpinWheelScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _rotationAnim;

  bool _spinning = false;
  bool _loadingWallet = true;
  int _coins = 0;
  int? _lastPrizeIndex;
  double _currentAngle = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _spinning = false;
          _currentAngle = _rotationAnim.value % (2 * math.pi);
        });
      }
    });
    _loadWallet();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    setState(() => _loadingWallet = true);
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null) {
        setState(() => _loadingWallet = false);
        return;
      }

      final data = await SupabaseService.requiredClient
          .from('wallets')
          .select('coins_balance')
          .eq('user_id', me)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _coins = data?['coins_balance'] as int? ?? 0;
        _loadingWallet = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingWallet = false);
    }
  }

  Future<void> _spin() async {
    if (_spinning || _coins < _kSpinCost) return;
    setState(() {
      _spinning = true;
      _lastPrizeIndex = null;
    });

    try {
      // Call the RPC — backend handles deduction + prize calculation
      final result = await SupabaseService.requiredClient
          .rpc('spin_wheel')
          .single();

      final prizeLabel = result['prize_label'] as String? ?? 'Try again';
      final newBalance =
          result['new_coins_balance'] as int? ?? (_coins - _kSpinCost);

      // Find matching prize index for animation target
      int targetIndex = _kPrizes.indexWhere((p) => p.label == prizeLabel);
      if (targetIndex < 0) {
        targetIndex = _kPrizes.indexWhere((p) => p.label == 'Try again');
      }
      if (targetIndex < 0) targetIndex = 0;

      _animateTo(targetIndex);

      setState(() {
        _coins = newBalance;
        _lastPrizeIndex = targetIndex;
      });
    } catch (_) {
      // Fallback: local spin (display only, no real prize — backend failed)
      final targetIndex = _localSpin();
      _animateTo(targetIndex);
      setState(() {
        _coins -= _kSpinCost;
        _lastPrizeIndex = targetIndex;
      });
    }
  }

  int _localSpin() {
    final total = _kPrizes.fold(0, (s, p) => s + p.weight);
    int r = math.Random().nextInt(total);
    for (int i = 0; i < _kPrizes.length; i++) {
      r -= _kPrizes[i].weight;
      if (r < 0) return i;
    }
    return 0;
  }

  void _animateTo(int prizeIndex) {
    final segmentAngle = (2 * math.pi) / _kPrizes.length;
    // The pointer is at top (0). Segment center for prizeIndex:
    final targetSegmentCenter = prizeIndex * segmentAngle + segmentAngle / 2;
    // We want that center to end at the top (0), so we need to rotate by (2π - targetSegmentCenter)
    final targetAngle =
        _currentAngle +
        (4 * 2 * math.pi) +
        (2 * math.pi - targetSegmentCenter - _currentAngle % (2 * math.pi));

    _rotationAnim = Tween<double>(begin: _currentAngle, end: targetAngle)
        .animate(
          CurvedAnimation(
            parent: _animController,
            curve: Curves.easeInOutCubic,
          ),
        );
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return Scaffold(
      backgroundColor: const Color(0xFF08060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        isArabic
                            ? Icons.arrow_forward_rounded
                            : Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        isArabic ? 'عجلة الحظ' : 'Spin the Wheel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    // Coin balance
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A2A10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFF0C15A).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🪙', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 4),
                          Text(
                            _loadingWallet ? '...' : '$_coins',
                            style: const TextStyle(
                              color: Color(0xFFF0C15A),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Cost label
              Text(
                isArabic
                    ? 'تكلفة الدوران: $_kSpinCost 🪙'
                    : 'Cost per spin: $_kSpinCost 🪙',
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 16),

              // Wheel
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pointer
                      const Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Color(0xFFF0C15A),
                        size: 40,
                      ),
                      const SizedBox(height: 4),
                      // Wheel canvas
                      AnimatedBuilder(
                        animation: _animController,
                        builder: (context, child) {
                          final angle = _animController.isAnimating
                              ? _rotationAnim.value
                              : _currentAngle;
                          return Transform.rotate(angle: angle, child: child);
                        },
                        child: CustomPaint(
                          size: const Size(300, 300),
                          painter: _WheelPainter(prizes: _kPrizes),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Result
                      if (_lastPrizeIndex != null && !_spinning)
                        AnimatedOpacity(
                          opacity: 1,
                          duration: const Duration(milliseconds: 400),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 40),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: _kPrizes[_lastPrizeIndex!].color
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _kPrizes[_lastPrizeIndex!].color,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _kPrizes[_lastPrizeIndex!].emoji,
                                  style: const TextStyle(fontSize: 22),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isArabic
                                      ? 'حصلت على: ${_kPrizes[_lastPrizeIndex!].label}'
                                      : 'You won: ${_kPrizes[_lastPrizeIndex!].label}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Spin button
                      GestureDetector(
                        onTap:
                            (_spinning || _coins < _kSpinCost || _loadingWallet)
                            ? null
                            : _spin,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 180,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: (_spinning || _coins < _kSpinCost)
                                ? null
                                : const LinearGradient(
                                    colors: [
                                      Color(0xFF8B26D9),
                                      Color(0xFF5A1A9E),
                                    ],
                                  ),
                            color: (_spinning || _coins < _kSpinCost)
                                ? const Color(0xFF2A1840)
                                : null,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: (_spinning || _coins < _kSpinCost)
                                ? null
                                : [
                                    const BoxShadow(
                                      color: Color(0x558B26D9),
                                      blurRadius: 16,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Center(
                            child: _spinning
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _coins < _kSpinCost
                                        ? (isArabic
                                              ? 'رصيد غير كافٍ'
                                              : 'Not enough coins')
                                        : (isArabic ? 'ادور!' : 'SPIN!'),
                                    style: TextStyle(
                                      color: _coins < _kSpinCost
                                          ? const Color(0xFF6E5A8A)
                                          : Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wheel painter
// ---------------------------------------------------------------------------

class _WheelPainter extends CustomPainter {
  const _WheelPainter({required this.prizes});
  final List<_SpinPrize> prizes;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final segmentAngle = (2 * math.pi) / prizes.length;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < prizes.length; i++) {
      final startAngle = -math.pi / 2 + i * segmentAngle;

      // Segment fill
      final paint = Paint()..color = prizes[i].color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        paint,
      );

      // Segment border
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        borderPaint,
      );

      // Text
      final midAngle = startAngle + segmentAngle / 2;
      final textRadius = radius * 0.62;
      final textOffset = Offset(
        center.dx + textRadius * math.cos(midAngle),
        center.dy + textRadius * math.sin(midAngle),
      );

      // Emoji
      textPainter.text = TextSpan(
        text: prizes[i].emoji,
        style: const TextStyle(fontSize: 18),
      );
      textPainter.layout();
      canvas.save();
      canvas.translate(textOffset.dx, textOffset.dy);
      canvas.rotate(midAngle + math.pi / 2);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2 - 10),
      );
      canvas.restore();

      // Label
      textPainter.text = TextSpan(
        text: prizes[i].label,
        style: const TextStyle(
          fontSize: 9,
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      );
      textPainter.layout(maxWidth: 60);
      canvas.save();
      canvas.translate(textOffset.dx, textOffset.dy);
      canvas.rotate(midAngle + math.pi / 2);
      textPainter.paint(canvas, Offset(-textPainter.width / 2, 4));
      canvas.restore();
    }

    // Center circle
    canvas.drawCircle(center, 22, Paint()..color = const Color(0xFF0D0618));
    canvas.drawCircle(
      center,
      22,
      Paint()
        ..color = const Color(0xFF8B26D9).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    textPainter.text = const TextSpan(
      text: '✦',
      style: TextStyle(fontSize: 16, color: Color(0xFFF0C15A)),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}
