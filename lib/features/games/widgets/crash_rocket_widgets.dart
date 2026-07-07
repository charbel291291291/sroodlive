import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/widgets/coin_ui.dart';
import '../models/crash_rocket_models.dart';

const rocketGold = Color(0xFFF4C95D);
const rocketBlue = Color(0xFF28C7FA);
const rocketInk = Color(0xFF060711);

Color rocketResultColor(double multiplier) {
  if (multiplier < 2) return const Color(0xFF42A5FF);
  if (multiplier < 5) return const Color(0xFF45D483);
  if (multiplier < 10) return const Color(0xFFFF5A6F);
  return const Color(0xFFFFCC55);
}

class SroodRocketScene extends StatelessWidget {
  const SroodRocketScene({
    required this.phase,
    required this.multiplier,
    required this.countdown,
    super.key,
  });

  final SroodRocketPhase phase;
  final double multiplier;
  final int countdown;

  @override
  Widget build(BuildContext context) {
    final flying = phase == SroodRocketPhase.flying;
    final crashed =
        phase == SroodRocketPhase.crashed || phase == SroodRocketPhase.settled;
    return CustomPaint(
      painter: _SpacePainter(
        progress: flying ? (multiplier / 12).clamp(0, 1) : 0,
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            left: flying ? 0 : 36,
            right: flying ? 28 : 36,
            bottom: flying ? 62 : 34,
            top: flying ? 22 : 64,
            child: crashed
                ? const Center(
                    child: Icon(
                      Icons.brightness_1,
                      color: Color(0xFFFF5C71),
                      size: 72,
                    ),
                  )
                : const CustomPaint(painter: _RocketPainter()),
          ),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: rocketBlue.withValues(alpha: 0.25)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  phase == SroodRocketPhase.bettingOpen
                      ? '$countdown'
                      : crashed
                      ? 'CRASHED  ${multiplier.toStringAsFixed(2)}x'
                      : '${multiplier.toStringAsFixed(2)}x',
                  style: TextStyle(
                    color: crashed ? const Color(0xFFFF7183) : Colors.white,
                    fontSize: crashed ? 25 : 34,
                    fontWeight: FontWeight.w900,
                    shadows: const [Shadow(color: rocketBlue, blurRadius: 14)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SroodRocketBetPanel extends StatelessWidget {
  const SroodRocketBetPanel({
    required this.slot,
    required this.amount,
    required this.autoCashout,
    required this.phase,
    required this.bet,
    required this.busy,
    required this.currentMultiplier,
    required this.onAmountDown,
    required this.onAmountUp,
    required this.onAmountSelected,
    required this.onAutoChanged,
    required this.onAction,
    this.compact = false,
    super.key,
  });

  final int slot;
  final int amount;
  final double autoCashout;
  final SroodRocketPhase phase;
  final SroodRocketBet? bet;
  final bool busy;
  final double currentMultiplier;
  final VoidCallback onAmountDown;
  final VoidCallback onAmountUp;
  final ValueChanged<int> onAmountSelected;
  final ValueChanged<double> onAutoChanged;
  final VoidCallback onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final canCashout =
        phase == SroodRocketPhase.flying && bet?.status == 'placed';
    final canBet = phase == SroodRocketPhase.bettingOpen && bet == null;
    final label = canCashout
        ? 'CASH OUT  ${currentMultiplier.toStringAsFixed(2)}x'
        : bet != null
        ? _statusLabel(bet!.status)
        : phase == SroodRocketPhase.bettingOpen
        ? 'PLACE BET'
        : 'BETTING CLOSED';
    final accent = canCashout ? rocketGold : rocketBlue;
    if (compact) {
      return _buildCompact(
        canBet: canBet,
        canCashout: canCashout,
        label: label,
        accent: accent,
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171D34), Color(0xFF090D1D)],
        ),
        border: Border.all(
          color: accent.withValues(alpha: canCashout ? 0.85 : 0.38),
          width: canCashout ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: canCashout ? 0.2 : 0.08),
            blurRadius: canCashout ? 20 : 12,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Text(
                  '$slot',
                  style: TextStyle(
                    color: accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BET $slot',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'COINS',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _StatusPill(
                label:
                    bet?.status.replaceAll('_', ' ').toUpperCase() ??
                    (canBet ? 'READY' : phase.name.toUpperCase()),
                color: bet?.status == 'cashed_out'
                    ? const Color(0xFF56E6A5)
                    : accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  onTap: canBet ? onAmountDown : null,
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: CoinAmountText(amount: amount, fontSize: 22),
                  ),
                ),
                _StepButton(
                  icon: Icons.add_rounded,
                  onTap: canBet ? onAmountUp : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              for (final preset in const [100, 1000, 10000, 100000])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _PresetButton(
                      amount: preset,
                      selected: amount == preset,
                      enabled: canBet,
                      onTap: () => onAmountSelected(preset),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: rocketGold, size: 17),
              const SizedBox(width: 5),
              const Text(
                'AUTO CASHOUT',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              _MiniStep(
                icon: Icons.remove,
                onTap: canBet
                    ? () => onAutoChanged(
                        (autoCashout - 0.1).clamp(1.1, 10).toDouble(),
                      )
                    : null,
              ),
              SizedBox(
                width: 58,
                child: Text(
                  '${autoCashout.toStringAsFixed(2)}x',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: rocketGold,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              _MiniStep(
                icon: Icons.add,
                onTap: canBet
                    ? () => onAutoChanged(
                        (autoCashout + 0.1).clamp(1.1, 10).toDouble(),
                      )
                    : null,
              ),
            ],
          ),
          Slider(
            min: 1.1,
            max: 10,
            divisions: 89,
            value: autoCashout.clamp(1.1, 10),
            onChanged: canBet ? onAutoChanged : null,
            activeColor: rocketGold,
            inactiveColor: Colors.white12,
          ),
          const SizedBox(height: 2),
          _RocketActionButton(
            label: label,
            enabled: !busy && (canBet || canCashout),
            busy: busy,
            cashout: canCashout,
            onTap: onAction,
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'cashed_out' => 'CASHED OUT',
    'lost' => 'ROUND LOST',
    'refunded' => 'REFUNDED',
    _ => 'BET PLACED',
  };

  Widget _buildCompact({
    required bool canBet,
    required bool canCashout,
    required String label,
    required Color accent,
  }) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF151C34), Color(0xFF080C1B)],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: accent.withValues(alpha: canCashout ? 0.85 : 0.38),
      ),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: canCashout ? 0.18 : 0.06),
          blurRadius: 14,
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'BET $slot',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            _StatusPill(
              label:
                  bet?.status.replaceAll('_', ' ').toUpperCase() ??
                  (canBet ? 'READY' : phase.name.toUpperCase()),
              color: bet?.status == 'cashed_out'
                  ? const Color(0xFF56E6A5)
                  : accent,
              compact: true,
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _StepButton(
                icon: Icons.remove_rounded,
                onTap: canBet ? onAmountDown : null,
                compact: true,
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: CoinAmountText(amount: amount, fontSize: 17),
                ),
              ),
              _StepButton(
                icon: Icons.add_rounded,
                onTap: canBet ? onAmountUp : null,
                compact: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final preset in const [100, 1000, 10000, 100000])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: _PresetButton(
                    amount: preset,
                    selected: amount == preset,
                    enabled: canBet,
                    compact: true,
                    onTap: () => onAmountSelected(preset),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.bolt_rounded, color: accent, size: 14),
            const SizedBox(width: 2),
            _MiniStep(
              icon: Icons.remove,
              onTap: canBet
                  ? () => onAutoChanged(
                      (autoCashout - 0.1).clamp(1.1, 10).toDouble(),
                    )
                  : null,
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'AUTO ${autoCashout.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    color: rocketGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            _MiniStep(
              icon: Icons.add,
              onTap: canBet
                  ? () => onAutoChanged(
                      (autoCashout + 0.1).clamp(1.1, 10).toDouble(),
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 7),
        _RocketActionButton(
          label: label,
          enabled: !busy && (canBet || canCashout),
          busy: busy,
          cashout: canCashout,
          compact: true,
          onTap: onAction,
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    this.compact = false,
  });
  final String label;
  final Color color;
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 5 : 9,
      vertical: compact ? 3 : 5,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: compact ? 7 : 9,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    this.compact = false,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: icon == Icons.add_rounded ? 'Increase bet' : 'Decrease bet',
    onPressed: onTap,
    padding: EdgeInsets.zero,
    constraints: BoxConstraints.tightFor(
      width: compact ? 34 : 48,
      height: compact ? 40 : 48,
    ),
    icon: Icon(icon, size: compact ? 18 : 21),
    color: rocketBlue,
    disabledColor: Colors.white24,
  );
}

class _MiniStep extends StatelessWidget {
  const _MiniStep({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 29,
    child: IconButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.06),
      ),
    ),
  );
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.amount,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.compact = false,
  });
  final int amount;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? rocketBlue.withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.045),
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: compact ? 25 : 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? rocketBlue.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          formatCoinAmount(amount),
          maxLines: 1,
          style: TextStyle(
            color: enabled ? Colors.white70 : Colors.white24,
            fontSize: compact ? 8 : 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}

