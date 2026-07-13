/// Compact coin-support pill shown under a seat (gift support total) and in
/// the participants sheet.
library;

import 'package:flutter/material.dart';

import '../../../theme/srood_room_theme.dart';

class SroodSupportPill extends StatelessWidget {
  const SroodSupportPill({
    required this.amount,
    this.compact = true,
    super.key,
  });

  final int amount;
  final bool compact;

  String get _label {
    if (amount >= 1000000) {
      final v = amount / 1000000;
      return '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      final v = amount / 1000;
      return '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)}k';
    }
    return amount.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B1A45), SroodRoomColors.bg],
        ),
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusPill),
        border: Border.all(
          color: const Color(0xFFD4A017).withValues(alpha: 0.70),
          width: 0.8,
        ),
        boxShadow: SroodRoomDecor.glow(SroodRoomColors.gold, opacity: 0.32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monetization_on_rounded,
            color: const Color(0xFFFFD700),
            size: compact ? 10 : 12,
          ),
          SizedBox(width: compact ? 2 : 3),
          Text(
            _label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFFFFE566),
              fontWeight: FontWeight.w800,
              fontSize: compact ? 9 : 10,
            ),
          ),
        ],
      ),
    );
  }
}
