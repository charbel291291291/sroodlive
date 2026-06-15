import '../../../core/supabase/supabase_service.dart';
import '../models/charisma_models.dart';

class CharismaService {
  const CharismaService();

  // ── Public RPCs ────────────────────────────────────────────────────────────

  Future<List<CharismaActiveChallenge>> getActiveChallenges({
    String? scope,
    String? agencyId,
  }) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'charisma_get_active_challenges',
      params: {
        'p_scope':     ?scope,
        'p_agency_id': ?agencyId,
      },
    );
    _log('charisma_get_active_challenges', raw);
    final list = _toList(raw);
    return list
        .map((e) => CharismaActiveChallenge.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CharismaEntry> joinChallenge(
    String challengeId, {
    String? roomId,
  }) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'charisma_join_challenge',
      params: {
        'p_challenge_id': challengeId,
        'p_room_id': ?roomId,
      },
    );
    _log('charisma_join_challenge', raw);
    return CharismaEntry.fromJson(_toMap(raw));
  }

  Future<Map<String, dynamic>> vote(String entryId) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'charisma_vote',
      params: {'p_entry_id': entryId},
    );
    _log('charisma_vote', raw);
    return _toMap(raw);
  }

  Future<List<CharismaLeaderboardEntry>> getLeaderboard(
      String challengeId) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'charisma_get_leaderboard',
      params: {'p_challenge_id': challengeId},
    );
    _log('charisma_get_leaderboard', raw);
    final list = _toList(raw);
    return list
        .map((e) =>
            CharismaLeaderboardEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Admin RPCs ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> adminCreateChallenge({
    required String title,
    String? titleAr,
    String scope = 'official',
    String? agencyId,
    required DateTime startsAt,
    required DateTime endsAt,
    int rewardCoins = 100000,
    String? rewardFrameId,
  }) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'admin_charisma_create_challenge',
      params: {
        'p_title':          title,
        'p_title_ar':        ?titleAr,
        'p_scope':          scope,
        'p_agency_id':       ?agencyId,
        'p_starts_at':      startsAt.toUtc().toIso8601String(),
        'p_ends_at':        endsAt.toUtc().toIso8601String(),
        'p_reward_coins':   rewardCoins,
        'p_reward_frame_id': ?rewardFrameId,
      },
    );
    _log('admin_charisma_create_challenge', raw);
    return _toMap(raw);
  }

  Future<Map<String, dynamic>> adminCrownWinner(String challengeId) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'admin_charisma_crown_winner',
      params: {'p_challenge_id': challengeId},
    );
    _log('admin_charisma_crown_winner', raw);
    return _toMap(raw);
  }

  Future<void> adminCancelChallenge(String challengeId) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'admin_charisma_cancel_challenge',
      params: {'p_challenge_id': challengeId},
    );
    _log('admin_charisma_cancel_challenge', raw);
  }

  Future<List<CharismaActiveChallenge>> adminGetChallenges({
    String? scope,
  }) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'admin_charisma_get_challenges',
      params: {'p_scope': ?scope},
    );
    _log('admin_charisma_get_challenges', raw);
    final list = _toList(raw);
    return list
        .map((e) => CharismaActiveChallenge.fromFlatJson(
            e as Map<String, dynamic>))
        .toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _toMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is List && v.isNotEmpty && v.first is Map<String, dynamic>) {
      return v.first as Map<String, dynamic>;
    }
    return {};
  }

  static List<dynamic> _toList(dynamic v) {
    if (v is List) return v;
    if (v is Map<String, dynamic>) return [v];
    return [];
  }

  static void _log(String rpc, dynamic v) {
    assert(() {
      final s = v.toString();
      // ignore: avoid_print
      print('[Charisma] $rpc → ${s.length > 120 ? "${s.substring(0, 120)}…" : s}');
      return true;
    }());
  }
}
