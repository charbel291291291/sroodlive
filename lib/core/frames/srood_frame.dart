/// Frame System v2 — catalog model.
///
/// One immutable description of a frame, mirroring the `frame_catalog` table.
/// Identifiers are stable machine codes (`code`); display names are never
/// used as identifiers. Display-only: nothing here grants entitlements.
library;

import 'package:flutter/foundation.dart';

/// Frame category. Mirrors the `frame_catalog.category` check constraint.
enum SroodFrameCategory {
  vip,
  normal,
  luxury,
  admin,
  superAdmin,
  agencyOwner,
  host,
  rechargeOwner,
  roomOwner,
  event,
  achievement,
  seasonal,
  specialEdition,
  purchased,
  reward,
  custom;

  static SroodFrameCategory fromWire(String? value) {
    return switch (value) {
      'vip' => vip,
      'normal' => normal,
      'luxury' => luxury,
      'admin' => admin,
      'super_admin' => superAdmin,
      'agency_owner' => agencyOwner,
      'host' => host,
      'recharge_owner' => rechargeOwner,
      'room_owner' => roomOwner,
      'event' => event,
      'achievement' => achievement,
      'seasonal' => seasonal,
      'special_edition' => specialEdition,
      'purchased' => purchased,
      'reward' => reward,
      _ => custom,
    };
  }

  String get wire => switch (this) {
    vip => 'vip',
    normal => 'normal',
    luxury => 'luxury',
    admin => 'admin',
    superAdmin => 'super_admin',
    agencyOwner => 'agency_owner',
    host => 'host',
    rechargeOwner => 'recharge_owner',
    roomOwner => 'room_owner',
    event => 'event',
    achievement => 'achievement',
    seasonal => 'seasonal',
    specialEdition => 'special_edition',
    purchased => 'purchased',
    reward => 'reward',
    custom => 'custom',
  };
}

/// How a frame is unlocked. Mirrors `frame_catalog.unlock_type`.
enum SroodFrameUnlock {
  free,
  vipLevel,
  role,
  level,
  purchase,
  reward,
  adminGrant,
  event;

  static SroodFrameUnlock fromWire(String? value) {
    return switch (value) {
      'free' => free,
      'vip_level' => vipLevel,
      'role' => role,
      'level' => level,
      'purchase' => purchase,
      'reward' => reward,
      'admin_grant' => adminGrant,
      'event' => event,
      _ => adminGrant, // unknown unlock types are treated as locked
    };
  }

  String get wire => switch (this) {
    free => 'free',
    vipLevel => 'vip_level',
    role => 'role',
    level => 'level',
    purchase => 'purchase',
    reward => 'reward',
    adminGrant => 'admin_grant',
    event => 'event',
  };
}

/// Frame rarity — presentation only (picker ordering, card treatment).
enum SroodFrameRarity {
  common,
  rare,
  epic,
  legendary,
  mythic;

  static SroodFrameRarity fromWire(String? value) {
    return switch (value) {
      'rare' => rare,
      'epic' => epic,
      'legendary' => legendary,
      'mythic' => mythic,
      _ => common,
    };
  }

  String get wire => switch (this) {
    common => 'common',
    rare => 'rare',
    epic => 'epic',
    legendary => 'legendary',
    mythic => 'mythic',
  };
}

/// Frame asset delivery type.
enum SroodFrameAssetType {
  /// Bundled Flutter asset (path in [SroodFrame.assetUrl]).
  bundled,

  /// Network image (CDN / Supabase storage URL).
  network,

  /// No bitmap — rendered by the tier placeholder painter.
  painter;

  static SroodFrameAssetType fromWire(String? value) {
    return switch (value) {
      'bundled' => bundled,
      'network' => network,
      _ => painter,
    };
  }

  String get wire => switch (this) {
    bundled => 'bundled',
    network => 'network',
    painter => 'painter',
  };
}

/// Sentinel for [SroodFrame.copyWith] so a caller can distinguish "leave this
/// field alone" from "set this nullable field to null".
const Object _unchanged = Object();

@immutable
class SroodFrame {
  const SroodFrame({
    required this.id,
    required this.code,
    required this.name,
    this.localizedNames = const {},
    this.category = SroodFrameCategory.custom,
    this.vipLevel,
    this.rarity = SroodFrameRarity.common,
    this.assetType = SroodFrameAssetType.painter,
    this.assetUrl,
    this.thumbnailUrl,
    this.animationUrl,
    this.isAnimated = false,
    this.isActive = true,
    this.sortOrder = 0,
    this.unlockType = SroodFrameUnlock.free,
    this.unlockValue,
    this.requiredRole,
    this.requiredLevel,
    this.requiredVipLevel,
    this.startsAt,
    this.expiresAt,
    this.legacyFrameKey,
    this.createdAt,
    this.updatedAt,
  });

  /// Stable identity (uuid in DB; the code for built-in registry entries).
  final String id;

  /// Stable machine code — the selection identifier. Never a display name.
  final String code;

  /// English display name.
  final String name;

  /// Locale code → localized display name (e.g. `{'ar': '...', 'fr': '...'}`).
  final Map<String, String> localizedNames;

  final SroodFrameCategory category;

  /// VIP tier this frame belongs to (for `category == vip`).
  final int? vipLevel;

  final SroodFrameRarity rarity;
  final SroodFrameAssetType assetType;

