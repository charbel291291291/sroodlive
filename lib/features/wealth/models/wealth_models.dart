import 'package:flutter/material.dart';

// Wealth tier enum - 10 tiers of 10 levels each (100 levels total).
enum WealthTier {
  bronze,
  silver,
  gold,
  emerald,
  sapphire,
  ruby,
  diamond,
  master,
  royal,
  legend;

  String get displayName {
    switch (this) {
      case WealthTier.bronze:   return 'Bronze';
      case WealthTier.silver:   return 'Silver';
      case WealthTier.gold:     return 'Gold';
      case WealthTier.emerald:  return 'Emerald';
      case WealthTier.sapphire: return 'Sapphire';
      case WealthTier.ruby:     return 'Ruby';
      case WealthTier.diamond:  return 'Diamond';
      case WealthTier.master:   return 'Master';
      case WealthTier.royal:    return 'Royal';
      case WealthTier.legend:   return 'Legend';
    }
  }

  // Tier number (1-10).
  int get number => index + 1;

  // Level range for this tier.
  int get minLevel => index * 10 + 1;
  int get maxLevel => index * 10 + 10;

  Color get color {
    switch (this) {
      case WealthTier.bronze:   return const Color(0xFF8B5E3C);
      case WealthTier.silver:   return const Color(0xFF9E9E9E);
      case WealthTier.gold:     return const Color(0xFFF0C15A);
      case WealthTier.emerald:  return const Color(0xFF2ECC71);
      case WealthTier.sapphire: return const Color(0xFF2E86DE);
      case WealthTier.ruby:     return const Color(0xFFE74C3C);
      case WealthTier.diamond:  return const Color(0xFF00D4FF);
      case WealthTier.master:   return const Color(0xFF9B59B6);
      case WealthTier.royal:    return const Color(0xFF8B26D9);
      case WealthTier.legend:   return const Color(0xFFFFD700);
    }
  }

  // Glow color for badge.
  Color get glowColor => color.withValues(alpha: 0.5);

  // Badge icon character used in the compact badge widget.
  String get icon {
    switch (this) {
      case WealthTier.bronze:   return String.fromCharCodes([0x1F7EB]); // 🟫 brown square
      case WealthTier.silver:   return '⭐'; // star
      case WealthTier.gold:     return String.fromCharCodes([0x1F31F]); // 🌟 glowing star
      case WealthTier.emerald:  return String.fromCharCodes([0x1F48E]); // 💎 gem stone
      case WealthTier.sapphire: return String.fromCharCodes([0x1F499]); // 💙 blue heart (distinct from diamond)
      case WealthTier.ruby:     return '❤'; // red heart
      case WealthTier.diamond:  return String.fromCharCodes([0x1F4A0]); // 💠 diamond shape
      case WealthTier.master:   return String.fromCharCodes([0x1F300]); // 🌀 cyclone purple
      case WealthTier.royal:    return String.fromCharCodes([0x1F451]); // 👑 crown
      case WealthTier.legend:   return String.fromCharCodes([0x1F3C6]); // 🏆 trophy
    }
  }

  // Unambiguous abbreviation used in compact badge text.
  // Silver/Sapphire and Ruby/Royal share the same first letter so two-char
  // codes are used to avoid display collisions.
  String get abbreviation {
    switch (this) {
      case WealthTier.bronze:   return 'B';
      case WealthTier.silver:   return 'Si';
      case WealthTier.gold:     return 'G';
      case WealthTier.emerald:  return 'E';
      case WealthTier.sapphire: return 'Sa';
      case WealthTier.ruby:     return 'Ru';
      case WealthTier.diamond:  return 'D';
      case WealthTier.master:   return 'M';
      case WealthTier.royal:    return 'Ro';
      case WealthTier.legend:   return 'L';
    }
  }

  static WealthTier fromNumber(int n) =>
      WealthTier.values[(n - 1).clamp(0, 9)];

