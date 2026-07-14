class CrashV3Bet {
  const CrashV3Bet({
    required this.id,
    required this.roundId,
    required this.slotNumber,
    required this.betAmount,
    required this.status,
    required this.payoutAmount,
    this.autoCashoutMultiplier,
    this.cashoutMultiplier,
    this.createdAt,
  });
  final String id, roundId, status;
  final int slotNumber, betAmount, payoutAmount;
  final double? autoCashoutMultiplier, cashoutMultiplier;
  final DateTime? createdAt;
  bool get canCashout => status == 'accepted';
  factory CrashV3Bet.fromJson(Map<String, dynamic> json) => CrashV3Bet(
    id: json['id'] as String,
    roundId: json['round_id'] as String,
    slotNumber: (json['slot_number'] as num).toInt(),
    betAmount: (json['bet_amount'] as num).toInt(),
    status: json['status'] as String,
    payoutAmount: (json['payout_amount'] as num?)?.toInt() ?? 0,
    autoCashoutMultiplier: (json['auto_cashout_multiplier'] as num?)
        ?.toDouble(),
    cashoutMultiplier: (json['cashout_multiplier'] as num?)?.toDouble(),
    createdAt: json['created_at'] == null
        ? null
        : DateTime.parse(json['created_at'] as String).toUtc(),
  );
}
