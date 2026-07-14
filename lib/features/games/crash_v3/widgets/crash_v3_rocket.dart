import 'package:flutter/material.dart';

class CrashV3Rocket extends StatelessWidget {
  const CrashV3Rocket({required this.progress, super.key});
  final double progress;
  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(24 * progress, -18 * progress),
    child: Transform.rotate(
      angle: -0.55,
      child: const Icon(
        Icons.rocket_launch_rounded,
        size: 54,
        color: Color(0xFFFFC857),
        shadows: [Shadow(color: Color(0xFFEC4899), blurRadius: 20)],
      ),
    ),
  );
}
