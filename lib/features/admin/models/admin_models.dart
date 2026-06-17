class AdminOverview {
  const AdminOverview({
    required this.pendingRechargeCount,
    required this.approvedRechargeCountToday,
    required this.totalCoinsChargedToday,
    required this.totalGiftCoinsSpentToday,
    required this.totalDiamondsEarnedToday,
    required this.totalGiftTransactionsToday,
  });

  final int pendingRechargeCount;
  final int approvedRechargeCountToday;
  final int totalCoinsChargedToday;
  final int totalGiftCoinsSpentToday;
  final int totalDiamondsEarnedToday;
  final int totalGiftTransactionsToday;

  factory AdminOverview.fromJson(Map<String, dynamic> json) {
    return AdminOverview(
      pendingRechargeCount: _intValue(json['pending_recharge_count']),
      approvedRechargeCountToday: _intValue(
        json['approved_recharge_count_today'],
      ),
      totalCoinsChargedToday: _intValue(json['total_coins_charged_today']),
      totalGiftCoinsSpentToday: _intValue(json['total_gift_coins_spent_today']),
      totalDiamondsEarnedToday: _intValue(json['total_diamonds_earned_today']),
      totalGiftTransactionsToday: _intValue(
        json['total_gift_transactions_today'],
      ),
    );
  }
}

class AdminRoleSpec {
  const AdminRoleSpec({
    required this.role,
    required this.label,
    required this.description,
    required this.priority,
  });

  final String role;
  final String label;
  final String description;
  final int priority;

  // Only roles that can be assigned (not o_super_admin — that is the owner)
  static const all = [
    AdminRoleSpec(
      role: 'p_super_admin',
      label: 'P-Super Admin',
      description: 'Partner role. High-level access. Cannot unban, change roles, or delete audit logs.',
      priority: 3,
    ),
    AdminRoleSpec(
      role: 'super_admin',
      label: 'Super Admin',
      description: 'Operational admin. Manages users, rooms, reports, agencies, and challenges.',
      priority: 2,
    ),
    AdminRoleSpec(
      role: 'admin',
      label: 'Admin',
      description: 'Basic moderator. Can review reports, close rooms, and temp-ban users.',
      priority: 1,
    ),
  ];

  static AdminRoleSpec byRole(String role) {
    return all.firstWhere(
      (item) => item.role == role,
      orElse: () => AdminRoleSpec(
        role: role,
        label: role,
        description: 'Custom role',
        priority: 0,
      ),
    );
  }
}

class AdminRechargeRequest {
  const AdminRechargeRequest({
    required this.id,
    required this.userId,
    required this.requestedCoins,
    required this.method,
    required this.status,
    this.publicUserId,
    this.nickname,
    this.requestedAmountUsd,
    this.referenceCode,
    this.agentCode,
    this.createdAt,
    this.agencyName,
    this.agentName,
  });

  final String id;
  final String userId;
  final String? publicUserId;
  final String? nickname;
  final int requestedCoins;
  final double? requestedAmountUsd;
  final String method;
  final String? referenceCode;
  final String? agentCode;
  final String status;
  final DateTime? createdAt;
  final String? agencyName;
  final String? agentName;

  factory AdminRechargeRequest.fromJson(Map<String, dynamic> json) {
    return AdminRechargeRequest(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      publicUserId: json['public_user_id']?.toString(),
      nickname: json['nickname']?.toString(),
      requestedCoins: _intValue(json['requested_coins']),
      requestedAmountUsd: _doubleValue(json['requested_amount_usd']),
      method: json['method']?.toString() ?? '-',
      referenceCode: json['reference_code']?.toString(),
      agentCode: json['agent_code']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      createdAt: _dateValue(json['created_at']),
      agencyName: json['agency_name']?.toString(),
      agentName: json['agent_name']?.toString(),
    );
  }
}

