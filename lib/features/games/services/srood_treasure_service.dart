import '../../../core/supabase/supabase_service.dart';
import '../models/srood_treasure_models.dart';

class SroodTreasureService {
  const SroodTreasureService();

  Future<TreasureState> getCurrentGame() async {
    final raw = await SupabaseService.requiredClient
        .rpc('treasure_get_current_game');
    _debugLog('treasure_get_current_game', raw);
    return TreasureState.fromJson(_toMap(raw));
  }

  Future<Map<String, dynamic>> startGame() async {
    final raw = await SupabaseService.requiredClient
        .rpc('treasure_start_game');
    _debugLog('treasure_start_game', raw);
    return _toMap(raw);
  }

  Future<void> selectPersonalBox(String gameId, int boxNumber) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'treasure_select_personal_box',
      params: {'p_game_id': gameId, 'p_box_number': boxNumber},
    );
    _debugLog('treasure_select_personal_box', raw);
  }

  Future<TreasureOpenResult> openBox(String gameId, int boxNumber) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'treasure_open_box',
      params: {'p_game_id': gameId, 'p_box_number': boxNumber},
    );
    _debugLog('treasure_open_box', raw);
    return TreasureOpenResult.fromJson(_toMap(raw));
  }

  Future<TreasureActionResult> acceptOffer(String gameId) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'treasure_accept_offer',
      params: {'p_game_id': gameId},
    );
    _debugLog('treasure_accept_offer', raw);
    return TreasureActionResult.fromJson(_toMap(raw));
  }

  Future<TreasureActionResult> takeBox(String gameId) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'treasure_take_box',
      params: {'p_game_id': gameId},
    );
    _debugLog('treasure_take_box', raw);
    return TreasureActionResult.fromJson(_toMap(raw));
  }

  Future<void> continueGame(String gameId) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'treasure_continue_game',
      params: {'p_game_id': gameId},
    );
    _debugLog('treasure_continue_game', raw);
  }

  Future<void> abandonGame(String gameId) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'treasure_abandon_game',
      params: {'p_game_id': gameId},
    );
    _debugLog('treasure_abandon_game', raw);
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _toMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is List && v.isNotEmpty && v.first is Map<String, dynamic>) {
      return v.first as Map<String, dynamic>;
    }
    return {};
  }

  static void _debugLog(String rpc, dynamic v) {
    assert(() {
      final s = v.toString();
      // ignore: avoid_print
      print('[Treasure] $rpc → ${s.length > 120 ? "${s.substring(0, 120)}…" : s}');
      return true;
    }());
  }
}
