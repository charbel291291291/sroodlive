import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/crash_rocket_models.dart';

class CrashRocketService {
  const CrashRocketService();

  SupabaseClient get _client => SupabaseService.requiredClient;

  Map<String, dynamic> _map(Object? raw, String operation) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw FormatException('$operation returned malformed data');
  }

  Future<SroodRocketState> fetchState({String? roomId}) async {
    final raw = await _client.rpc(
      'get_active_crash_rocket_round',
      params: {'p_room_id': roomId},
    );
    return SroodRocketState.fromJson(
      _map(raw, 'get_active_crash_rocket_round'),
    );
  }

  Future<({SroodRocketBet bet, int balance})> placeBet({
    required String? roomId,
    required int slot,
    required int amount,
    required double? autoCashout,
    required String clientBetId,
  }) async {
    final raw = await _client.rpc(
      'place_crash_rocket_bet',
      params: {
        'p_room_id': roomId,
        'p_bet_slot': slot,
        'p_amount': amount,
        'p_auto_cashout_multiplier': autoCashout,
        'p_client_bet_id': clientBetId,
      },
    );
    final data = _map(raw, 'place_crash_rocket_bet');
    final bet = data['bet'];
    if (bet is! Map) throw const FormatException('Malformed bet response');
    return (
      bet: SroodRocketBet.fromJson(Map<String, dynamic>.from(bet)),
      balance: _intValue(data['wallet_balance']),
    );
  }

  Future<({SroodRocketBet bet, int balance})> cashout({
    required String betId,
    required String clientCashoutId,
  }) async {
    final raw = await _client.rpc(
      'cashout_crash_rocket_bet',
      params: {'p_bet_id': betId, 'p_client_cashout_id': clientCashoutId},
    );
    final data = _map(raw, 'cashout_crash_rocket_bet');
    final bet = data['bet'];
    if (bet is! Map) throw const FormatException('Malformed cashout response');
    return (
      bet: SroodRocketBet.fromJson(Map<String, dynamic>.from(bet)),
      balance: _intValue(data['wallet_balance']),
    );
  }

  Future<void> advance({String? roomId}) async {
    await _client.rpc(
      'advance_crash_rocket_round',
      params: {'p_room_id': roomId},
    );
  }

  RealtimeChannel subscribe({
    required String? roomId,
    required void Function() onChange,
    required void Function(RealtimeSubscribeStatus status) onStatus,
  }) {
    final channel = _client.channel('srood_rocket:${roomId ?? 'global'}');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'crash_rocket_rounds',
          callback: (payload) {
            final changedRoom = payload.newRecord['room_id']?.toString();
            if (changedRoom == roomId) onChange();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'crash_rocket_round_events',
          callback: (_) => onChange(),
        )
        .subscribe((status, [error]) => onStatus(status));
    return channel;
  }
}

int _intValue(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
