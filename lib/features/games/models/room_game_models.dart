// Server-authoritative room game round models.
// All users in the same room share one [RoomGameRound].
// The server is the sole source of truth — Flutter only displays results.

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum GameCode {
  hungryCat;

  String get value => switch (this) {
        GameCode.hungryCat => 'hungry_cat',
      };

  static GameCode fromValue(String v) => switch (v) {
        'hungry_cat' => GameCode.hungryCat,
        _ => throw ArgumentError('Unknown game_code: $v'),
      };
}

enum RoundStatus {
  waiting,
  bettingOpen,
  bettingClosed,
  running,
  revealed,
  finished,
  cancelled;

  String get value => switch (this) {
        RoundStatus.waiting => 'waiting',
        RoundStatus.bettingOpen => 'betting_open',
        RoundStatus.bettingClosed => 'betting_closed',
        RoundStatus.running => 'running',
        RoundStatus.revealed => 'revealed',
        RoundStatus.finished => 'finished',
        RoundStatus.cancelled => 'cancelled',
      };

  static RoundStatus fromValue(String v) => switch (v) {
        'waiting' => RoundStatus.waiting,
        'betting_open' => RoundStatus.bettingOpen,
        'betting_closed' => RoundStatus.bettingClosed,
        'running' => RoundStatus.running,
        'revealed' => RoundStatus.revealed,
        'finished' => RoundStatus.finished,
        'cancelled' => RoundStatus.cancelled,
        _ => RoundStatus.cancelled,
      };

  bool get isBettingAccepted => this == RoundStatus.bettingOpen;
  bool get isActive =>
      this != RoundStatus.finished && this != RoundStatus.cancelled;
  bool get isSettled =>
      this == RoundStatus.finished || this == RoundStatus.cancelled;
  bool get isResultVisible =>
      this == RoundStatus.revealed || this == RoundStatus.finished;
}

// ─────────────────────────────────────────────────────────────────────────────
// RoomGameRound
// ─────────────────────────────────────────────────────────────────────────────

class RoomGameRound {
  const RoomGameRound({
    required this.id,
    required this.roomId,
    required this.gameCode,
    required this.roundNumber,
    required this.status,
    required this.seedHash,
    required this.createdAt,
    required this.updatedAt,
    this.seed,
    this.resultJson,
    this.bettingOpensAt,
    this.bettingClosesAt,
    this.startedAt,
    this.revealAt,
    this.finishedAt,
    this.createdBy,
  });

  final String id;
  final String roomId;
  final GameCode gameCode;
  final int roundNumber;
  final RoundStatus status;
  final String seedHash;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Revealed only after round is finished (for provably-fair audit).
  final String? seed;

  /// Null until status is revealed/finished.
  /// hungry_cat: {winning_food_id, winning_food_icon, winning_food_name,
  ///              winning_multiplier, rarity}
  final Map<String, dynamic>? resultJson;

  final DateTime? bettingOpensAt;
  final DateTime? bettingClosesAt;
  final DateTime? startedAt;
  final DateTime? revealAt;
  final DateTime? finishedAt;
  final String? createdBy;

  // ── Convenience getters ──────────────────────────────────────────────────

  bool get isHungryCat => gameCode == GameCode.hungryCat;

  String? get winningFoodId => resultJson?['winning_food_id'] as String?;
  String? get winningFoodIcon => resultJson?['winning_food_icon'] as String?;
  String? get winningFoodName => resultJson?['winning_food_name'] as String?;

