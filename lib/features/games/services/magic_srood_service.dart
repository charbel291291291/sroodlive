import '../../../core/supabase/supabase_service.dart';
import '../models/hungry_cat_models.dart';

/// Magic Srood game service — mirrors HungryCatGameService exactly
/// but targets `magic_srood_*` tables and RPCs.
class MagicSroodService {
  const MagicSroodService();

  Future<List<HungryCatFood>> fetchItemConfig() async {
    final raw = await SupabaseService.requiredClient
        .from('magic_srood_config')
        .select()
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    final rows = _asList(raw, 'magic_srood_config');
    return rows
        .map((row) {
          final data = _asMap(row, 'magic_srood_config row');
          final foodId = _requiredString(data, 'food_id', 'magic_srood_config');
          _requiredString(data, 'name', 'magic_srood_config[$foodId]');
          final multiplier = _requiredDouble(
            data,
            'multiplier',
            'magic_srood_config[$foodId]',
          );
          final weight = _requiredDouble(
            data,
            'weight',
            'magic_srood_config[$foodId]',
          );
          if (multiplier <= 0 || weight <= 0) {
            throw const FormatException(
              'magic_srood_config: multiplier and weight must be positive',
            );
          }
          return HungryCatFood.fromJson(data);
        })
        .toList(growable: false);
  }

  Future<int> fetchCoinBalance() async {
    final userId = SupabaseService.requiredClient.auth.currentUser?.id;
    if (userId == null) throw StateError('not_authenticated');
    final data = await SupabaseService.requiredClient
        .from('wallets')
        .select('coins_balance')
        .eq('user_id', userId)
        .maybeSingle();
    if (data == null) return 0;
    return _requiredInt(data, 'coins_balance', 'wallets');
  }

  Future<HungryCatGlobalRound> getOrCreateRound() async {
    final raw = await SupabaseService.requiredClient.rpc(
      'get_or_create_magic_srood_round',
    );
    return parseActiveRoundResponse(raw);
  }

  Future<Map<String, int>> getMyRoundBets(String roundId) async {
    final raw = await SupabaseService.requiredClient
        .from('magic_srood_global_bets')
        .select('food_id, bet_amount, status')
        .eq('round_id', roundId)
        .order('created_at', ascending: true);
    final rows = _asList(raw, 'magic_srood_global_bets');
    final totals = <String, int>{};
    for (final row in rows) {
      final data = _asMap(row, 'magic_srood_global_bets row');
      final foodId = _requiredString(
        data,
        'food_id',
        'magic_srood_global_bets',
      );
      final amount = _requiredInt(
        data,
        'bet_amount',
        'magic_srood_global_bets[$foodId]',
      );
      final status = _requiredString(
        data,
        'status',
        'magic_srood_global_bets[$foodId]',
      );
      if (amount <= 0 ||
          (status != 'pending' && status != 'won' && status != 'lost')) {
        throw const FormatException(
          'magic_srood_global_bets: malformed bet row',
        );
      }
      totals[foodId] = (totals[foodId] ?? 0) + amount;
    }
    return totals;
  }

