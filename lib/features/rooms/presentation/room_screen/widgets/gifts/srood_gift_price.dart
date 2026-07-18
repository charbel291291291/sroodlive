/// Shared coin-amount formatting and display for the gift drawer: gift
/// prices, wallet balance, and total cost all go through [formatGiftCoins]
/// so "1.5M" never becomes "2M" and small values never get truncated to a
/// bare "K"/"M".
library;

import 'package:flutter/material.dart';

import '../../../theme/srood_room_theme.dart';

/// Formats a coin amount per the exact rule set:
/// 999 → "999", 1000 → "1K", 1200 → "1.2K", 120000 → "120K",
/// 500000 → "500K", 1000000 → "1M", 1500000 → "1.5M", 2500000 → "2.5M".
///
/// Rounds to at most one decimal place (never to a whole unit — 1.5M must
/// never become 2M) and drops a trailing ".0".
String formatGiftCoins(int coins) {
  if (coins < 0) return '0';
  if (coins < 1000) return coins.toString();

  if (coins < 1000000) {
    return '${_oneDecimal(coins / 1000)}K';
  }

  return '${_oneDecimal(coins / 1000000)}M';
}

String _oneDecimal(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) {
    return rounded.toInt().toString();
  }
  return rounded.toStringAsFixed(1);
}

/// Coin icon + formatted gold price text, the single price presentation
/// used across gift tiles, the footer balance, and the total-cost line.
class SroodGiftPrice extends StatelessWidget {
  const SroodGiftPrice({
    required this.coins,
    this.iconSize = 11,
    this.fontSize = SroodRoomDims.textXs,
    this.color = const Color(0xFFD8CFEA),
    this.fontWeight = FontWeight.w700,
    this.semanticsLabel,
    super.key,
  });

  final int coins;
  final double iconSize;
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monetization_on_rounded,
            color: SroodRoomColors.gold,
            size: iconSize,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              formatGiftCoins(coins),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: fontWeight,
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
