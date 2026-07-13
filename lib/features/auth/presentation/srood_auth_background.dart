/// Login backdrop: the premium brand image dimmed behind the form with a
/// vertical scrim so text and fields always win the contrast fight.
library;

import 'package:flutter/material.dart';

class SroodAuthBackground extends StatelessWidget {
  const SroodAuthBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/login_bg.webp',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF12061F)),
        ),
        // Stronger, form-first scrim: darkest where the card sits.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.40),
                Colors.black.withValues(alpha: 0.72),
              ],
              stops: const [0.0, 0.35, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}
