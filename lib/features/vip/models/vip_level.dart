import 'package:flutter/foundation.dart';

/// Metadata for a single VIP tier, as stored in the vip_levels table.
/// Used for VIP purchase UI, admin tools, and level display.
@immutable
class VipLevelMeta {
  const VipLevelMeta({
    required this.id,
    required this.level,
    required this.name,
    this.priceCoins,
    this.priceUsd,
    required this.durationDays,
    this.badgeUrl,
    this.profileFrameUrl,
    this.micFrameUrl,
    this.entranceEffectKey,
    this.chatBubbleStyle,
    required this.roomPrivileges,
    required this.priorityRank,
    required this.isActive,
  });

  final String id;
  final int level;
  final String name;
  final int? priceCoins;
  final double? priceUsd;
  final int durationDays;
  final String? badgeUrl;
  final String? profileFrameUrl;
  final String? micFrameUrl;
  final String? entranceEffectKey;
  final String? chatBubbleStyle;
  final Map<String, dynamic> roomPrivileges;
  final int priorityRank;
  final bool isActive;

  factory VipLevelMeta.fromJson(Map<String, dynamic> json) {
    return VipLevelMeta(
      id: (json['id'] as String?) ?? '',
      level: (json['level'] as int?) ?? 0,
      name: (json['name'] as String?) ?? 'VIP',
      priceCoins: json['price_coins'] as int?,
      priceUsd: json['price_usd'] != null
          ? double.tryParse(json['price_usd'].toString())
          : null,
      durationDays: (json['duration_days'] as int?) ?? 30,
      badgeUrl: json['badge_url'] as String?,
      profileFrameUrl: json['profile_frame_url'] as String?,
      micFrameUrl: json['mic_frame_url'] as String?,
      entranceEffectKey: json['entrance_effect_key'] as String?,
      chatBubbleStyle: json['chat_bubble_style'] as String?,
      roomPrivileges: json['room_privileges'] is Map
          ? Map<String, dynamic>.from(json['room_privileges'] as Map)
          : <String, dynamic>{},
      priorityRank: (json['priority_rank'] as int?) ?? 0,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }

  bool get hasKickProtection => roomPrivileges['kick_protection'] == true;
  bool get hasStrongKickProtection => roomPrivileges['strong_kick'] == true;
  bool get hasSilentEntry => roomPrivileges['silent_entry'] == true;
  bool get hasAntiKick => roomPrivileges['anti_kick'] == true;
  bool get requiresKickConfirmation => roomPrivileges['kick_confirm'] == true;
}