  double? get winningMultiplier {
    final v = resultJson?['winning_multiplier'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  bool get isResultVisible => status.isResultVisible;

  /// Seconds remaining until betting closes. Negative = already closed.
  double get bettingSecondsRemaining {
    if (bettingClosesAt == null) return 0;
    return bettingClosesAt!.difference(DateTime.now().toUtc()).inMilliseconds /
        1000.0;
  }

  factory RoomGameRound.fromJson(Map<String, dynamic> j) => RoomGameRound(
        id: j['id'] as String,
        roomId: j['room_id'] as String,
        gameCode: GameCode.fromValue(j['game_code'] as String),
        roundNumber: (j['round_number'] as num?)?.toInt() ?? 0,
        status: RoundStatus.fromValue(j['status'] as String? ?? 'cancelled'),
        seedHash: j['seed_hash'] as String? ?? '',
        seed: j['seed'] as String?,
        resultJson: j['result_json'] as Map<String, dynamic>?,
        bettingOpensAt: _dt(j['betting_opens_at']),
        bettingClosesAt: _dt(j['betting_closes_at']),
        startedAt: _dt(j['started_at']),
        revealAt: _dt(j['reveal_at']),
        finishedAt: _dt(j['finished_at']),
        createdBy: j['created_by'] as String?,
        createdAt: _dt(j['created_at']) ?? DateTime.now(),
        updatedAt: _dt(j['updated_at']) ?? DateTime.now(),
      );

  RoomGameRound copyWith({
    RoundStatus? status,
    Map<String, dynamic>? resultJson,
    DateTime? startedAt,
    DateTime? revealAt,
    DateTime? finishedAt,
    DateTime? updatedAt,
  }) =>
      RoomGameRound(
        id: id,
        roomId: roomId,
        gameCode: gameCode,
        roundNumber: roundNumber,
        status: status ?? this.status,
        seedHash: seedHash,
        seed: seed,
        resultJson: resultJson ?? this.resultJson,
        bettingOpensAt: bettingOpensAt,
        bettingClosesAt: bettingClosesAt,
        startedAt: startedAt ?? this.startedAt,
        revealAt: revealAt ?? this.revealAt,
        finishedAt: finishedAt ?? this.finishedAt,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString())?.toLocal();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RoomGameBet
// ─────────────────────────────────────────────────────────────────────────────

enum BetStatus {
  pending,
  running,
  won,
  lost,
  refunded,
  cashedOut;

  static BetStatus fromValue(String v) => switch (v) {
        'pending' => BetStatus.pending,
        'running' => BetStatus.running,
        'won' => BetStatus.won,
        'lost' => BetStatus.lost,
        'refunded' => BetStatus.refunded,
        'cashed_out' => BetStatus.cashedOut,
        _ => BetStatus.pending,
      };

  bool get isSettled =>
      this == BetStatus.won ||
      this == BetStatus.lost ||
      this == BetStatus.refunded ||
      this == BetStatus.cashedOut;
}

class RoomGameBet {
  const RoomGameBet({
    required this.id,
    required this.roundId,
    required this.roomId,
    required this.userId,
    required this.betAmount,
    required this.betJson,
    required this.status,
    required this.payoutAmount,
    required this.createdAt,
    this.cashoutMultiplier,
    this.settledAt,
  });

  final String id;
  final String roundId;
  final String roomId;
  final String userId;
  final int betAmount;
  final Map<String, dynamic> betJson;
  final BetStatus status;
  final int payoutAmount;
  final double? cashoutMultiplier;
  final DateTime createdAt;
  final DateTime? settledAt;

  // Hungry Cat helpers
  String? get foodId => betJson['food_id'] as String?;

  factory RoomGameBet.fromJson(Map<String, dynamic> j) => RoomGameBet(
        id: j['id'] as String,
        roundId: j['round_id'] as String,
        roomId: j['room_id'] as String,
        userId: j['user_id'] as String,
        betAmount: (j['bet_amount'] as num).toInt(),
        betJson: (j['bet_json'] as Map<String, dynamic>?) ?? const {},
        status: BetStatus.fromValue(j['status'] as String? ?? 'pending'),
        payoutAmount: (j['payout_amount'] as num?)?.toInt() ?? 0,
        cashoutMultiplier: (j['cashout_multiplier'] as num?)?.toDouble(),
        createdAt:
            DateTime.tryParse(j['created_at'].toString())?.toLocal() ??
                DateTime.now(),
        settledAt: j['settled_at'] == null
            ? null
            : DateTime.tryParse(j['settled_at'].toString())?.toLocal(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Round creation response
// ─────────────────────────────────────────────────────────────────────────────

class RoomGameRoundCreated {
  const RoomGameRoundCreated({
    required this.roundId,
    required this.roundNumber,
    required this.seedHash,
    required this.bettingOpensAt,
    required this.bettingClosesAt,
    this.startedAt,
    this.revealAt,
  });

  final String roundId;
  final int roundNumber;
  final String seedHash;
  final DateTime bettingOpensAt;
  final DateTime bettingClosesAt;
  final DateTime? startedAt;
  final DateTime? revealAt;

  factory RoomGameRoundCreated.fromJson(Map<String, dynamic> j) =>
      RoomGameRoundCreated(
        roundId: j['round_id'] as String,
        roundNumber: (j['round_number'] as num?)?.toInt() ?? 1,
        seedHash: j['seed_hash'] as String? ?? '',
        bettingOpensAt:
            DateTime.tryParse(j['betting_opens_at'].toString())!.toLocal(),
        bettingClosesAt:
            DateTime.tryParse(j['betting_closes_at'].toString())!.toLocal(),
        startedAt: j['started_at'] == null
            ? null
            : DateTime.tryParse(j['started_at'].toString())?.toLocal(),
        revealAt: j['reveal_at'] == null
            ? null
            : DateTime.tryParse(j['reveal_at'].toString())?.toLocal(),
      );
}
