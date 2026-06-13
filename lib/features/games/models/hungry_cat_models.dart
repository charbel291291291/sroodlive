/// Food item from `hungry_cat_config` — multipliers and weights live in the
/// database (single source of truth), never hardcoded in the client.
class HungryCatFood {
  const HungryCatFood({
    required this.foodId,
    required this.name,
    required this.icon,
    required this.multiplier,
    required this.weight,
    required this.rarity,
    required this.sortOrder,
  });

  final String foodId;
  final String name;
  final String icon;
  final double multiplier;
  final double weight;
  final String rarity;
  final int sortOrder;

  factory HungryCatFood.fromJson(Map<String, dynamic> json) {
    return HungryCatFood(
      foodId: json['food_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '🍽️',
      multiplier: _toDouble(json['multiplier']),
      weight: _toDouble(json['weight']),
      rarity: json['rarity']?.toString() ?? 'common',
      sortOrder: json['sort_order'] is int ? json['sort_order'] as int : 0,
    );
  }

  Map<String, dynamic> toBridgeJson() => {
        'foodId': foodId,
        'name': name,
        'icon': icon,
        'multiplier': multiplier,
        'rarity': rarity,
      };
}

class HungryCatSpinResult {
  const HungryCatSpinResult({
    required this.spinId,
    required this.foodId,
    required this.foodName,
    required this.foodIcon,
    required this.multiplier,
    required this.rarity,
    required this.betAmount,
    required this.rewardAmount,
    required this.newBalance,
  });

  final String spinId;
  final String foodId;
  final String foodName;
  final String foodIcon;
  final double multiplier;
  final String rarity;
  final int betAmount;
  final int rewardAmount;
  final int newBalance;

  factory HungryCatSpinResult.fromJson(Map<String, dynamic> json) {
    return HungryCatSpinResult(
      spinId: json['spin_id']?.toString() ?? '',
      foodId: json['food_id']?.toString() ?? '',
      foodName: json['food_name']?.toString() ?? '',
      foodIcon: json['food_icon']?.toString() ?? '🍽️',
      multiplier: _toDouble(json['multiplier']),
      rarity: json['rarity']?.toString() ?? 'common',
      betAmount: json['bet_amount'] is int ? json['bet_amount'] as int : 0,
      rewardAmount:
          json['reward_amount'] is int ? json['reward_amount'] as int : 0,
      newBalance: json['new_balance'] is int ? json['new_balance'] as int : 0,
    );
  }

  Map<String, dynamic> toBridgeJson() => {
        'spinId': spinId,
        'foodId': foodId,
        'foodName': foodName,
        'foodIcon': foodIcon,
        'multiplier': multiplier,
        'rarity': rarity,
        'betAmount': betAmount,
        'rewardAmount': rewardAmount,
        'newBalance': newBalance,
      };
}

/// One entry in the user's spin history — used for the live banner.
class HungryCatHistoryEntry {
  const HungryCatHistoryEntry({
    required this.foodIcon,
    required this.foodName,
    required this.multiplier,
    required this.rarity,
    required this.rewardAmount,
    required this.betAmount,
  });

  final String foodIcon;
  final String foodName;
  final double multiplier;
  final String rarity;
  final int rewardAmount;
  final int betAmount;

  factory HungryCatHistoryEntry.fromJson(Map<String, dynamic> json) {
    return HungryCatHistoryEntry(
      foodIcon: json['food_icon']?.toString() ?? '🍽️',
      foodName: json['food_name']?.toString() ?? '',
      multiplier: _toDouble(json['multiplier']),
      rarity: json['rarity']?.toString() ?? 'common',
      rewardAmount:
          json['reward_amount'] is int ? json['reward_amount'] as int : 0,
      betAmount: json['bet_amount'] is int ? json['bet_amount'] as int : 0,
    );
  }

  Map<String, dynamic> toBridgeJson() => {
        'foodIcon': foodIcon,
        'foodName': foodName,
        'multiplier': multiplier,
        'rarity': rarity,
        'rewardAmount': rewardAmount,
        'betAmount': betAmount,
      };
}

double _toDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
