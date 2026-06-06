class UserLevel {
  const UserLevel({
    required this.level,
    required this.xp,
    required this.totalSpentCoins,
    required this.totalReceivedGiftsValue,
    required this.totalRoomMinutes,
  });

  final int level;
  final int xp;
  final int totalSpentCoins;
  final int totalReceivedGiftsValue;
  final int totalRoomMinutes;

  factory UserLevel.fromJson(Map<String, dynamic> json) => UserLevel(
    level: _intValue(json['level'], fallback: 1),
    xp: _intValue(json['xp']),
    totalSpentCoins: _intValue(json['total_spent_coins']),
    totalReceivedGiftsValue: _intValue(json['total_received_gifts_value']),
    totalRoomMinutes: _intValue(json['total_room_minutes']),
  );
}

class LevelRule {
  const LevelRule({
    required this.level,
    required this.title,
    required this.requiredXp,
    required this.benefits,
    this.badgeKey,
    this.colorName,
  });

  final int level;
  final String title;
  final int requiredXp;
  final List<String> benefits;
  final String? badgeKey;
  final String? colorName;

  factory LevelRule.fromJson(Map<String, dynamic> json) => LevelRule(
    level: _intValue(json['level'], fallback: 1),
    title: json['title']?.toString() ?? 'Level',
    requiredXp: _intValue(json['required_xp']),
    badgeKey: json['badge_key']?.toString(),
    colorName: json['color_name']?.toString(),
    benefits: _stringList(json['benefits']),
  );
}

class AgencyApplication {
  const AgencyApplication({
    required this.id,
    required this.applicationType,
    required this.status,
    this.message,
    this.createdAt,
  });

  final String id;
  final String applicationType;
  final String status;
  final String? message;
  final DateTime? createdAt;

  factory AgencyApplication.fromJson(Map<String, dynamic> json) =>
      AgencyApplication(
        id: json['id']?.toString() ?? '',
        applicationType: json['application_type']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        message: json['message']?.toString(),
        createdAt: _dateValue(json['created_at']),
      );
}

class AgencyMembership {
  const AgencyMembership({
    required this.role,
    required this.status,
    required this.agencyName,
    required this.commissionRate,
    required this.monthlyTargetCoins,
    required this.monthlyTargetHours,
    this.country,
  });

  final String role;
  final String status;
  final String agencyName;
  final double commissionRate;
  final int monthlyTargetCoins;
  final double monthlyTargetHours;
  final String? country;

  factory AgencyMembership.fromJson(Map<String, dynamic> json) {
    final agency = json['agencies'] is Map<String, dynamic>
        ? json['agencies'] as Map<String, dynamic>
        : <String, dynamic>{};

    return AgencyMembership(
      role: json['role']?.toString() ?? 'host',
      status: json['status']?.toString() ?? 'pending',
      agencyName: agency['name']?.toString() ?? 'Agency',
      country: agency['country']?.toString(),
      commissionRate: _doubleValue(agency['commission_rate']),
      monthlyTargetCoins: _intValue(agency['monthly_target_coins']),
      monthlyTargetHours: _doubleValue(agency['monthly_target_hours']),
    );
  }
}

class IncomeAccount {
  const IncomeAccount({
    required this.availableBalanceUsd,
    required this.pendingBalanceUsd,
    required this.lifetimeIncomeUsd,
    required this.availableCoinsReward,
    required this.pendingCoinsReward,
  });

  final double availableBalanceUsd;
  final double pendingBalanceUsd;
  final double lifetimeIncomeUsd;
  final int availableCoinsReward;
  final int pendingCoinsReward;

  factory IncomeAccount.fromJson(Map<String, dynamic> json) => IncomeAccount(
    availableBalanceUsd: _doubleValue(json['available_balance_usd']),
    pendingBalanceUsd: _doubleValue(json['pending_balance_usd']),
    lifetimeIncomeUsd: _doubleValue(json['lifetime_income_usd']),
    availableCoinsReward: _intValue(json['available_coins_reward']),
    pendingCoinsReward: _intValue(json['pending_coins_reward']),
  );
}

class IncomeTransaction {
  const IncomeTransaction({
    required this.sourceType,
    required this.status,
    required this.amountUsd,
    required this.coinsValue,
    this.description,
    this.createdAt,
  });

  final String sourceType;
  final String status;
  final double amountUsd;
  final int coinsValue;
  final String? description;
  final DateTime? createdAt;

