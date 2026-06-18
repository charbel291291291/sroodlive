import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_service.dart';

// ── Role constants ────────────────────────────────────────────────────────────

const kRoleOSuperAdmin = 'o_super_admin';
const kRolePSuperAdmin = 'p_super_admin';
const kRoleSuperAdmin  = 'super_admin';
const kRoleAdmin       = 'admin';

// Display names shown in UI
const kRoleLabels = <String, String>{
  kRoleOSuperAdmin: 'O-Super Admin',
  kRolePSuperAdmin: 'P-Super Admin',
  kRoleSuperAdmin:  'Super Admin',
  kRoleAdmin:       'Admin',
};

// ── Permission key constants ──────────────────────────────────────────────────

const kPermUsersView         = 'users.view';
const kPermUsersEdit         = 'users.edit';
const kPermUsersTempBan      = 'users.temp_ban';
const kPermUsersPermanentBan = 'users.permanent_ban';
const kPermUsersUnban        = 'users.unban';
const kPermUsersDelete       = 'users.delete';
const kPermWalletViewBalance = 'wallet.view_balance';
const kPermWalletViewLogs    = 'wallet.view_logs';
const kPermWalletCredit      = 'wallet.credit';
const kPermWalletDebit       = 'wallet.debit';
const kPermWalletPrices      = 'wallet.prices';
const kPermRoomsView         = 'rooms.view';
const kPermRoomsClose        = 'rooms.close';
const kPermRoomsDelete       = 'rooms.delete';
const kPermRoomsPin          = 'rooms.pin';
const kPermReportsView       = 'reports.view';
const kPermReportsManage     = 'reports.manage';
const kPermContentRemove     = 'content.remove';
const kPermAgenciesView      = 'agencies.view';
const kPermAgenciesCreate    = 'agencies.create';
const kPermAgenciesDelete    = 'agencies.delete';
const kPermHostsManage       = 'hosts.manage';
const kPermGiftsManage       = 'gifts.manage';
const kPermGiftsPrices       = 'gifts.prices';
const kPermVipManage         = 'vip.manage';
const kPermVipGrant          = 'vip.grant';
const kPermFramesManage      = 'frames.manage';
const kPermFramesGrant       = 'frames.grant';
const kPermCharismaOfficial  = 'charisma.official_manage';
const kPermCharismaAgency    = 'charisma.agency_manage';
const kPermCharismaCrown     = 'charisma.crown_winner';
const kPermDrawManage        = 'draw.manage';
const kPermDrawForceSettle   = 'draw.force_settle';
const kPermTreasureManage    = 'treasure.manage';
const kPermTreasurePrize     = 'treasure.prize_settings';
const kPermGamesLogs         = 'games.logs';
const kPermFinanceReport     = 'financial_reports.view';
const kPermFinanceExport     = 'financial_reports.export';
const kPermAnalytics         = 'analytics.view';
const kPermBanners           = 'banners.manage';
const kPermNotifSend         = 'notifications.send';
const kPermNotifBroadcast    = 'notifications.broadcast';
const kPermSettings          = 'settings.manage';
const kPermAdminsView        = 'admins.view';
const kPermAdminsCreate      = 'admins.create';
const kPermAdminsRemove      = 'admins.remove';
const kPermAdminsChangeRoles = 'admins.change_roles';
const kPermAuditLogs         = 'audit_logs.view';

// ── Service ───────────────────────────────────────────────────────────────────

class AdminRole {
  const AdminRole({
    required this.role,
    required this.isActive,
    required this.canUnban,
  });

  final String role;
  final bool isActive;
  final bool canUnban;

  bool get isOSuperAdmin => role == kRoleOSuperAdmin;
  bool get isPSuperAdmin => role == kRolePSuperAdmin;
  bool get isSuperAdmin  => role == kRoleSuperAdmin;
  bool get isAdmin       => role == kRoleAdmin;
  bool get isAnyAdmin    => isActive && role.isNotEmpty;

  String get displayLabel => kRoleLabels[role] ?? role;

  // Tier-based helpers (higher tiers include lower)
  bool get isAtLeastPSuperAdmin =>
      isOSuperAdmin || isPSuperAdmin;

  bool get isAtLeastSuperAdmin =>
      isOSuperAdmin || isPSuperAdmin || isSuperAdmin;

