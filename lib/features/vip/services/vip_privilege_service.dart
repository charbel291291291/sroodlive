import '../../../core/supabase/supabase_service.dart';
import '../../../core/vip/vip_privileges.dart';
import '../../rooms/utils/vip_room_features.dart';

// ---------------------------------------------------------------------------
// Privilege identifiers â€” match column names in user_vip_settings.
// ---------------------------------------------------------------------------

enum VipPrivilege {
  notBeingFollowed('not_being_followed', VipPrivilegeKey.notBeingFollowed),
  antiEnteringRoom('anti_entering_room', VipPrivilegeKey.antiEnteringRoom),
  privateBrowsing('private_browsing', VipPrivilegeKey.privateBrowsing),
  doNotDisturb('do_not_disturb', VipPrivilegeKey.doNotDisturb),
  invisibility('invisibility', VipPrivilegeKey.invisibility),
  antiKick('anti_kick', VipPrivilegeKey.antiKick);

  const VipPrivilege(this.columnName, this.privilegeKey);

  /// Column name in user_vip_settings table.
  final String columnName;

  /// Corresponding canonical privilege key in VipPrivileges.
  final VipPrivilegeKey privilegeKey;

  /// Minimum VIP level required â€” delegated to the central config.
  int get minVipLevel => VipPrivileges.spec(privilegeKey).minVipLevel;
}

// ---------------------------------------------------------------------------
// VipPrivilegeService
// ---------------------------------------------------------------------------

class VipPrivilegeService {
  const VipPrivilegeService();

  // â”€â”€ Read / write settings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Load current user's VIP privilege settings.
  /// Returns a map of [VipPrivilege] â†’ enabled (bool).
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
  ///
  /// Uses the [set_my_vip_setting] RPC which enforces the VIP level requirement
  /// server-side before writing to user_vip_settings.
  /// Does nothing (client-side guard) if [effectiveVipLevel] is already too low.
  /// Throws on backend error so the caller can revert optimistic UI updates.
  Future<void> setSetting({
    required VipPrivilege privilege,
    required bool enabled,
    required int effectiveVipLevel,
  }) async {
    if (!canUsePrivilege(effectiveVipLevel, privilege)) return;

    final client = SupabaseService.requiredClient;
    if (client.auth.currentUser == null) return;

    await client.rpc(
      'set_my_vip_setting',
      params: {'p_key': privilege.columnName, 'p_enabled': enabled},
    );
  }

  // â”€â”€ Privilege checks â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Whether a VIP level is high enough to use a privilege.
  /// Delegates to the central VipPrivileges config.
  static bool canUsePrivilege(int effectiveVipLevel, VipPrivilege privilege) {
    return VipPrivileges.canUse(effectiveVipLevel, privilege.privilegeKey);
  }

  /// Whether the target user has anti-follow enabled (blocks new followers).
  Future<bool> isFollowBlocked(String targetUserId) async {
    return _isPrivilegeActiveForUser(
      targetUserId,
      VipPrivilege.notBeingFollowed,
    );
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

  // â”€â”€ Private helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
