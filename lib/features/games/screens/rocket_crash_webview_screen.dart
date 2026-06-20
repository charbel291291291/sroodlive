import 'dart:async';
import 'dart:convert';

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
  late final WebViewController _controller;
  final _service = const CrashGameService();

  bool _pageLoaded = false;
  bool _pageError  = false;
  String? _pageErrorMsg;

  // True while _initGame() is awaiting RPCs; prevents concurrent re-entry.
  bool _isInitializing = false;

  // True once _roundId and _currentRoundNumber have been assigned from the
  // server. Financial actions (bet/refund/cashout) are rejected until true.
  bool _serverRoundReady = false;

  // Realtime channel health - drives the LIVE dot in the status bar.
  bool _realtimeConnected = false;

  // Round display state - drives the status bar overlay.
  int    _displayRoundNumber = 0;
  String _displayPhase       = 'betting';

  // Bet idempotency guard. BetIds are added BEFORE the financial RPC awaits
  // and are NEVER removed on error, so a network timeout cannot open a
  // double-cashout/refund window.
  final Set<String> _settledBetIds = {};

  // Global round state - client is a pure observer; server drives lifecycle.
  String? _roundId;
  int _currentRoundNumber = 0;
  RealtimeChannel? _roundChannel;

  // Server-local clock offset (serverNowMs - localNowMs), set on every
  // successful init. Used so realtime callbacks can send an accurate
  // serverNowMs without trusting the local clock alone.
  double _serverTimeOffsetMs = 0;

  // History for the top results band.
  List<double> _recentResults = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF020818),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF020818))
      ..addJavaScriptChannel(
        'SroodBridge',
        onMessageReceived: (msg) => _onWebMessage(msg.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (!mounted) return;
          setState(() => _pageLoaded = true);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == false) return;
          if (!mounted) return;
          setState(() {
            _pageLoaded   = true;
            _pageError    = true;
            _pageErrorMsg = e.description;
          });
        },
      ))
      ..loadFlutterAsset('assets/games/rocket_crash/index.html');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[RocketCrash] app resumed - refreshing round');
      _initGame();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeRoundChannel();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    ));
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
    final type    = msg['type']    as String?               ?? '';
    final payload = msg['payload'] as Map<String, dynamic>? ?? {};

    debugPrint('[RocketCrash] <- $type');

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
        break; // no-op: backend (pg_cron) drives flight start
      case 'REQUEST_SETTLE_ROUND':
        break; // no-op: backend (pg_cron) drives settlement
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
    if (SupabaseService.requiredClient.auth.currentUser == null) return;

    // Set directly for the security guard, then setState for UI.
    _isInitializing   = true;
    _serverRoundReady = false;
    if (mounted) setState(() { _isInitializing = true; _serverRoundReady = false; });

    try {
      final balance = await _service.fetchBalance();
      final round   = await _service.getOrCreateRocketRound();
      final history = await _service.getRocketResults();

      _roundId = round['round_id']?.toString();
      final phase            = round['status']?.toString() ?? 'betting';
      final bettingEndsAtMs  = _parseTimestampMs(round['betting_ends_at']);
      final flightStartsAtMs = _parseTimestampMs(round['flight_starts_at']);
      final serverNowMs      = _toDouble(round['server_now']);
      final roundNumber      = _parseInt(round['round_number']);

      if (serverNowMs > 0) {
        _serverTimeOffsetMs = serverNowMs - DateTime.now().millisecondsSinceEpoch;
      }
      _currentRoundNumber = roundNumber;

      // Server round is now valid; financial actions are unblocked.
      _serverRoundReady = _roundId != null && roundNumber > 0;

      final histValues = history
          .map((h) => _toDouble(h['crash_multiplier']))
          .where((v) => v > 0)
          .toList();

      // Update all UI-driving state in one batch.
      if (mounted) {
        setState(() {
          _serverRoundReady   = _roundId != null && roundNumber > 0;
          _displayRoundNumber = roundNumber;
          _displayPhase       = phase;
          _recentResults      = histValues.take(15).toList();
        });
      }

      // Dispose any previous channel before creating a new subscription.
      _disposeRoundChannel();
      _subscribeToRounds();

      debugPrint('[RocketCrash] round loaded roundId=$_roundId phase=$phase '
          'balance=$balance serverOffset=${_serverTimeOffsetMs.round()}ms '
          'histCount=${histValues.length}');

      _post('INIT_GAME', {
        'balance'      : balance,
        'locale'       : isArabic ? 'ar' : 'en',
        'sound'        : true,
        'serverSynced' : true,
        'round'        : {
          'roundId'         : _roundId,
          'roundNumber'     : roundNumber,
          'phase'           : phase,
          'bettingEndsAtMs' : bettingEndsAtMs,
          'flightStartsAtMs': flightStartsAtMs,
          // Never expose crash_multiplier before the round has crashed.
          'crashMultiplier' : null,
          'serverNowMs'     : serverNowMs,
          'history'         : histValues,
          'myBets'          : [null, null],
          // Tells JS the user joined mid-flight so it can show a graceful state.
          'midRoundJoin'    : phase == 'flying',
        },
      });

      if (_roundId != null) _sendBetFeed(_roundId!);

    } catch (e, st) {
      debugPrint('[RocketCrash] init error: $e\n$st');
      _serverRoundReady = false;
      if (mounted) setState(() => _serverRoundReady = false);
      if (!mounted) return;
      _post('INIT_GAME', {
        'balance': 0,
        'locale' : isArabic ? 'ar' : 'en',
        'sound'  : true,
        'error'  : 'wallet_error',
      });
    } finally {
      _isInitializing = false;
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  // -- Realtime --------------------------------------------------------------

  // Estimated server time in ms - used for animation timing.
  double get _serverNowMs =>
      DateTime.now().millisecondsSinceEpoch + _serverTimeOffsetMs;

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
          final connected = status == RealtimeSubscribeStatus.subscribed;
          if (mounted) setState(() => _realtimeConnected = connected);
        });
  }

  void _onAnyRoundChange(PostgresChangePayload payload) {
    if (!mounted) return;
    final rec    = payload.newRecord;
    final status = rec['status']?.toString();
    final rNum   = _parseInt(rec['round_number']);
    debugPrint('[RocketCrash] round change status=$status rNum=$rNum');

    if (status == 'betting') {
      // Only adopt strictly newer rounds. Same-round UPDATE events are ignored
      // to prevent spurious _settledBetIds.clear() during an active round.
      if (rNum <= _currentRoundNumber) return;
      final newId           = rec['id']?.toString();
      final bettingEndsAtMs = _parseTimestampMs(rec['betting_ends_at']);
      _roundId            = newId;
      _currentRoundNumber = rNum;
      _serverRoundReady   = newId != null;
      _settledBetIds.clear();
      setState(() {
        _serverRoundReady   = newId != null;
        _displayRoundNumber = rNum;
        _displayPhase       = 'betting';
      });
      _post('SET_ROUND_STATE', {
        'roundId'        : newId,
        'roundNumber'    : rNum,
        'phase'          : 'betting',
        'bettingEndsAtMs': bettingEndsAtMs,
        'serverNowMs'    : _serverNowMs,
      });
      if (newId != null) _sendBetFeed(newId);

    } else if (status == 'flying') {
      // Allow same-round forward transition; reject stale old-round events.
      if (rNum < _currentRoundNumber) return;
      final fsMs = _parseTimestampMs(rec['flight_starts_at']);
      setState(() => _displayPhase = 'flying');
      // Never forward crash_multiplier during flight - reveal only on crashed.
      _post('SET_ROUND_STATE', {
        'roundId'         : rec['id'],
        'phase'           : 'flying',
        'flightStartsAtMs': fsMs > 0 ? fsMs : null,
        'crashMultiplier' : null,
        'serverNowMs'     : _serverNowMs,
      });

    } else if (status == 'crashed') {
      // Allow same-round forward transition; reject stale old-round events.
      if (rNum < _currentRoundNumber) return;
      // Backend has revealed the crash point - safe to forward now.
      final cm = _toDouble(rec['crash_multiplier']);
      setState(() => _displayPhase = 'crashed');
      _post('SET_ROUND_STATE', {
        'roundId'        : rec['id'],
        'phase'          : 'crashed',
        'crashMultiplier': cm,
      });
      _refreshHistory();
    }
  }

  Future<void> _refreshHistory() async {
    try {
      final history = await _service.getRocketResults();
      if (!mounted) return;
      final histValues = history
          .map((h) => _toDouble(h['crash_multiplier']))
          .where((v) => v > 0)
          .toList();
      _post('HISTORY_UPDATE', {'history': histValues});
      setState(() => _recentResults = histValues.take(15).toList());
    } catch (e) {
      debugPrint('[RocketCrash] refreshHistory error: $e');
    }
  }

  Future<void> _sendBetFeed(String roundId) async {
    try {
      final bets = await _service.getRocketRoundBets(roundId);
      if (!mounted) return;
      _post('BETS_UPDATE', {
        'bets': bets.map((b) => {
          'displayName'           : b['display_name'],
          'betAmount'             : b['bet_amount'],
          'autoCashoutMultiplier' : b['auto_cashout_multiplier'],
          'cashoutMultiplier'     : b['cashout_multiplier'],
          'winAmount'             : b['win_amount'],
          'status'                : b['status'],
          'isOwn'                 : b['is_own'] ?? false,
        }).toList(),
      });
    } catch (e) {
      debugPrint('[RocketCrash] betFeed error: $e');
    }
  }

  // -- Wallet handlers -------------------------------------------------------

  Future<void> _handlePlaceBet(Map<String, dynamic> payload) async {
    final slotIndex   = _parseInt(payload['slotIndex']);
    final amount      = _parseInt(payload['amount']);
    final roundId     = payload['roundId']?.toString() ?? _roundId;
    final autoCashout = payload['autoCashoutMultiplier'] is num
        ? (payload['autoCashoutMultiplier'] as num).toDouble()
        : null;

    if (!_serverRoundReady || roundId == null) {
      _post('BET_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : 'server_not_ready',
        'userMessage': _friendlyCode('server_not_ready'),
      });
      return;
    }
    if (amount <= 0) {
      _post('BET_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : 'invalid_amount',
        'userMessage': _friendlyCode('invalid_amount'),
      });
      return;
    }

    try {
      final result     = await _service.placeRocketBet(roundId, amount, autoCashout);
      if (!mounted) return;
      final betId      = result['bet_id']?.toString();
      final newBalance = _parseInt(result['new_balance']);

      if (betId == null || betId.isEmpty) {
        _post('BET_REJECTED', {
          'slotIndex'  : slotIndex,
          'code'       : 'no_bet_id',
          'userMessage': _friendlyCode('network_error'),
        });
        return;
      }

      HapticFeedback.lightImpact();
      debugPrint('[RocketCrash] bet placed betId=$betId amount=$amount');
      _post('BET_ACCEPTED', {
        'slotIndex' : slotIndex,
        'betId'     : betId,
        'amount'    : amount,
        'newBalance': newBalance,
      });

      _sendBetFeed(roundId);

    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] placeBet error: $e');
      final code = _mapError('$e');
      _post('BET_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : code,
        'userMessage': _friendlyCode(code),
      });
    }
  }

  Future<void> _handleBetDebit(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    // Reject legacy debit path once the server round is active.
    if (_serverRoundReady) {
      _post('BET_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : 'use_place_bet',
        'userMessage': _friendlyCode('server_not_ready'),
      });
      return;
    }
    final amount = _parseInt(payload['amount']);
    if (amount <= 0) {
      _post('BET_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : 'invalid_amount',
        'userMessage': _friendlyCode('invalid_amount'),
      });
      return;
    }
    try {
      final result     = await _service.armBet(amount, slotIndex: slotIndex);
      if (!mounted) return;
      final betId      = result['bet_id']?.toString();
      final newBalance = _parseInt(result['new_balance']);
      if (betId == null || betId.isEmpty) {
        _post('BET_REJECTED', {
          'slotIndex'  : slotIndex,
          'code'       : 'no_bet_id',
          'userMessage': _friendlyCode('network_error'),
        });
        return;
      }
      HapticFeedback.lightImpact();
      _post('BET_ACCEPTED', {
        'slotIndex' : slotIndex,
        'betId'     : betId,
        'amount'    : amount,
        'newBalance': newBalance,
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] armBet error: $e');
      final code = _mapError('$e');
      _post('BET_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : code,
        'userMessage': _friendlyCode(code),
      });
    }
  }

  Future<void> _handleBetRefund(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final betId     = payload['betId']?.toString();

    if (!_serverRoundReady) {
      _post('REFUND_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : 'server_not_ready',
        'userMessage': _friendlyCode('server_not_ready'),
      });
      return;
    }
    if (betId == null || betId.isEmpty) {
      _post('REFUND_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : 'no_bet_id',
        'userMessage': _friendlyCode('network_error'),
      });
      return;
    }
    if (_settledBetIds.contains(betId)) {
      _post('REFUND_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : 'already_settled',
        'userMessage': _friendlyCode('already_settled'),
      });
      return;
    }

    // Guard BEFORE the await. betId stays in the set even on error so that a
    // network timeout (where the server may have already processed the request)
    // cannot open a duplicate refund window.
    _settledBetIds.add(betId);

    try {
      final result         = await _service.refundBet(betId);
      if (!mounted) return;
      final newBalance     = _parseInt(result['new_balance']);
      final refundedAmount = _parseInt(result['refunded_amount']);
      _post('REFUND_ACCEPTED', {
        'slotIndex'     : slotIndex,
        'betId'         : betId,
        'refundedAmount': refundedAmount,
        'newBalance'    : newBalance,
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] refund error: $e');
      final code = _mapError('$e');
      _post('REFUND_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : code,
        'userMessage': _friendlyCode(code),
      });
    }
  }

  Future<void> _handleCashout(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final betId     = payload['betId']?.toString();

    debugPrint('[RocketCashout] request slot=$slotIndex betId=$betId');

    // Server round must be ready. The JS-supplied multiplier is NEVER used.
    if (!_serverRoundReady || _roundId == null) {
      debugPrint('[RocketCashout] rejected: server_not_ready slot=$slotIndex');
      _post('CASHOUT_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : 'server_not_ready',
        'userMessage': _friendlyCode('server_not_ready'),
      });
      return;
    }
    if (betId == null || betId.isEmpty) {
      debugPrint('[RocketCashout] rejected: no_bet_id slot=$slotIndex');
      _post('CASHOUT_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : 'no_bet_id',
        'userMessage': _friendlyCode('network_error'),
      });
      return;
    }
    if (_settledBetIds.contains(betId)) {
      debugPrint('[RocketCashout] rejected: already_settled betId=$betId');
      _post('CASHOUT_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : 'already_settled',
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
          'slotIndex'  : slotIndex,
          'code'       : 'round_crashed',
          'userMessage': _friendlyCode('round_crashed'),
        });
        return;
      }

      final winAmount  = _parseInt(result['win_amount']);
      final newBalance = _parseInt(result['new_balance']);
      // Use only server-returned multiplier.
      final actualMult = _parseDouble(
        result['cashout_multiplier'] ?? result['multiplier'] ?? 1.0,
      );

      HapticFeedback.mediumImpact();
      debugPrint('[RocketCashout] accepted slot=$slotIndex x$actualMult win=$winAmount balance=$newBalance');
      _post('CASHOUT_ACCEPTED', {
        'slotIndex' : slotIndex,
        'betId'     : betId,
        'winAmount' : winAmount,
        'multiplier': actualMult,
        'newBalance': newBalance,
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCashout] error slot=$slotIndex: $e');
      final code = _mapError('$e');
      _post('CASHOUT_REJECTED', {
        'slotIndex'  : slotIndex,
        'code'       : code,
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

  Future<void> _refreshBalance() async {
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
    debugPrint('[RocketCrash] -> $type');
    final message = jsonEncode({'type': type, 'payload': payload});
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
    if (e.contains('insufficient_coins'))    return 'insufficient_coins';
    if (e.contains('not_authenticated'))     return 'not_authenticated';
    if (e.contains('already_settled'))       return 'already_settled';
    if (e.contains('bet_not_found'))         return 'bet_not_found';
    if (e.contains('not_refundable'))        return 'not_refundable';
    if (e.contains('round_not_found'))       return 'round_not_found';
    if (e.contains('betting_closed'))        return 'betting_closed';
    if (e.contains('game_disabled'))         return 'game_disabled';
    if (e.contains('round_not_flying'))      return 'round_not_flying';
    if (e.contains('round_already_crashed')) return 'round_already_crashed';
    if (e.contains('invalid_auto_cashout'))  return 'invalid_auto_cashout';
    return 'network_error';
  }

  // User-facing message for a given error code, respecting locale.
  String _friendlyCode(String code) {
    final ar = widget.isArabic;
    switch (code) {
      case 'insufficient_coins':    return ar ? 'Ø±ØµÙŠØ¯ ØºÙŠØ± ÙƒØ§ÙÙ' : 'Insufficient coins';
      case 'not_authenticated':     return ar ? 'ÙŠØ±Ø¬Ù‰ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ù…Ø¬Ø¯Ø¯Ø§Ù‹' : 'Please sign in again';
      case 'already_settled':       return ar ? 'ØªÙ…Øª Ø§Ù„Ø¹Ù…Ù„ÙŠØ© Ù…Ø³Ø¨Ù‚Ø§Ù‹' : 'Already processed';
      case 'bet_not_found':         return ar ? 'Ø§Ù„Ø±Ù‡Ø§Ù† ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯' : 'Bet not found';
      case 'not_refundable':        return ar ? 'Ù„Ø§ ÙŠÙ…ÙƒÙ† Ø§Ø³ØªØ±Ø¯Ø§Ø¯ Ù‡Ø°Ø§ Ø§Ù„Ø±Ù‡Ø§Ù†' : 'Bet is not refundable';
      case 'round_not_found':       return ar ? 'Ø§Ù„Ø¬ÙˆÙ„Ø© ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯Ø©' : 'Round not found';
      case 'betting_closed':        return ar ? 'Ø§Ù†ØªÙ‡Ù‰ ÙˆÙ‚Øª Ø§Ù„Ø±Ù‡Ø§Ù†' : 'Betting is closed';
      case 'game_disabled':         return ar ? 'Ø§Ù„Ù„Ø¹Ø¨Ø© ØºÙŠØ± Ù…ØªØ§Ø­Ø© Ø­Ø§Ù„ÙŠØ§Ù‹' : 'Game is currently unavailable';
      case 'round_not_flying':      return ar ? 'Ø§Ù„ØµØ§Ø±ÙˆØ® Ù„Ù… ÙŠÙ†Ø·Ù„Ù‚ Ø¨Ø¹Ø¯' : 'Round is not in flight';
      case 'round_already_crashed': return ar ? 'Ø§Ù†Ù‡Ø§Ø± Ø§Ù„ØµØ§Ø±ÙˆØ® Ø¨Ø§Ù„ÙØ¹Ù„' : 'Rocket already crashed';
      case 'invalid_auto_cashout':  return ar ? 'Ù…Ø¶Ø§Ø¹Ù Ø§Ù„Ø³Ø­Ø¨ Ø§Ù„ØªÙ„Ù‚Ø§Ø¦ÙŠ ØºÙŠØ± ØµØ§Ù„Ø­' : 'Invalid auto cashout multiplier';
      case 'round_crashed':         return ar ? 'Ø§Ù†Ù‡Ø§Ø± Ø§Ù„ØµØ§Ø±ÙˆØ® Ù‚Ø¨Ù„ Ø§Ù„Ø³Ø­Ø¨' : 'Rocket crashed before cashout';
      case 'server_not_ready':      return ar ? 'Ø¬Ø§Ø±ÙŠ Ø§Ù„Ù…Ø²Ø§Ù…Ù†Ø©ØŒ ÙŠØ±Ø¬Ù‰ Ø§Ù„Ø§Ù†ØªØ¸Ø§Ø±...' : 'Syncing with server...';
      case 'invalid_amount':        return ar ? 'Ù…Ø¨Ù„Øº Ø§Ù„Ø±Ù‡Ø§Ù† ØºÙŠØ± ØµØ§Ù„Ø­' : 'Invalid bet amount';
      default:                      return ar ? 'Ø­Ø¯Ø« Ø®Ø·Ø£ØŒ ÙŠØ±Ø¬Ù‰ Ø§Ù„Ù…Ø­Ø§ÙˆÙ„Ø© Ù…Ø¬Ø¯Ø¯Ø§Ù‹' : 'Something went wrong, please retry';
    }
  }

  // -- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final showSyncBanner = _pageLoaded && (_isInitializing || !_serverRoundReady);

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
              _TopStatusBar(
                results        : _recentResults,
                isArabic       : widget.isArabic,
                roundNumber    : _displayRoundNumber,
                phase          : _displayPhase,
                isConnected    : _realtimeConnected,
                isSyncing      : showSyncBanner,
              ),
              if (!_pageLoaded) _buildLoading(),
              if (_pageError)   _buildError(),
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
              width: 36, height: 36,
              child: CircularProgressIndicator(
                color: Color(0xFF00D4FF), strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.isArabic
                  ? 'Ø¬Ø§Ø±ÙŠ Ø§Ù„Ø§ØªØµØ§Ù„ Ø¨Ø§Ù„Ø¬ÙˆÙ„Ø© Ø§Ù„Ø­ÙŠØ©...'
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
                        _pageLoaded   = false;
                        _pageError    = false;
                        _pageErrorMsg = null;
                      });
                      _controller.loadFlutterAsset(
                          'assets/games/rocket_crash/index.html');
                    },
                    child: Text(
                      widget.isArabic ? 'Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„Ù…Ø­Ø§ÙˆÙ„Ø©' : 'Try again',
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
          ? 'ØªØ¹Ø°Ø± Ø§Ù„Ø§ØªØµØ§Ù„ Ø¨Ø§Ù„Ù„Ø¹Ø¨Ø©. ÙŠØ±Ø¬Ù‰ Ø§Ù„ØªØ­Ù‚Ù‚ Ù…Ù† Ø§ØªØµØ§Ù„Ùƒ Ø¨Ø§Ù„Ø¥Ù†ØªØ±Ù†Øª.'
          : 'Could not connect to the game. Check your internet connection.';
    }
    final lower = raw.toLowerCase();
    if (lower.contains('net::err_internet') ||
        lower.contains('net::err_name') ||
        lower.contains('offline')) {
      return widget.isArabic
          ? 'Ù„Ø§ ÙŠÙˆØ¬Ø¯ Ø§ØªØµØ§Ù„ Ø¨Ø§Ù„Ø¥Ù†ØªØ±Ù†Øª.'
          : 'No internet connection.';
    }
    if (lower.contains('ssl') || lower.contains('certificate')) {
      return widget.isArabic
          ? 'Ø®Ø·Ø£ ÙÙŠ Ø´Ù‡Ø§Ø¯Ø© Ø§Ù„Ø£Ù…Ø§Ù†.'
          : 'Security certificate error.';
    }
    return widget.isArabic
        ? 'ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ù„Ø¹Ø¨Ø©. ÙŠØ±Ø¬Ù‰ Ø§Ù„Ù…Ø­Ø§ÙˆÙ„Ø© Ù…Ø¬Ø¯Ø¯Ø§Ù‹.'
        : 'Failed to load the game. Please try again.';
  }
}

