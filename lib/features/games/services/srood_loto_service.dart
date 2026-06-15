import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/srood_loto_models.dart';

class SroodLotoService {
  const SroodLotoService();

  SupabaseClient get _client => SupabaseService.requiredClient;

  /// Returns the current draw, settings, user tickets, and balance.
  /// Also triggers settle + create-next-draw server-side on each call.
  Future<LotoCurrentDraw> getCurrentDraw() async {
    final raw = await _client.rpc('loto_get_current_draw');
    _debugLog('loto_get_current_draw', raw);
    return LotoCurrentDraw.fromJson(_toMap(raw));
  }

  /// Buy one ticket for the current draw.
  /// Throws if game disabled, draw closed, duplicate numbers, or balance low.
  Future<Map<String, dynamic>> buyTicket(List<int> numbers) async {
    final raw = await _client.rpc(
      'loto_buy_ticket',
      params: {'p_numbers': numbers},
    );
    _debugLog('loto_buy_ticket', raw);
    return _toMap(raw);
  }

  /// Get all user tickets for a specific draw, with draw results.
  Future<List<LotoTicket>> getMyTickets(String drawId) async {
    final raw = await _client.rpc(
      'loto_get_my_tickets',
      params: {'p_draw_id': drawId},
    );
    _debugLog('loto_get_my_tickets', raw);
    return _toList(raw)
        .map((e) => LotoTicket.fromJson(_toMap(e)))
        .toList();
  }

  /// Returns last 20 settled draws with user's ticket for each.
  Future<List<LotoRecentDraw>> getRecentDraws() async {
    final raw = await _client.rpc('loto_get_recent_draws');
    _debugLog('loto_get_recent_draws', raw);
    return _toList(raw)
        .map((e) => LotoRecentDraw.fromJson(_toMap(e)))
        .toList();
  }

  // ── Admin ──────────────────────────────────────────────────────────────────

  Future<void> adminForceSettle(String drawId) async {
    await _client.rpc(
      'admin_loto_force_settle_draw',
      params: {'p_draw_id': drawId},
    );
  }

  Future<void> adminVoidDraw(String drawId) async {
    await _client.rpc(
      'admin_loto_void_draw',
      params: {'p_draw_id': drawId},
    );
  }

  Future<void> adminUpdateSettings({
    bool? isEnabled,
    int? ticketPriceCoins,
    int? numberMin,
    int? numberMax,
    int? numbersPerTicket,
    int? drawIntervalMinutes,
    int? match3Prize,
    int? match4Prize,
    int? match5Prize,
    int? match6Prize,
    bool? progressiveJackpotEnabled,
    double? jackpotContributionPct,
  }) async {
    await _client.rpc(
      'admin_loto_update_settings',
      params: {
        'p_is_enabled': ?isEnabled,
        'p_ticket_price_coins': ?ticketPriceCoins,
        'p_number_min': ?numberMin,
        'p_number_max': ?numberMax,
        'p_numbers_per_ticket': ?numbersPerTicket,
        'p_draw_interval_minutes': ?drawIntervalMinutes,
        'p_match_3_prize': ?match3Prize,
        'p_match_4_prize': ?match4Prize,
        'p_match_5_prize': ?match5Prize,
        'p_match_6_prize': ?match6Prize,
        'p_progressive_jackpot_enabled': ?progressiveJackpotEnabled,
        'p_jackpot_contribution_pct': ?jackpotContributionPct,
      },
    );
  }

  Future<Map<String, dynamic>> adminGetDrawSummary(String drawId) async {
    final raw = await _client.rpc(
      'admin_loto_get_draw_summary',
      params: {'p_draw_id': drawId},
    );
    return _toMap(raw);
  }

  // ── Safe parsing helpers ───────────────────────────────────────────────────

  /// Safely coerce any PostgREST RPC response to a Map.
  ///
  /// PostgREST passes `RETURNS jsonb` values through as-is:
  /// - jsonb object  → response body is `{}` → Dart gives Map
  /// - jsonb array   → response body is `[]` → Dart gives List (caller must use _toList instead)
  ///
  /// When called on a List we take the first element, which covers the rare
  /// case where PostgREST wraps a single-row scalar in `[{...}]`.
  static Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return {};
  }

  /// Safely coerce any PostgREST RPC response to a List.
  ///
  /// For `RETURNS jsonb` functions that return a JSON array PostgREST delivers
  /// the array directly as the response body, so Dart sees a `List<dynamic>`.
  /// We also handle the edge case where the result is a single Map whose
  /// first value is a list (some PostgREST versions wrap scalars).
  static List<dynamic> _toList(dynamic value) {
    if (value is List) return value;
    if (value is Map) {
      for (final v in value.values) {
        if (v is List) return v;
      }
    }
    return const [];
  }

  static void _debugLog(String rpc, dynamic value) {
    if (!kDebugMode) return;
    final preview = value?.toString() ?? 'null';
    debugPrint(
      '[SroodLoto] $rpc → ${value.runtimeType} '
      '| preview: ${preview.length > 120 ? "${preview.substring(0, 120)}…" : preview}',
    );
  }
}
