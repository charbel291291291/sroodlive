import '../../../../core/supabase/supabase_service.dart';
import '../models/crash_v3_bet.dart';
import '../models/crash_v3_history_item.dart';
import '../models/crash_v3_round.dart';
import '../models/crash_v3_settings.dart';

class CrashV3Snapshot {
  const CrashV3Snapshot({
    required this.serverTime,
    required this.settings,
    required this.bets,
    required this.history,
    this.round,
  });
  final DateTime serverTime;
  final CrashV3Settings settings;
  final CrashV3Round? round;
  final List<CrashV3Bet> bets;
  final List<CrashV3HistoryItem> history;
}

class CrashV3Service {
  const CrashV3Service();
  Future<CrashV3Snapshot> getState() async {
    final raw = await SupabaseService.requiredClient.rpc('crash_v3_get_state');
    final json = Map<String, dynamic>.from(raw as Map);
    final roundJson = json['current_round'];
    return CrashV3Snapshot(
      serverTime: DateTime.parse(json['server_time'] as String).toUtc(),
      settings: CrashV3Settings.fromJson(
        Map<String, dynamic>.from(json['settings'] as Map),
      ),
      round: roundJson == null
          ? null
          : CrashV3Round.fromJson(Map<String, dynamic>.from(roundJson as Map)),
      bets: (json['my_bets'] as List)
          .map(
            (value) =>
                CrashV3Bet.fromJson(Map<String, dynamic>.from(value as Map)),
          )
          .toList(growable: false),
      history: (json['recent_history'] as List)
          .map(
            (value) => CrashV3HistoryItem.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<CrashV3Bet> placeBet({
    required String roundId,
    required int slot,
    required int amount,
    required String idempotencyKey,
    double? autoCashout,
  }) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'crash_v3_place_bet',
      params: {
        'p_round_id': roundId,
        'p_slot_number': slot,
        'p_bet_amount': amount,
        'p_auto_cashout_multiplier': autoCashout,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return CrashV3Bet.fromJson(
      Map<String, dynamic>.from((raw as Map)['bet'] as Map),
    );
  }

  Future<CrashV3Bet> cashout(
    CrashV3Bet bet, {
    required String idempotencyKey,
  }) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'crash_v3_cashout',
      params: {'p_bet_id': bet.id, 'p_idempotency_key': idempotencyKey},
    );
    return CrashV3Bet.fromJson(
      Map<String, dynamic>.from((raw as Map)['bet'] as Map),
    );
  }

  Future<int> walletBalance() async {
    final userId = SupabaseService.requiredClient.auth.currentUser!.id;
    final row = await SupabaseService.requiredClient
        .from('wallets')
        .select('coins_balance')
        .eq('user_id', userId)
        .single();
    return (row['coins_balance'] as num).toInt();
  }

  Future<List<Map<String, dynamic>>> myHistory({DateTime? cursor}) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'crash_v3_get_my_history',
      params: {'p_limit': 30, 'p_cursor': cursor?.toIso8601String()},
    );
    return (raw as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> verifyRound(String roundId) async =>
      Map<String, dynamic>.from(
        await SupabaseService.requiredClient.rpc(
              'crash_v3_verify_round',
              params: {'p_round_id': roundId},
            )
            as Map,
      );
}
