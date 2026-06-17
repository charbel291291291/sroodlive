import '../models/user_vip.dart';
import '../models/vip_permissions.dart';
import 'vip_service.dart';

/// Centralizes VIP feature-gate checks.
///
/// Derives [VipPermissions] from [VipService]'s in-memory cache — no extra
/// network round-trip when VIP data is already loaded.
///
/// Usage:
/// ```dart
/// final perms = await VipPermissionsService().getMyPermissions();
/// if (perms.canSendChatImage) { ... }
/// ```
///
/// For synchronous checks when the UserVip is already in scope:
/// ```dart
/// final perms = VipPermissionsService.fromUserVip(vip);
/// ```
class VipPermissionsService {
  const VipPermissionsService();

  /// Fetch permissions for the current authenticated user.
  ///
  /// Reads from [VipService] cache first (no round-trip if already loaded).
  /// Returns [VipPermissions.none] when not authenticated.
  Future<VipPermissions> getMyPermissions() async {
    final vip = await VipService().getMyVip();
    return fromUserVip(vip);
  }

  /// Derive permissions for any cached [UserVip] snapshot.
  ///
  /// Call this when you already have the [UserVip] in a widget's state —
  /// avoids an async call entirely.
  static VipPermissions fromUserVip(UserVip? vip) {
    return VipPermissions.fromLevel(vip?.effectiveVipLevel ?? 0);
  }

  // ── Focused checks ────────────────────────────────────────────────────────

  /// Whether the current user may send images in room chat.
  Future<bool> canSendChatImage() async {
    final perms = await getMyPermissions();
    return perms.canSendChatImage;
  }

  /// Sync check from an already-loaded [UserVip].
  static bool canSendChatImageSync(UserVip? vip) =>
      fromUserVip(vip).canSendChatImage;
}
