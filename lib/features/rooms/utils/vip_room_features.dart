import 'package:flutter/material.dart';

enum VipLevel {
  none(0),
  vip1(1),
  vip2(2),
  vip3(3),
  vip4(4),
  vip5(5);

  const VipLevel(this.value);

  final int value;

  static VipLevel fromInt(int level) {
    final normalized = level.clamp(0, 5).toInt();

    return switch (normalized) {
      1 => VipLevel.vip1,
      2 => VipLevel.vip2,
      3 => VipLevel.vip3,
      4 => VipLevel.vip4,
      5 => VipLevel.vip5,
      _ => VipLevel.none,
    };
  }
}

class VipFeatures {
  const VipFeatures._();

  static bool isVipActive({required int vipLevel, DateTime? vipExpiresAt}) {
    if (vipLevel <= 0) {
      return false;
    }

    if (vipExpiresAt == null) {
      return true;
    }

    return vipExpiresAt.isAfter(DateTime.now());
  }

  static int effectiveVipLevel({
    required int vipLevel,
    DateTime? vipExpiresAt,
  }) {
    if (!isVipActive(vipLevel: vipLevel, vipExpiresAt: vipExpiresAt)) {
      return 0;
    }

    return vipLevel.clamp(0, 5).toInt();
  }

  static String vipLabel(int level) {
    final effectiveLevel = level.clamp(0, 5);
    return effectiveLevel <= 0 ? '' : 'VIP $effectiveLevel';
  }

  static bool canUseVipFrame(String frameId, int effectiveVipLevel) {
    final requiredLevel = switch (frameId) {
      'vip_bronze_star' || 'vip_1' => 1,
      'vip_silver_flame' || 'vip_2' => 2,
      'vip_gold_crown' || 'vip_3' => 3,
      'vip_platinum_diamond' || 'vip_4' => 4,
      'vip_royal_king' || 'vip_5' => 5,
      _ => 0,
    };

    return effectiveVipLevel >= requiredLevel;
  }

  static bool hasSilentEntry(int effectiveVipLevel) {
    return effectiveVipLevel >= 4;
  }

  static bool hasKickProtection(int effectiveVipLevel) {
    return effectiveVipLevel >= 3;
  }

  static bool hasStrongKickProtection(int effectiveVipLevel) {
    return effectiveVipLevel >= 5;
  }

  static bool requiresKickConfirmation(int effectiveVipLevel) {
    return effectiveVipLevel == 4;
  }

  static bool hasProfileGlow(int effectiveVipLevel) {
    return effectiveVipLevel > 0;
  }

  static bool hasEntryBanner(int effectiveVipLevel) {
    return effectiveVipLevel > 0 && !hasSilentEntry(effectiveVipLevel);
  }

  static int visualPriorityScore(int effectiveVipLevel) {
    return effectiveVipLevel * 100;
  }

  static bool canKickVip5User({
    required bool isRoomOwner,
    required bool isSuperAdmin,
  }) {
    return isRoomOwner || isSuperAdmin;
  }
}

class VipVisualStyle {
  const VipVisualStyle._();

  static Color nameColor(int level, BuildContext context) {
    return switch (level) {
      1 => const Color(0xFFFFD978),
      2 => const Color(0xFFFFB0A6),
      3 => const Color(0xFFE4B5FF),
      4 => const Color(0xFF9BE8FF),
      5 => const Color(0xFFFFD15C),
      _ => DefaultTextStyle.of(context).style.color ?? Colors.white,
    };
  }

  static List<Color> gradient(int level) {
    return switch (level) {
      1 => const [Color(0xFFFFE3A3), Color(0xFFD99A2B)],
      2 => const [Color(0xFFFFCFB8), Color(0xFFFF6F7E)],
      3 => const [Color(0xFFFFD978), Color(0xFF8B26D9)],
      4 => const [Color(0xFFD8F6FF), Color(0xFF4CC9F0)],
      5 => const [Color(0xFFFFD978), Color(0xFFE0002B), Color(0xFF7D2BFF)],
      _ => const [Color(0xFF5A3A86), Color(0xFF241638)],
    };
  }

  static List<BoxShadow> glow(int level, {bool compact = false}) {
    if (level <= 0) {
      return const [];
    }

    final blur = compact ? 10.0 : 18.0 + (level * 3);
    final alpha = compact ? 0.18 : 0.20 + (level * 0.035);
    final color = switch (level) {
      1 => const Color(0xFFFFD978),
      2 => const Color(0xFFFFB0A6),
      3 => const Color(0xFFE4B5FF),
      4 => const Color(0xFF9BE8FF),
      5 => const Color(0xFFFFD15C),
      _ => Colors.transparent,
    };

    return [
      BoxShadow(
        color: color.withValues(alpha: alpha.clamp(0.0, 0.42)),
        blurRadius: blur,
        spreadRadius: compact ? 0 : level * 0.45,
      ),
    ];
  }
}

bool hasInvisibleEntry(int vipLevel) {
  return VipFeatures.hasSilentEntry(vipLevel);
}

bool hasStrongInvisibleEntry(int vipLevel) {
  return vipLevel >= 5;
}

bool requiresKickConfirmation(int vipLevel) {
  return VipFeatures.requiresKickConfirmation(vipLevel);
}

bool hasAntiKickProtection(int vipLevel) {
  return VipFeatures.hasStrongKickProtection(vipLevel);
}

bool canKickVip5User({required bool isRoomOwner, required bool isSuperAdmin}) {
  return VipFeatures.canKickVip5User(
    isRoomOwner: isRoomOwner,
    isSuperAdmin: isSuperAdmin,
  );
}
