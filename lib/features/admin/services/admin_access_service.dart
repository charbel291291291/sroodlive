import '../../../core/supabase/supabase_service.dart';

class AdminAccessService {
  const AdminAccessService();

  /// Roles that may open the admin dashboard. Both 'admin' and 'super_admin'
  /// are authorized admin roles, alongside the existing scoped admin roles.
  static const Set<String> adminRoles = {
    'super_admin',
    'admin',
    'finance_admin',
    'bd_admin',
    'content_admin',
    'room_admin',
    'support_admin',
    'support',
    'moderator',
    'viewer',
  };

  /// True if any of [roles] is an authorized admin role. Comparison is
  /// trimmed and case-insensitive so a stored value like 'Super_Admin' or
  /// ' super_admin ' still grants access.
  static bool isAdminRole(Iterable<String> roles) {
    return roles.any(
      (role) => adminRoles.contains(role.trim().toLowerCase()),
    );
  }

  Future<List<String>> fetchCurrentUserRoles() async {
    final data = await SupabaseService.requiredClient
        .from('app_user_roles')
        .select('role');

    return (data as List<dynamic>)
        .map((item) => (item as Map<String, dynamic>)['role']?.toString() ?? '')
        .where((role) => role.isNotEmpty)
        .toList();
  }

  Future<bool> canAccessAdmin() async {
    final roles = await fetchCurrentUserRoles();
    return isAdminRole(roles);
  }

  Future<bool> canApproveRecharge() async {
    final roles = await fetchCurrentUserRoles();
    return roles.contains('super_admin') || roles.contains('finance_admin');
  }

  Future<bool> canAdjustWallet() => canApproveRecharge();

  Future<bool> canManageBd() async {
    final roles = await fetchCurrentUserRoles();
    return roles.contains('super_admin') || roles.contains('bd_admin');
  }

  Future<bool> canManageContent() async {
    final roles = await fetchCurrentUserRoles();
    return roles.contains('super_admin') || roles.contains('content_admin');
  }

  Future<bool> canManageRooms() async {
    final roles = await fetchCurrentUserRoles();
    return roles.contains('super_admin') ||
        roles.contains('room_admin') ||
        roles.contains('moderator');
  }

  Future<bool> isSuperAdmin() async {
    return (await fetchCurrentUserRoles()).contains('super_admin');
  }

  Future<bool> isFinanceAdmin() async {
    return (await fetchCurrentUserRoles()).contains('finance_admin');
  }

  Future<bool> isAdmin() async {
    return (await fetchCurrentUserRoles()).contains('admin');
  }
}