// -- Top status bar -----------------------------------------------------------
// Combines LIVE status (connection dot + round # + phase chip) with the
// scrollable history of recent crash multipliers. Replaces _RecentResultsBand.

class _TopStatusBar extends StatelessWidget {
  const _TopStatusBar({
    required this.results,
    required this.isArabic,
    required this.roundNumber,
    required this.phase,
    required this.isConnected,
    required this.isSyncing,
  });

  final List<double> results;
  final bool         isArabic;
  final int          roundNumber;
  final String       phase;
  final bool         isConnected;
  final bool         isSyncing;

  // Premium color scale for history chips.
  // < 2x  muted blue-gray
  // 2-10x amber
  // 10-50x soft purple
  // >= 50x gold
  Color _chipColor(double m) {
    if (m < 2.0)  return const Color(0xFF78909C);
    if (m < 10.0) return const Color(0xFFFFAB40);
    if (m < 50.0) return const Color(0xFFCE93D8);
    return const Color(0xFFFFD700);
  }

  Color get _phaseColor {
    switch (phase) {
      case 'flying':  return const Color(0xFFFFAB40);
      case 'crashed': return const Color(0xFFEF5350);
      default:        return const Color(0xFF66BB6A);
    }
  }

  String _phaseLabel(bool ar) {
    switch (phase) {
      case 'flying':  return ar ? 'ÙŠØ·ÙŠØ±' : 'Flying';
      case 'crashed': return ar ? 'ØªØ­Ø·Ù…' : 'Crashed';
      default:        return ar ? 'Ø±Ù‡Ø§Ù†' : 'Betting';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        height: 40,
        color: Colors.black.withValues(alpha: 0.68),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: isSyncing
            ? _buildSyncRow(context)
            : _buildLiveRow(context),
      ),
    );
  }

  Widget _buildSyncRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 13, height: 13,
          child: CircularProgressIndicator(
            color: const Color(0xFFFFAB40).withValues(alpha: 0.9),
            strokeWidth: 1.8,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          isArabic ? 'Ø¬Ø§Ø±ÙŠ Ù…Ø²Ø§Ù…Ù†Ø© Ø§Ù„Ø¬ÙˆÙ„Ø© Ø§Ù„Ø­ÙŠØ©...' : 'Syncing live round...',
          style: const TextStyle(
            color: Color(0xFFFFAB40),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLiveRow(BuildContext context) {
    return Row(
      children: [
        // Connection dot + LIVE label.
        _LiveDot(connected: isConnected),
        const SizedBox(width: 4),
        if (roundNumber > 0) ...[
          Text(
            '#$roundNumber',
            style: const TextStyle(
              color: Color(0xFF90A4AE),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 5),
        ],
        // Phase chip.
        _PhaseChip(label: _phaseLabel(isArabic), color: _phaseColor),
        const SizedBox(width: 6),
        // Divider.
        Container(
          width: 1, height: 16,
          color: Colors.white.withValues(alpha: 0.12),
        ),
        const SizedBox(width: 4),
        // History multipliers.
        Expanded(
          child: results.isEmpty
              ? const SizedBox.shrink()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  reverse: isArabic,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 5),
                  itemBuilder: (_, i) {
                    final m = results[i];
                    final c = _chipColor(m);
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color  : c.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(5),
                          border : Border.all(
                              color: c.withValues(alpha: 0.4), width: 0.8),
                        ),
                        child: Text(
                          '${m.toStringAsFixed(2)}x',
                          style: TextStyle(
                            color      : c,
                            fontSize   : 10,
                            fontWeight : FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected ? const Color(0xFF66BB6A) : const Color(0xFF78909C);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: connected
                ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 5)]
                : null,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          connected ? 'LIVE' : 'SYNC',
          style: TextStyle(
            color     : color,
            fontSize  : 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.label, required this.color});
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color       : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border      : Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color     : color,
          fontSize  : 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
