enum WalletTransactionType {
  rechargeRequest,
  adminAdjustment,
  giftSent,
  giftReceived,
  agencyRecharge,
  refund,
  system,
}

enum WalletDirection { credit, debit, neutral }

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.direction,
    required this.coinsDelta,
    required this.diamondsDelta,
    this.balanceCoinsAfter,
    this.balanceDiamondsAfter,
    this.relatedUserId,
    this.note,
    this.createdAt,
  });

  final String id;
  final String userId;
  final WalletTransactionType type;
  final WalletDirection direction;
  final int coinsDelta;
  final int diamondsDelta;
  final int? balanceCoinsAfter;
  final int? balanceDiamondsAfter;
  final String? relatedUserId;
  final String? note;
  final DateTime? createdAt;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      type: _typeFromKey(json['type']?.toString()),
      direction: _directionFromKey(json['direction']?.toString()),
      coinsDelta: _intValue(json['coins_delta']),
      diamondsDelta: _intValue(json['diamonds_delta']),
      balanceCoinsAfter: _nullableInt(json['balance_coins_after']),
      balanceDiamondsAfter: _nullableInt(json['balance_diamonds_after']),
      relatedUserId: json['related_user_id']?.toString(),
      note: json['note']?.toString(),
      createdAt: _dateValue(json['created_at']),
    );
  }

  String get label {
    return switch (type) {
      WalletTransactionType.rechargeRequest => 'Recharge',
      WalletTransactionType.adminAdjustment => 'Adjustment',
      WalletTransactionType.giftSent => 'Gift sent',
      WalletTransactionType.giftReceived => 'Gift received',
      WalletTransactionType.agencyRecharge => 'Agency recharge',
      WalletTransactionType.refund => 'Refund',
      WalletTransactionType.system => 'System',
    };
  }

  static WalletTransactionType _typeFromKey(String? key) {
    return switch (key) {
      'recharge_request' => WalletTransactionType.rechargeRequest,
      'admin_adjustment' => WalletTransactionType.adminAdjustment,
      'gift_sent' => WalletTransactionType.giftSent,
      'gift_received' => WalletTransactionType.giftReceived,
      'agency_recharge' => WalletTransactionType.agencyRecharge,
      'refund' => WalletTransactionType.refund,
      _ => WalletTransactionType.system,
    };
  }

  static WalletDirection _directionFromKey(String? key) {
    return switch (key) {
      'credit' => WalletDirection.credit,
      'debit' => WalletDirection.debit,
      _ => WalletDirection.neutral,
    };
  }

  static int _intValue(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _nullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    return _intValue(value);
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }
}