  /// Bundled asset path or network URL, per [assetType].
  final String? assetUrl;
  final String? thumbnailUrl;

  /// Optional animated variant (e.g. webp/apng URL).
  final String? animationUrl;
  final bool isAnimated;
  final bool isActive;
  final int sortOrder;

  final SroodFrameUnlock unlockType;

  /// Free-form unlock parameter (e.g. price in coins for `purchase`).
  final String? unlockValue;

  /// Server-side role requirement (e.g. `admin`, `super_admin`, `host`).
  final String? requiredRole;

  /// Minimum user level requirement.
  final int? requiredLevel;

  /// Minimum VIP level requirement.
  final int? requiredVipLevel;

  /// Availability window (seasonal / event frames).
  final DateTime? startsAt;
  final DateTime? expiresAt;

  /// Pre-v2 `avatar_frames.frame_key` this row was migrated from, when any.
  ///
  /// Read-only: `admin_upsert_frame_v2` has no parameter for it, so the admin
  /// editor displays and searches it but cannot change it.
  final String? legacyFrameKey;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Display name for [localeCode], falling back to English.
  String nameFor(String localeCode) => localizedNames[localeCode] ?? name;

  /// Whether the frame is inside its availability window at [now].
  bool isAvailableAt(DateTime now) {
    if (!isActive) return false;
    if (startsAt != null && now.isBefore(startsAt!)) return false;
    if (expiresAt != null && !now.isBefore(expiresAt!)) return false;
    return true;
  }

  factory SroodFrame.fromJson(Map<String, dynamic> json) {
    final rawNames = json['localized_names'];
    return SroodFrame(
      id: json['id']?.toString() ?? json['code'].toString(),
      code: json['code'].toString(),
      name: json['name']?.toString() ?? 'Frame',
      localizedNames: rawNames is Map
          ? rawNames.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      category: SroodFrameCategory.fromWire(json['category']?.toString()),
      vipLevel: (json['vip_level'] as num?)?.toInt(),
      rarity: SroodFrameRarity.fromWire(json['rarity']?.toString()),
      assetType: SroodFrameAssetType.fromWire(json['asset_type']?.toString()),
      assetUrl: json['asset_url']?.toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      animationUrl: json['animation_url']?.toString(),
      isAnimated: json['is_animated'] == true,
      isActive: json['is_active'] != false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      unlockType: SroodFrameUnlock.fromWire(json['unlock_type']?.toString()),
      unlockValue: json['unlock_value']?.toString(),
      requiredRole: json['required_role']?.toString(),
      requiredLevel: (json['required_level'] as num?)?.toInt(),
      requiredVipLevel: (json['required_vip_level'] as num?)?.toInt(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      legacyFrameKey: json['legacy_frame_key']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  /// Field-wise copy. Nullable fields keep their current value unless the
  /// caller passes something — including an explicit `null` to clear them.
  SroodFrame copyWith({
    String? id,
    String? code,
    String? name,
    Map<String, String>? localizedNames,
    SroodFrameCategory? category,
    Object? vipLevel = _unchanged,
    SroodFrameRarity? rarity,
    SroodFrameAssetType? assetType,
    Object? assetUrl = _unchanged,
    Object? thumbnailUrl = _unchanged,
    Object? animationUrl = _unchanged,
    bool? isAnimated,
    bool? isActive,
    int? sortOrder,
    SroodFrameUnlock? unlockType,
    Object? unlockValue = _unchanged,
    Object? requiredRole = _unchanged,
    Object? requiredLevel = _unchanged,
    Object? requiredVipLevel = _unchanged,
    Object? startsAt = _unchanged,
    Object? expiresAt = _unchanged,
    Object? legacyFrameKey = _unchanged,
  }) {
    return SroodFrame(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      localizedNames: localizedNames ?? this.localizedNames,
      category: category ?? this.category,
      vipLevel: vipLevel == _unchanged ? this.vipLevel : vipLevel as int?,
      rarity: rarity ?? this.rarity,
      assetType: assetType ?? this.assetType,
      assetUrl: assetUrl == _unchanged ? this.assetUrl : assetUrl as String?,
      thumbnailUrl: thumbnailUrl == _unchanged
          ? this.thumbnailUrl
          : thumbnailUrl as String?,
      animationUrl: animationUrl == _unchanged
          ? this.animationUrl
          : animationUrl as String?,
      isAnimated: isAnimated ?? this.isAnimated,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      unlockType: unlockType ?? this.unlockType,
      unlockValue: unlockValue == _unchanged
          ? this.unlockValue
          : unlockValue as String?,
      requiredRole: requiredRole == _unchanged
          ? this.requiredRole
          : requiredRole as String?,
      requiredLevel: requiredLevel == _unchanged
          ? this.requiredLevel
          : requiredLevel as int?,
      requiredVipLevel: requiredVipLevel == _unchanged
          ? this.requiredVipLevel
          : requiredVipLevel as int?,
      startsAt: startsAt == _unchanged ? this.startsAt : startsAt as DateTime?,
      expiresAt: expiresAt == _unchanged
          ? this.expiresAt
          : expiresAt as DateTime?,
      legacyFrameKey: legacyFrameKey == _unchanged
          ? this.legacyFrameKey
          : legacyFrameKey as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) => other is SroodFrame && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
