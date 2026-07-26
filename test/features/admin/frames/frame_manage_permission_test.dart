/// Frame Management v2 — who may manage frames, client side.
///
/// The database is authoritative: every frames-v2 admin RPC and every
/// avatar-frames storage write policy is gated on `public.has_admin_access()`,
/// which is `has_app_role('admin') or has_app_role('super_admin')` and is
/// satisfied by all four `admin_users_role_check` values. These tests pin the
/// client mirror of that gate so the UI can never be *stricter* than the
/// server (hiding a screen an account may actually use) nor looser than it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/admin/services/admin_access_service.dart';

AdminRole _role(String role, {bool isActive = true}) =>
    AdminRole(role: role, isActive: isActive, canUnban: false);

void main() {
  group('frames.manage', () {
    test('a plain admin can manage frames', () {
      expect(_role(kRoleAdmin).hasPermission(kPermFramesManage), isTrue);
    });

    test('super admin can manage frames', () {
      expect(_role(kRoleSuperAdmin).hasPermission(kPermFramesManage), isTrue);
    });

    test('both super-admin tiers above it can manage frames', () {
      expect(_role(kRolePSuperAdmin).hasPermission(kPermFramesManage), isTrue);
      expect(_role(kRoleOSuperAdmin).hasPermission(kPermFramesManage), isTrue);
    });

    test('every role the server gate accepts can manage frames', () {
      // has_admin_access() accepts exactly AdminAccessService.validRoles.
      for (final role in AdminAccessService.validRoles) {
        expect(
          _role(role).hasPermission(kPermFramesManage),
          isTrue,
          reason: '$role passes has_admin_access() on the server',
        );
      }
    });

    test('a non-admin gets read-only, not manage', () {
      expect(AdminRole.empty.hasPermission(kPermFramesManage), isFalse);
      expect(_role('').hasPermission(kPermFramesManage), isFalse);
      expect(_role('moderator').hasPermission(kPermFramesManage), isFalse);
      expect(_role('viewer').hasPermission(kPermFramesManage), isFalse);
    });
  });

  group('the frames.manage grant widened nothing else', () {
    test('a plain admin still holds exactly its previous keys plus frames', () {
      const admin = AdminRole(
        role: kRoleAdmin,
        isActive: true,
        canUnban: false,
      );
      const granted = <String>{
        kPermUsersView,
        kPermUsersTempBan,
        kPermRoomsView,
        kPermRoomsClose,
        kPermReportsView,
        kPermReportsManage,
        kPermContentRemove,
        kPermFramesManage,
      };
      for (final key in granted) {
        expect(admin.hasPermission(key), isTrue, reason: '$key must be held');
      }
      for (final key in <String>[
        kPermFramesGrant,
        kPermUsersEdit,
        kPermUsersPermanentBan,
        kPermUsersUnban,
        kPermUsersDelete,
        kPermWalletCredit,
        kPermWalletDebit,
        kPermWalletPrices,
        kPermGiftsManage,
        kPermVipGrant,
        kPermSettings,
        kPermAdminsView,
        kPermAdminsCreate,
        kPermAdminsChangeRoles,
        kPermAuditLogs,
      ]) {
        expect(
          admin.hasPermission(key),
          isFalse,
          reason: '$key must stay outside the plain-admin set',
        );
      }
    });

    test('owner-level exclusions are untouched for the super tiers', () {
      expect(_role(kRoleSuperAdmin).hasPermission(kPermAdminsCreate), isFalse);
      expect(_role(kRolePSuperAdmin).hasPermission(kPermUsersDelete), isFalse);
      expect(_role(kRoleOSuperAdmin).hasPermission(kPermUsersDelete), isTrue);
    });
  });
}