class AdminWalletSummary {
  const AdminWalletSummary({
    required this.userId,
    required this.coinsBalance,
    required this.diamondsBalance,
    required this.lifetimeCoinsCharged,
    required this.lifetimeCoinsSpent,
    required this.lifetimeDiamondsEarned,
    this.publicUserId,
    this.nickname,
    this.avatarUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String userId;
  final String? publicUserId;
  final String? nickname;
  final String? avatarUrl;
  final int coinsBalance;
  final int diamondsBalance;
  final int lifetimeCoinsCharged;
  final int lifetimeCoinsSpent;
  final int lifetimeDiamondsEarned;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminWalletSummary.fromJson(Map<String, dynamic> json) {
    return AdminWalletSummary(
      userId: json['user_id']?.toString() ?? '',
      publicUserId: json['public_user_id']?.toString(),
      nickname: json['nickname']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      coinsBalance: _intValue(json['coins_balance']),
      diamondsBalance: _intValue(json['diamonds_balance']),
      lifetimeCoinsCharged: _intValue(json['lifetime_coins_charged']),
      lifetimeCoinsSpent: _intValue(json['lifetime_coins_spent']),
      lifetimeDiamondsEarned: _intValue(json['lifetime_diamonds_earned']),
      createdAt: _dateValue(json['created_at']),
      updatedAt: _dateValue(json['updated_at']),
    );
  }
}

class AdminUserSummary {
  const AdminUserSummary({
    required this.userId,
    required this.coinsBalance,
    required this.diamondsBalance,
    required this.roles,
    this.publicUserId,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.vipLevel = 0,
    this.createdAt,
  });

  final String userId;
  final String? publicUserId;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final int vipLevel;
  final int coinsBalance;
  final int diamondsBalance;
  final List<String> roles;
  final DateTime? createdAt;

  String get title {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) return handle;
    return publicUserId ?? userId;
  }

  factory AdminUserSummary.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    return AdminUserSummary(
      userId: json['user_id']?.toString() ?? '',
      publicUserId: json['public_user_id']?.toString(),
      displayName: json['display_name']?.toString(),
      username: json['username']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      vipLevel: _intValue(json['vip_level']),
      coinsBalance: _intValue(json['coins_balance']),
      diamondsBalance: _intValue(json['diamonds_balance']),
      roles: rawRoles is List
          ? rawRoles.map((item) => item.toString()).toList()
          : const [],
      createdAt: _dateValue(json['created_at']),
    );
  }
}

class AdminWalletTransaction {
  const AdminWalletTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.direction,
    required this.coinsDelta,
    required this.diamondsDelta,
    this.publicUserId,
    this.nickname,
    this.note,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String? publicUserId;
  final String? nickname;
  final String type;
  final String direction;
  final int coinsDelta;
  final int diamondsDelta;
  final String? note;
  final DateTime? createdAt;

  factory AdminWalletTransaction.fromJson(Map<String, dynamic> json) {
    return AdminWalletTransaction(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      publicUserId: json['public_user_id']?.toString(),
      nickname: json['nickname']?.toString(),
      type: json['type']?.toString() ?? 'system',
      direction: json['direction']?.toString() ?? 'neutral',
      coinsDelta: _intValue(json['coins_delta']),
      diamondsDelta: _intValue(json['diamonds_delta']),
      note: json['note']?.toString(),
      createdAt: _dateValue(json['created_at']),
    );
  }
}

class AdminGiftTransaction {
  const AdminGiftTransaction({
    required this.id,
    required this.giftName,
    required this.giftCode,
    required this.giftPriceCoins,
    this.senderPublicUserId,
    this.receiverPublicUserId,
    this.createdAt,
  });

  final String id;
  final String? senderPublicUserId;
  final String? receiverPublicUserId;
  final String giftName;
  final String giftCode;
  final int giftPriceCoins;
  final DateTime? createdAt;

