enum SroodRocketPhase {
  waiting,
  bettingOpen,
  flying,
  crashed,
  settled;

  static SroodRocketPhase parse(Object? value) => switch (value?.toString()) {
    'betting_open' => bettingOpen,
    'flying' => flying,
    'crashed' => crashed,
    'settled' => settled,
    _ => waiting,
  };
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
double? _doubleOrNull(Object? value) => value == null
    ? null
    : (value is num ? value.toDouble() : double.tryParse('$value'));

class SroodRocketRound {
  const SroodRocketRound({
    required this.id,
    required this.roomId,
    required this.phase,
    required this.roundNumber,
    required this.startsAt,
    required this.bettingClosesAt,
    this.flyStartedAt,
    this.crashedAt,
    this.crashMultiplier,
    this.seedHash,
    this.seedReveal,
  });

  factory SroodRocketRound.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final startsAt = _date(json['starts_at']);
    final bettingClosesAt = _date(json['betting_closes_at']);
    if (id == null || startsAt == null || bettingClosesAt == null) {
      throw const FormatException('Malformed Srood Rocket round');
    }
    return SroodRocketRound(
      id: id,
      roomId: json['room_id']?.toString(),
      phase: SroodRocketPhase.parse(json['status']),
      roundNumber: _int(json['round_number']),
      startsAt: startsAt,
      bettingClosesAt: bettingClosesAt,
      flyStartedAt: _date(json['fly_started_at']),
      crashedAt: _date(json['crashed_at']),
      crashMultiplier: _doubleOrNull(json['crash_multiplier']),
      seedHash: json['crash_seed_hash']?.toString(),
      seedReveal: json['crash_seed_reveal']?.toString(),
    );
  }

  final String id;
  final String? roomId;
  final SroodRocketPhase phase;
  final int roundNumber;
  final DateTime startsAt;
  final DateTime bettingClosesAt;
  final DateTime? flyStartedAt;
  final DateTime? crashedAt;
  final double? crashMultiplier;
  final String? seedHash;
  final String? seedReveal;
}

class SroodRocketBet {
  const SroodRocketBet({
    required this.id,
    required this.roundId,
    required this.slot,
    required this.amount,
    required this.status,
    this.autoCashout,
    this.cashoutMultiplier,
    this.payoutAmount,
  });

  factory SroodRocketBet.fromJson(Map<String, dynamic> json) => SroodRocketBet(
    id: json['id']?.toString() ?? '',
    roundId: json['round_id']?.toString() ?? '',
    slot: _int(json['bet_slot']),
    amount: _int(json['amount']),
    status: json['status']?.toString() ?? 'placed',
    autoCashout: _doubleOrNull(json['auto_cashout_multiplier']),
    cashoutMultiplier: _doubleOrNull(json['cashout_multiplier']),
    payoutAmount: json['payout_amount'] == null
        ? null
        : _int(json['payout_amount']),
  );

  final String id;
  final String roundId;
  final int slot;
  final int amount;
  final String status;
  final double? autoCashout;
  final double? cashoutMultiplier;
  final int? payoutAmount;
}

class SroodRocketFeedEntry {
  const SroodRocketFeedEntry({
    required this.betId,
    required this.userId,
    required this.name,
    required this.amount,
    this.avatarUrl,
    this.payout,
    this.multiplier,
  });

  factory SroodRocketFeedEntry.fromJson(Map<String, dynamic> json) =>
      SroodRocketFeedEntry(
        betId: json['bet_id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        name: json['display_name']?.toString().trim().isNotEmpty == true
            ? json['display_name'].toString()
            : 'Srood Player',
        amount: _int(json['amount']),
        avatarUrl: json['avatar_url']?.toString(),
        payout: json['payout_amount'] == null
            ? null
            : _int(json['payout_amount']),
        multiplier: _doubleOrNull(json['cashout_multiplier']),
      );

  final String betId;
  final String userId;
  final String name;
  final int amount;
  final String? avatarUrl;
  final int? payout;
  final double? multiplier;

  SroodRocketFeedEntry merge(SroodRocketFeedEntry older) =>
      SroodRocketFeedEntry(
        betId: betId.isNotEmpty ? betId : older.betId,
        userId: userId.isNotEmpty ? userId : older.userId,
        name: name != 'Srood Player' ? name : older.name,
        amount: amount > 0 ? amount : older.amount,
        avatarUrl: avatarUrl ?? older.avatarUrl,
        payout: payout ?? older.payout,
        multiplier: multiplier ?? older.multiplier,
      );
}

class SroodRocketState {
  const SroodRocketState({
    required this.serverNow,
    required this.walletBalance,
    required this.round,
    required this.myBets,
    required this.feed,
    required this.history,
  });

  factory SroodRocketState.fromJson(Map<String, dynamic> json) {
    final roundRaw = json['round'];
    final now = _date(json['server_now']);
    if (roundRaw is! Map || now == null) {
      throw const FormatException('Malformed Srood Rocket state');
    }
    List<Map<String, dynamic>> maps(Object? value) => value is List
        ? value
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const [];
    final feedEntries = maps(
      json['public_feed'],
    ).map(SroodRocketFeedEntry.fromJson).toList();
    final mergedFeed = <String, SroodRocketFeedEntry>{};
    for (final entry in feedEntries.reversed) {
      final key = entry.betId.isNotEmpty
          ? entry.betId
          : '${entry.userId}_${entry.amount}_${mergedFeed.length}';
      mergedFeed[key] = mergedFeed[key]?.merge(entry) ?? entry;
    }
    return SroodRocketState(
      serverNow: now,
      walletBalance: _int(json['wallet_balance']),
      round: SroodRocketRound.fromJson(Map<String, dynamic>.from(roundRaw)),
      myBets: maps(json['my_bets']).map(SroodRocketBet.fromJson).toList(),
      feed: mergedFeed.values.toList().reversed.toList(),
      history: maps(json['history'])
          .map((e) => _doubleOrNull(e['crash_multiplier']))
          .whereType<double>()
          .toList(),
    );
  }

  final DateTime serverNow;
  final int walletBalance;
  final SroodRocketRound round;
  final List<SroodRocketBet> myBets;
  final List<SroodRocketFeedEntry> feed;
  final List<double> history;
}
