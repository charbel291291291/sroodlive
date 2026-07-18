/// A titled sub-grid of gifts, used to break the VIP category into its four
/// named collections (Country Royals, Lebanese Icons, Royal and Mythic,
/// Classic VIP) instead of one flat list.
library;

import 'package:flutter/material.dart';

import '../../../../models/room_gift.dart';
import '../../../theme/srood_room_theme.dart';
import 'srood_gift_tile.dart';

class SroodGiftSection extends StatelessWidget {
  const SroodGiftSection({
    required this.title,
    required this.gifts,
    required this.isArabic,
    required this.selectedGiftCode,
    required this.onGiftTap,
    required this.crossAxisCount,
    super.key,
  });

  final String title;
  final List<RoomGift> gifts;
  final bool isArabic;
  final String? selectedGiftCode;
  final ValueChanged<RoomGift> onGiftTap;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    if (gifts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: SroodRoomDims.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: SroodRoomDims.space4,
              bottom: SroodRoomDims.space8,
            ),
            child: Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF0C15A),
                    fontSize: SroodRoomDims.textMd,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${gifts.length})',
                  style: const TextStyle(
                    color: Color(0xFF8C819E),
                    fontSize: SroodRoomDims.textXs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: gifts.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 8,
              crossAxisSpacing: 6,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, index) {
              final gift = gifts[index];
              return SroodGiftTile(
                key: ValueKey('gift_section_tile_${gift.code}'),
                gift: gift,
                isArabic: isArabic,
                selected: selectedGiftCode == gift.code,
                onTap: () => onGiftTap(gift),
              );
            },
          ),
        ],
      ),
    );
  }
}
