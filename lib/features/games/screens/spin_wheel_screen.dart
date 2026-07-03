import 'dart:math' as math;
import 'package:srood_live/shared/utils/error_utils.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/coin_ui.dart';
import '../services/game_sound_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

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
  final Color accent;
  final int weight;

  const _SpinPrize({
    required this.label,
    required this.emoji,
    required this.color,
    required this.accent,
    required this.weight,
  });
}

const _kSpinCost = 50;

final _kPrizes = <_SpinPrize>[
  _SpinPrize(label: '10 coins',      emoji: '🪙', color: Color(0xFF3B2A6E), accent: Color(0xFF7B5EBE), weight: 30),
  _SpinPrize(label: '50 coins',      emoji: '🪙', color: Color(0xFF5A1E8A), accent: Color(0xFFAA60E8), weight: 25),
  _SpinPrize(label: '5 diamonds',    emoji: '💎', color: Color(0xFF133666), accent: Color(0xFF4A8FD4), weight: 20),
  _SpinPrize(label: '100 coins',     emoji: '🪙', color: Color(0xFF7020BF), accent: Color(0xFFC875FF), weight: 12),
  _SpinPrize(label: '20 diamonds',   emoji: '💎', color: Color(0xFF0E3A5A), accent: Color(0xFF3AAFDF), weight: 7),
  _SpinPrize(label: '500 coins',     emoji: '🎉', color: Color(0xFF2E0E44), accent: Color(0xFF9B40CF), weight: 4),
  _SpinPrize(label: 'Try again',     emoji: '🔄', color: Color(0xFF1E1430), accent: Color(0xFF5A4A7A), weight: 15),
  _SpinPrize(label: '1000 coins',    emoji: '👑', color: Color(0xFF7A5500), accent: Color(0xFFF0C15A), weight: 2),
];