  // Default permission checks (mirrors Postgres has_admin_permission logic)
  bool hasPermission(String key) {
    switch (role) {
      case kRoleOSuperAdmin:
        return true;
      case kRolePSuperAdmin:
        return !{
          kPermUsersUnban,
          kPermUsersDelete,
          kPermWalletDebit,
          kPermWalletPrices,
          kPermGiftsPrices,
          kPermSettings,
          kPermAdminsCreate,
          kPermAdminsRemove,
          kPermAdminsChangeRoles,
          kPermDrawForceSettle,
          'draw.void_refund',
          kPermTreasurePrize,
        }.contains(key);
      case kRoleSuperAdmin:
        // super_admin has broad operational access across all modules but must
        // not reach owner-level authority. Excluded keys:
        //   • Admin staff management  (create/remove/change-roles of admins)
        //   • User unban / delete     (owner-only destructive user actions)
        //   • Financial overrides     (price changes, debit, force-settle, void)
        //   • Prize / treasure config (owner-only economy settings)
        // All excluded actions have a second guard in the dashboard
        // (isOSuperAdmin / canUnban), so this is belt-and-suspenders.
        return !{
          kPermAdminsCreate,
          kPermAdminsRemove,
          kPermAdminsChangeRoles,
          kPermUsersUnban,
          kPermUsersDelete,
          kPermWalletDebit,
          kPermWalletPrices,
          kPermGiftsPrices,
          kPermDrawForceSettle,
          'draw.void_refund',
          kPermTreasurePrize,
        }.contains(key);
      case kRoleAdmin:
        return {
          kPermUsersView,
          kPermUsersTempBan,
          kPermRoomsView,
          kPermRoomsClose,
          kPermReportsView,
          kPermReportsManage,
          kPermContentRemove,
        }.contains(key);
      default:
        return false;
    }
  }

  static const empty = AdminRole(
    role: '',
    isActive: false,
    canUnban: false,
  );

  factory AdminRole.fromJson(Map<String, dynamic> j) => AdminRole(
    role:     (j['role'] as String?) ?? '',
    isActive: (j['is_active'] as bool?) ?? false,
    canUnban: (j['can_unban'] as bool?) ?? false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class AdminAccessService {
  const AdminAccessService();

  static const Set<String> validRoles = {
    kRoleOSuperAdmin,
    kRolePSuperAdmin,
    kRoleSuperAdmin,
    kRoleAdmin,
  };

  /// Fetch the current user's admin role info from Supabase.
  Future<AdminRole> fetchCurrentAdminRole() async {
    final client = SupabaseService.requiredClient;
    final user   = client.auth.currentUser;

    if (user == null) {
      if (kDebugMode) debugPrint('[AdminAccess] No authenticated user.');
      return AdminRole.empty;
    }

    try {
      final raw = await client.rpc('admin_get_my_role');
      final j   = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
      final role = AdminRole.fromJson(j);

      if (kDebugMode) {
        debugPrint('[AdminAccess] uid=${user.id} role=${role.role} canUnban=${role.canUnban}');
      }

      return role;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminAccess] fetchCurrentAdminRole failed: $e');
        debugPrintStack(stackTrace: st);
      }
      return AdminRole.empty;
    }
  }

  /// Legacy shim: returns list with single role string for places that still
  /// call fetchCurrentUserRoles(). Remove callers gradually.
  Future<List<String>> fetchCurrentUserRoles() async {
    final role = await fetchCurrentAdminRole();
    return role.isAnyAdmin ? [role.role] : const [];
  }

  static bool isAdminRole(Iterable<String> roles) =>
      roles.any(validRoles.contains);

  Future<bool> canAccessAdmin() async =>
      (await fetchCurrentAdminRole()).isAnyAdmin;

  Future<bool> canUnbanUsers() async =>
      (await fetchCurrentAdminRole()).canUnban;

  Future<bool> isOSuperAdmin() async =>
      (await fetchCurrentAdminRole()).isOSuperAdmin;

  Future<bool> isPSuperAdmin() async =>
      (await fetchCurrentAdminRole()).isPSuperAdmin;

  Future<bool> isSuperAdmin() async =>
      (await fetchCurrentAdminRole()).isSuperAdmin;

  Future<bool> isAdmin() async =>
      (await fetchCurrentAdminRole()).isAdmin;

  // Legacy shim — used by admin_dashboard_screen
  Future<bool> canApproveRecharge() async =>
      (await fetchCurrentAdminRole()).hasPermission(kPermWalletCredit);

  Future<bool> canAdjustWallet() => canApproveRecharge();

  Future<bool> canManageBd() async =>
      (await fetchCurrentAdminRole()).hasPermission(kPermAgenciesView);

  Future<bool> canManageContent() async =>
      (await fetchCurrentAdminRole()).hasPermission(kPermGiftsManage);

  Future<bool> canManageRooms() async =>
      (await fetchCurrentAdminRole()).hasPermission(kPermRoomsClose);
}
