import 'package:flutter/material.dart';

import '../../wealth/models/wealth_models.dart';

Color _bLighten(Color c, [double t = 0.55]) => Color.lerp(c, Colors.white, t)!;
Color _bDarken(Color c, [double t = 0.42]) => Color.lerp(c, Colors.black, t)!;

/// Premium tier badge used in My Level screen (hero card + table) and
/// anywhere Charm/Wealth levels are displayed.
///
/// Visual: glossy horizontal pill with a metallic gem circle on the left and
/// the [level] number on the right. Tier color and icon are derived
/// automatically from [level] unless [tier] is supplied as an override
/// (useful when the table row's display tier differs from the level's
/// computed tier).
class LevelFrameBadge extends StatelessWidget {
  const LevelFrameBadge({
    required this.level,
    required this.size,
    this.tier,
    this.showNumber = true,
    super.key,
  });

  /// The level number to display (1–100).
  final int level;

  /// Visual height of the badge; width scales proportionally.
  final double size;

  /// Optional tier override for color/icon. When null, derived from [level].
  final WealthTier? tier;

  /// Whether the level number is shown to the right of the gem circle.
  final bool showNumber;

  @override
  Widget build(BuildContext context) {
    final t = tier ?? WealthTier.fromLevel(level.clamp(1, 100));
    final c = t.color;
    final light = _bLighten(c);
    final dark = _bDarken(c);

    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: showNumber ? size * 1.60 : size),
      padding: showNumber
          ? EdgeInsets.fromLTRB(size * 0.10, 0, size * 0.24, 0)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, c, dark],
          stops: const [0.0, 0.50, 1.0],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.65),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.55), blurRadius: size * 0.32),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: size * 0.12,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Top-edge gloss shine
          if (showNumber)
            Positioned(
              top: size * 0.06,
              left: size * 0.20,
              right: size * 0.20,
              child: Container(
                height: size * 0.26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.52),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Gem circle with tier icon
              Container(
                width: size * 0.68,
                height: size * 0.68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.white, light, dark],
                    stops: const [0.0, 0.40, 1.0],
                    center: const Alignment(-0.30, -0.38),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.82),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.withValues(alpha: 0.70),
                      blurRadius: size * 0.18,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    t.icon,
                    style: TextStyle(
                      fontSize: size * 0.37,
                      // Prevent emoji from inheriting decoration
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              if (showNumber) ...[
                SizedBox(width: size * 0.11),
                Text(
                  '$level',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.44,
                    height: 1.0,
                    decoration: TextDecoration.none,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 2),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
