import '../../../core/supabase/supabase_service.dart';
import '../../rooms/utils/vip_room_features.dart';

// ---------------------------------------------------------------------------
// Privilege identifiers — match column names in user_vip_settings.
// ---------------------------------------------------------------------------

enum VipPrivilege {
  notBeingFollowed('not_being_followed', 5),
  antiEnteringRoom('anti_entering_room', 6),
  privateBrowsing('private_browsing', 6),
  doNotDisturb('do_not_disturb', 7),
  invisibility('invisibility', 8),
  antiKick('anti_kick', 8);

  const VipPrivilege(this.columnName, this.minVipLevel);

  /// Column name in user_vip_settings table.
  final String columnName;

  /// Minimum VIP level required to use this privilege.
  final int minVipLevel;
}

// ---------------------------------------------------------------------------
// VipPrivilegeService
// ---------------------------------------------------------------------------

class VipPrivilegeService {
  const VipPrivilegeService();

  // ── Read / write settings ──────────────────────────────────────────────

  /// Load current user's VIP privilege settings.
  /// Returns a map of [VipPrivilege] → enabled (bool).
  Future<Map<VipPrivilege, bool>> loadSettings() async {
    final client = SupabaseService.requiredClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return {};

    try {
      final row = await client
          .from('user_vip_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) return {for (final p in VipPrivilege.values) p: false};

      return {
        for (final p in VipPrivilege.values)
          p: (row[p.columnName] as bool?) ?? false,
      };
    } catch (_) {
      return {for (final p in VipPrivilege.values) p: false};
    }
  }

  /// Save one privilege toggle for the current user.
  /// Does nothing if the user's effective VIP level is too low.
  Future<void> setSetting({
    required VipPrivilege privilege,
    required bool enabled,
    required int effectiveVipLevel,
  }) async {
    if (!canUsePrivilege(effectiveVipLevel, privilege)) return;

    final client = SupabaseService.requiredClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    await client.from('user_vip_settings').upsert(
      {
        'user_id': userId,
        privilege.columnName: enabled,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id',
    );
  }

  // ── Privilege checks ───────────────────────────────────────────────────

  /// Whether a VIP level is high enough to use a privilege.
  static bool canUsePrivilege(int effectiveVipLevel, VipPrivilege privilege) {
    return effectiveVipLevel >= privilege.minVipLevel;
  }

  /// Whether the target user has anti-follow enabled (blocks new followers).
  Future<bool> isFollowBlocked(String targetUserId) async {
    return _isPrivilegeActiveForUser(targetUserId, VipPrivilege.notBeingFollowed);
  }

  /// Whether a moderator can kick the target in a room.
  /// Room owner and super_admin can always kick regardless of VIP.
  Future<bool> isKickBlocked({
    required String targetUserId,
    required bool actorIsRoomOwner,
    required bool actorIsSuperAdmin,
  }) async {
    if (actorIsRoomOwner || actorIsSuperAdmin) return false;
    return _isPrivilegeActiveForUser(targetUserId, VipPrivilege.antiKick);
  }

  /// Whether the user should be hidden from discovery/online lists.
  Future<bool> shouldHidePresence(String userId) async {
    return _isPrivilegeActiveForUser(userId, VipPrivilege.invisibility);
  }

  /// Whether notifications should be suppressed for the target user.
  Future<bool> shouldSuppressNotification(String targetUserId) async {
    return _isPrivilegeActiveForUser(targetUserId, VipPrivilege.doNotDisturb);
  }

  // ── Private helpers ────────────────────────────────────────────────────

  Future<bool> _isPrivilegeActiveForUser(
    String userId,
    VipPrivilege privilege,
  ) async {
    try {
      final client = SupabaseService.requiredClient;
      final row = await client
          .from('user_vip_settings')
          .select(privilege.columnName)
          .eq('user_id', userId)
          .maybeSingle();
      return (row?[privilege.columnName] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Convenience: get effective VIP level for the current logged-in user
// from the profiles table.
// ---------------------------------------------------------------------------

Future<int> currentUserEffectiveVipLevel() async {
  try {
    final client = SupabaseService.requiredClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return 0;

    final row = await client
        .from('profiles')
        .select('vip_level, vip_expires_at')
        .eq('id', userId)
        .maybeSingle();

    if (row == null) return 0;

    final level = (row['vip_level'] as int?) ?? 0;
    final expiresAt = row['vip_expires_at'] != null
        ? DateTime.tryParse(row['vip_expires_at'].toString())
        : null;

    return VipFeatures.effectiveVipLevel(
      vipLevel: level,
      vipExpiresAt: expiresAt,
    );
  } catch (_) {
    return 0;
  }
}
