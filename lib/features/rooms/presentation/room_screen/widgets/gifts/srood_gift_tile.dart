/// A single gift grid tile: thumbnail, full name (up to 2 lines), price, and
/// an optional premium badge for VIP gifts. Pure presentation — selection,
/// quantity, and send all stay owned by the sheet.
library;

import 'package:flutter/material.dart';

import '../../../../models/room_gift.dart';
import '../../../theme/srood_room_theme.dart';
import '../common/srood_gift_artwork.dart';
import 'srood_gift_price.dart';

class SroodGiftTile extends StatelessWidget {
  const SroodGiftTile({
    required this.gift,
    required this.isArabic,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final RoomGift gift;
  final bool isArabic;
  final bool selected;
  final VoidCallback onTap;

  bool get _isVip => gift.categoryKey == 'vip';

  @override
  Widget build(BuildContext context) {
    final name = isArabic ? gift.arabicName : gift.name;

    return Semantics(
      button: true,
      selected: selected,
      label: isArabic
          ? '$name، ${formatGiftCoins(gift.priceCoins)} عملة'
                '${_isVip ? '، VIP' : ''}'
          : '$name, ${formatGiftCoins(gift.priceCoins)} coins'
                '${_isVip ? ', VIP' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd + 2),
        onTap: onTap,
        child: Container(
          key: ValueKey('gift_tile_${gift.code}'),
          padding: const EdgeInsets.fromLTRB(5, 7, 5, 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF42105C) : Colors.transparent,
            borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd + 2),
            border: Border.all(
              color: selected ? const Color(0xFFF0C15A) : Colors.transparent,
              width: 1.6,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFFD10DFF).withValues(alpha: 0.32),
                      blurRadius: 16,
                    ),
                  ]
                : const [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isVip)
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF9B4DFF,
                              ).withValues(alpha: 0.30),
                              blurRadius: 18,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                      ),
                    Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final sz = (constraints.maxWidth * 0.82).clamp(
                            32.0,
                            56.0,
                          );
                          return SroodGiftArtwork(gift: gift, size: sz);
                        },
                      ),
                    ),
                    if (_isVip)
                      Positioned(
                        top: 0,
                        right: isArabic ? null : 0,
                        left: isArabic ? 0 : null,
                        child: const _PremiumBadge(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: SroodRoomDims.space4),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: SroodRoomDims.textSm,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              SroodGiftPrice(coins: gift.priceCoins),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1038),
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          BorderSide(color: SroodRoomColors.gold, width: 1),
        ),
      ),
      child: const Icon(
        Icons.workspace_premium_rounded,
        color: SroodRoomColors.gold,
        size: 10,
      ),
    );
  }
}
