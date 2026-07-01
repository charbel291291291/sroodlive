const List<String> kRouletteBetZones = [
  'straight_zero',
  'low',
  'mid',
  'high',
  'red',
  'black',
  'even',
  'odd',
];

const List<int> kRouletteBetAmounts = [100, 1000, 5000, 10000, 20000, 100000];

class RouletteRound {
  const RouletteRound({
    required this.roundId,
    required this.roomId,
    required this.status,
    required this.winningNumber,
    required this.startedAt,
    required this.bettingClosesAt,
    required this.settledAt,
  });

  factory RouletteRound.fromJson(Map<String, dynamic> json) {
    return RouletteRound(
      roundId: json['round_id'].toString(),
      roomId: json['room_id']?.toString(),
      status: json['status']?.toString() ?? 'betting_open',
      winningNumber: json['winning_number'] == null
          ? null
          : _toInt(json['winning_number']),
      startedAt:
          DateTime.tryParse(json['started_at']?.toString() ?? '') ??
          DateTime.now(),
      bettingClosesAt:
          DateTime.tryParse(json['betting_closes_at']?.toString() ?? '') ??
          DateTime.now(),
      settledAt: json['settled_at'] == null
          ? null
          : DateTime.tryParse(json['settled_at'].toString()),
    );
  }

  final String roundId;
  final String? roomId;
  final String status;
  final int? winningNumber;
  final DateTime startedAt;
  final DateTime bettingClosesAt;
  final DateTime? settledAt;

  bool get isBettingOpen => status == 'betting_open';
}

class RouletteBet {
  const RouletteBet({
    required this.betId,
    required this.betZone,
    required this.betAmount,
    required this.payoutMultiplier,
    required this.status,
    required this.payoutAmount,
  });

  factory RouletteBet.fromJson(Map<String, dynamic> json) {
    return RouletteBet(
      betId: json['bet_id'].toString(),
      betZone: json['bet_zone']?.toString() ?? '',
      betAmount: _toInt(json['bet_amount']),
      payoutMultiplier: _toDouble(json['payout_multiplier']),
      status: json['status']?.toString() ?? 'active',
      payoutAmount: _toInt(json['payout_amount']),
    );
  }

  final String betId;
  final String betZone;
  final int betAmount;
  final double payoutMultiplier;
  final String status;
  final int payoutAmount;
}

class RouletteZoneTotal {
  const RouletteZoneTotal({required this.betZone, required this.totalAmount});

  factory RouletteZoneTotal.fromJson(Map<String, dynamic> json) {
    return RouletteZoneTotal(
      betZone: json['bet_zone']?.toString() ?? '',
      totalAmount: _toInt(json['total_amount']),
    );
  }

  final String betZone;
  final int totalAmount;
}

class RouletteState {
  const RouletteState({
    required this.serverNow,
    required this.round,
    required this.recentResults,
    required this.balance,
    required this.myBets,
    required this.zoneTotals,
  });

  factory RouletteState.fromJson(Map<String, dynamic> json) {
    final roundRaw = json['round'] as Map<String, dynamic>?;
    final recentRaw = json['recent_results'] as List<dynamic>? ?? const [];
    final myBetsRaw = json['my_bets'] as List<dynamic>? ?? const [];
    final zoneTotalsRaw = json['zone_totals'] as List<dynamic>? ?? const [];
    return RouletteState(
      serverNow:
          DateTime.tryParse(json['server_now']?.toString() ?? '') ??
          DateTime.now(),
      round: roundRaw == null ? null : RouletteRound.fromJson(roundRaw),
      recentResults: recentRaw.map(_toInt).toList(growable: false),
      balance: _toInt(json['balance']),
      myBets: myBetsRaw
          .map((b) => RouletteBet.fromJson(b as Map<String, dynamic>))
          .toList(growable: false),
      zoneTotals: zoneTotalsRaw
          .map((z) => RouletteZoneTotal.fromJson(z as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final DateTime serverNow;
  final RouletteRound? round;
  final List<int> recentResults;
  final int balance;
  final List<RouletteBet> myBets;
  final List<RouletteZoneTotal> zoneTotals;

  bool get canBet => round != null && round!.isBettingOpen;
}

class RoulettePlaceBetResult {
  const RoulettePlaceBetResult({
    required this.betId,
    required this.newBalance,
    required this.betZone,
    required this.betAmount,
    required this.roundId,
  });

  factory RoulettePlaceBetResult.fromJson(Map<String, dynamic> json) {
    return RoulettePlaceBetResult(
      betId: json['bet_id'].toString(),
      newBalance: _toInt(json['new_balance']),
      betZone: json['bet_zone']?.toString() ?? '',
      betAmount: _toInt(json['bet_amount']),
      roundId: json['round_id'].toString(),
    );
  }

  final String betId;
  final int newBalance;
  final String betZone;
  final int betAmount;
  final String roundId;
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