  factory AdminGiftTransaction.fromJson(Map<String, dynamic> json) {
    return AdminGiftTransaction(
      id: json['id']?.toString() ?? '',
      senderPublicUserId: json['sender_public_user_id']?.toString(),
      receiverPublicUserId: json['receiver_public_user_id']?.toString(),
      giftName: json['gift_name']?.toString() ?? 'Gift',
      giftCode: json['gift_code']?.toString() ?? '',
      giftPriceCoins: _intValue(json['gift_price_coins']),
      createdAt: _dateValue(json['created_at']),
    );
  }
}

class AdminAgency {
  const AdminAgency({
    required this.id,
    required this.name,
    required this.code,
    required this.isActive,
    required this.commissionRate,
    this.country,
    this.whatsapp,
  });

  final String id;
  final String name;
  final String code;
  final String? country;
  final String? whatsapp;
  final bool isActive;
  final double commissionRate;

  factory AdminAgency.fromJson(Map<String, dynamic> json) {
    return AdminAgency(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      country: json['country']?.toString(),
      whatsapp: json['whatsapp']?.toString(),
      isActive: json['is_active'] == true,
      commissionRate: _doubleValue(json['commission_rate']) ?? 0,
    );
  }
}

class AdminAgent {
  const AdminAgent({
    required this.id,
    required this.name,
    required this.code,
    required this.isActive,
    required this.commissionRate,
    this.agencyCode,
    this.agencyName,
    this.whatsapp,
  });

  final String id;
  final String name;
  final String code;
  final String? agencyCode;
  final String? agencyName;
  final String? whatsapp;
  final bool isActive;
  final double commissionRate;

  factory AdminAgent.fromJson(Map<String, dynamic> json) {
    return AdminAgent(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      agencyCode: json['agency_code']?.toString(),
      agencyName: json['agency_name']?.toString(),
      whatsapp: json['whatsapp']?.toString(),
      isActive: json['is_active'] == true,
      commissionRate: _doubleValue(json['commission_rate']) ?? 0,
    );
  }
}

class AdminRoomSummary {
  const AdminRoomSummary({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.maxSeats,
    required this.isPrivate,
    required this.isLocked,
    required this.isClosed,
    required this.activeMembers,
    this.description,
    this.ownerPublicUserId,
    this.ownerName,
    this.language,
    this.closedAt,
    this.closedReason,
    this.createdAt,
  });

  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final String? ownerPublicUserId;
  final String? ownerName;
  final String? language;
  final int maxSeats;
  final bool isPrivate;
  final bool isLocked;
  final bool isClosed;
  final DateTime? closedAt;
  final String? closedReason;
  final int activeMembers;
  final DateTime? createdAt;

  factory AdminRoomSummary.fromJson(Map<String, dynamic> json) {
    return AdminRoomSummary(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      ownerId: json['owner_id']?.toString() ?? '',
      ownerPublicUserId: json['owner_public_user_id']?.toString(),
      ownerName: json['owner_name']?.toString(),
      language: json['language']?.toString(),
      maxSeats: _intValue(json['max_seats']),
      isPrivate: json['is_private'] == true,
      isLocked: json['is_locked'] == true,
      isClosed: json['is_closed'] == true,
      closedAt: _dateValue(json['closed_at']),
      closedReason: json['closed_reason']?.toString(),
      activeMembers: _intValue(json['active_members']),
      createdAt: _dateValue(json['created_at']),
    );
  }
}

class AdminGiftSummary {
  const AdminGiftSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.priceCoins,
    required this.isActive,
    required this.sortOrder,
    required this.sentCount,
    required this.coinsSpent,
    this.arabicName,
    this.icon,
    this.category = 'hot',
  });

  final String id;
  final String code;
  final String name;
  final String? arabicName;
  final int priceCoins;
  final String? icon;
  final String category;
  final bool isActive;
  final int sortOrder;
  final int sentCount;
  final int coinsSpent;

  factory AdminGiftSummary.fromJson(Map<String, dynamic> json) {
    return AdminGiftSummary(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Gift',
      arabicName: json['arabic_name']?.toString(),
      priceCoins: _intValue(json['price_coins']),
      icon: json['icon']?.toString(),
      category: json['category']?.toString() ?? 'hot',
      isActive: json['is_active'] == true,
      sortOrder: _intValue(json['sort_order']),
      sentCount: _intValue(json['sent_count']),
      coinsSpent: _intValue(json['coins_spent']),
    );
  }
}

