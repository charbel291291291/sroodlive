import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/room_game_models.dart';

/// Server-authoritative room game service.
///
/// All users in the same room subscribe to one shared [RoomGameRound].
/// No game result is ever generated on the client.
///
/// ## Lifecycle (Hungry Cat)
///   1. Host calls [createRound] → status = betting_open
///   2. All room members call [placeBet] while betting_open
///   3. Host calls [lockRound] (when betting_closes_at passes) → server picks
///      winner and transitions directly to finished
///   4. All clients receive Realtime update with result_json
///   5. Clients animate the wheel to the official winning slot
///
/// ## Lifecycle (Crash Rocket)
///   1. Host calls [createRound] → status = betting_open (crash_m pre-committed)
///   2. All room members call [placeBet]
///   3. Host calls [lockRound] (betting closes) → status = running, started_at set
///   4. All clients start the multiplier curve from started_at
///   5. Users call [cashoutCrash] to cash out mid-flight
///   6. Host calls [revealCrashRound] at reveal_at → server settles, result revealed
///   7. All clients receive Realtime update with crash_multiplier
///
/// ## Late joiner / reconnect
///   Call [getActiveRound] on join to sync to current state immediately.
class RoomGameService {
  const RoomGameService();

  SupabaseClient get _client => SupabaseService.requiredClient;

  // ── Round management (host only) ──────────────────────────────────────────

  /// Creates a new server-authoritative round for [roomId].
  /// Only the room owner may call this.
  /// Returns full timing metadata needed to drive client animations.
  Future<RoomGameRoundCreated> createRound({
    required String roomId,
    required GameCode gameCode,
    int bettingSeconds = 10,
  }) async {
    final data = await _client.rpc(
      'create_room_game_round',
      params: {
        'p_room_id': roomId,
        'p_game_code': gameCode.value,
        'p_betting_seconds': bettingSeconds,
      },
    ) as Map<String, dynamic>;
    return RoomGameRoundCreated.fromJson(data);
  }

  /// Closes betting and (for hungry_cat) immediately reveals result + settles.
  /// For crash_rocket, transitions to 'running' — call [revealCrashRound] later.
  Future<Map<String, dynamic>> lockRound(String roundId) async {
    final data = await _client.rpc(
      'lock_room_game_round',
      params: {'p_round_id': roundId},
    ) as Map<String, dynamic>;
    return data;
  }

  /// Reveals the crash multiplier and settles all crash bets.
  /// Host calls this when [RoomGameRound.revealAt] has passed.
  /// Server validates the timing server-side.
  Future<Map<String, dynamic>> revealCrashRound(String roundId) async {
    final data = await _client.rpc(
      'reveal_room_crash_round',
      params: {'p_round_id': roundId},
    ) as Map<String, dynamic>;
    return data;
  }

  /// Cancels round and refunds all bets. Host only.
  Future<Map<String, dynamic>> cancelRound(
    String roundId, {
    String reason = 'cancelled_by_host',
  }) async {
    final data = await _client.rpc(
      'cancel_room_game_round',
      params: {
        'p_round_id': roundId,
        'p_reason': reason,
      },
    ) as Map<String, dynamic>;
    return data;
  }

  // ── Player actions ────────────────────────────────────────────────────────

  /// Places a bet on the current round.
  /// Deducts coins atomically on the server.
  ///
  /// [betJson] is game-specific:
  ///   hungry_cat:   {"food_id": "golden_fish"}
  ///   crash_rocket: {"auto_cashout_multiplier": 2.5}  // optional
  Future<RoomGameBet> placeBet({
    required String roundId,
    required int betAmount,
    required Map<String, dynamic> betJson,
  }) async {
    final data = await _client.rpc(
      'place_room_game_bet',
      params: {
        'p_round_id': roundId,
        'p_bet_amount': betAmount,
        'p_bet_json': betJson,
      },
    ) as Map<String, dynamic>;

    // The RPC returns {bet_id, new_balance}; fetch full bet for the return
    final betId = data['bet_id'] as String;
    final betRow = await _client
        .from('room_game_bets')
        .select()
        .eq('id', betId)
        .single();
    return RoomGameBet.fromJson(betRow);
  }