class _RocketActionButton extends StatelessWidget {
  const _RocketActionButton({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.cashout,
    required this.onTap,
    this.compact = false,
  });
  final String label;
  final bool enabled;
  final bool busy;
  final bool cashout;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final colors = cashout
        ? const [Color(0xFFFFE07A), Color(0xFFE69A22)]
        : const [Color(0xFF53DAFF), Color(0xFF1686E8)];
    return Opacity(
      opacity: enabled || busy ? 1 : 0.38,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: compact ? 42 : 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(14),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: colors.first.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: rocketInk,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          cashout
                              ? Icons.savings_rounded
                              : Icons.rocket_launch_rounded,
                          color: rocketInk,
                          size: compact ? 15 : 19,
                        ),
                        SizedBox(width: compact ? 4 : 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 190),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: rocketInk,
                              fontSize: compact ? 10 : 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpacePainter extends CustomPainter {
  const _SpacePainter({required this.progress});
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = rocketInk);
    final random = math.Random(77);
    for (var i = 0; i < 42; i++) {
      final p = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawCircle(
        p,
        random.nextDouble() * 1.4 + 0.4,
        Paint()
          ..color = Colors.white.withValues(
            alpha: 0.25 + random.nextDouble() * 0.6,
          ),
      );
    }
    final path = Path()
      ..moveTo(12, size.height - 20)
      ..quadraticBezierTo(
        size.width * .48,
        size.height * .8,
        size.width - 25,
        22,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = rocketBlue.withValues(alpha: .28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpacePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _RocketPainter extends CustomPainter {
  const _RocketPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .57, size.height * .52);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.62);
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-34, -11, 68, 22),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Color(0xFFB6DFF0), rocketBlue],
        ).createShader(body.outerRect),
    );
    canvas.drawPath(
      Path()
        ..moveTo(34, -11)
        ..lineTo(52, 0)
        ..lineTo(34, 11)
        ..close(),
      Paint()..color = rocketGold,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-26, 10)
        ..lineTo(-38, 25)
        ..lineTo(-5, 11)
        ..close(),
      Paint()..color = rocketBlue,
    );
    canvas.drawCircle(const Offset(9, 0), 6, Paint()..color = rocketInk);
    canvas.drawCircle(const Offset(9, 0), 4, Paint()..color = rocketBlue);
    canvas.drawPath(
      Path()
        ..moveTo(-34, -6)
        ..lineTo(-58, 0)
        ..lineTo(-34, 6)
        ..close(),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFF465F), rocketGold, Colors.transparent],
        ).createShader(const Rect.fromLTWH(-60, -8, 28, 16)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
