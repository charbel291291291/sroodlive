class CrashV3HistoryItem {
  const CrashV3HistoryItem({
    required this.roundId,
    required this.publicRoundId,
    required this.crashMultiplier,
    required this.createdAt,
  });
  final String roundId;
  final int publicRoundId;
  final double crashMultiplier;
  final DateTime createdAt;
  factory CrashV3HistoryItem.fromJson(Map<String, dynamic> json) =>
      CrashV3HistoryItem(
        roundId: json['id'] as String,
        publicRoundId: (json['public_round_id'] as num).toInt(),
        crashMultiplier: (json['crash_multiplier'] as num).toDouble(),
        createdAt: DateTime.parse(
          (json['settled_at'] ?? json['created_at']) as String,
        ).toUtc(),
      );
}