class _SpinWheelScreenState extends State<SpinWheelScreen>
    with TickerProviderStateMixin {
  late AnimationController _wheelCtrl;
  late Animation<double> _rotationAnim;
  late AnimationController _resultCtrl;
  late Animation<double> _resultScale;
  late Animation<double> _resultOpacity;

  bool _spinning = false;
  bool _loadingWallet = true;
  int _coins = 0;
  int? _lastPrizeIndex;
  double _currentAngle = 0;
  int? _lastTickSegment;

  final GameSoundService _sounds = GameSoundService(
    tag: 'SpinWheel',
    tickAsset: 'assets/sounds/spin_wheel_tick.mp3',
    tickDebounce: const Duration(milliseconds: 70),
    events: const {
      'spin': GameSound('assets/sounds/spin_wheel_spin.mp3'),
      'result': GameSound('assets/sounds/spin_wheel_result.mp3'),
    },
  );

  @override
  void initState() {
    super.initState();

    _wheelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _wheelCtrl.addListener(() {
      if (!_spinning) return;
      final segmentAngle = (2 * math.pi) / _kPrizes.length;
      final segment = (_rotationAnim.value / segmentAngle).floor();
      if (segment == _lastTickSegment) return;
      _lastTickSegment = segment;
      _sounds.playTick();
    });
    _wheelCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _spinning = false;
          _currentAngle = _rotationAnim.value % (2 * math.pi);
        });
        HapticFeedback.heavyImpact();
        _sounds.playEvent('result');
        _resultCtrl.forward(from: 0);
      }
    });

    _resultCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _resultScale = CurvedAnimation(parent: _resultCtrl, curve: Curves.easeOutBack);
    _resultOpacity = CurvedAnimation(parent: _resultCtrl, curve: Curves.easeIn);

    _sounds.init();
    _loadWallet();
  }

  @override
  void dispose() {
    _wheelCtrl.dispose();
    _resultCtrl.dispose();
    _sounds.dispose();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    setState(() => _loadingWallet = true);
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null) { setState(() => _loadingWallet = false); return; }
      final data = await SupabaseService.requiredClient
          .from('wallets')
          .select('coins_balance')
          .eq('user_id', me)
          .maybeSingle();
      if (!mounted) return;
      setState(() { _coins = data?['coins_balance'] as int? ?? 0; _loadingWallet = false; });
    } catch (e, st) {
      debugError('SpinWheelScreen._loadWallet', e, st);
      if (mounted) setState(() => _loadingWallet = false);
    }
  }

  Future<void> _spin() async {
    if (_spinning || _coins < _kSpinCost) return;
    HapticFeedback.mediumImpact();
    _sounds.playEvent('spin');
    _lastTickSegment = null;
    setState(() { _spinning = true; _lastPrizeIndex = null; });
    _resultCtrl.reset();

    // Per-spin idempotency key: a network retry of the same spin returns the
    // original server result instead of charging/paying twice.
    final spinId =
        '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';

    try {
      final result = await SupabaseService.requiredClient
          .rpc('spin_wheel', params: {'p_client_spin_id': spinId})
          .single();
      if (!mounted) return;
      final prizeLabel = result['prize_label'] as String? ?? 'Try again';
      final newBalance = result['new_coins_balance'] as int? ?? (_coins - _kSpinCost);
      int targetIndex = _kPrizes.indexWhere((p) => p.label == prizeLabel);
      if (targetIndex < 0) targetIndex = _kPrizes.indexWhere((p) => p.label == 'Try again');
      if (targetIndex < 0) targetIndex = 0;
      _animateTo(targetIndex);
      setState(() { _coins = newBalance; _lastPrizeIndex = targetIndex; });
    } catch (e, st) {
      // The spin is decided entirely server-side; never simulate a result or
      // adjust the balance locally when the RPC fails.
      debugError('SpinWheelScreen._spin', e, st);
      if (!mounted) return;
      setState(() => _spinning = false);
      SroodToast.show(
        context,
        widget.isArabic ? 'تعذر الدوران، حاول مجدداً' : 'Spin failed, please try again',
        type: SroodToastType.error,
      );
      _loadWallet();
    }
  }

  void _animateTo(int prizeIndex) {
    final segmentAngle = (2 * math.pi) / _kPrizes.length;
    final targetSegmentCenter = prizeIndex * segmentAngle + segmentAngle / 2;
    final targetAngle =
        _currentAngle +
        (5 * 2 * math.pi) +
        (2 * math.pi - targetSegmentCenter - _currentAngle % (2 * math.pi));

    _rotationAnim = Tween<double>(begin: _currentAngle, end: targetAngle).animate(
      CurvedAnimation(parent: _wheelCtrl, curve: Curves.easeInOutCubic),
    );
    _wheelCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

    return Scaffold(
      backgroundColor: const Color(0xFF08060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF13062A), Color(0xFF07030D)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        isArabic ? 'عجلة الحظ' : 'Spin the Wheel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    CoinBalancePill(amount: _coins, loading: _loadingWallet),
                  ],
                ),
              ),

              // ── Cost label ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  isArabic ? 'تكلفة الدوران: $_kSpinCost 🪙' : 'Cost per spin: $_kSpinCost 🪙',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // ── Wheel area (flexible) ────────────────────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Reserve space for pointer(36) + gap(6) + result(56) + gap(12) + button(52) + gap(8)
                    const reserved = 36 + 6 + 56 + 12 + 52 + 8;
                    final wheelDiameter = (constraints.maxHeight - reserved).clamp(160.0, 340.0);

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Pointer
                        _GoldenPointer(size: 28),
                        const SizedBox(height: 2),

                        // Wheel with outer glow ring
                        _GlowingWheel(
                          diameter: wheelDiameter,
                          prizes: _kPrizes,
                          controller: _wheelCtrl,
                          rotationAnim: () => _animController(context),
                          currentAngle: _currentAngle,
                        ),

                        const SizedBox(height: 12),

                        // Result card
                        SizedBox(
                          height: 56,
                          child: _lastPrizeIndex != null && !_spinning
                              ? ScaleTransition(
                                  scale: _resultScale,
                                  child: FadeTransition(
                                    opacity: _resultOpacity,
                                    child: _ResultCard(
                                      prize: _kPrizes[_lastPrizeIndex!],
                                      isArabic: isArabic,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),

                        const SizedBox(height: 12),

                        // Spin button
                        _SpinButton(
                          spinning: _spinning,
                          canSpin: !_loadingWallet && _coins >= _kSpinCost,
                          isArabic: isArabic,
                          onTap: _spin,
                        ),

                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper: return the correct animation value regardless of state
  double _animController(BuildContext context) {
    if (_wheelCtrl.isAnimating) return _rotationAnim.value;
    return _currentAngle;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _GoldenPointer extends StatelessWidget {
  const _GoldenPointer({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF0C15A),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.60),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(Icons.arrow_drop_down_rounded, color: Colors.black87, size: size * 0.85),
    );
  }
}

class _GlowingWheel extends StatelessWidget {
  const _GlowingWheel({
    required this.diameter,
    required this.prizes,
    required this.controller,
    required this.rotationAnim,
    required this.currentAngle,
  });

  final double diameter;
  final List<_SpinPrize> prizes;
  final AnimationController controller;
  final double Function() rotationAnim;
  final double currentAngle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow
        Container(
          width: diameter + 24,
          height: diameter + 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B26D9).withValues(alpha: 0.40),
                blurRadius: 30,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: const Color(0xFFF0C15A).withValues(alpha: 0.12),
                blurRadius: 50,
                spreadRadius: 6,
              ),
            ],
          ),
        ),
        // Outer decorative ring
        Container(
          width: diameter + 10,
          height: diameter + 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                const Color(0xFFF0C15A).withValues(alpha: 0.80),
                const Color(0xFF8B26D9).withValues(alpha: 0.60),
                const Color(0xFFF0C15A).withValues(alpha: 0.80),
                const Color(0xFF8B26D9).withValues(alpha: 0.60),
                const Color(0xFFF0C15A).withValues(alpha: 0.80),
              ],
            ),
          ),
        ),
        // Wheel
        AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final angle = controller.isAnimating ? rotationAnim() : currentAngle;
            return Transform.rotate(angle: angle, child: child);
          },
          child: CustomPaint(
            size: Size(diameter, diameter),
            painter: _WheelPainter(prizes: prizes),
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.prize, required this.isArabic});
  final _SpinPrize prize;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final isTryAgain = prize.label == 'Try again';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            prize.color.withValues(alpha: 0.85),
            prize.accent.withValues(alpha: 0.25),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: prize.accent.withValues(alpha: 0.70), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: prize.accent.withValues(alpha: 0.30),
            blurRadius: 16,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(prize.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              isTryAgain
                  ? (isArabic ? 'حاول مرة أخرى!' : 'Try again!')
                  : (isArabic
                      ? 'مبروك! حصلت على ${prize.label}'
                      : 'You won: ${prize.label}!'),
              style: TextStyle(
                color: isTryAgain ? Colors.white60 : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpinButton extends StatelessWidget {
  const _SpinButton({
    required this.spinning,
    required this.canSpin,
    required this.isArabic,
    required this.onTap,
  });
  final bool spinning;
  final bool canSpin;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (spinning || !canSpin) ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 180,
        height: 52,
        decoration: BoxDecoration(
          gradient: (spinning || !canSpin)
              ? null
              : const LinearGradient(
                  colors: [Color(0xFFAA40F0), Color(0xFF6010B0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: (spinning || !canSpin) ? const Color(0xFF1E1430) : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: canSpin
                ? const Color(0xFF8B26D9).withValues(alpha: 0.60)
                : Colors.white12,
          ),
          boxShadow: (spinning || !canSpin)
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.50),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Center(
          child: spinning
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Text(
                  !canSpin
                      ? (isArabic ? 'رصيد غير كافٍ' : 'Not enough coins')
                      : (isArabic ? '🎰 ادور!' : '🎰 SPIN!'),
                  style: TextStyle(
                    color: canSpin ? Colors.white : const Color(0xFF5A4A7A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wheel painter
// ─────────────────────────────────────────────────────────────────────────────

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

      // Segment fill with gradient effect (draw two arcs)
      final paint = Paint()..color = prizes[i].color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        paint,
      );

      // Accent highlight near outer edge
      final accentPaint = Paint()
        ..color = prizes[i].accent.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.32
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - radius * 0.16),
        startAngle + 0.04,
        segmentAngle - 0.08,
        false,
        accentPaint,
      );

      // Segment divider
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        borderPaint,
      );

      // Text placement
      final midAngle = startAngle + segmentAngle / 2;
      final textRadius = radius * 0.60;
      final textOffset = Offset(
        center.dx + textRadius * math.cos(midAngle),
        center.dy + textRadius * math.sin(midAngle),
      );

      // Emoji
      textPainter.text = TextSpan(
        text: prizes[i].emoji,
        style: TextStyle(fontSize: radius * 0.12),
      );
      textPainter.layout();
      canvas.save();
      canvas.translate(textOffset.dx, textOffset.dy);
      canvas.rotate(midAngle + math.pi / 2);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2 - radius * 0.06),
      );
      canvas.restore();

      // Label
      textPainter.text = TextSpan(
        text: prizes[i].label,
        style: TextStyle(
          fontSize: (radius * 0.072).clamp(8, 11),
          color: Colors.white,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      );
      textPainter.layout(maxWidth: radius * 0.55);
      canvas.save();
      canvas.translate(textOffset.dx, textOffset.dy);
      canvas.rotate(midAngle + math.pi / 2);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, radius * 0.04),
      );
      canvas.restore();
    }

    // Center jewel
    final centerR = radius * 0.10;
    canvas.drawCircle(
      center,
      centerR + 4,
      Paint()
        ..color = Colors.black
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(center, centerR + 2, Paint()..color = const Color(0xFF1A0B30));
    canvas.drawCircle(
      center,
      centerR + 2,
      Paint()
        ..color = const Color(0xFFF0C15A).withValues(alpha: 0.80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(center, centerR, Paint()..color = const Color(0xFF0D0618));

    textPainter.text = TextSpan(
      text: '✦',
      style: TextStyle(
        fontSize: centerR * 1.2,
        color: const Color(0xFFF0C15A),
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}
