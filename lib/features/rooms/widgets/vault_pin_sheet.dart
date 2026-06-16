import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A bottom sheet presenting a 4-digit PIN entry with a vault/gold theme.
/// Shows a "vault door" icon at the top and a numeric keypad below.
///
/// Returns the entered 4-digit PIN string via [Navigator.pop], or null if
/// the user cancelled.
///
/// Usage:
/// ```dart
/// final pin = await showVaultPinSheet(context, title: 'Close Room');
/// if (pin != null) { /* proceed */ }
/// ```
Future<String?> showVaultPinSheet(
  BuildContext context, {
  String? title,
  String? subtitle,
  bool requirePin = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => VaultPinSheet(
      title: title,
      subtitle: subtitle,
      requirePin: requirePin,
    ),
  );
}

class VaultPinSheet extends StatefulWidget {
  const VaultPinSheet({
    super.key,
    this.title,
    this.subtitle,
    this.requirePin = false,
  });

  final String? title;
  final String? subtitle;
  /// If true, the confirm button only activates once 4 digits are entered.
  final bool requirePin;

  @override
  State<VaultPinSheet> createState() => _VaultPinSheetState();
}

class _VaultPinSheetState extends State<VaultPinSheet>
    with SingleTickerProviderStateMixin {
  final List<String> _digits = [];
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onKey(String digit) {
    if (_digits.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _digits.add(digit));
  }

  void _onDelete() {
    if (_digits.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _digits.removeLast());
  }

  void _onConfirm() {
    if (widget.requirePin && _digits.length < 4) {
      _shakeCtrl.forward(from: 0);
      HapticFeedback.heavyImpact();
      return;
    }
    final pin = _digits.isEmpty ? null : _digits.join();
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E0755), Color(0xFF120430)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 20,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Vault icon
          _VaultIcon(),
          const SizedBox(height: 16),

          // Title
          Text(
            widget.title ?? 'Enter PIN',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 24),

          // PIN dots
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(sin(_shakeAnim.value * pi * 6) * 8, 0),
              child: child,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _digits.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? const Color(0xFFFFD700)
                        : Colors.transparent,
                    border: Border.all(
                      color: filled
                          ? const Color(0xFFFFD700)
                          : Colors.white.withValues(alpha: 0.35),
                      width: 2,
                    ),
                    boxShadow: filled
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                              blurRadius: 8,
                            )
                          ]
                        : null,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 28),

          // Numpad
          _Numpad(onKey: _onKey, onDelete: _onDelete),
          const SizedBox(height: 20),

          // Confirm + Cancel buttons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B26D9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Numpad extends StatelessWidget {
  const _Numpad({required this.onKey, required this.onDelete});

  final void Function(String) onKey;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(
      children: [
        ...keys.map(
          (row) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((d) => _NumKey(label: d, onTap: () => onKey(d))).toList(),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 88), // empty left slot
            _NumKey(label: '0', onTap: () => onKey('0')),
            SizedBox(
              width: 88,
              height: 72,
              child: Center(
                child: IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.backspace_outlined, color: Colors.white70, size: 22),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NumKey extends StatelessWidget {
  const _NumKey({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 72,
      child: Center(
        child: Material(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              width: 64,
              height: 56,
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultIcon extends StatefulWidget {
  @override
  State<_VaultIcon> createState() => _VaultIconState();
}

class _VaultIconState extends State<_VaultIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _rotate = Tween<double>(begin: 0, end: 2 * pi).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer ring
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFFFD700).withValues(alpha: 0.35),
              width: 2,
            ),
          ),
        ),
        // Inner vault door
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF3D1A7A), Color(0xFF1E0755)],
            ),
            border: Border.all(
              color: const Color(0xFFFFD700).withValues(alpha: 0.65),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                blurRadius: 16,
              ),
            ],
          ),
          child: const Icon(
            Icons.lock_rounded,
            color: Color(0xFFFFD700),
            size: 28,
          ),
        ),
        // Rotating tick marks
        AnimatedBuilder(
          animation: _rotate,
          builder: (_, child) => Transform.rotate(
            angle: _rotate.value,
            child: SizedBox(
              width: 80,
              height: 80,
              child: CustomPaint(painter: _DialPainter()),
            ),
          ),
        ),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    for (int i = 0; i < 8; i++) {
      final angle = (i * pi / 4);
      final from = Offset(
        center.dx + (r - 8) * cos(angle),
        center.dy + (r - 8) * sin(angle),
      );
      final to = Offset(
        center.dx + r * cos(angle),
        center.dy + r * sin(angle),
      );
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
