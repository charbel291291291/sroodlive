/// Presentation models for gift events flowing from the screen state into
/// overlay widgets.
library;

import 'package:flutter/foundation.dart';

import '../../../models/room_gift.dart';

/// Result of a successful gift send, used to spawn a floating event banner.
class SroodGiftSendResult {
  const SroodGiftSendResult({
    required this.gift,
    required this.receiverUserId,
    required this.receiverName,
    required this.quantity,
  });

  final RoomGift gift;
  final String receiverUserId;
  final String receiverName;
  final int quantity;
}

/// One floating gift banner entry (auto-expires via a state-owned timer).
class SroodRoomGiftEvent {
  const SroodRoomGiftEvent({
    required this.id,
    required this.gift,
    required this.receiverName,
    required this.quantity,
  });

  final int id;
  final RoomGift gift;
  final String receiverName;
  final int quantity;
}

/// Currently-playing full-screen luxury gift video.
class SroodActiveLuxuryGiftVideo {
  const SroodActiveLuxuryGiftVideo({
    required this.key,
    required this.giftName,
    required this.receiverName,
    required this.assetPath,
  });

  final Key key;
  final String giftName;
  final String receiverName;
  final String assetPath;
}
