import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/vip/models/user_vip.dart';
import 'package:srood_live/features/vip/models/vip_permissions.dart';

void main() {
  group('UserVip', () {
    test('expired VIP has no effective level', () {
      final vip = UserVip(
        userId: 'user-1',
        vipLevel: 9,
        vipExpiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(vip.isVipActive, isFalse);
      expect(vip.effectiveVipLevel, 0);
      expect(vip.label, isEmpty);
    });

    test('active VIP clamps level and computes progress safely', () {
      final vip = UserVip(
        userId: 'user-1',
        vipLevel: 12,
        vipExpiresAt: DateTime.now().add(const Duration(days: 1)),
        rechargeExp: 150,
        currentTierRequiredExp: 100,
        nextTierRequiredExp: 200,
        monthlyExp: 75,
        monthlyMaintainExp: 100,
      );

      expect(vip.effectiveVipLevel, 9);
      expect(vip.nextTierProgress, 0.5);
      expect(vip.monthlyMaintainProgress, 0.75);
    });

    test('golden ID respects its own expiry', () {
      final vip = UserVip(
        userId: 'user-1',
        vipLevel: 1,
        isGoldenId: true,
        goldenIdExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );

      expect(vip.isGoldenIdActive, isFalse);
    });
  });

  group('VipPermissions', () {
    test('permission thresholds match effective VIP levels', () {
      expect(VipPermissions.fromLevel(0).canUseProfileFrame, isFalse);
      expect(VipPermissions.fromLevel(3).canUsePremiumEntrance, isTrue);
      expect(VipPermissions.fromLevel(7).canSendChatImage, isTrue);
      expect(VipPermissions.fromLevel(8).canUseAnimatedFrame, isTrue);
      expect(VipPermissions.fromLevel(7).maxChatImageMb, 5);
    });
  });
}
