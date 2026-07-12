import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import 'crash_v2_models.dart';

/// Crash Rocket v2 — thin RPC + realtime client.
///
/// Every mutation goes through a SECURITY DEFINER RPC with an idempotency key.
/// The client never writes game or wallet tables and never advances rounds.
class CrashV2Service {
  const CrashV2Service();

  SupabaseClient get _client => SupabaseService.requiredClient;

  Map<String, dynamic> _map(Object? raw, String operation) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw FormatException('$operation returned malformed data');
  }

  Future<CrashV2State> fetchState({String? roomId}) async {
    final raw = await _client.rpc(
      'crash_v2_get_state',
      params: {'p_room_id': roomId},
    );
    return CrashV2State.fromJson(_map(raw, 'crash_v2_get_state'));
  }

  Future<({CrashV2Bet bet, int balance})> placeBet({
    required String? roomId,
    required int slot,
    required int amount,
    required double? autoCashout,
    required String idempotencyKey,
  }) async {
    final raw = await _client.rpc(
      'crash_v2_place_bet',
      params: {
        'p_room_id': roomId,
        'p_bet_slot': slot,
        'p_amount': amount,
        'p_auto_cashout_multiplier': autoCashout,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _betResult(raw, 'crash_v2_place_bet');
  }

  Future<({CrashV2Bet bet, int balance})> cancelBet({
    required String betId,
  }) async {
    final raw = await _client.rpc(
      'crash_v2_cancel_bet',
      params: {'p_bet_id': betId},
    );
    return _betResult(raw, 'crash_v2_cancel_bet');
  }

  Future<({CrashV2Bet bet, int balance})> cashOut({
    required String betId,
    required String idempotencyKey,
  }) async {
    final raw = await _client.rpc(
      'crash_v2_cash_out',
      params: {'p_bet_id': betId, 'p_idempotency_key': idempotencyKey},
    );
    return _betResult(raw, 'crash_v2_cash_out');
  }

  Future<CrashV2Bet> setAutoCashout({
    required String betId,
    required double? autoCashout,
  }) async {
    final raw = await _client.rpc(
      'crash_v2_set_auto_cashout',
      params: {'p_bet_id': betId, 'p_auto_cashout_multiplier': autoCashout},
    );
    final data = _map(raw, 'crash_v2_set_auto_cashout');
    final bet = data['bet'];
    if (bet is! Map) throw const FormatException('Malformed bet response');
    return CrashV2Bet.fromJson(Map<String, dynamic>.from(bet));
  }

  Future<Map<String, dynamic>> verifyRound({
    required int roundNumber,
    String? roomId,
  }) async {
    final raw = await _client.rpc(
      'crash_v2_verify_round',
      params: {'p_public_round_number': roundNumber, 'p_room_id': roomId},
    );
    return _map(raw, 'crash_v2_verify_round');
  }

  Future<List<Map<String, dynamic>>> recentRounds({
    String? roomId,
    int limit = 20,
  }) async {
    final raw = await _client.rpc(
      'crash_v2_get_recent_rounds',
      params: {'p_room_id': roomId, 'p_limit': limit},
    );
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  ({CrashV2Bet bet, int balance}) _betResult(Object? raw, String operation) {
    final data = _map(raw, operation);
    final bet = data['bet'];
    if (bet is! Map) throw FormatException('Malformed $operation response');
    return (
      bet: CrashV2Bet.fromJson(Map<String, dynamic>.from(bet)),
      balance: _intValue(data['wallet_balance']),
    );
  }

  /// Realtime: round row changes + public activity events for this scope.
  /// The caller refreshes authoritative state via [fetchState] on signal —
  /// payloads are treated as hints, never as settlement values.
  RealtimeChannel subscribe({
    required String? roomId,
    required void Function() onChange,
    required void Function(RealtimeSubscribeStatus status) onStatus,
  }) {
    final channel = _client.channel('crash_v2:${roomId ?? 'global'}');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'crash_v2_rounds',
          callback: (payload) {
            final changedRoom = payload.newRecord['room_id']?.toString();
            if (changedRoom == roomId) onChange();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'crash_v2_round_events',
          callback: (_) => onChange(),
        )
        .subscribe((status, [error]) => onStatus(status));
    return channel;
  }
}

int _intValue(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
