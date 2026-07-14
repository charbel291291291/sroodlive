class CrashV3Settings {
  const CrashV3Settings({
    required this.gameEnabled,
    required this.maintenanceMode,
    required this.emergencyStop,
    required this.minimumBet,
    required this.maximumBet,
    required this.maximumPayoutPerBet,
    required this.maximumMultiplier,
    required this.growthRate,
  });
  final bool gameEnabled, maintenanceMode, emergencyStop;
  final int minimumBet, maximumBet, maximumPayoutPerBet;
  final double maximumMultiplier, growthRate;
  factory CrashV3Settings.fromJson(Map<String, dynamic> json) =>
      CrashV3Settings(
        gameEnabled: json['game_enabled'] as bool,
        maintenanceMode: json['maintenance_mode'] as bool,
        emergencyStop: json['emergency_stop'] as bool,
        minimumBet: (json['minimum_bet'] as num).toInt(),
        maximumBet: (json['maximum_bet'] as num).toInt(),
        maximumPayoutPerBet: (json['maximum_payout_per_bet'] as num).toInt(),
        maximumMultiplier: (json['maximum_multiplier'] as num).toDouble(),
        growthRate: (json['default_growth_rate'] as num).toDouble(),
      );
}
