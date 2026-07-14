enum CrashV3RoundStatus {
  waiting,
  betting,
  locked,
  flying,
  crashed,
  settling,
  settled,
  cancelled,
}

class CrashV3Round {
  const CrashV3Round({
    required this.id,
    required this.publicRoundId,
    required this.status,
    required this.serverSeedHash,
    required this.clientSeed,
    required this.nonce,
    required this.growthRate,
    this.startsAt,
    this.bettingOpensAt,
    this.bettingClosesAt,
    this.flightStartedAt,
    this.crashedAt,
    this.settledAt,
    this.crashMultiplier,
    this.revealedServerSeed,
    this.resultHash,
    this.eventSequence = 0,
  });
  final String id;
  final int publicRoundId;
  final CrashV3RoundStatus status;
  final DateTime? startsAt,
      bettingOpensAt,
      bettingClosesAt,
      flightStartedAt,
      crashedAt,
      settledAt;
  final double? crashMultiplier;
  final String serverSeedHash, clientSeed;
  final int nonce;
  final String? revealedServerSeed, resultHash;
  final double growthRate;
  final int eventSequence;
  factory CrashV3Round.fromJson(Map<String, dynamic> json) => CrashV3Round(
    id: json['id'] as String,
    publicRoundId: (json['public_round_id'] as num).toInt(),
    status: CrashV3RoundStatus.values.byName(json['status'] as String),
    startsAt: _date(json['starts_at']),
    bettingOpensAt: _date(json['betting_opens_at']),
    bettingClosesAt: _date(json['betting_closes_at']),
    flightStartedAt: _date(json['flight_started_at']),
    crashedAt: _date(json['crashed_at']),
    settledAt: _date(json['settled_at']),
    crashMultiplier: (json['crash_multiplier'] as num?)?.toDouble(),
    serverSeedHash: json['server_seed_hash'] as String,
    clientSeed: json['client_seed'] as String,
    nonce: (json['nonce'] as num).toInt(),
    revealedServerSeed: json['revealed_server_seed'] as String?,
    resultHash: json['result_hash'] as String?,
    growthRate: (json['growth_rate'] as num).toDouble(),
    eventSequence: (json['event_sequence'] as num?)?.toInt() ?? 0,
  );
  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();
}
