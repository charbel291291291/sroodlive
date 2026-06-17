import 'package:flutter/material.dart';

import '../theme/vip_tier_colors.dart';

class VipTierChip extends StatelessWidget {
  final int level;
  final bool filled;
  final bool compact;

  const VipTierChip({
    super.key,
    required this.level,
    this.filled = true,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final style = VipTierColors.of(level);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        gradient: filled
            ? LinearGradient(
                colors: [style.start, style.end],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
        color: filled ? null : style.start.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? style.border.withValues(alpha: 0.75) : style.border,
          width: 1,
        ),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: style.shadow,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : const [],
      ),
      child: Text(
        style.label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: filled ? style.text : style.border,
          fontSize: compact ? 12 : 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
