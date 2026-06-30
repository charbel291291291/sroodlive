import 'dart:math';

import '../../../core/supabase/supabase_service.dart';
import '../models/fish_hunt_models.dart';

/// Srood Fish Hunt game service. Wallet debit/credit, the hit/miss roll and
/// the final result are all server-authoritative inside `fish_hunt_place_shot`
/// — this service only forwards the caller's choice and renders the response.
class FishHuntService {
  const FishHuntService();

  static final Random _random = Random.secure();

  Future<FishHuntState> fetchState({String? roomId}) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'fish_hunt_get_state',
      params: {'p_room_id': roomId},
    );
    return FishHuntState.fromJson(raw as Map<String, dynamic>);
  }

  Future<FishHuntShotResult> placeShot({
    required String fishId,
    required int betAmount,
    String? roomId,
  }) async {
    final clientShotId = _generateClientShotId();
    final raw = await SupabaseService.requiredClient.rpc(
      'fish_hunt_place_shot',
      params: {
        'p_room_id': roomId,
        'p_fish_id': fishId,
        'p_bet_amount': betAmount,
        'p_client_shot_id': clientShotId,
      },
    );
    return FishHuntShotResult.fromJson(raw as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> fetchLeaderboard({String? roomId}) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'fish_hunt_get_leaderboard',
      params: {'p_room_id': roomId},
    );
    return (raw as List<dynamic>).cast<Map<String, dynamic>>().toList(
      growable: false,
    );
  }

  String _generateClientShotId() {
    final userId =
        SupabaseService.requiredClient.auth.currentUser?.id ?? 'anon';
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32);
    return 'fh_${userId}_${nowMicros}_$salt';
  }
}
