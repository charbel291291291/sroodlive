/// Crash Rocket v2 — client models.
///
/// Mirrors the server contract of `crash_v2_get_state` and the
/// `crash_v2_rounds` / `crash_v2_round_events` realtime payloads.
/// The client renders state; it never decides results — multipliers shown
/// during flight are cosmetic projections of the server curve, and every
/// settlement value comes from the server response.
library;

enum CrashV2Phase {
  waiting,
  bettingOpen,
  bettingLocked,
  flying,
  crashed,
  settling,
  completed;

  static CrashV2Phase parse(Object? value) => switch (value?.toString()) {
    'betting_open' => bettingOpen,
    'betting_locked' => bettingLocked,
    'flying' => flying,
    'crashed' => crashed,
    'settling' => settling,
    'completed' => completed,
    _ => waiting,
  };

  bool get isBettingOpen => this == bettingOpen;
  bool get isFlying => this == flying;
  bool get isCrashedVisual =>
      this == crashed || this == settling || this == completed;
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
double _double(Object? value, [double fallback = 0]) => value == null
    ? fallback
    : (value is num ? value.toDouble() : double.tryParse('$value') ?? fallback);
double? _doubleOrNull(Object? value) => value == null
    ? null
    : (value is num ? value.toDouble() : double.tryParse('$value'));

class CrashV2Round {
  const CrashV2Round({
    required this.id,
    required this.roomId,
    required this.phase,
    required this.roundNumber,
    required this.bettingOpenAt,
    required this.bettingCloseAt,
    this.startedAt,
    this.crashedAt,
    this.completedAt,
    this.crashMultiplier,
    this.serverSeedHash,
    this.serverSeed,
    this.clientSeed,
    this.nonce,
  });

  factory CrashV2Round.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final open = _date(json['betting_open_at']);
    final close = _date(json['betting_close_at']);
    if (id == null || open == null || close == null) {
      throw const FormatException('Malformed crash v2 round');
    }
    return CrashV2Round(
      id: id,
      roomId: json['room_id']?.toString(),
      phase: CrashV2Phase.parse(json['status']),
      roundNumber: _int(json['public_round_number']),
      bettingOpenAt: open,
      bettingCloseAt: close,
      startedAt: _date(json['started_at']),
      crashedAt: _date(json['crashed_at']),
      completedAt: _date(json['completed_at']),
      crashMultiplier: _doubleOrNull(json['crash_multiplier']),
      serverSeedHash: json['server_seed_hash']?.toString(),
      serverSeed: json['server_seed']?.toString(),
      clientSeed: json['client_seed']?.toString(),
      nonce: json['nonce'] == null ? null : _int(json['nonce']),
    );
  }

  final String id;
  final String? roomId;
  final CrashV2Phase phase;
  final int roundNumber;
  final DateTime bettingOpenAt;
  final DateTime bettingCloseAt;
  final DateTime? startedAt;
  final DateTime? crashedAt;
  final DateTime? completedAt;
  final double? crashMultiplier;
  final String? serverSeedHash;
  final String? serverSeed;
  final String? clientSeed;
  final int? nonce;
}

class CrashV2Bet {
  const CrashV2Bet({
    required this.id,
    required this.roundId,
    required this.slot,
    required this.amount,
    required this.status,
    this.autoCashout,
    this.cashoutMultiplier,
    this.payout,
  });

  factory CrashV2Bet.fromJson(Map<String, dynamic> json) => CrashV2Bet(
    id: json['id']?.toString() ?? '',
    roundId: json['round_id']?.toString() ?? '',
    slot: _int(json['bet_slot']),
    amount: _int(json['amount']),
    status: json['status']?.toString() ?? 'placed',
    autoCashout: _doubleOrNull(json['auto_cashout_multiplier']),
    cashoutMultiplier: _doubleOrNull(json['cashout_multiplier']),
    payout: json['payout'] == null ? null : _int(json['payout']),
  );

  final String id;
  final String roundId;
  final int slot;
  final int amount;
  final String status;
  final double? autoCashout;
  final double? cashoutMultiplier;
  final int? payout;

  bool get isPlaced => status == 'placed';
  bool get isCashedOut => status == 'cashed_out';
}

class CrashV2Config {
  const CrashV2Config({
    this.minBet = 100,
    this.maxBet = 1000000,
    this.maxPayout = 1000000000,
    this.minAutoCashout = 1.01,
    this.maxAutoCashout = 1000,
    this.growthRate = 0.09,
    this.maxMultiplier = 1000,
    this.bettingSeconds = 8,
    this.waitingSeconds = 3,
    this.lockSeconds = 1,
    this.crashDisplaySeconds = 4,
  });