class AdminUserDetail {
  const AdminUserDetail({
    required this.userId,
    required this.coinsBalance,
    required this.diamondsBalance,
    required this.lifetimeCoinsCharged,
    required this.lifetimeCoinsSpent,
    required this.lifetimeDiamondsEarned,
    required this.roles,
    required this.activeRestrictions,
    this.email,
    this.publicUserId,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.bio,
    this.dateOfBirth,
    this.vipLevel = 0,
    this.vipTitle,
    this.vipStartedAt,
    this.vipExpiresAt,
    this.selectedAvatarFrameKey,
    this.createdAt,
  });

  final String userId;
  final String? email;
  final String? publicUserId;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final DateTime? dateOfBirth;
  final int vipLevel;
  final String? vipTitle;
  final DateTime? vipStartedAt;
  final DateTime? vipExpiresAt;
  final String? selectedAvatarFrameKey;
  final int coinsBalance;
  final int diamondsBalance;
  final int lifetimeCoinsCharged;
  final int lifetimeCoinsSpent;
  final int lifetimeDiamondsEarned;
  final List<String> roles;
  final List<AdminUserRestriction> activeRestrictions;
  final DateTime? createdAt;

  String get title {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) return handle;
    return publicUserId ?? email ?? userId;
  }

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    final rawRestrictions = json['active_restrictions'];
    return AdminUserDetail(
      userId: json['user_id']?.toString() ?? '',
      email: json['email']?.toString(),
      publicUserId: json['public_user_id']?.toString(),
      displayName: json['display_name']?.toString(),
      username: json['username']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      bio: json['bio']?.toString(),
      dateOfBirth: _dateValue(json['date_of_birth']),
      vipLevel: _intValue(json['vip_level']),
      vipTitle: json['vip_title']?.toString(),
      vipStartedAt: _dateValue(json['vip_started_at']),
      vipExpiresAt: _dateValue(json['vip_expires_at']),
      selectedAvatarFrameKey: json['selected_avatar_frame_key']?.toString(),
      coinsBalance: _intValue(json['coins_balance']),
      diamondsBalance: _intValue(json['diamonds_balance']),
      lifetimeCoinsCharged: _intValue(json['lifetime_coins_charged']),
      lifetimeCoinsSpent: _intValue(json['lifetime_coins_spent']),
      lifetimeDiamondsEarned: _intValue(json['lifetime_diamonds_earned']),
      roles: rawRoles is List
          ? rawRoles.map((item) => item.toString()).toList()
          : const [],
      activeRestrictions: rawRestrictions is List
          ? rawRestrictions
                .whereType<Map<String, dynamic>>()
                .map(AdminUserRestriction.fromJson)
                .toList()
          : const [],
      createdAt: _dateValue(json['created_at']),
    );
  }
}

