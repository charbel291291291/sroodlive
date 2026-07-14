import 'package:flutter/material.dart';

class CrashV3ResultOverlay extends StatelessWidget {
  const CrashV3ResultOverlay({required this.multiplier, super.key});
  final double multiplier;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xE6260B35),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFFF557D), width: 2),
        ),
        child: Text(
          'CRASHED\n${multiplier.toStringAsFixed(2)}×',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ),
  );
}
