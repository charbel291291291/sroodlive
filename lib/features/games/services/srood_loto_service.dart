import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/srood_loto_models.dart';

class SroodLotoService {
  const SroodLotoService();

  SupabaseClient get _client => SupabaseService.requiredClient;

  /// Returns the current draw, settings, user tickets, and balance.
  /// Also triggers settle + create-next-draw server-side on each call.
  Future<LotoCurrentDraw> getCurrentDraw() async {
    final result = await _client.rpc('loto_get_current_draw').single();
    return LotoCurrentDraw.fromJson(result);
  }

  /// Buy one ticket for the current draw.
  /// Throws if game disabled, draw closed, duplicate numbers, or balance low.
  Future<Map<String, dynamic>> buyTicket(List<int> numbers) async {
    final result = await _client.rpc(
      'loto_buy_ticket',
      params: {'p_numbers': numbers},
    ).single();
    return result;
  }

  /// Get all user tickets for a specific draw, with draw results.
  Future<List<LotoTicket>> getMyTickets(String drawId) async {
    final result = await _client.rpc(
      'loto_get_my_tickets',
      params: {'p_draw_id': drawId},
    ).single();
    final list = result as List<dynamic>? ?? [];
    return list.map((e) => LotoTicket.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Returns last 20 settled draws with user's ticket for each.
  Future<List<LotoRecentDraw>> getRecentDraws() async {
    final result = await _client.rpc('loto_get_recent_draws').single();
    final list = result as List<dynamic>? ?? [];
    return list.map((e) => LotoRecentDraw.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ── Admin ──────────────────────────────────────────────────────────────────

  Future<void> adminForceSettle(String drawId) async {
    await _client.rpc(
      'admin_loto_force_settle_draw',
      params: {'p_draw_id': drawId},
    ).single();
  }

  Future<void> adminVoidDraw(String drawId) async {
    await _client.rpc(
      'admin_loto_void_draw',
      params: {'p_draw_id': drawId},
    ).single();
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
        if (isEnabled != null)                 'p_is_enabled': isEnabled,
        if (ticketPriceCoins != null)          'p_ticket_price_coins': ticketPriceCoins,
        if (numberMin != null)                 'p_number_min': numberMin,
        if (numberMax != null)                 'p_number_max': numberMax,
        if (numbersPerTicket != null)          'p_numbers_per_ticket': numbersPerTicket,
        if (drawIntervalMinutes != null)       'p_draw_interval_minutes': drawIntervalMinutes,
        if (match3Prize != null)               'p_match_3_prize': match3Prize,
        if (match4Prize != null)               'p_match_4_prize': match4Prize,
        if (match5Prize != null)               'p_match_5_prize': match5Prize,
        if (match6Prize != null)               'p_match_6_prize': match6Prize,
        if (progressiveJackpotEnabled != null) 'p_progressive_jackpot_enabled': progressiveJackpotEnabled,
        if (jackpotContributionPct != null)    'p_jackpot_contribution_pct': jackpotContributionPct,
      },
    ).single();
  }

  Future<Map<String, dynamic>> adminGetDrawSummary(String drawId) async {
    final result = await _client.rpc(
      'admin_loto_get_draw_summary',
      params: {'p_draw_id': drawId},
    ).single();
    return result;
  }
}
