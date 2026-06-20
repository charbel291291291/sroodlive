import 'package:flutter/material.dart';
import '../models/wealth_models.dart';

// Compact inline badge showing tier color + level number.
// Use anywhere a quick wealth indicator is needed (profile, room list, chat).
class WealthBadgeWidget extends StatelessWidget {
  const WealthBadgeWidget({
    required this.wealthLevel,
    required this.tierNumber,
    this.size = WealthBadgeSize.small,
    super.key,
  });

  final int wealthLevel;
  final int tierNumber;
  final WealthBadgeSize size;

  @override
  Widget build(BuildContext context) {
    if (wealthLevel <= 0) return const SizedBox.shrink();

    final tier = WealthTier.fromNumber(tierNumber.clamp(1, 10));
    final color = tier.color;

    final double fontSize;
    final double padH;
    final double padV;
    final double borderRadius;

    switch (size) {
      case WealthBadgeSize.small:
        fontSize = 10; padH = 5; padV = 2; borderRadius = 6;
      case WealthBadgeSize.medium:
        fontSize = 12; padH = 7; padV = 3; borderRadius = 8;
      case WealthBadgeSize.large:
        fontSize = 14; padH = 10; padV = 4; borderRadius = 10;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tier.displayName[0], // single letter: B, S, G, E, Sa, R, D, M, Ro, L
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize * 0.9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          SizedBox(width: padH * 0.3),
          Text(
            '$wealthLevel',
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

enum WealthBadgeSize { small, medium, large }

// Larger badge card for profile hero / Wealth Center header.
class WealthTierBadgeCard extends StatelessWidget {
  const WealthTierBadgeCard({
    required this.wealth,
    super.key,
  });

  final UserWealth wealth;

  @override
  Widget build(BuildContext context) {
    final tier = wealth.tier;
    final color = tier.color;

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.30),
            color.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.9), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.50),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            tier.icon,
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(height: 2),
          Text(
            'LV ${wealth.wealthLevel}',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
