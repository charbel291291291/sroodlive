/// Floating gift-event banners pinned near the top of the stage. Events are
/// spawned and expired by the screen state; this overlay only renders them.
library;

import 'package:flutter/material.dart';

import '../../../theme/srood_room_theme.dart';
import '../../models/srood_gift_events.dart';
import '../common/srood_gift_artwork.dart';

class SroodGiftEventOverlay extends StatelessWidget {
  const SroodGiftEventOverlay({
    required this.events,
    required this.isArabic,
    super.key,
  });

  final List<SroodRoomGiftEvent> events;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 120, 18, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: events
                .map(
                  (event) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GiftEventBanner(event: event, isArabic: isArabic),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _GiftEventBanner extends StatelessWidget {
  const _GiftEventBanner({required this.event, required this.isArabic});

  final SroodRoomGiftEvent event;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final giftName = isArabic ? event.gift.arabicName : event.gift.name;
    final qty = event.quantity > 1 ? ' ×${event.quantity}' : '';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: SroodRoomMotion.normal,
      curve: SroodRoomMotion.curve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * -10),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B1A45), SroodRoomColors.bg],
          ),
          borderRadius: BorderRadius.circular(SroodRoomDims.radiusPill),
          border: Border.all(
            color: const Color(0xFFD4A017).withValues(alpha: 0.68),
            width: 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: SroodRoomColors.gold.withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            SroodGiftArtwork(gift: event.gift, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isArabic ? 'هدية' : 'Gift sent',
                    style: const TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: SroodRoomDims.textXs,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isArabic
                        ? '$giftName$qty إلى ${event.receiverName}'
                        : '$giftName$qty to ${event.receiverName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: isArabic ? TextAlign.right : TextAlign.left,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: SroodRoomDims.textMd,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