class AdminUserRestriction {
  const AdminUserRestriction({
    required this.id,
    required this.type,
    this.reason,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String type;
  final String? reason;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  factory AdminUserRestriction.fromJson(Map<String, dynamic> json) {
    return AdminUserRestriction(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      reason: json['reason']?.toString(),
      expiresAt: _dateValue(json['expires_at']),
      createdAt: _dateValue(json['created_at']),
    );
  }
}

class AdminUserLedgerRow {
  const AdminUserLedgerRow({
    required this.id,
    required this.type,
    required this.direction,
    required this.coinsDelta,
    required this.diamondsDelta,
    this.note,
    this.createdAt,
  });

  final String id;
  final String type;
  final String direction;
  final int coinsDelta;
  final int diamondsDelta;
  final String? note;
  final DateTime? createdAt;

  factory AdminUserLedgerRow.fromJson(Map<String, dynamic> json) {
    return AdminUserLedgerRow(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      direction: json['direction']?.toString() ?? '',
      coinsDelta: _intValue(json['coins_delta']),
      diamondsDelta: _intValue(json['diamonds_delta']),
      note: json['note']?.toString(),
      createdAt: _dateValue(json['created_at']),
    );
  }
}

class AdminUserRechargeRow {
  const AdminUserRechargeRow({
    required this.id,
    required this.requestedCoins,
    required this.method,
    required this.status,
    this.requestedAmountUsd,
    this.referenceCode,
    this.agentCode,
    this.createdAt,
    this.approvedAt,
    this.rejectedAt,
  });

  final String id;
  final int requestedCoins;
  final double? requestedAmountUsd;
  final String method;
  final String status;
  final String? referenceCode;
  final String? agentCode;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;

  factory AdminUserRechargeRow.fromJson(Map<String, dynamic> json) {
    return AdminUserRechargeRow(
      id: json['id']?.toString() ?? '',
      requestedCoins: _intValue(json['requested_coins']),
      requestedAmountUsd: _doubleValue(json['requested_amount_usd']),
      method: json['method']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      referenceCode: json['reference_code']?.toString(),
      agentCode: json['agent_code']?.toString(),
      createdAt: _dateValue(json['created_at']),
      approvedAt: _dateValue(json['approved_at']),
      rejectedAt: _dateValue(json['rejected_at']),
    );
  }
}

class AdminUserGiftRow {
  const AdminUserGiftRow({
    required this.id,
    required this.direction,
    required this.giftName,
    required this.giftCode,
    required this.giftPriceCoins,
    this.otherPublicUserId,
    this.createdAt,
  });

  final String id;
  final String direction;
  final String? otherPublicUserId;
  final String giftName;
  final String giftCode;
  final int giftPriceCoins;
  final DateTime? createdAt;

  factory AdminUserGiftRow.fromJson(Map<String, dynamic> json) {
    return AdminUserGiftRow(
      id: json['id']?.toString() ?? '',
      direction: json['direction']?.toString() ?? '',
      otherPublicUserId: json['other_public_user_id']?.toString(),
      giftName: json['gift_name']?.toString() ?? 'Gift',
      giftCode: json['gift_code']?.toString() ?? '',
      giftPriceCoins: _intValue(json['gift_price_coins']),
      createdAt: _dateValue(json['created_at']),
    );
  }
}

class AdminFinanceReport {
  const AdminFinanceReport({
    required this.approvedRecharges,
    required this.rejectedRecharges,
    required this.pendingRecharges,
    required this.coinsCharged,
    required this.giftTransactions,
    required this.giftCoinsSpent,
    required this.diamondsEarned,
    required this.manualAdjustmentCount,
  });

  final int approvedRecharges;
  final int rejectedRecharges;
  final int pendingRecharges;
  final int coinsCharged;
  final int giftTransactions;
  final int giftCoinsSpent;
  final int diamondsEarned;
  final int manualAdjustmentCount;

  factory AdminFinanceReport.fromJson(Map<String, dynamic> json) {
    return AdminFinanceReport(
      approvedRecharges: _intValue(json['approved_recharges']),
      rejectedRecharges: _intValue(json['rejected_recharges']),
      pendingRecharges: _intValue(json['pending_recharges']),
      coinsCharged: _intValue(json['coins_charged']),
      giftTransactions: _intValue(json['gift_transactions']),
      giftCoinsSpent: _intValue(json['gift_coins_spent']),
      diamondsEarned: _intValue(json['diamonds_earned']),
      manualAdjustmentCount: _intValue(json['manual_adjustment_count']),
    );
  }
}

class AdminWithdrawalRequest {
  const AdminWithdrawalRequest({
    required this.id,
    required this.userId,
    required this.diamondsAmount,
    required this.grossUsd,
    required this.hostShareUsd,
    required this.platformShareUsd,
    required this.method,
    required this.accountDetails,
    required this.status,
    this.publicUserId,
    this.displayName,
    this.agencyShareUsd = 0,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String? publicUserId;
  final String? displayName;
  final int diamondsAmount;
  final double grossUsd;
  final double hostShareUsd;
  final double agencyShareUsd;
  final double platformShareUsd;
  final String method;
  final String accountDetails;
  final String? notes;
  final String status;
  final DateTime? createdAt;

  factory AdminWithdrawalRequest.fromJson(Map<String, dynamic> json) {
    return AdminWithdrawalRequest(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      publicUserId: json['public_user_id']?.toString(),
      displayName: json['display_name']?.toString(),
      diamondsAmount: _intValue(json['diamonds']),
      grossUsd: _doubleValue(json['gross_usd']) ?? 0,
      hostShareUsd: _doubleValue(json['host_share_usd']) ?? 0,
      agencyShareUsd: _doubleValue(json['agency_share_usd']) ?? 0,
      platformShareUsd: _doubleValue(json['platform_share_usd']) ?? 0,
      method: json['method']?.toString() ?? '-',
      accountDetails: json['account_details']?.toString() ?? '-',
      notes: json['notes']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      createdAt: _dateValue(json['created_at']),
    );
  }
}

class AdminBdReportRow {
  const AdminBdReportRow({
    required this.approvedCount,
    required this.coinsCharged,
    this.agencyName,
    this.agencyCode,
    this.agentName,
    this.agentCode,
  });

  final String? agencyName;
  final String? agencyCode;
  final String? agentName;
  final String? agentCode;
  final int approvedCount;
  final int coinsCharged;

  factory AdminBdReportRow.fromJson(Map<String, dynamic> json) {
    return AdminBdReportRow(
      agencyName: json['agency_name']?.toString(),
      agencyCode: json['agency_code']?.toString(),
      agentName: json['agent_name']?.toString(),
      agentCode: json['agent_code']?.toString(),
      approvedCount: _intValue(json['approved_count']),
      coinsCharged: _intValue(json['coins_charged']),
    );
  }
}

class AdminAvatarFrameSummary {
  const AdminAvatarFrameSummary({
    required this.id,
    required this.frameKey,
    required this.name,
    required this.category,
    required this.isActive,
    required this.isFeatured,
    required this.sortOrder,
    required this.usageCount,
    this.vipLevel,
    this.requiredVipLevel,
    this.assetUrl,
  });

  final String id;
  final String frameKey;
  final String name;
  final String category;
  final int? vipLevel;
  final int? requiredVipLevel;
  final String? assetUrl;
  final bool isActive;
  final bool isFeatured;
  final int sortOrder;
  final int usageCount;

  factory AdminAvatarFrameSummary.fromJson(Map<String, dynamic> json) {
    return AdminAvatarFrameSummary(
      id: json['id']?.toString() ?? '',
      frameKey: json['frame_key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? 'normal',
      vipLevel: _nullableIntValue(json['vip_level']),
      requiredVipLevel: _nullableIntValue(json['required_vip_level']),
      assetUrl: json['asset_url']?.toString(),
      isActive: json['is_active'] == true,
      isFeatured: json['is_featured'] == true,
      sortOrder: _intValue(json['sort_order']),
      usageCount: _intValue(json['usage_count']),
    );
  }
}

class AdminVipPackage {
  const AdminVipPackage({
    required this.id,
    required this.vipLevel,
    required this.code,
    required this.name,
    required this.priceCoins,
    required this.durationDays,
    required this.isActive,
    required this.sortOrder,
    this.arabicName,
    this.badgeLabel,
    this.entranceBannerKey,
  });

  final String id;
  final int vipLevel;
  final String code;
  final String name;
  final String? arabicName;
  final int priceCoins;
  final int durationDays;
  final String? badgeLabel;
  final String? entranceBannerKey;
  final bool isActive;
  final int sortOrder;

  factory AdminVipPackage.fromJson(Map<String, dynamic> json) {
    return AdminVipPackage(
      id: json['id']?.toString() ?? '',
      vipLevel: _intValue(json['vip_level']),
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      arabicName: json['arabic_name']?.toString(),
      priceCoins: _intValue(json['price_coins']),
      durationDays: _intValue(json['duration_days']),
      badgeLabel: json['badge_label']?.toString(),
      entranceBannerKey: json['entrance_banner_key']?.toString(),
      isActive: json['is_active'] == true,
      sortOrder: _intValue(json['sort_order']),
    );
  }
}

class AdminEntranceBanner {
  const AdminEntranceBanner({
    required this.id,
    required this.bannerKey,
    required this.name,
    required this.isActive,
    required this.sortOrder,
    this.arabicName,
    this.vipLevel,
    this.assetUrl,
    this.gradientStart,
    this.gradientEnd,
    this.messageTemplate,
  });

  final String id;
  final String bannerKey;
  final String name;
  final String? arabicName;
  final int? vipLevel;
  final String? assetUrl;
  final String? gradientStart;
  final String? gradientEnd;
  final String? messageTemplate;
  final bool isActive;
  final int sortOrder;

  factory AdminEntranceBanner.fromJson(Map<String, dynamic> json) {
    return AdminEntranceBanner(
      id: json['id']?.toString() ?? '',
      bannerKey: json['banner_key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      arabicName: json['arabic_name']?.toString(),
      vipLevel: _nullableIntValue(json['vip_level']),
      assetUrl: json['asset_url']?.toString(),
      gradientStart: json['gradient_start']?.toString(),
      gradientEnd: json['gradient_end']?.toString(),
      messageTemplate: json['message_template']?.toString(),
      isActive: json['is_active'] == true,
      sortOrder: _intValue(json['sort_order']),
    );
  }
}

class AdminGiftCategory {
  const AdminGiftCategory({
    required this.id,
    required this.categoryKey,
    required this.name,
    required this.isActive,
    required this.sortOrder,
    this.arabicName,
    this.icon,
  });

  final String id;
  final String categoryKey;
  final String name;
  final String? arabicName;
  final String? icon;
  final bool isActive;
  final int sortOrder;

  factory AdminGiftCategory.fromJson(Map<String, dynamic> json) {
    return AdminGiftCategory(
      id: json['id']?.toString() ?? '',
      categoryKey: json['category_key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      arabicName: json['arabic_name']?.toString(),
      icon: json['icon']?.toString(),
      isActive: json['is_active'] == true,
      sortOrder: _intValue(json['sort_order']),
    );
  }
}

class AdminPromoBanner {
  const AdminPromoBanner({
    required this.id,
    required this.slideKey,
    required this.sortOrder,
    required this.isActive,
    required this.labelEn,
    required this.labelAr,
    required this.titleEn,
    required this.titleAr,
    required this.subtitleEn,
    required this.subtitleAr,
    required this.ctaEn,
    required this.ctaAr,
    required this.iconName,
    this.gradientStart,
    this.gradientMid,
    this.gradientEnd,
    this.iconBgColor,
    this.imageUrl,
    this.targetRoute,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String slideKey;
  final int sortOrder;
  final bool isActive;
  final String labelEn;
  final String labelAr;
  final String titleEn;
  final String titleAr;
  final String subtitleEn;
  final String subtitleAr;
  final String ctaEn;
  final String ctaAr;
  final String iconName;
  final String? gradientStart;
  final String? gradientMid;
  final String? gradientEnd;
  final String? iconBgColor;
  final String? imageUrl;
  final String? targetRoute;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminPromoBanner.fromJson(Map<String, dynamic> json) {
    return AdminPromoBanner(
      id: json['id']?.toString() ?? '',
      slideKey: json['slide_key']?.toString() ?? '',
      sortOrder: _intValue(json['sort_order']),
      isActive: json['is_active'] == true,
      labelEn: json['label_en']?.toString() ?? '',
      labelAr: json['label_ar']?.toString() ?? '',
      titleEn: json['title_en']?.toString() ?? '',
      titleAr: json['title_ar']?.toString() ?? '',
      subtitleEn: json['subtitle_en']?.toString() ?? '',
      subtitleAr: json['subtitle_ar']?.toString() ?? '',
      ctaEn: json['cta_en']?.toString() ?? '',
      ctaAr: json['cta_ar']?.toString() ?? '',
      iconName: json['icon_name']?.toString() ?? 'mic_rounded',
      gradientStart: json['gradient_start']?.toString(),
      gradientMid: json['gradient_mid']?.toString(),
      gradientEnd: json['gradient_end']?.toString(),
      iconBgColor: json['icon_bg_color']?.toString(),
      imageUrl: json['image_url']?.toString(),
      targetRoute: json['target_route']?.toString(),
      createdAt: _dateValue(json['created_at']),
      updatedAt: _dateValue(json['updated_at']),
    );
  }
}

class AdminAuditLog {
  const AdminAuditLog({
    required this.id,
    required this.action,
    required this.metadata,
    this.adminPublicUserId,
    this.adminName,
    this.targetPublicUserId,
    this.targetName,
    this.entityType,
    this.entityId,
    this.createdAt,
  });

  final String id;
  final String? adminPublicUserId;
  final String? adminName;
  final String? targetPublicUserId;
  final String? targetName;
  final String action;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  factory AdminAuditLog.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'];
    return AdminAuditLog(
      id: json['id']?.toString() ?? '',
      adminPublicUserId: json['admin_public_user_id']?.toString(),
      adminName: json['admin_name']?.toString(),
      targetPublicUserId: json['target_public_user_id']?.toString(),
      targetName: json['target_name']?.toString(),
      action: json['action']?.toString() ?? '',
      entityType: json['entity_type']?.toString(),
      entityId: json['entity_id']?.toString(),
      metadata: rawMetadata is Map<String, dynamic> ? rawMetadata : const {},
      createdAt: _dateValue(json['created_at']),
    );
  }
}

int _intValue(dynamic value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableIntValue(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _doubleValue(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

DateTime? _dateValue(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminReport — user_reports table
// ─────────────────────────────────────────────────────────────────────────────

class AdminReport {
  const AdminReport({
    required this.id,
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    this.reporterPublicUserId,
    this.reporterName,
    this.details,
    this.resolvedBy,
    this.resolvedByName,
    this.resolvedAt,
    this.resolutionNote,
    this.createdAt,
  });

  final String id;
  final String reporterId;
  final String? reporterPublicUserId;
  final String? reporterName;
  final String targetType;
  final String targetId;
  final String reason;
  final String? details;
  final String status;
  final String? resolvedBy;
  final String? resolvedByName;
  final DateTime? resolvedAt;
  final String? resolutionNote;
  final DateTime? createdAt;

  bool get isPending   => status == 'pending';
  bool get isResolved  => status == 'resolved';
  bool get isRejected  => status == 'rejected';

  factory AdminReport.fromJson(Map<String, dynamic> json) {
    return AdminReport(
      id:                    json['id']?.toString() ?? '',
      reporterId:            json['reporter_id']?.toString() ?? '',
      reporterPublicUserId:  json['reporter_public_user_id']?.toString(),
      reporterName:          json['reporter_name']?.toString(),
      targetType:            json['target_type']?.toString() ?? 'other',
      targetId:              json['target_id']?.toString() ?? '',
      reason:                json['reason']?.toString() ?? '',
      details:               json['details']?.toString(),
      status:                json['status']?.toString() ?? 'pending',
      resolvedBy:            json['resolved_by']?.toString(),
      resolvedByName:        json['resolved_by_name']?.toString(),
      resolvedAt:            _dateValue(json['resolved_at']),
      resolutionNote:        json['resolution_note']?.toString(),
      createdAt:             _dateValue(json['created_at']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminWithdrawalHistoryEntry — resolved withdrawal requests
// Reuses AdminWithdrawalRequest — no extra model needed.
// ─────────────────────────────────────────────────────────────────────────────