  /// Cashes out a crash bet mid-flight.
  /// The server validates: round is still running AND the submitted multiplier
  /// hasn't exceeded the pre-committed crash point.
  /// Client-submitted multiplier is clamped to server's current value.
  Future<Map<String, dynamic>> cashoutCrash({
    required String betId,
    required double multiplier,
  }) async {
    final data = await _client.rpc(
      'cashout_room_crash_bet',
      params: {
        'p_bet_id': betId,
        'p_multiplier': multiplier,
      },
    ) as Map<String, dynamic>;
    return data;
  }

  // ── State sync ────────────────────────────────────────────────────────────

  /// Fetches the current active round for a room + game combination.
  /// Use on screen mount or reconnect to sync late joiners to the correct state.
  ///
  /// Returns null if no active round exists.
  Future<({RoomGameRound? round, List<RoomGameBet> myBets})>
      getActiveRound({
    required String roomId,
    required GameCode gameCode,
  }) async {
    final data = await _client.rpc(
      'get_active_room_game_round',
      params: {
        'p_room_id': roomId,
        'p_game_code': gameCode.value,
      },
    ) as Map<String, dynamic>;

    final roundJson = data['active_round'] as Map<String, dynamic>?;
    if (roundJson == null) return (round: null, myBets: <RoomGameBet>[]);

    final round = RoomGameRound.fromJson(roundJson);
    final betsRaw = data['my_bets'] as List<dynamic>? ?? const [];
    final bets = betsRaw
        .map((e) => RoomGameBet.fromJson(e as Map<String, dynamic>))
        .toList();

    return (round: round, myBets: bets);
  }

  /// Fetches the calling user's bets for a specific round.
  Future<List<RoomGameBet>> fetchMyBets(String roundId) async {
    final rows = await _client
        .from('room_game_bets')
        .select()
        .eq('round_id', roundId)
        .eq('user_id', _client.auth.currentUser?.id ?? '')
        .order('created_at');
    return (rows as List<dynamic>)
        .map((e) => RoomGameBet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Realtime subscription ─────────────────────────────────────────────────

  /// Subscribes to [room_game_rounds] for a specific room + game.
  ///
  /// [onRoundUpdate] is called every time the round row changes
  /// (status transitions, result_json reveal, etc.).
  ///
  /// Returns a [RealtimeChannel] — call `.unsubscribe()` on it to clean up.
  ///
  /// All clients in the room receive the SAME event at the SAME time.
  /// The [RoomGameRound.result_json] is null until status = revealed/finished,
  /// so clients never see the result before the server reveals it.
  RealtimeChannel subscribeToRound({
    required String roomId,
    required GameCode gameCode,
    required void Function(RoomGameRound round) onRoundUpdate,
    void Function(String error)? onError,
  }) {
    final channel = _client.channel('room_game_round:$roomId:${gameCode.value}');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'room_game_rounds',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: roomId,
      ),
      callback: (payload) {
        try {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          if (row['game_code'] != gameCode.value) return;

          final round = RoomGameRound.fromJson(row);
          onRoundUpdate(round);
        } catch (e) {
          onError?.call(e.toString());
        }
      },
    );

    channel.subscribe((status, [error]) {
      if (error != null) onError?.call(error.toString());
    });

    return channel;
  }

