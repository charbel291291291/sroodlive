/// Gift artwork tile — local asset or network image over a dark jewel
/// backdrop, with the gift's material icon as fallback.
library;

import 'package:flutter/material.dart';

import '../../../../models/room_gift.dart';
import '../../../theme/srood_room_theme.dart';

class SroodGiftArtwork extends StatelessWidget {
  const SroodGiftArtwork({required this.gift, required this.size, super.key});

  final RoomGift gift;
  final double size;

  @override
  Widget build(BuildContext context) {
    final localPath = gift.localAssetPath;

    Widget imageWidget;
    if (localPath != null) {
      imageWidget = Image.asset(
        localPath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          gift.materialIcon,
          color: SroodRoomColors.gold,
          size: size * 0.56,
        ),
      );
    } else {
      imageWidget = Image.network(
        gift.imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          gift.materialIcon,
          color: SroodRoomColors.gold,
          size: size * 0.56,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd + 2),
        gradient: const RadialGradient(
          colors: [Color(0xFF2B0B3E), Color(0xFF12091D), Color(0xFF06030A)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD10DFF).withValues(alpha: 0.20),
            blurRadius: 16,
          ),
        ],
      ),
      child: imageWidget,
    );
  }
}
