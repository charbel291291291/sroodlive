import '../../../core/supabase/supabase_service.dart';

class AdminAccessService {
  const AdminAccessService();

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
    return roles.contains('super_admin') ||
        roles.contains('finance_admin') ||
        roles.contains('bd_admin') ||
        roles.contains('content_admin') ||
        roles.contains('room_admin') ||
        roles.contains('support_admin') ||
        roles.contains('admin') ||
        roles.contains('support') ||
        roles.contains('moderator') ||
        roles.contains('viewer');
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