  /// Subscribes to [room_game_bets] for a specific round.
  ///
  /// Useful for showing a live bet board (all players' bets in the room).
  /// Also useful for the calling user's own bet status updates.
  RealtimeChannel subscribeToBets({
    required String roundId,
    required void Function(RoomGameBet bet) onBetUpdate,
    void Function(String error)? onError,
  }) {
    final channel = _client.channel('room_game_bets:$roundId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'room_game_bets',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'round_id',
        value: roundId,
      ),
      callback: (payload) {
        try {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          final bet = RoomGameBet.fromJson(row);
          onBetUpdate(bet);
        } catch (e) {
          onError?.call(e.toString());
        }
      },
    );

    channel.subscribe((status, [error]) {
      if (error != null) onError?.call(error.toString());
    });

    return channel;
  }

  // ── Error classification ──────────────────────────────────────────────────

  /// Translates a raw Supabase exception message into a user-friendly key.
  static RoomGameError classifyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('round_already_active')) return RoomGameError.roundAlreadyActive;
    if (msg.contains('not_room_host')) return RoomGameError.notRoomHost;
    if (msg.contains('not_room_member')) return RoomGameError.notRoomMember;
    if (msg.contains('betting_closed')) return RoomGameError.bettingClosed;
    if (msg.contains('insufficient_coins')) return RoomGameError.insufficientBalance;
    if (msg.contains('invalid_bet_amount')) return RoomGameError.invalidBet;
    if (msg.contains('bet_not_cashable')) return RoomGameError.betNotCashable;
    if (msg.contains('round_not_running')) return RoomGameError.roundNotRunning;
    if (msg.contains('too_early_to_reveal')) return RoomGameError.tooEarlyToReveal;
    if (msg.contains('round_already_ended')) return RoomGameError.roundAlreadyEnded;
    if (msg.contains('game_disabled')) return RoomGameError.gameDisabled;
    return RoomGameError.unknown;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error taxonomy
// ─────────────────────────────────────────────────────────────────────────────

enum RoomGameError {
  roundAlreadyActive,
  notRoomHost,
  notRoomMember,
  bettingClosed,
  insufficientBalance,
  invalidBet,
  betNotCashable,
  roundNotRunning,
  tooEarlyToReveal,
  roundAlreadyEnded,
  gameDisabled,
  unknown;

  String localizedMessage({bool isArabic = false}) => switch (this) {
        RoomGameError.roundAlreadyActive => isArabic
            ? 'جولة نشطة بالفعل في هذه الغرفة'
            : 'A round is already active in this room',
        RoomGameError.notRoomHost => isArabic
            ? 'فقط مالك الغرفة يمكنه بدء الجولة'
            : 'Only the room host can start a round',
        RoomGameError.notRoomMember => isArabic
            ? 'يجب أن تكون عضواً في الغرفة للمراهنة'
            : 'You must be in the room to place a bet',
        RoomGameError.bettingClosed => isArabic
            ? 'انتهى وقت الرهان'
            : 'Betting is closed',
        RoomGameError.insufficientBalance => isArabic
            ? 'رصيدك غير كافٍ'
            : 'Insufficient balance',
        RoomGameError.invalidBet => isArabic
            ? 'مبلغ الرهان غير صالح'
            : 'Invalid bet amount',
        RoomGameError.betNotCashable => isArabic
            ? 'لا يمكن صرف هذا الرهان'
            : 'This bet cannot be cashed out',
        RoomGameError.roundNotRunning => isArabic
            ? 'الجولة غير نشطة'
            : 'Round is not running',
        RoomGameError.tooEarlyToReveal => isArabic
            ? 'لم يحن وقت الكشف بعد'
            : 'Too early to reveal the result',
        RoomGameError.roundAlreadyEnded => isArabic
            ? 'الجولة انتهت بالفعل'
            : 'Round has already ended',
        RoomGameError.gameDisabled => isArabic
            ? 'اللعبة معطلة حالياً'
            : 'Game is currently disabled',
        RoomGameError.unknown => isArabic
            ? 'حدث خطأ، حاول مرة أخرى'
            : 'An error occurred, please try again',
      };
}
