import 'package:flutter/foundation.dart';

import '../../../core/utils/vip_visuals.dart';
import '../../../core/vip/vip_spec.dart';

/// Lightweight, immutable snapshot of one user's current VIP status.
/// Constructed from the JSON returned by get_my_vip() / get_user_vip() RPCs
/// or from the profiles table columns.
@immutable
class UserVip {
  const UserVip({
    required this.userId,
    required this.vipLevel,
    this.vipStartedAt,
    this.vipExpiresAt,
    this.vipTitle,
    this.isGoldenId = false,
    this.goldenIdExpiresAt,
  });

  /// VIP level (0 = no VIP, 1-9 = active VIP tier).
  final String userId;
  final int vipLevel;
  final DateTime? vipStartedAt;
  final DateTime? vipExpiresAt;
  final String? vipTitle;
  final bool isGoldenId;
  final DateTime? goldenIdExpiresAt;

  // ── Computed ──────────────────────────────────────────────────────────────

  /// Whether VIP is currently active (non-zero level + not expired).
  bool get isVipActive {
    if (vipLevel <= 0) return false;
    if (vipExpiresAt == null) return true;
    return vipExpiresAt!.isAfter(DateTime.now());
  }

  /// Returns the effective VIP level (0 when expired/inactive).
  int get effectiveVipLevel => isVipActive ? vipLevel.clamp(1, 9) : 0;

  /// Whether this user has any visible VIP status.
  bool get hasVip => effectiveVipLevel > 0;

  /// VIP visual pack for the effective level (null for non-VIP users).
  VipVisuals? get visuals => getVipVisualStyle(effectiveVipLevel);

  /// Unified VIP spec for the effective level.
  VipSpec get spec => VipSpecResolver.resolve(effectiveVipLevel);

  /// Whether golden ID display is currently active.
  bool get isGoldenIdActive {
    if (!isGoldenId) return false;
    if (goldenIdExpiresAt == null) return true;
    return goldenIdExpiresAt!.isAfter(DateTime.now());
  }

  /// The display label for this VIP tier ("VIP 5", "VIP 9", …).
  String get label => hasVip ? 'VIP $effectiveVipLevel' : '';

  // ── Factory ───────────────────────────────────────────────────────────────

  /// Builds from the JSON object returned by the get_my_vip / get_user_vip
  /// RPCs.  Null-safe for every field.
  factory UserVip.fromJson(Map<String, dynamic> json) {
    return UserVip(
      userId: (json['user_id'] as String?) ?? '',
      vipLevel: (json['vip_level'] as int?) ?? 0,
      vipStartedAt: json['vip_started_at'] != null
          ? DateTime.tryParse(json['vip_started_at'].toString())
          : null,
      vipExpiresAt: json['vip_expires_at'] != null
          ? DateTime.tryParse(json['vip_expires_at'].toString())
          : null,
      vipTitle: json['vip_title'] as String?,
      isGoldenId: (json['is_golden_id'] as bool?) ?? false,
      goldenIdExpiresAt: json['golden_id_expires_at'] != null
          ? DateTime.tryParse(json['golden_id_expires_at'].toString())
          : null,
    );
  }

  /// Builds from raw profiles row columns (e.g. when reading directly).
  factory UserVip.fromProfileRow(Map<String, dynamic> row, String userId) {
    return UserVip(
      userId: userId,
      vipLevel: (row['vip_level'] as int?) ?? 0,
      vipStartedAt: row['vip_started_at'] != null
          ? DateTime.tryParse(row['vip_started_at'].toString())
          : null,
      vipExpiresAt: row['vip_expires_at'] != null
          ? DateTime.tryParse(row['vip_expires_at'].toString())
          : null,
      vipTitle: row['vip_title'] as String?,
      isGoldenId: (row['is_golden_id'] as bool?) ?? false,
      goldenIdExpiresAt: row['golden_id_expires_at'] != null
          ? DateTime.tryParse(row['golden_id_expires_at'].toString())
          : null,
    );
  }

  /// Returns a non-VIP placeholder for a given user.
  factory UserVip.none(String userId) => UserVip(userId: userId, vipLevel: 0);

  UserVip copyWith({
    int? vipLevel,
    DateTime? vipStartedAt,
    DateTime? vipExpiresAt,
    String? vipTitle,
    bool? isGoldenId,
    DateTime? goldenIdExpiresAt,
  }) {
    return UserVip(
      userId: userId,
      vipLevel: vipLevel ?? this.vipLevel,
      vipStartedAt: vipStartedAt ?? this.vipStartedAt,
      vipExpiresAt: vipExpiresAt ?? this.vipExpiresAt,
      vipTitle: vipTitle ?? this.vipTitle,
      isGoldenId: isGoldenId ?? this.isGoldenId,
      goldenIdExpiresAt: goldenIdExpiresAt ?? this.goldenIdExpiresAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserVip &&
          other.userId == userId &&
          other.vipLevel == vipLevel &&
          other.vipExpiresAt == vipExpiresAt &&
          other.isGoldenId == isGoldenId;

  @override
  int get hashCode => Object.hash(userId, vipLevel, vipExpiresAt, isGoldenId);

  @override
  String toString() =>
      'UserVip(userId: $userId, level: $vipLevel, active: $isVipActive)';
}
