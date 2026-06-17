import 'package:flutter/foundation.dart';

/// Immutable snapshot of VIP feature permissions for one user.
///
/// Computed from the user's effective VIP level (expiry-aware).
/// Mirrors the rules in [get_user_vip_permissions] on the backend.
///
/// Construct via:
///   [VipPermissions.fromLevel]  — pure, no network (preferred when level is known)
///   [VipPermissions.fromJson]   — from RPC response
///   [VipPermissions.none]       — safe zero-value (non-VIP)
@immutable
class VipPermissions {
  const VipPermissions({
    required this.vipLevel,
    required this.canSendChatImage,
    required this.canUsePremiumEntrance,
    required this.canUseProfileFrame,
    required this.canUseAnimatedFrame,
    required this.canUsePremiumBubble,
    required this.maxChatImageMb,
    required this.maxRoomUploadMb,
  });

  final int vipLevel;

  /// VIP 7+: may send image messages in live room chat.
  final bool canSendChatImage;

  /// VIP 3+: premium room entrance effect is active.
  final bool canUsePremiumEntrance;

  /// VIP 1+: VIP avatar frame is unlocked.
  final bool canUseProfileFrame;

  /// VIP 8+: animated avatar frame is unlocked.
  final bool canUseAnimatedFrame;

  /// VIP 5+: premium chat bubble style is available.
  final bool canUsePremiumBubble;

  /// Maximum image size in MB for chat images (0 = not allowed).
  final int maxChatImageMb;

  /// Maximum upload size in MB for room media (0 = not allowed).
  final int maxRoomUploadMb;

  // ── Factories ────────────────────────────────────────────────────────────

  /// Compute permissions purely from VIP level — no network call needed.
  /// [level] should be the effective level (0 when expired or non-VIP).
  factory VipPermissions.fromLevel(int level) {
    return VipPermissions(
      vipLevel: level,
      canUseProfileFrame:    level >= 1,
      canUsePremiumEntrance: level >= 3,
      canUsePremiumBubble:   level >= 5,
      canSendChatImage:      level >= 7,
      canUseAnimatedFrame:   level >= 8,
      maxChatImageMb:  level >= 10 ? 10 : (level >= 7 ? 5 : 0),
      maxRoomUploadMb: level >= 10 ? 50 : (level >= 5 ? 20 : 0),
    );
  }

  /// Zero-value permissions — all false, all limits 0.
  factory VipPermissions.none() => VipPermissions.fromLevel(0);

  /// Parse from [get_user_vip_permissions] RPC response.
  factory VipPermissions.fromJson(Map<String, dynamic> json) {
    return VipPermissions(
      vipLevel:              (json['vip_level']              as int?)  ?? 0,
      canSendChatImage:      (json['can_send_chat_image']    as bool?) ?? false,
      canUsePremiumEntrance: (json['can_use_premium_entrance'] as bool?) ?? false,
      canUseProfileFrame:    (json['can_use_profile_frame']  as bool?) ?? false,
      canUseAnimatedFrame:   (json['can_use_animated_frame'] as bool?) ?? false,
      canUsePremiumBubble:   (json['can_use_premium_bubble'] as bool?) ?? false,
      maxChatImageMb:        (json['max_chat_image_mb']      as int?)  ?? 0,
      maxRoomUploadMb:       (json['max_room_upload_mb']     as int?)  ?? 0,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Human-readable unlock hint for the chat-image gate.
  static const String chatImageUnlockHint = 'Image messages unlock at VIP 7';
  static const String chatImageUnlockHintAr = 'رسائل الصور تُفتح من VIP 7';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VipPermissions &&
          other.vipLevel == vipLevel &&
          other.canSendChatImage == canSendChatImage &&
          other.canUsePremiumEntrance == canUsePremiumEntrance &&
          other.canUseProfileFrame == canUseProfileFrame &&
          other.canUseAnimatedFrame == canUseAnimatedFrame &&
          other.canUsePremiumBubble == canUsePremiumBubble &&
          other.maxChatImageMb == maxChatImageMb &&
          other.maxRoomUploadMb == maxRoomUploadMb;

  @override
  int get hashCode => Object.hash(
        vipLevel,
        canSendChatImage,
        canUsePremiumEntrance,
        canUseProfileFrame,
        canUseAnimatedFrame,
        canUsePremiumBubble,
        maxChatImageMb,
        maxRoomUploadMb,
      );

  @override
  String toString() =>
      'VipPermissions(vipLevel: $vipLevel, canSendChatImage: $canSendChatImage, '
      'maxChatImageMb: $maxChatImageMb)';
}
