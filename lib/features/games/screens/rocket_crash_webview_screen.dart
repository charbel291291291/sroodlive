import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../services/crash_game_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

/// Rocket Crash -- global shared rounds, server-calculated cashout, real-time sync.
///
/// -- Bridge Web -> Flutter ---------------------------------------------------
///   GAME_READY              page loaded; request init
///   REQUEST_PLACE_BET       arm a slot in the global round
///   REQUEST_BET_DEBIT       legacy; rejected once server round is ready
///   REQUEST_BET_REFUND      cancel a slot (server round path only)
///   REQUEST_CASHOUT_CREDIT  cash out; server ALWAYS calculates multiplier
///   REQUEST_BET_LOST        rocket crashed (legacy local path only)
///   REQUEST_START_FLIGHT    ignored - backend (pg_cron) drives flight start
///   REQUEST_SETTLE_ROUND    ignored - backend (pg_cron) drives settlement
///   REQUEST_WALLET_REFRESH  refresh balance from DB
///   SET_SOUND_SETTING       sound pref (JS localStorage)
///   GAME_CLOSED             pop screen
///
/// -- Bridge Flutter -> Web ---------------------------------------------------
///   INIT_GAME               balance, locale, round state, history
///   SET_ROUND_STATE         phase transition (betting/flying/crashed)
///   HISTORY_UPDATE          last 20 crash multipliers
///   BETS_UPDATE             current round bet feed
///   WALLET_UPDATED          new balance
///   BET_ACCEPTED            bet_id, amount, newBalance
///   BET_REJECTED            code + userMessage
///   REFUND_ACCEPTED/REJECTED
///   CASHOUT_ACCEPTED        winAmount, multiplier, newBalance
///   CASHOUT_REJECTED        code + userMessage
class RocketCrashWebviewScreen extends StatefulWidget {
  const RocketCrashWebviewScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<RocketCrashWebviewScreen> createState() =>
      _RocketCrashWebviewScreenState();
}

