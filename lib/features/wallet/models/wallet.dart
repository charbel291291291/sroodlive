class UserWallet {
  const UserWallet({
    required this.userId,
    required this.coinsBalance,
    required this.diamondsBalance,
    required this.lifetimeCoinsCharged,
    required this.lifetimeCoinsSpent,
    required this.lifetimeDiamondsEarned,
    required this.updatedAt,
    required this.createdAt,
  });

  final String userId;
  final int coinsBalance;
  final int diamondsBalance;
  final int lifetimeCoinsCharged;
  final int lifetimeCoinsSpent;
  final int lifetimeDiamondsEarned;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  factory UserWallet.empty(String userId) {
    return UserWallet(
      userId: userId,
      coinsBalance: 0,
      diamondsBalance: 0,
      lifetimeCoinsCharged: 0,
      lifetimeCoinsSpent: 0,
      lifetimeDiamondsEarned: 0,
      updatedAt: null,
      createdAt: null,
    );
  }

  factory UserWallet.fromJson(Map<String, dynamic> json) {
    return UserWallet(
      userId: json['user_id']?.toString() ?? '',
      coinsBalance: _intValue(json['coins_balance']),
      diamondsBalance: _intValue(json['diamonds_balance']),
      lifetimeCoinsCharged: _intValue(json['lifetime_coins_charged']),
      lifetimeCoinsSpent: _intValue(json['lifetime_coins_spent']),
      lifetimeDiamondsEarned: _intValue(json['lifetime_diamonds_earned']),
      updatedAt: _dateValue(json['updated_at']),
      createdAt: _dateValue(json['created_at']),
    );
  }

  static int _intValue(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }
}
