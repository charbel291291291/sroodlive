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
    // EXP progress — only populated by get_my_vip (own user); null for others
    this.rechargeExp = 0,
    this.monthlyExp = 0,
    this.cycleStartedAt,
    this.lastRechargeAt,
    this.currentTierRequiredExp,
    this.nextTierRequiredExp,
    this.monthlyMaintainExp,
    this.expToNextTier,
    this.expToMaintain,
  });

  // ── Core identity ──────────────────────────────────────────────────────────

  /// VIP level (0 = no VIP, 1-9 = active VIP tier).
  final String userId;
  final int vipLevel;
  final DateTime? vipStartedAt;
  final DateTime? vipExpiresAt;
  final String? vipTitle;
  final bool isGoldenId;
  final DateTime? goldenIdExpiresAt;

  // ── Recharge EXP progress (Phase H) ───────────────────────────────────────
  // Only populated when loaded via get_my_vip() (current user).
  // All other consumers (room members, leaderboard, messages) receive 0/null.

  /// Lifetime recharged coins converted to VIP EXP (1 coin = 1 EXP).
  final int rechargeExp;

  /// EXP accumulated in the current monthly VIP cycle.
  final int monthlyExp;

  /// When the current VIP cycle started (null until first recharge).
  final DateTime? cycleStartedAt;

  /// Timestamp of the most recent qualifying recharge.
  final DateTime? lastRechargeAt;

  /// Lifetime EXP required to hold the current VIP tier (null when no VIP).
  final int? currentTierRequiredExp;

  /// Lifetime EXP required to reach the next tier (null at VIP 9 / max).
  final int? nextTierRequiredExp;

  /// Monthly EXP required to renew the current tier for another month.
  final int? monthlyMaintainExp;

  /// Remaining lifetime EXP to reach the next tier (null if no next tier).
  /// Server-computed: GREATEST(0, next_tier_required_exp - recharge_exp).
  final int? expToNextTier;

  /// Remaining monthly EXP to secure current-tier renewal (null if no tier).
  /// Server-computed: GREATEST(0, monthly_maintain_exp - monthly_exp).
  final int? expToMaintain;

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

  /// Whether the monthly maintenance EXP has been met for the current cycle.
  bool get isMonthlyMaintainMet {
    final maintain = monthlyMaintainExp;
    if (maintain == null || maintain <= 0) return false;
    return monthlyExp >= maintain;
  }

  /// Progress fraction [0.0, 1.0] toward the next VIP tier.
  /// Returns null when already at max tier or no EXP data available.
  double? get nextTierProgress {
    final next = nextTierRequiredExp;
    final current = currentTierRequiredExp;
    if (next == null) return null;
    final base = current ?? 0;
    final range = next - base;
    if (range <= 0) return 1.0;
    final earned = rechargeExp - base;
    return (earned / range).clamp(0.0, 1.0);
  }

  /// Progress fraction [0.0, 1.0] toward monthly maintenance threshold.
  /// Returns null when no current tier or no maintain data.
  double? get monthlyMaintainProgress {
    final maintain = monthlyMaintainExp;
    if (maintain == null || maintain <= 0) return null;
    return (monthlyExp / maintain).clamp(0.0, 1.0);
  }

  // ── Factory ───────────────────────────────────────────────────────────────

  /// Builds from the JSON object returned by get_my_vip() RPC.
  /// Null-safe for every field — unknown keys are ignored.
  factory UserVip.fromJson(Map<String, dynamic> json) {
    return UserVip(
      userId: (json['user_id'] as String?) ?? '',
      vipLevel: (json['vip_level'] as int?) ?? 0,
      vipStartedAt: _parseDate(json['vip_started_at']),
      vipExpiresAt: _parseDate(json['vip_expires_at']),
      vipTitle: json['vip_title'] as String?,
      isGoldenId: (json['is_golden_id'] as bool?) ?? false,
      goldenIdExpiresAt: _parseDate(json['golden_id_expires_at']),
      // EXP fields — null-safe; absent in get_user_vip / get_users_with_vip
      rechargeExp: _parseInt(json['vip_recharge_exp']),
      monthlyExp: _parseInt(json['vip_monthly_exp']),
      cycleStartedAt: _parseDate(json['vip_cycle_started_at']),
      lastRechargeAt: _parseDate(json['vip_last_recharge_at']),
      currentTierRequiredExp: _parseNullableInt(json['current_tier_required_exp']),
      nextTierRequiredExp: _parseNullableInt(json['next_tier_required_exp']),
      monthlyMaintainExp: _parseNullableInt(json['monthly_maintain_exp']),
      expToNextTier: _parseNullableInt(json['exp_to_next_tier']),
      expToMaintain: _parseNullableInt(json['exp_to_maintain']),
    );
  }

  /// Builds from raw profiles row columns (e.g. realtime channel payload).
  /// EXP fields are included when the profiles row contains them (Phase F+).
  factory UserVip.fromProfileRow(Map<String, dynamic> row, String userId) {
    return UserVip(
      userId: userId,
      vipLevel: (row['vip_level'] as int?) ?? 0,
      vipStartedAt: _parseDate(row['vip_started_at']),
      vipExpiresAt: _parseDate(row['vip_expires_at']),
      vipTitle: row['vip_title'] as String?,
      isGoldenId: (row['is_golden_id'] as bool?) ?? false,
      goldenIdExpiresAt: _parseDate(row['golden_id_expires_at']),
      // EXP fields — present if the realtime payload includes them
      rechargeExp: _parseInt(row['vip_recharge_exp']),
      monthlyExp: _parseInt(row['vip_monthly_exp']),
      cycleStartedAt: _parseDate(row['vip_cycle_started_at']),
      lastRechargeAt: _parseDate(row['vip_last_recharge_at']),
      // Threshold fields not in raw profile row — those come from vip_levels join
    );
  }

  /// Returns a non-VIP placeholder for a given user.
  factory UserVip.none(String userId) => UserVip(userId: userId, vipLevel: 0);

  // ── Copy ──────────────────────────────────────────────────────────────────

  UserVip copyWith({
    int? vipLevel,
    DateTime? vipStartedAt,
    DateTime? vipExpiresAt,
    String? vipTitle,
    bool? isGoldenId,
    DateTime? goldenIdExpiresAt,
    int? rechargeExp,
    int? monthlyExp,
    DateTime? cycleStartedAt,
    DateTime? lastRechargeAt,
    int? currentTierRequiredExp,
    int? nextTierRequiredExp,
    int? monthlyMaintainExp,
    int? expToNextTier,
    int? expToMaintain,
  }) {
    return UserVip(
      userId: userId,
      vipLevel: vipLevel ?? this.vipLevel,
      vipStartedAt: vipStartedAt ?? this.vipStartedAt,
      vipExpiresAt: vipExpiresAt ?? this.vipExpiresAt,
      vipTitle: vipTitle ?? this.vipTitle,
      isGoldenId: isGoldenId ?? this.isGoldenId,
      goldenIdExpiresAt: goldenIdExpiresAt ?? this.goldenIdExpiresAt,
      rechargeExp: rechargeExp ?? this.rechargeExp,
      monthlyExp: monthlyExp ?? this.monthlyExp,
      cycleStartedAt: cycleStartedAt ?? this.cycleStartedAt,
      lastRechargeAt: lastRechargeAt ?? this.lastRechargeAt,
      currentTierRequiredExp: currentTierRequiredExp ?? this.currentTierRequiredExp,
      nextTierRequiredExp: nextTierRequiredExp ?? this.nextTierRequiredExp,
      monthlyMaintainExp: monthlyMaintainExp ?? this.monthlyMaintainExp,
      expToNextTier: expToNextTier ?? this.expToNextTier,
      expToMaintain: expToMaintain ?? this.expToMaintain,
    );
  }

  // ── Equality — keyed on identity fields only, not EXP snapshot ───────────

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
      'UserVip(userId: $userId, level: $vipLevel, active: $isVipActive, '
      'rechargeExp: $rechargeExp, monthlyExp: $monthlyExp)';

  // ── Private parsing helpers ───────────────────────────────────────────────

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  /// Parses int or bigint from JSON (Supabase may return num or String).
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  static int? _parseNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