class _RocketCrashWebviewScreenState extends State<RocketCrashWebviewScreen>
    with WidgetsBindingObserver {
  static const Set<String> _dedupePostTypes = {
    'INIT_GAME',
    'SET_ROUND_STATE',
    'WALLET_UPDATED',
  };

  late final WebViewController _controller;
  final _service = const CrashGameService();

  bool _pageError = false;
  String? _pageErrorMsg;

  // Boot/splash controller. The loading overlay hides as soon as the JS bridge
  // is alive (GAME_READY) or the first game data is delivered - it does NOT
  // depend solely on onPageFinished, which is unreliable for loadFlutterAsset
  // on Android and was leaving the "Connecting to live round..." splash stuck.
  bool _bootResolved = false;
  Timer? _bootTimeout;

  // True while _initGame() is awaiting RPCs; prevents concurrent re-entry.
  bool _isInitializing = false;

  // True once _roundId and _currentRoundNumber have been assigned from the
  // server. Financial actions (bet/refund/cashout) are rejected until true.
  bool _serverRoundReady = false;

  // Bet idempotency guard. BetIds are added BEFORE the financial RPC awaits
  // and are NEVER removed on error, so a network timeout cannot open a
  // double-cashout/refund window.
  final Set<String> _settledBetIds = {};

  // Global round state - client is a pure observer; server drives lifecycle.
  String? _roundId;
  int _currentRoundNumber = 0;
  RealtimeChannel? _roundChannel;
  Timer? _roundRefreshDebounce;
  bool _roundRefreshInFlight = false;
  // When a refresh is requested while one is already running, we remember it
  // here so the latest server state is never dropped (instead of returning).
  bool _refreshPending = false;
  String? _refreshPendingReason;
  bool _loggedEmptyRealtimePayload = false;

  // Periodic reconciliation poll. Realtime can be unreliable on mobile
  // (backgrounding, dropped sockets); this guarantees the client converges to
  // the true server round even if no realtime event arrives. Runs only while
  // the screen is foregrounded.
  Timer? _reconcilePoll;

  // Rounds for which a settle_rocket_crash_round RPC is currently in flight.
  // Prevents the client from spamming the settle RPC for the same stuck round.
  final Set<String> _settleInFlightRoundIds = {};

  // Throttle _sendBetFeed: skip if same roundId called within 2 s.
  String? _lastBetFeedRoundId;
  int _lastBetFeedMs = 0;

  // Debounce _refreshHistory: only fire 3 s after the last crashed event.
  Timer? _historyDebounce;

  Future<void>? _balanceRefreshFuture;
  final Map<String, String> _lastPostedMessages = {};

  // Server-local clock offset (serverNowMs - localNowMs), set on every
  // successful init. Used so realtime callbacks can send an accurate
  // serverNowMs without trusting the local clock alone.
  double _serverTimeOffsetMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF020818),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF020818))
      ..addJavaScriptChannel(
        'SroodBridge',
        onMessageReceived: (msg) => _onWebMessage(msg.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            _resolveBoot('page_finished');
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == false) return;
            if (!mounted) return;
            setState(() {
              _pageError = true;
              _pageErrorMsg = e.description;
            });
          },
        ),
      )
      ..loadFlutterAsset('assets/games/rocket_crash/index.html');

    _startBootTimeout();
  }

  // Hides the loading splash once the page/bridge is proven alive or the first
  // game data has been delivered. Idempotent.
  void _resolveBoot(String reason) {
    _bootTimeout?.cancel();
    if (_bootResolved) return;
    debugPrint('[RocketCrash] boot overlay hidden reason=$reason');
    if (mounted) {
      setState(() => _bootResolved = true);
    } else {
      _bootResolved = true;
    }
  }

  // Safety net: if no usable game data arrives within 5s, swap the splash for a
  // friendly retry state instead of leaving the user on "Connecting...".
  void _startBootTimeout() {
    _bootTimeout?.cancel();
    _bootTimeout = Timer(const Duration(seconds: 5), () {
      if (!mounted || _bootResolved) return;
      debugPrint('[RocketCrash] boot fallback timeout fired - no game data');
      setState(() {
        _pageError = true;
        _pageErrorMsg = 'sync_timeout';
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[RocketCrash] app resumed - refreshing round');
      _initGame();
    } else if (state == AppLifecycleState.paused) {
      // Stop polling while backgrounded; _initGame() restarts it on resume.
      _reconcilePoll?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roundRefreshDebounce?.cancel();
    _historyDebounce?.cancel();
    _reconcilePoll?.cancel();
    _bootTimeout?.cancel();
    _disposeRoundChannel();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(systemNavigationBarColor: Colors.transparent),
    );
    super.dispose();
  }

  // -- Subscription cleanup --------------------------------------------------

  // Unsubscribes and removes the realtime channel, then nulls the reference.
  // Safe to call multiple times; the null check prevents double-unsubscribe.
  void _disposeRoundChannel() {
    final ch = _roundChannel;
    if (ch == null) return;
    _roundChannel = null;
    ch.unsubscribe();
    try {
      SupabaseService.requiredClient.removeChannel(ch);
    } catch (_) {}
  }

  // -- Web -> Flutter --------------------------------------------------------

  Future<void> _onWebMessage(String raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = msg['type'] as String? ?? '';
    final payload = msg['payload'] as Map<String, dynamic>? ?? {};

    debugPrint('[RocketCrash] <- $type');

    // Any message proves the JS bridge is alive and the page rendered, so the
    // loading splash can come down immediately (GAME_READY is the first one).
    _resolveBoot('bridge:$type');

    switch (type) {
      case 'GAME_READY':
        await _initGame();
      case 'REQUEST_PLACE_BET':
        await _handlePlaceBet(payload);
      case 'REQUEST_BET_DEBIT':
        await _handleBetDebit(payload);
      case 'REQUEST_BET_REFUND':
        await _handleBetRefund(payload);
      case 'REQUEST_CASHOUT_CREDIT':
        await _handleCashout(payload);
      case 'REQUEST_BET_LOST':
        _handleBetLost(payload);
      case 'REQUEST_START_FLIGHT':
        await _handleStartFlight(payload);
      case 'REQUEST_SETTLE_ROUND':
        await _handleSettleRound(payload);
      case 'REQUEST_WALLET_REFRESH':
        await _refreshBalance();
      case 'SET_SOUND_SETTING':
        break;
      case 'GAME_CLOSED':
        if (mounted) Navigator.of(context).maybePop();
    }
  }

  // -- Init ------------------------------------------------------------------

  Future<void> _initGame() async {
    // Guard: prevent concurrent re-entry on rapid app resume or duplicate GAME_READY.
    if (_isInitializing) return;
    final isArabic = context.isArabic;
    if (SupabaseService.requiredClient.auth.currentUser == null) {
      return;
    }

    // Set directly for the security guard, then setState for UI.
    _isInitializing = true;
    _serverRoundReady = false;
    if (mounted) {
      setState(() {});
    }

    try {
      final initResults = await Future.wait<Object>([
        _service.fetchBalance(),
        _service.getOrCreateRocketRound(),
        _service.getRocketResults(),
      ]);
      final balance = initResults[0] as int;
      final round = initResults[1] as Map<String, dynamic>;
      final history = initResults[2] as List<Map<String, dynamic>>;

      _roundId = round['round_id']?.toString();
      final phase = round['status']?.toString() ?? 'betting';
      final bettingEndsAtMs = _parseTimestampMs(round['betting_ends_at']);
      final flightStartsAtMs = _parseTimestampMs(round['flight_starts_at']);
      final serverNowMs = _toDouble(round['server_now']);
      final roundNumber = _parseInt(round['round_number']);
      final crashMultiplier = _toDouble(round['crash_multiplier']);

      if (serverNowMs > 0) {
        _serverTimeOffsetMs =
            serverNowMs - DateTime.now().millisecondsSinceEpoch;
      }
      _currentRoundNumber = roundNumber;

      // Server round is now valid; financial actions are unblocked.
      _serverRoundReady =
          _roundId != null && roundNumber > 0 && phase != 'crashed';

      final histValues = history
          .map((h) => _toDouble(h['crash_multiplier']))
          .where((v) => v > 0)
          .take(20)
          .toList();

      debugPrint('[RocketCrash] INIT_GAME history len=${histValues.length}');

      // Dispose any previous channel before creating a new subscription.
      _disposeRoundChannel();
      _subscribeToRounds();

      debugPrint(
        '[RocketCrash] round loaded roundId=$_roundId phase=$phase '
        'balance=$balance serverOffset=${_serverTimeOffsetMs.round()}ms '
        'histCount=${histValues.length}',
      );

      final roundPayload = <String, dynamic>{
        'roundId': _roundId,
        'roundNumber': roundNumber,
        'phase': phase,
        'serverSynced': true,
        'bettingEndsAtMs': bettingEndsAtMs,
        'flightStartsAtMs': flightStartsAtMs,
        'serverNowMs': serverNowMs,
        'history': histValues,
        'myBets': [null, null],
        // Tells JS the user joined mid-flight so it can show a graceful state.
        'midRoundJoin': phase == 'flying',
      };
      if (phase == 'crashed') {
        roundPayload['crashMultiplier'] = crashMultiplier;
      }

      _post('INIT_GAME', {
        'balance': balance,
        'locale': isArabic ? 'ar' : 'en',
        'sound': true,
        'serverSynced': true,
        'round': roundPayload,
      });

      if (_roundId != null) _sendBetFeed(_roundId!);
    } catch (e, st) {
      debugPrint('[RocketCrash] init error: $e\n$st');
      _serverRoundReady = false;
      if (!mounted) return;
      _post('INIT_GAME', {
        'balance': 0,
        'locale': isArabic ? 'ar' : 'en',
        'sound': true,
        // Keep serverSynced true even on error so the WebView shows a syncing
        // state and never falls back to the local simulation. The
        // reconciliation poll (started below) will deliver a real round.
        'serverSynced': true,
        'error': 'wallet_error',
      });
    } finally {
      _isInitializing = false;
      if (mounted) setState(() {});
      // Always run the reconciliation poll, even after an init error, so the
      // client keeps trying to converge on the live server round.
      _startReconcilePoll();
    }
  }

  // -- Realtime --------------------------------------------------------------

  // Estimated server time in ms - used for animation timing.
  double get _serverNowMs =>
      DateTime.now().millisecondsSinceEpoch + _serverTimeOffsetMs;

  void _refreshRoundFromServer(String reason) {
    if (!mounted) return;
    if (SupabaseService.requiredClient.auth.currentUser == null) return;

    debugPrint('[RocketCrash] refreshing round from server reason=$reason');
    _roundRefreshDebounce?.cancel();
    _roundRefreshDebounce = Timer(
      const Duration(milliseconds: 800),
      () => _runRoundRefresh(reason),
    );
  }

  // Fetches the live round and forwards it to the WebView. If a refresh is
  // already running, the request is remembered (not dropped) and re-run once
  // the current one finishes, so the latest server state is never missed.
  Future<void> _runRoundRefresh(String reason) async {
    if (!mounted) return;
    if (_roundRefreshInFlight) {
      _refreshPending = true;
      _refreshPendingReason = reason;
      return;
    }
    _roundRefreshInFlight = true;
    try {
      final round = await _service.getOrCreateRocketRound();
      if (!mounted) return;

      final roundId = round['round_id']?.toString();
      final phase = round['status']?.toString() ?? 'betting';
      final bettingEndsAtMs = _parseTimestampMs(round['betting_ends_at']);
      final flightStartsAtMs = _parseTimestampMs(round['flight_starts_at']);
      final serverNowMs = _toDouble(round['server_now']);
      final roundNumber = _parseInt(round['round_number']);
      final crashMultiplier = _toDouble(round['crash_multiplier']);

      if (serverNowMs > 0) {
        _serverTimeOffsetMs =
            serverNowMs - DateTime.now().millisecondsSinceEpoch;
      }

      final prevRoundNumber = _currentRoundNumber;
      _roundId = roundId;
      _currentRoundNumber = roundNumber;
      _serverRoundReady =
          roundId != null && roundNumber > 0 && phase != 'crashed';

      setState(() {
        _serverRoundReady =
            roundId != null && roundNumber > 0 && phase != 'crashed';
      });

      debugPrint(
        '[RocketCrash] refreshed round phase=$phase roundId=$roundId '
        'rNum=$roundNumber reason=$reason',
      );

      final payload = <String, dynamic>{
        'roundId': roundId,
        'roundNumber': roundNumber,
        'phase': phase,
        'serverSynced': true,
        'bettingEndsAtMs': bettingEndsAtMs,
        'flightStartsAtMs': flightStartsAtMs,
        'serverNowMs': serverNowMs > 0 ? serverNowMs : _serverNowMs,
        'midRoundJoin': phase == 'flying',
      };
      if (phase == 'crashed') {
        payload['crashMultiplier'] = crashMultiplier;
      }

      _post('SET_ROUND_STATE', payload);
      debugPrint('[RocketCrash] -> SET_ROUND_STATE refreshed');

      if (roundId != null) _sendBetFeed(roundId);

      // Refresh the last-20 history whenever a round just crashed or a newer
      // round has appeared (the previous round therefore crashed). This is the
      // fallback for the realtime 'crashed' branch when realtime is unreliable.
      if (phase == 'crashed' ||
          (prevRoundNumber > 0 && roundNumber > prevRoundNumber)) {
        _refreshHistory();
      }

      // Safety settlement: if the round is still 'flying' but, by the server's
      // own crash point and flight start time, it should already have crashed
      // (e.g. cron settlement stalled - DB showed crash_multiplier 1.05 stuck
      // flying for 13s), drive the existing settle RPC once. The server stays
      // authoritative: it computes payouts; we only ask it to settle.
      if (phase == 'flying' &&
          roundId != null &&
          crashMultiplier > 0 &&
          flightStartsAtMs > 0) {
        final nowMs = serverNowMs > 0 ? serverNowMs : _serverNowMs;
        final elapsedSec = (nowMs - flightStartsAtMs) / 1000.0;
        if (elapsedSec > 0) {
          final currentMult = math.exp(0.055 * elapsedSec);
          if (currentMult >= crashMultiplier) {
            debugPrint(
              '[RocketCrash] stuck flying detected round=$roundId '
              'currentMult=${currentMult.toStringAsFixed(2)} '
              'crashMult=${crashMultiplier.toStringAsFixed(2)} - settling',
            );
            _trySettleStuckRound(roundId);
          }
        }
      }
    } catch (e, st) {
      debugPrint('[RocketCrash] refreshRound error reason=$reason: $e\n$st');
    } finally {
      _roundRefreshInFlight = false;
      // Re-run if another refresh was requested while this one was in flight.
      if (_refreshPending) {
        _refreshPending = false;
        final pendingReason = _refreshPendingReason ?? reason;
        _refreshPendingReason = null;
        _refreshRoundFromServer(pendingReason);
      }
    }
  }

  // Drives the betting -> flying transition. The JS sends REQUEST_START_FLIGHT
  // when the betting countdown ends; we call the existing server RPC (the
  // server commits the crash point and flight start time - we never decide it).
  Future<void> _handleStartFlight(Map<String, dynamic> payload) async {
    final roundId = payload['roundId']?.toString() ?? _roundId;
    if (roundId == null || roundId.isEmpty) {
      debugPrint('[RocketCrash] start flight rejected: no roundId');
      return;
    }
    try {
      final result = await _service.startRocketFlight(roundId);
      if (!mounted) return;

      final flightStartsAtMs = _parseTimestampMs(result['flight_starts_at']);
      final serverNowMs = _toDouble(result['server_now']);
      if (serverNowMs > 0) {
        _serverTimeOffsetMs =
            serverNowMs - DateTime.now().millisecondsSinceEpoch;
      }

      _roundId = roundId;
      _serverRoundReady = true;
      setState(() => _serverRoundReady = true);

      debugPrint(
        '[RocketCrash] start flight ok round=$roundId fsMs=$flightStartsAtMs',
      );

      // Forward the flying state to JS. crash_multiplier is intentionally NOT
      // sent: the JS must never know the crash point before the round crashes
      // (server authority / no JS-decided payouts).
      _post('SET_ROUND_STATE', {
        'roundId': roundId,
        'roundNumber': _currentRoundNumber,
        'phase': 'flying',
        'serverSynced': true,
        'bettingEndsAtMs': null,
        'flightStartsAtMs': flightStartsAtMs > 0 ? flightStartsAtMs : null,
        'serverNowMs': serverNowMs > 0 ? serverNowMs : _serverNowMs,
        'midRoundJoin': false,
      });

      _sendBetFeed(roundId);
      // Reconcile against the server shortly after, in case the round had
      // already advanced (e.g. another client started it first).
      _refreshRoundFromServer('start_flight_after_rpc');
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] start flight error round=$roundId: $e');
      _refreshRoundFromServer('start_flight_error');
    }
  }

  // Drives settlement of a round via the existing server RPC. The server
  // auto-cashes qualifying bets, marks the rest lost, and flips the round to
  // 'crashed'. We never compute payouts here.
  Future<void> _handleSettleRound(Map<String, dynamic> payload) async {
    final roundId = payload['roundId']?.toString() ?? _roundId;
    if (roundId == null || roundId.isEmpty) return;
    if (_settleInFlightRoundIds.contains(roundId)) return;
    _settleInFlightRoundIds.add(roundId);
    debugPrint('[RocketCrash] settle requested round=$roundId');
    try {
      await _service.settleRocketRound(roundId);
    } catch (e) {
      debugPrint('[RocketCrash] settle round error round=$roundId: $e');
    } finally {
      _settleInFlightRoundIds.remove(roundId);
      _refreshRoundFromServer('settle_round_after_rpc');
    }
  }

  // Settles a round that the client has determined is overdue (still flying
  // past its crash point). Guarded so the settle RPC is not spammed.
  Future<void> _trySettleStuckRound(String roundId) async {
    if (_settleInFlightRoundIds.contains(roundId)) return;
    _settleInFlightRoundIds.add(roundId);
    debugPrint('[RocketCrash] settling stuck flying round=$roundId');
    try {
      await _service.settleRocketRound(roundId);
    } catch (e) {
      debugPrint('[RocketCrash] settle stuck round error round=$roundId: $e');
    } finally {
      _settleInFlightRoundIds.remove(roundId);
      _refreshRoundFromServer('settle_stuck_flying');
    }
  }

  // Starts (or restarts) the periodic reconciliation poll. Cheap insurance
  // against unreliable realtime: every 8 s the client re-reads the live round
  // and converges the WebView to it, so it can never get stuck on
  // LAUNCHING/FLYING if a realtime phase-transition event is missed.
  void _startReconcilePoll() {
    _reconcilePoll?.cancel();
    _reconcilePoll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) {
        _reconcilePoll?.cancel();
        return;
      }
      _refreshRoundFromServer('poll');
    });
  }

  // Whole-table subscription - follows new betting rounds (INSERT) and phase
  // transitions (UPDATE) without per-round resubscription.
  // Caller must call _disposeRoundChannel() before calling this.
  void _subscribeToRounds() {
    _roundChannel = SupabaseService.requiredClient
        .channel('rocket_crash_global_rounds')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rocket_crash_global_rounds',
          callback: _onAnyRoundChange,
        )
        .subscribe((status, [err]) {
          debugPrint('[RocketCrash] realtime $status ${err ?? ''}');
        });
  }

  void _onAnyRoundChange(PostgresChangePayload payload) {
    if (!mounted) return;

    if (payload.newRecord.isEmpty && payload.oldRecord.isEmpty) {
      if (!_loggedEmptyRealtimePayload) {
        debugPrint(
          '[RocketCrash] empty realtime payload, refreshing from server',
        );
        _loggedEmptyRealtimePayload = true;
      }
      _refreshRoundFromServer('empty_realtime_payload');
      return;
    }

    final rec = payload.newRecord.isNotEmpty
        ? payload.newRecord
        : payload.oldRecord;

    final status = rec['status']?.toString();
    final rNum = _parseInt(rec['round_number']);
    final rowId = rec['id']?.toString();

    debugPrint(
      '[RocketCrash] round change status=$status rNum=$rNum '
      'id=$rowId newKeys=${payload.newRecord.keys.toList()} '
      'oldKeys=${payload.oldRecord.keys.toList()}',
    );

    if (status == null || status.isEmpty || rNum <= 0 || rowId == null) {
      debugPrint('[RocketCrash] malformed realtime payload, refreshing');
      _refreshRoundFromServer('malformed_realtime_payload');
      return;
    }

    if (status == 'betting') {
      if (rNum <= _currentRoundNumber) return;

      final bettingEndsAtMs = _parseTimestampMs(rec['betting_ends_at']);

      _roundId = rowId;
      _currentRoundNumber = rNum;
      _serverRoundReady = true;
      _settledBetIds.clear();

      setState(() {
        _serverRoundReady = true;
      });

      _post('SET_ROUND_STATE', {
        'roundId': rowId,
        'roundNumber': rNum,
        'phase': 'betting',
        'serverSynced': true,
        'bettingEndsAtMs': bettingEndsAtMs,
        'flightStartsAtMs': null,
        'serverNowMs': _serverNowMs,
        'midRoundJoin': false,
      });

      _sendBetFeed(rowId);
    } else if (status == 'flying') {
      if (rNum < _currentRoundNumber) return;

      final fsMs = _parseTimestampMs(rec['flight_starts_at']);
      final bettingEndsAtMs = _parseTimestampMs(rec['betting_ends_at']);

      _roundId = rowId;
      _currentRoundNumber = rNum;
      _serverRoundReady = true;

      setState(() {
        _serverRoundReady = true;
      });

      _post('SET_ROUND_STATE', {
        'roundId': rowId,
        'roundNumber': rNum,
        'phase': 'flying',
        'serverSynced': true,
        'bettingEndsAtMs': bettingEndsAtMs,
        'flightStartsAtMs': fsMs > 0 ? fsMs : null,
        'serverNowMs': _serverNowMs,
        'midRoundJoin': true,
      });

      _sendBetFeed(rowId);
    } else if (status == 'crashed') {
      if (rNum < _currentRoundNumber) return;

      final cm = _toDouble(rec['crash_multiplier']);
      final bettingEndsAtMs = _parseTimestampMs(rec['betting_ends_at']);
      final fsMs = _parseTimestampMs(rec['flight_starts_at']);

      _roundId = rowId;
      _currentRoundNumber = rNum;
      _serverRoundReady = false;

      setState(() {
        _serverRoundReady = false;
      });

      _post('SET_ROUND_STATE', {
        'roundId': rowId,
        'roundNumber': rNum,
        'phase': 'crashed',
        'serverSynced': true,
        'bettingEndsAtMs': bettingEndsAtMs,
        'flightStartsAtMs': fsMs > 0 ? fsMs : null,
        'serverNowMs': _serverNowMs,
        'midRoundJoin': false,
        'crashMultiplier': cm,
      });

      _refreshHistory();
    }
  }

  // Debounced: fetches server history shortly after a crashed event. Kept short
  // (800 ms) so the authoritative last-20 strip is not stale, while still
  // coalescing duplicate crashed events into a single fetch.
  void _refreshHistory() {
    _historyDebounce?.cancel();
    _historyDebounce = Timer(const Duration(milliseconds: 800), () async {
      try {
        final history = await _service.getRocketResults();
        if (!mounted) return;
        final histValues = history
            .map((h) => _toDouble(h['crash_multiplier']))
            .where((v) => v > 0)
            .toList();
        _post('HISTORY_UPDATE', {'history': histValues});
      } catch (e) {
        debugPrint('[RocketCrash] refreshHistory error: $e');
      }
    });
  }

  // Throttled: at most one RPC call per roundId per 2 s.
  Future<void> _sendBetFeed(String roundId) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (roundId == _lastBetFeedRoundId && nowMs - _lastBetFeedMs < 2000) {
      return;
    }
    _lastBetFeedRoundId = roundId;
    _lastBetFeedMs = nowMs;

    try {
      final bets = await _service.getRocketRoundBets(roundId);
      if (!mounted) return;
      _post('BETS_UPDATE', {
        'bets': bets
            .map(
              (b) => {
                'displayName': b['display_name'],
                'betAmount': b['bet_amount'],
                'autoCashoutMultiplier': b['auto_cashout_multiplier'],
                'cashoutMultiplier': b['cashout_multiplier'],
                'winAmount': b['win_amount'],
                'status': b['status'],
                'isOwn': b['is_own'] ?? false,
              },
            )
            .toList(),
      });
    } catch (e) {
      debugPrint('[RocketCrash] betFeed error: $e');
    }
  }

  // -- Wallet handlers -------------------------------------------------------

  Future<void> _handlePlaceBet(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final amount = _parseInt(payload['amount']);
    final roundId = payload['roundId']?.toString() ?? _roundId;
    final autoCashout = payload['autoCashoutMultiplier'] is num
        ? (payload['autoCashoutMultiplier'] as num).toDouble()
        : null;

    if (!_serverRoundReady || roundId == null) {
      _post('BET_REJECTED', {
        'slotIndex': slotIndex,
        'code': 'server_not_ready',
        'userMessage': _friendlyCode('server_not_ready'),
      });
      return;
    }
    if (amount <= 0) {
      _post('BET_REJECTED', {
        'slotIndex': slotIndex,
        'code': 'invalid_amount',
        'userMessage': _friendlyCode('invalid_amount'),
      });
      return;
    }

    try {
      final result = await _service.placeRocketBet(
        roundId,
        amount,
        autoCashout,
      );
      if (!mounted) return;
      final betId = result['bet_id']?.toString();
      final newBalance = _parseInt(result['new_balance']);

      if (betId == null || betId.isEmpty) {
        _post('BET_REJECTED', {
          'slotIndex': slotIndex,
          'code': 'no_bet_id',
          'userMessage': _friendlyCode('network_error'),
        });
        return;
      }

      HapticFeedback.lightImpact();
      debugPrint('[RocketCrash] bet placed betId=$betId amount=$amount');
      _post('BET_ACCEPTED', {
        'slotIndex': slotIndex,
        'betId': betId,
        'roundId': roundId,
        'amount': amount,
        'newBalance': newBalance,
      });

      _sendBetFeed(roundId);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] placeBet error: $e');
      final code = _mapError('$e');
      _post('BET_REJECTED', {
        'slotIndex': slotIndex,
        'code': code,
        'userMessage': _friendlyCode(code),
      });
    }
  }

  Future<void> _handleBetDebit(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    // Reject legacy debit path once the server round is active.
    if (_serverRoundReady) {
      _post('BET_REJECTED', {
        'slotIndex': slotIndex,
        'code': 'use_place_bet',
        'userMessage': _friendlyCode('server_not_ready'),
      });
      return;
    }
    final amount = _parseInt(payload['amount']);
    if (amount <= 0) {
      _post('BET_REJECTED', {
        'slotIndex': slotIndex,
        'code': 'invalid_amount',
        'userMessage': _friendlyCode('invalid_amount'),
      });
      return;
    }
    try {
      final result = await _service.armBet(amount, slotIndex: slotIndex);
      if (!mounted) return;
      final betId = result['bet_id']?.toString();
      final newBalance = _parseInt(result['new_balance']);
      if (betId == null || betId.isEmpty) {
        _post('BET_REJECTED', {
          'slotIndex': slotIndex,
          'code': 'no_bet_id',
          'userMessage': _friendlyCode('network_error'),
        });
        return;
      }
      HapticFeedback.lightImpact();
      _post('BET_ACCEPTED', {
        'slotIndex': slotIndex,
        'betId': betId,
        'amount': amount,
        'newBalance': newBalance,
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] armBet error: $e');
      final code = _mapError('$e');
      _post('BET_REJECTED', {
        'slotIndex': slotIndex,
        'code': code,
        'userMessage': _friendlyCode(code),
      });
    }
  }

  Future<void> _handleBetRefund(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final betId = payload['betId']?.toString();

    if (!_serverRoundReady) {
      _post('REFUND_REJECTED', {
        'slotIndex': slotIndex,
        'code': 'server_not_ready',
        'userMessage': _friendlyCode('server_not_ready'),
      });
      return;
    }
    if (betId == null || betId.isEmpty) {
      _post('REFUND_REJECTED', {
        'slotIndex': slotIndex,
        'code': 'no_bet_id',
        'userMessage': _friendlyCode('network_error'),
      });
      return;
    }
    if (_settledBetIds.contains(betId)) {
      _post('REFUND_REJECTED', {
        'slotIndex': slotIndex,
        'code': 'already_settled',
        'userMessage': _friendlyCode('already_settled'),
      });
      return;
    }

    // Guard BEFORE the await. betId stays in the set even on error so that a
    // network timeout (where the server may have already processed the request)
    // cannot open a duplicate refund window.
    _settledBetIds.add(betId);

    try {
      final result = await _service.refundBet(betId);
      if (!mounted) return;
      final newBalance = _parseInt(result['new_balance']);
      final refundedAmount = _parseInt(result['refunded_amount']);
      _post('REFUND_ACCEPTED', {
        'slotIndex': slotIndex,
        'betId': betId,
        'refundedAmount': refundedAmount,
        'newBalance': newBalance,
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] refund error: $e');
      final code = _mapError('$e');
      _post('REFUND_REJECTED', {
        'slotIndex': slotIndex,
        'code': code,
        'userMessage': _friendlyCode(code),
      });
    }
  }

  Future<void> _handleCashout(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final betId = payload['betId']?.toString();

    debugPrint('[RocketCashout] request slot=$slotIndex betId=$betId');

    // Server round must be ready. The JS-supplied multiplier is NEVER used.
    if (!_serverRoundReady || _roundId == null) {
      debugPrint('[RocketCashout] rejected: server_not_ready slot=$slotIndex');
      _post('CASHOUT_REJECTED', {
        'slotIndex': slotIndex,
        'code': 'server_not_ready',
        'userMessage': _friendlyCode('server_not_ready'),
      });
      return;
    }
    if (betId == null || betId.isEmpty) {
      debugPrint('[RocketCashout] rejected: no_bet_id slot=$slotIndex');
      _post('CASHOUT_REJECTED', {
        'slotIndex': slotIndex,
        'code': 'no_bet_id',
        'userMessage': _friendlyCode('network_error'),
      });
      return;
    }
    if (_settledBetIds.contains(betId)) {
      debugPrint('[RocketCashout] rejected: already_settled betId=$betId');
      _post('CASHOUT_REJECTED', {
        'slotIndex': slotIndex,
        'code': 'already_settled',
        'userMessage': _friendlyCode('already_settled'),
      });
      return;
    }

    // Guard BEFORE the await. betId stays in the set even on error so that a
    // network timeout cannot open a duplicate cashout window.
    _settledBetIds.add(betId);

    try {
      // Server always calculates the multiplier; JS payload value is ignored.
      debugPrint('[RocketCashout] calling server RPC betId=$betId');
      final result = await _service.cashOutRocketBet(betId);
      if (!mounted) return;

      final status = result['status']?.toString();
      if (status == 'lost') {
        debugPrint('[RocketCashout] rejected: round_crashed betId=$betId');
        _post('CASHOUT_REJECTED', {
          'slotIndex': slotIndex,
          'code': 'round_crashed',
          'userMessage': _friendlyCode('round_crashed'),
        });
        return;
      }

      final winAmount = _parseInt(result['win_amount']);
      final newBalance = _parseInt(result['new_balance']);
      // Use only server-returned multiplier.
      final actualMult = _parseDouble(
        result['cashout_multiplier'] ?? result['multiplier'] ?? 1.0,
      );

      HapticFeedback.mediumImpact();
      debugPrint(
        '[RocketCashout] accepted slot=$slotIndex x$actualMult win=$winAmount balance=$newBalance',
      );
      _post('CASHOUT_ACCEPTED', {
        'slotIndex': slotIndex,
        'betId': betId,
        'winAmount': winAmount,
        'multiplier': actualMult,
        'newBalance': newBalance,
      });
      _refreshBalance();
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCashout] error slot=$slotIndex: $e');
      final code = _mapError('$e');
      _post('CASHOUT_REJECTED', {
        'slotIndex': slotIndex,
        'code': code,
        'userMessage': _friendlyCode(code),
      });
    }
  }

  void _handleBetLost(Map<String, dynamic> payload) {
    final betId = payload['betId']?.toString();
    if (betId == null || betId.isEmpty) return;
    if (_settledBetIds.contains(betId)) return;
    _settledBetIds.add(betId);
    // Global rounds: server settle already marks lost. Legacy fallback only.
    if (_roundId == null) {
      final crashMult = _parseDouble(payload['crashMultiplier'] ?? 1.0);
      _service.markBetLost(betId, crashMult).catchError((e) {
        debugPrint('[RocketCrash] markBetLost error: $e');
      });
    }
  }

  Future<void> _refreshBalance() {
    final inFlight = _balanceRefreshFuture;
    if (inFlight != null) return inFlight;

    final refresh = _runBalanceRefresh().whenComplete(() {
      _balanceRefreshFuture = null;
    });
    _balanceRefreshFuture = refresh;
    return refresh;
  }

  Future<void> _runBalanceRefresh() async {
    try {
      final balance = await _service.fetchBalance();
      if (!mounted) return;
      debugPrint('[RocketCrash] wallet updated coins=$balance');
      _post('WALLET_UPDATED', {'balance': balance});
    } catch (e) {
      debugPrint('[RocketCrash] refreshBalance error: $e');
    }
  }

  // -- Flutter -> Web --------------------------------------------------------

  void _post(String type, Map<String, dynamic> payload) {
    if (!mounted) return;
    final message = jsonEncode({'type': type, 'payload': payload});
    if (_dedupePostTypes.contains(type) &&
        _lastPostedMessages[type] == message) {
      debugPrint('[RocketCrash] -> $type skipped duplicate');
      return;
    }
    if (_dedupePostTypes.contains(type)) {
      _lastPostedMessages[type] = message;
    }

    debugPrint('[RocketCrash] -> $type');
    final encoded = jsonEncode(message);
    _controller.runJavaScript(
      'window.onSroodMessage && window.onSroodMessage(JSON.parse($encoded));',
    );
  }

  // -- Helpers ---------------------------------------------------------------

  int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double _parseDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 1.0;
    return 1.0;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  // Parses a server timestamp field to milliseconds since epoch.
  // Accepts: int/double ms values, ISO-8601 strings, numeric strings.
  // Returns 0 if the value is null or cannot be parsed.
  double _parseTimestampMs(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v.toDouble();
    if (v is double) return v;
    if (v is String) {
      final asNum = double.tryParse(v);
      if (asNum != null) return asNum;
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.toUtc().millisecondsSinceEpoch.toDouble();
    }
    return 0;
  }

  String _mapError(String e) {
    if (e.contains('insufficient_coins')) return 'insufficient_coins';
    if (e.contains('not_authenticated')) return 'not_authenticated';
    if (e.contains('already_settled')) return 'already_settled';
    if (e.contains('bet_not_found')) return 'bet_not_found';
    if (e.contains('not_refundable')) return 'not_refundable';
    if (e.contains('round_not_found')) return 'round_not_found';
    if (e.contains('betting_closed')) return 'betting_closed';
    if (e.contains('game_disabled')) return 'game_disabled';
    if (e.contains('round_not_flying')) return 'round_not_flying';
    if (e.contains('round_already_crashed')) return 'round_already_crashed';
    if (e.contains('invalid_auto_cashout')) return 'invalid_auto_cashout';
    return 'network_error';
  }

  // User-facing message for a given error code, respecting locale.
  String _friendlyCode(String code) {
    final ar = widget.isArabic;
    switch (code) {
      case 'insufficient_coins':
        return ar ? 'رصيد غير كافٍ' : 'Insufficient coins';
      case 'not_authenticated':
        return ar ? 'يرجى تسجيل الدخول مجدداً' : 'Please sign in again';
      case 'already_settled':
        return ar ? 'تمت العملية مسبقاً' : 'Already processed';
      case 'bet_not_found':
        return ar ? 'الرهان غير موجود' : 'Bet not found';
      case 'not_refundable':
        return ar ? 'لا يمكن استرداد هذا الرهان' : 'Bet is not refundable';
      case 'round_not_found':
        return ar ? 'الجولة غير موجودة' : 'Round not found';
      case 'betting_closed':
        return ar ? 'انتهى وقت الرهان' : 'Betting is closed';
      case 'game_disabled':
        return ar ? 'اللعبة غير متاحة حالياً' : 'Game is currently unavailable';
      case 'round_not_flying':
        return ar ? 'الصاروخ لم ينطلق بعد' : 'Round is not in flight';
      case 'round_already_crashed':
        return ar ? 'انهار الصاروخ بالفعل' : 'Rocket already crashed';
      case 'invalid_auto_cashout':
        return ar
            ? 'مضاعف السحب التلقائي غير صالح'
            : 'Invalid auto cashout multiplier';
      case 'round_crashed':
        return ar ? 'انهار الصاروخ قبل السحب' : 'Rocket crashed before cashout';
      case 'server_not_ready':
        return ar
            ? 'جاري المزامنة، يرجى الانتظار...'
            : 'Syncing with server...';
      case 'invalid_amount':
        return ar ? 'مبلغ الرهان غير صالح' : 'Invalid bet amount';
      default:
        return ar
            ? 'حدث خطأ، يرجى المحاولة مجدداً'
            : 'Something went wrong, please retry';
    }
  }

  // -- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF020818),
        body: SafeArea(
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              WebViewWidget(controller: _controller),
              // Splash stays only until the bridge is alive / first data arrives
              // (or the timeout swaps in the error/retry state).
              if (!_bootResolved && !_pageError) _buildLoading(),
              if (_pageError) _buildError(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: const Color(0xFF020818),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ðŸš€', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 20),
            const Text(
              'Rocket Crash',
              style: TextStyle(
                color: Color(0xFF00D4FF),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: Color(0xFF00D4FF),
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.isArabic
                  ? 'جاري الاتصال بالجولة الحية...'
                  : 'Connecting to live round...',
              style: TextStyle(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      color: const Color(0xFF020818),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1230),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF1A4AFF).withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A4AFF).withValues(alpha: 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ðŸš€', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 10),
                const Text(
                  'Rocket Crash',
                  style: TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _friendlyWebError(_pageErrorMsg),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A6FFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _pageError = false;
                        _pageErrorMsg = null;
                        _bootResolved = false;
                      });
                      _startBootTimeout();
                      _controller.loadFlutterAsset(
                        'assets/games/rocket_crash/index.html',
                      );
                    },
                    child: Text(
                      widget.isArabic ? 'إعادة المحاولة' : 'Try again',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Converts a raw WebView error description to a user-friendly message.
  String _friendlyWebError(String? raw) {
    if (raw == null || raw.isEmpty) {
      return widget.isArabic
          ? 'تعذر الاتصال باللعبة. يرجى التحقق من اتصالك بالإنترنت.'
          : 'Could not connect to the game. Check your internet connection.';
    }
    if (raw == 'sync_timeout') {
      return widget.isArabic
          ? 'تعذّر مزامنة الجولة الحية. يرجى المحاولة مجدداً.'
          : 'Unable to sync live round. Please try again.';
    }
    final lower = raw.toLowerCase();
    if (lower.contains('net::err_internet') ||
        lower.contains('net::err_name') ||
        lower.contains('offline')) {
      return widget.isArabic
          ? 'لا يوجد اتصال بالإنترنت.'
          : 'No internet connection.';
    }
    if (lower.contains('ssl') || lower.contains('certificate')) {
      return widget.isArabic
          ? 'خطأ في شهادة الأمان.'
          : 'Security certificate error.';
    }
    return widget.isArabic
        ? 'تعذر تحميل اللعبة. يرجى المحاولة مجدداً.'
        : 'Failed to load the game. Please try again.';
  }
}
