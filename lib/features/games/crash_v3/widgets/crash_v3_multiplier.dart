import 'package:flutter/material.dart';

class CrashV3Multiplier extends StatelessWidget {
  const CrashV3Multiplier({
    required this.value,
    required this.status,
    super.key,
  });
  final double value;
  final String status;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '${value.toStringAsFixed(2)}×',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 48,
          fontWeight: FontWeight.w900,
          letterSpacing: -2,
        ),
      ),
      Text(
        status.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFE879F9),
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
    ],
  );
}