  static WealthTier fromLevel(int level) =>
      fromNumber(((level - 1) ~/ 10) + 1);
}

// Full wealth progress snapshot for the authenticated user.
class UserWealth {
  const UserWealth({
    required this.wealthLevel,
    required this.wealthXp,
    required this.tierNumber,
    required this.tierName,
    required this.colorHex,
    required this.badgeKey,
    this.nextLevel,
    this.nextLevelRequiredXp,
    this.xpToNextLevel,
    this.levelProgress,
    this.totalRechargedXp = 0,
    this.totalSpentGiftXp = 0,
    this.lastXpAt,
  });

  final int wealthLevel;
  final int wealthXp;
  final int tierNumber;
  final String tierName;
  final String colorHex;
  final String badgeKey;
  final int? nextLevel;
  final int? nextLevelRequiredXp;
  final int? xpToNextLevel;
  final double? levelProgress;
  final int totalRechargedXp;
  final int totalSpentGiftXp;
  final DateTime? lastXpAt;

  bool get isMaxLevel => nextLevel == null;
  WealthTier get tier => WealthTier.fromNumber(tierNumber);

  factory UserWealth.fromJson(Map<String, dynamic> json) => UserWealth(
    wealthLevel:         _int(json['wealth_level'], 1),
    wealthXp:            _int(json['wealth_xp']),
    tierNumber:          _int(json['tier_number'], 1),
    tierName:            json['tier_name']?.toString() ?? 'Bronze',
    colorHex:            json['color_hex']?.toString() ?? '#8B5E3C',
    badgeKey:            json['badge_key']?.toString() ?? 'wealth_bronze',
    nextLevel:           _nullInt(json['next_level']),
    nextLevelRequiredXp: _nullInt(json['next_level_required_xp']),
    xpToNextLevel:       _nullInt(json['xp_to_next_level']),
    levelProgress:       _nullDouble(json['level_progress']),
    totalRechargedXp:    _int(json['total_recharged_xp']),
    totalSpentGiftXp:    _int(json['total_spent_gift_xp']),
    lastXpAt: json['last_xp_at'] != null
        ? DateTime.tryParse(json['last_xp_at'].toString())
        : null,
  );

  // Minimal snapshot used for displaying another user's badge.
  factory UserWealth.displayFromJson(Map<String, dynamic> json) => UserWealth(
    wealthLevel: _int(json['wealth_level'], 1),
    wealthXp:    0,
    tierNumber:  _int(json['tier_number'], 1),
    tierName:    json['tier_name']?.toString() ?? 'Bronze',
    colorHex:    json['color_hex']?.toString() ?? '#8B5E3C',
    badgeKey:    json['badge_key']?.toString() ?? 'wealth_bronze',
  );

  static UserWealth get empty => const UserWealth(
    wealthLevel: 1, wealthXp: 0, tierNumber: 1,
    tierName: 'Bronze', colorHex: '#8B5E3C', badgeKey: 'wealth_bronze',
    levelProgress: 0,
  );
}

// One row from wealth_level_rules.
class WealthLevelRule {
  const WealthLevelRule({
    required this.level,
    required this.tierNumber,
    required this.tierName,
    required this.requiredXp,
    required this.badgeKey,
    required this.colorHex,
  });

  final int level;
  final int tierNumber;
  final String tierName;
  final int requiredXp;
  final String badgeKey;
  final String colorHex;

  WealthTier get tier => WealthTier.fromNumber(tierNumber);

  factory WealthLevelRule.fromJson(Map<String, dynamic> json) => WealthLevelRule(
    level:      _int(json['level'], 1),
    tierNumber: _int(json['tier_number'], 1),
    tierName:   json['tier_name']?.toString() ?? 'Bronze',
    requiredXp: _int(json['required_xp']),
    badgeKey:   json['badge_key']?.toString() ?? 'wealth_bronze',
    colorHex:   json['color_hex']?.toString() ?? '#8B5E3C',
  );
}

// Helpers

int _int(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? _nullInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _nullDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
