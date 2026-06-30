class FishHuntFish {
  const FishHuntFish({
    required this.fishId,
    required this.fishType,
    required this.rewardMultiplier,
    required this.hitProbability,
    required this.spawnedAt,
    required this.expiresAt,
  });

  factory FishHuntFish.fromJson(Map<String, dynamic> json) {
    return FishHuntFish(
      fishId: json['fish_id'].toString(),
      fishType: json['fish_type']?.toString() ?? 'small',
      rewardMultiplier: _toDouble(json['reward_multiplier']),
      hitProbability: _toDouble(json['hit_probability']),
      spawnedAt:
          DateTime.tryParse(json['spawned_at']?.toString() ?? '') ??
          DateTime.now(),
      expiresAt:
          DateTime.tryParse(json['expires_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  final String fishId;
  final String fishType;
  final double rewardMultiplier;
  final double hitProbability;
  final DateTime spawnedAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());
}

class FishHuntShot {
  const FishHuntShot({
    required this.fishId,
    required this.betAmount,
    required this.result,
    required this.payoutAmount,
    required this.createdAt,
  });

  factory FishHuntShot.fromJson(Map<String, dynamic> json) {
    return FishHuntShot(
      fishId: json['fish_id']?.toString() ?? '',
      betAmount: _toInt(json['bet_amount']),
      result: json['result']?.toString() ?? 'miss',
      payoutAmount: _toInt(json['payout_amount']),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  final String fishId;
  final int betAmount;
  final String result;
  final int payoutAmount;
  final DateTime createdAt;
}

class FishHuntState {
  const FishHuntState({
    required this.roundId,
    required this.roundStatus,
    required this.fish,
    required this.balance,
    required this.recentShots,
    required this.serverNow,
  });

  factory FishHuntState.fromJson(Map<String, dynamic> json) {
    final fishRaw = json['fish'] as List<dynamic>? ?? const [];
    final shotsRaw = json['recent_shots'] as List<dynamic>? ?? const [];
    return FishHuntState(
      roundId: json['round_id']?.toString(),
      roundStatus: json['round_status']?.toString(),
      fish: fishRaw
          .map((f) => FishHuntFish.fromJson(f as Map<String, dynamic>))
          .toList(growable: false),
      balance: _toInt(json['balance']),
      recentShots: shotsRaw
          .map((s) => FishHuntShot.fromJson(s as Map<String, dynamic>))
          .toList(growable: false),
      serverNow:
          DateTime.tryParse(json['server_now']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  final String? roundId;
  final String? roundStatus;
  final List<FishHuntFish> fish;
  final int balance;
  final List<FishHuntShot> recentShots;
  final DateTime serverNow;

  bool get hasActiveRound => roundId != null && roundStatus == 'active';
}

class FishHuntShotResult {
  const FishHuntShotResult({
    required this.result,
    required this.payoutAmount,
    required this.newBalance,
    required this.fishId,
  });

  factory FishHuntShotResult.fromJson(Map<String, dynamic> json) {
    return FishHuntShotResult(
      result: json['result']?.toString() ?? 'miss',
      payoutAmount: _toInt(json['payout_amount']),
      newBalance: _toInt(json['new_balance']),
      fishId: json['fish_id']?.toString() ?? '',
    );
  }

  final String result;
  final int payoutAmount;
  final int newBalance;
  final String fishId;

  bool get isHit => result == 'hit';
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
