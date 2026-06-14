import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_service.dart';

class AdminAccessService {
  const AdminAccessService();

  /// Roles allowed to open the admin dashboard.
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

  static String normalizeRole(String role) => role.trim().toLowerCase();

  static List<String> normalizeRoles(Iterable<String> roles) {
    return roles
        .map(normalizeRole)
        .where((role) => role.isNotEmpty)
        .toSet()
        .toList();
  }

  static bool isAdminRole(Iterable<String> roles) {
    final normalized = normalizeRoles(roles);
    return normalized.any(adminRoles.contains);
  }

  Future<List<String>> fetchCurrentUserRoles() async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      if (kDebugMode) {
        debugPrint('[AdminAccess] No authenticated user found.');
      }
      return const [];
    }

    try {
      final data = await client
          .from('app_user_roles')
          .select('role')
          .eq('user_id', user.id);

      final roles = normalizeRoles(
        (data as List<dynamic>).map(
          (item) => (item as Map<String, dynamic>)['role']?.toString() ?? '',
        ),
      );

      if (kDebugMode) {
        debugPrint('[AdminAccess] User email: ${user.email}');
        debugPrint('[AdminAccess] User id: ${user.id}');
        debugPrint('[AdminAccess] Roles: $roles');
        debugPrint('[AdminAccess] Can access admin: ${isAdminRole(roles)}');
      }

      return roles;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AdminAccess] Failed to fetch roles: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return const [];
    }
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