  factory CrashV2Config.fromJson(Map<String, dynamic> json) => CrashV2Config(
    minBet: _int(json['min_bet']),
    maxBet: _int(json['max_bet']),
    maxPayout: _int(json['max_payout']),
    minAutoCashout: _double(json['min_auto_cashout'], 1.01),
    maxAutoCashout: _double(json['max_auto_cashout'], 1000),
    growthRate: _double(json['growth_rate'], 0.09),
    maxMultiplier: _double(json['max_multiplier'], 1000),
    bettingSeconds: _int(json['betting_seconds']),
    waitingSeconds: _int(json['waiting_seconds']),
    lockSeconds: _int(json['lock_seconds']),
    crashDisplaySeconds: _int(json['crash_display_seconds']),
  );

  final int minBet;
  final int maxBet;
  final int maxPayout;
  final double minAutoCashout;
  final double maxAutoCashout;
  final double growthRate;
  final double maxMultiplier;
  final int bettingSeconds;
  final int waitingSeconds;
  final int lockSeconds;
  final int crashDisplaySeconds;
}

class CrashV2FeedEntry {
  const CrashV2FeedEntry({
    required this.betId,
    required this.userId,
    required this.name,
    required this.amount,
    this.avatarUrl,
    this.payout,
    this.multiplier,
  });

  factory CrashV2FeedEntry.fromJson(Map<String, dynamic> json) =>
      CrashV2FeedEntry(
        betId: json['bet_id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        name: json['display_name']?.toString().trim().isNotEmpty == true
            ? json['display_name'].toString()
            : 'Srood Player',
        amount: _int(json['amount']),
        avatarUrl: json['avatar_url']?.toString(),
        payout: json['payout'] == null ? null : _int(json['payout']),
        multiplier: _doubleOrNull(json['cashout_multiplier']),
      );

  final String betId;
  final String userId;
  final String name;
  final int amount;
  final String? avatarUrl;
  final int? payout;
  final double? multiplier;

  CrashV2FeedEntry merge(CrashV2FeedEntry older) => CrashV2FeedEntry(
    betId: betId.isNotEmpty ? betId : older.betId,
    userId: userId.isNotEmpty ? userId : older.userId,
    name: name != 'Srood Player' ? name : older.name,
    amount: amount > 0 ? amount : older.amount,
    avatarUrl: avatarUrl ?? older.avatarUrl,
    payout: payout ?? older.payout,
    multiplier: multiplier ?? older.multiplier,
  );
}

class CrashV2State {
  const CrashV2State({
    required this.enabled,
    required this.paused,
    required this.serverNow,
    required this.walletBalance,
    required this.config,
    required this.players,
    required this.totalBet,
    required this.myBets,
    required this.feed,
    required this.history,
    this.round,
    this.maintenanceMessage,
  });

  factory CrashV2State.fromJson(Map<String, dynamic> json) {
    final now = _date(json['server_now']) ?? DateTime.now().toUtc();
    final enabled = json['enabled'] == true;
    List<Map<String, dynamic>> maps(Object? value) => value is List
        ? value
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const [];

    final feedEntries = maps(
      json['public_feed'],
    ).map(CrashV2FeedEntry.fromJson).toList();
    final merged = <String, CrashV2FeedEntry>{};
    for (final entry in feedEntries.reversed) {
      final key = entry.betId.isNotEmpty
          ? entry.betId
          : '${entry.userId}_${entry.amount}_${merged.length}';
      merged[key] = merged[key]?.merge(entry) ?? entry;
    }

    final roundRaw = json['round'];
    return CrashV2State(
      enabled: enabled,
      paused: json['paused'] == true,
      maintenanceMessage: json['maintenance_message']?.toString(),
      serverNow: now,
      walletBalance: _int(json['wallet_balance']),
      config: json['config'] is Map
          ? CrashV2Config.fromJson(Map<String, dynamic>.from(json['config']))
          : const CrashV2Config(),
      players: _int(json['players']),
      totalBet: _int(json['total_bet']),
      round: roundRaw is Map
          ? CrashV2Round.fromJson(Map<String, dynamic>.from(roundRaw))
          : null,
      myBets: maps(json['my_bets']).map(CrashV2Bet.fromJson).toList(),
      feed: merged.values.toList().reversed.toList(),
      history: maps(json['history'])
          .map((e) => _doubleOrNull(e['crash_multiplier']))
          .whereType<double>()
          .toList(),
    );
  }

  final bool enabled;
  final bool paused;
  final String? maintenanceMessage;
  final DateTime serverNow;
  final int walletBalance;
  final CrashV2Config config;
  final int players;
  final int totalBet;
  final CrashV2Round? round;
  final List<CrashV2Bet> myBets;
  final List<CrashV2FeedEntry> feed;
  final List<double> history;
}