  factory IncomeTransaction.fromJson(Map<String, dynamic> json) =>
      IncomeTransaction(
        sourceType: json['source_type']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        amountUsd: _doubleValue(json['amount_usd']),
        coinsValue: _intValue(json['coins_value']),
        description: json['description']?.toString(),
        createdAt: _dateValue(json['created_at']),
      );
}

class BadgeItem {
  const BadgeItem({
    required this.id,
    required this.badgeKey,
    required this.name,
    required this.category,
    required this.rarity,
    required this.isOwned,
    required this.isEquipped,
    this.description,
    this.requiredLevel,
    this.requiredVipLevel,
    this.priceCoins = 0,
  });

  final String id;
  final String badgeKey;
  final String name;
  final String? description;
  final String category;
  final String rarity;
  final int? requiredLevel;
  final int? requiredVipLevel;
  final int priceCoins;
  final bool isOwned;
  final bool isEquipped;

  factory BadgeItem.fromJson(
    Map<String, dynamic> json, {
    bool isOwned = false,
    bool isEquipped = false,
  }) => BadgeItem(
    id: json['id']?.toString() ?? '',
    badgeKey: json['badge_key']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Badge',
    description: json['description']?.toString(),
    category: json['category']?.toString() ?? 'achievement',
    rarity: json['rarity']?.toString() ?? 'common',
    requiredLevel: _nullableInt(json['required_level']),
    requiredVipLevel: _nullableInt(json['required_vip_level']),
    priceCoins: _intValue(json['price_coins']),
    isOwned: isOwned,
    isEquipped: isEquipped,
  );
}

class FeedbackTicket {
  const FeedbackTicket({
    required this.id,
    required this.category,
    required this.title,
    required this.message,
    required this.status,
    this.adminReply,
    this.createdAt,
  });

  final String id;
  final String category;
  final String title;
  final String message;
  final String status;
  final String? adminReply;
  final DateTime? createdAt;

  factory FeedbackTicket.fromJson(Map<String, dynamic> json) => FeedbackTicket(
    id: json['id']?.toString() ?? '',
    category: json['category']?.toString() ?? 'other',
    title: json['title']?.toString() ?? 'Feedback',
    message: json['message']?.toString() ?? '',
    status: json['status']?.toString() ?? 'open',
    adminReply: json['admin_reply']?.toString(),
    createdAt: _dateValue(json['created_at']),
  );
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.category,
    required this.subject,
    required this.message,
    required this.status,
    this.adminReply,
    this.createdAt,
  });

  final String id;
  final String category;
  final String subject;
  final String message;
  final String status;
  final String? adminReply;
  final DateTime? createdAt;

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
    id: json['id']?.toString() ?? '',
    category: json['category']?.toString() ?? 'other',
    subject: json['subject']?.toString() ?? 'Support',
    message: json['message']?.toString() ?? '',
    status: json['status']?.toString() ?? 'open',
    adminReply: json['admin_reply']?.toString(),
    createdAt: _dateValue(json['created_at']),
  );
}

class UserSettings {
  const UserSettings({
    required this.language,
    required this.themeMode,
    required this.notificationsEnabled,
    required this.roomInvitesEnabled,
    required this.giftNotificationsEnabled,
    required this.privacyProfileVisibility,
    required this.privacyShowOnline,
  });

  final String language;
  final String themeMode;
  final bool notificationsEnabled;
  final bool roomInvitesEnabled;
  final bool giftNotificationsEnabled;
  final String privacyProfileVisibility;
  final bool privacyShowOnline;

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
    language: json['language']?.toString() ?? 'en',
    themeMode: json['theme_mode']?.toString() ?? 'dark',
    notificationsEnabled: json['notifications_enabled'] != false,
    roomInvitesEnabled: json['room_invites_enabled'] != false,
    giftNotificationsEnabled: json['gift_notifications_enabled'] != false,
    privacyProfileVisibility:
        json['privacy_profile_visibility']?.toString() ?? 'public',
    privacyShowOnline: json['privacy_show_online'] != false,
  );
}

int _intValue(dynamic value, {int fallback = 0}) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _nullableInt(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value.toString());
}

double _doubleValue(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _dateValue(dynamic value) {
  if (value == null) {
    return null;
  }

  return DateTime.tryParse(value.toString());
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }

  return const [];
}