  Future<({String betId, int newBalance})> placeGlobalBet({
    required String roundId,
    required String foodId,
    required int amount,
  }) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'place_magic_srood_global_bet',
      params: {'p_round_id': roundId, 'p_food_id': foodId, 'p_amount': amount},
    );
    return parseBetResponse(raw);
  }

  static ({String betId, int newBalance}) parseBetResponse(Object? raw) {
    final data = _asMap(raw, 'place_magic_srood_global_bet');
    final betId = _requiredString(
      data,
      'bet_id',
      'place_magic_srood_global_bet',
    );
    final newBalance = _requiredInt(
      data,
      'new_balance',
      'place_magic_srood_global_bet',
    );
    if (newBalance < 0) {
      throw const FormatException(
        'place_magic_srood_global_bet: new_balance cannot be negative',
      );
    }
    return (betId: betId, newBalance: newBalance);
  }

  Future<HungryCatGlobalRound> settleGlobalRound(String roundId) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'settle_magic_srood_global_round',
      params: {'p_round_id': roundId},
    );
    final data = _asMap(raw, 'settle_magic_srood_global_round');
    final responseRoundId = _requiredString(
      data,
      'round_id',
      'settle_magic_srood_global_round',
    );
    if (responseRoundId != roundId) {
      throw const FormatException(
        'settle_magic_srood_global_round: round_id mismatch',
      );
    }
    final status = _requiredString(
      data,
      'status',
      'settle_magic_srood_global_round',
    );
    if (status != 'settled') {
      throw FormatException(
        'settle_magic_srood_global_round: unexpected status $status',
      );
    }
    final serverNow = _requiredDateTime(
      data,
      'server_now',
      'settle_magic_srood_global_round',
    );
    final winningFoodId = _requiredString(
      data,
      'winning_food_id',
      'settle_magic_srood_global_round',
    );
    final winningMultiplier = _requiredDouble(
      data,
      'winning_multiplier',
      'settle_magic_srood_global_round',
    );
    if (winningMultiplier <= 0) {
      throw const FormatException(
        'settle_magic_srood_global_round: invalid winning_multiplier',
      );
    }
    return HungryCatGlobalRound(
      roundId: responseRoundId,
      roundNumber: 0,
      status: status,
      bettingEndsAt: serverNow,
      serverNow: serverNow,
      winningFoodId: winningFoodId,
      winningFoodIcon: _optionalString(data['winning_food_icon']),
      winningFoodName: _optionalString(data['winning_food_name']),
      winningMultiplier: winningMultiplier,
    );
  }

  Future<Map<String, int>> getTeamBetTotals(String roundId) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'get_magic_srood_team_totals',
      params: {'p_round_id': roundId},
    );
    final data = _asMap(raw, 'get_magic_srood_team_totals');
    return data.map((key, value) {
      final total = _toInt(value);
      if (total == null || total < 0) {
        throw FormatException(
          'get_magic_srood_team_totals: invalid total for $key',
        );
      }
      return MapEntry(key, total);
    });
  }

  Future<List<HungryCatHistoryEntry>> getGlobalHistory({int limit = 20}) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'get_magic_srood_global_history',
      params: {'p_limit': limit},
    );
    final rows = _asList(raw, 'get_magic_srood_global_history');
    return rows
        .map(
          (row) => HungryCatHistoryEntry.fromJson(
            _asMap(row, 'get_magic_srood_global_history row'),
          ),
        )
        .toList(growable: false);
  }

  static HungryCatGlobalRound parseActiveRoundResponse(Object? raw) {
    const operation = 'get_or_create_magic_srood_round';
    final data = _asMap(raw, operation);
    final roundId = _requiredString(data, 'round_id', operation);
    final status = _requiredString(data, 'status', operation);
    if (status != 'betting' && status != 'settled') {
      throw FormatException('$operation: unexpected status $status');
    }
    final bettingEndsAt = _requiredDateTime(data, 'betting_ends_at', operation);
    final serverNow = _requiredDateTime(data, 'server_now', operation);
    final multiplier = data['winning_multiplier'] == null
        ? null
        : _requiredDouble(data, 'winning_multiplier', operation);
    return HungryCatGlobalRound(
      roundId: roundId,
      roundNumber: _requiredInt(data, 'round_number', operation),
      status: status,
      bettingEndsAt: bettingEndsAt,
      serverNow: serverNow,
      winningFoodId: _optionalString(data['winning_food_id']),
      winningFoodIcon: _optionalString(data['winning_food_icon']),
      winningFoodName: _optionalString(data['winning_food_name']),
      winningMultiplier: multiplier,
    );
  }
}

Map<String, dynamic> _asMap(Object? raw, String operation) {
  Object? value = raw;
  if (value is List && value.length == 1) value = value.first;
  if (value is! Map) {
    throw FormatException(
      '$operation: expected an object, received ${value.runtimeType}',
    );
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<dynamic> _asList(Object? raw, String operation) {
  if (raw is! List) {
    throw FormatException(
      '$operation: expected a list, received ${raw.runtimeType}',
    );
  }
  return raw;
}

String _requiredString(
  Map<String, dynamic> data,
  String key,
  String operation,
) {
  final value = _optionalString(data[key]);
  if (value == null) {
    throw FormatException('$operation: missing or invalid $key');
  }
  return value;
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _requiredInt(Map<String, dynamic> data, String key, String operation) {
  final value = _toInt(data[key]);
  if (value == null) {
    throw FormatException('$operation: missing or invalid $key');
  }
  return value;
}

int? _toInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

double _requiredDouble(
  Map<String, dynamic> data,
  String key,
  String operation,
) {
  final value = data[key];
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  if (parsed == null || !parsed.isFinite) {
    throw FormatException('$operation: missing or invalid $key');
  }
  return parsed;
}

DateTime _requiredDateTime(
  Map<String, dynamic> data,
  String key,
  String operation,
) {
  final value = _optionalString(data[key]);
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$operation: missing or invalid $key');
  }
  return parsed.toUtc();
}
