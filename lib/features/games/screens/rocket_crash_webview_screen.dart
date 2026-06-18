import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../services/crash_game_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

/// Rocket Crash — global shared rounds, server-calculated cashout, real-time sync.
///
/// ── Bridge Web → Flutter ──────────────────────────────────────────────────
///   GAME_READY              page loaded; request init
///   REQUEST_PLACE_BET       arm a slot in the global round
///   REQUEST_BET_DEBIT       legacy fallback if round unavailable
///   REQUEST_BET_REFUND      cancel a slot (legacy path only)
///   REQUEST_CASHOUT_CREDIT  cash out; server calculates multiplier for global bets
///   REQUEST_BET_LOST        rocket crashed (legacy path; global settle handles it)
///   REQUEST_START_FLIGHT    JS countdown ended; Flutter calls start_rocket_crash_flight
///   REQUEST_SETTLE_ROUND    JS detected crash; Flutter calls settle_rocket_crash_round
///   REQUEST_WALLET_REFRESH  refresh balance from DB
///   SET_SOUND_SETTING       sound pref (JS localStorage)
///   GAME_CLOSED             pop screen
///
/// ── Bridge Flutter → Web ──────────────────────────────────────────────────
///   INIT_GAME               balance, locale, round state, history
///   SET_ROUND_STATE         phase transition (betting/flying/crashed)
///   HISTORY_UPDATE          last 20 crash multipliers
///   BETS_UPDATE             current round bet feed
///   WALLET_UPDATED          new balance
///   BET_ACCEPTED            bet_id, amount, newBalance
///   BET_REJECTED            code
///   REFUND_ACCEPTED/REJECTED
///   CASHOUT_ACCEPTED        winAmount, multiplier, newBalance
///   CASHOUT_REJECTED        code
class RocketCrashWebviewScreen extends StatefulWidget {
  const RocketCrashWebviewScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<RocketCrashWebviewScreen> createState() =>
      _RocketCrashWebviewScreenState();
}

class _RocketCrashWebviewScreenState extends State<RocketCrashWebviewScreen> {
  late final WebViewController _controller;
  final _service = const CrashGameService();

  bool _pageLoaded = false;
  bool _pageError  = false;
  String? _pageErrorMsg;

  // Idempotency guard for cashout / refund calls.
  final Set<String> _settledBetIds = {};

  // Global round state
  String? _roundId;
  bool _flightStarted = false;
  bool _settling      = false;
  Timer? _bettingEndTimer;
  RealtimeChannel? _roundChannel;

  @override
  void initState() {
    super.initState();
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
            _pageLoaded  = true;
            _pageError   = true;
            _pageErrorMsg = e.description;
          });
        },
      ))
      ..loadFlutterAsset('assets/games/rocket_crash/index.html');
  }

  @override
  void dispose() {
    _bettingEndTimer?.cancel();
    _roundChannel?.unsubscribe();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    ));
    super.dispose();
  }

  // ── Web → Flutter ─────────────────────────────────────────────────────────

  Future<void> _onWebMessage(String raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type    = msg['type']    as String?              ?? '';
    final payload = msg['payload'] as Map<String, dynamic>? ?? {};

    debugPrint('[RocketCrash] ← $type');

    switch (type) {
      case 'GAME_READY':
        await _initGame();
      case 'REQUEST_PLACE_BET':
        await _handlePlaceBet(payload);
      case 'REQUEST_BET_DEBIT':
        await _handleBetDebit(payload); // legacy local fallback
      case 'REQUEST_BET_REFUND':
        await _handleBetRefund(payload);
      case 'REQUEST_CASHOUT_CREDIT':
        await _handleCashout(payload);
      case 'REQUEST_BET_LOST':
        _handleBetLost(payload);
      case 'REQUEST_START_FLIGHT':
        final rId = payload['roundId']?.toString() ?? _roundId;
        if (rId != null) await _startFlight(rId);
      case 'REQUEST_SETTLE_ROUND':
        final rId = payload['roundId']?.toString() ?? _roundId;
        if (rId != null) await _triggerSettle(rId);
      case 'REQUEST_WALLET_REFRESH':
        await _refreshBalance();
      case 'SET_SOUND_SETTING':
        break;
      case 'GAME_CLOSED':
        if (mounted) Navigator.of(context).maybePop();
    }
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _initGame() async {
    final isArabic = context.isArabic;
    if (SupabaseService.requiredClient.auth.currentUser == null) return;

    try {
      final balance = await _service.fetchBalance();
      final round   = await _service.getOrCreateRocketRound();
      final history = await _service.getRocketResults();

      _roundId = round['round_id']?.toString();
      final phase           = round['status']?.toString() ?? 'betting';
      final bettingEndsAtMs = _toDouble(round['betting_ends_at']);
      final flightStartsAtMs= _toDouble(round['flight_starts_at']);
      final crashMultiplier = _toDouble(round['crash_multiplier']);
      final serverNowMs     = _toDouble(round['server_now']);
      final roundNumber     = _parseInt(round['round_number']);

      if (_roundId != null) _subscribeToRound(_roundId!);

      // Schedule betting-end transition
      if (phase == 'betting') {
        _scheduleBettingEnd(bettingEndsAtMs, serverNowMs);
      }

      final histValues = history
          .map((h) => _toDouble(h['crash_multiplier']))
          .where((v) => v > 0)
          .toList();

      _post('INIT_GAME', {
        'balance': balance,
        'locale' : isArabic ? 'ar' : 'en',
        'sound'  : true,
        'round'  : {
          'roundId'        : _roundId,
          'roundNumber'    : roundNumber,
          'phase'          : phase,
          'bettingEndsAtMs': bettingEndsAtMs,
          'flightStartsAtMs': flightStartsAtMs,
          'crashMultiplier': crashMultiplier,
          'serverNowMs'    : serverNowMs,
          'history'        : histValues,
          'myBets'         : [null, null],
        },
      });

      // Load bet feed for current round
      if (_roundId != null) _sendBetFeed(_roundId!);

    } catch (e, st) {
      debugPrint('[RocketCrash] init error: $e\n$st');
      _post('INIT_GAME', {
        'balance': 0,
        'locale' : isArabic ? 'ar' : 'en',
        'sound'  : true,
        'error'  : 'wallet_error',
      });
    }
  }

  void _scheduleBettingEnd(double bettingEndsAtMs, double serverNowMs) {
    _bettingEndTimer?.cancel();
    if (bettingEndsAtMs <= 0) return;
    final offset       = serverNowMs - DateTime.now().millisecondsSinceEpoch;
    final localMs      = bettingEndsAtMs - offset;
    final delayMs      = (localMs - DateTime.now().millisecondsSinceEpoch).round();
    final delay        = Duration(milliseconds: delayMs.clamp(0, 60000));
    if (delayMs <= 200) {
      if (_roundId != null) _startFlight(_roundId!);
    } else {
      _bettingEndTimer = Timer(delay, () {
        if (_roundId != null) _startFlight(_roundId!);
      });
    }
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _subscribeToRound(String roundId) {
    _roundChannel?.unsubscribe();
    _roundChannel = SupabaseService.requiredClient
        .channel('rc_round_$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rocket_crash_global_rounds',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roundId,
          ),
          callback: _onRoundUpdate,
        )
        .subscribe((status, [err]) {
          debugPrint('[RocketCrash] realtime $status ${err ?? ''}');
        });
  }

  void _onRoundUpdate(PostgresChangePayload payload) {
    if (!mounted) return;
    final rec    = payload.newRecord;
    final status = rec['status']?.toString();
    debugPrint('[RocketCrash] round update status=$status');

    if (status == 'flying') {
      final fsMs = rec['flight_starts_at'] != null
          ? DateTime.parse(rec['flight_starts_at'] as String)
              .toUtc()
              .millisecondsSinceEpoch
              .toDouble()
          : null;
      final cm = _toDouble(rec['crash_multiplier']);
      _post('SET_ROUND_STATE', {
        'roundId'        : rec['id'],
        'phase'          : 'flying',
        'flightStartsAtMs': fsMs,
        'crashMultiplier': cm,
        'serverNowMs'    : DateTime.now().millisecondsSinceEpoch.toDouble(),
      });
    } else if (status == 'crashed') {
      final cm = _toDouble(rec['crash_multiplier']);
      _post('SET_ROUND_STATE', {
        'roundId'        : rec['id'],
        'phase'          : 'crashed',
        'crashMultiplier': cm,
      });
      if (!_settling) {
        _settling = true;
        Future.delayed(const Duration(milliseconds: 4200), _loadNextRound);
      }
    }
  }

  // ── Round lifecycle ───────────────────────────────────────────────────────

  Future<void> _startFlight(String roundId) async {
    if (_flightStarted) return;
    _flightStarted = true;
    try {
      final result = await _service.startRocketFlight(roundId);
      if (!mounted) return;
      _post('SET_ROUND_STATE', {
        'roundId'         : roundId,
        'phase'           : 'flying',
        'flightStartsAtMs': _toDouble(result['flight_starts_at']),
        'crashMultiplier' : _toDouble(result['crash_multiplier']),
        'serverNowMs'     : _toDouble(result['server_now']),
      });
    } catch (e) {
      debugPrint('[RocketCrash] startFlight error: $e');
      _flightStarted = false;
    }
  }

  Future<void> _triggerSettle(String roundId) async {
    if (_settling) return;
    _settling = true;
    try {
      await _service.settleRocketRound(roundId);
      debugPrint('[RocketCrash] settled round $roundId');
      // Realtime fires the crashed update; also schedule next round as fallback.
      Future.delayed(const Duration(milliseconds: 4200), _loadNextRound);
    } catch (e) {
      debugPrint('[RocketCrash] settle error: $e');
      _settling = false;
    }
  }

  Future<void> _loadNextRound() async {
    if (!mounted) return;
    _bettingEndTimer?.cancel();
    _flightStarted = false;
    _settling      = false;

    try {
      final round = await _service.getOrCreateRocketRound();
      if (!mounted) return;

      final newId           = round['round_id']?.toString();
      final bettingEndsAtMs = _toDouble(round['betting_ends_at']);
      final serverNowMs     = _toDouble(round['server_now']);
      final roundNumber     = _parseInt(round['round_number']);

      if (newId != null && newId != _roundId) {
        _roundId = newId;
        _subscribeToRound(newId);
      }

      _post('SET_ROUND_STATE', {
        'roundId'        : newId,
        'roundNumber'    : roundNumber,
        'phase'          : 'betting',
        'bettingEndsAtMs': bettingEndsAtMs,
        'serverNowMs'    : serverNowMs,
      });

      _scheduleBettingEnd(bettingEndsAtMs, serverNowMs);

      // Refresh history
      final history = await _service.getRocketResults();
      if (!mounted) return;
      final histValues = history
          .map((h) => _toDouble(h['crash_multiplier']))
          .where((v) => v > 0)
          .toList();
      _post('HISTORY_UPDATE', {'history': histValues});

    } catch (e) {
      debugPrint('[RocketCrash] loadNextRound error: $e');
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

  // ── Wallet handlers ───────────────────────────────────────────────────────

  Future<void> _handlePlaceBet(Map<String, dynamic> payload) async {
    final slotIndex   = _parseInt(payload['slotIndex']);
    final amount      = _parseInt(payload['amount']);
    final roundId     = payload['roundId']?.toString() ?? _roundId;
    final autoCashout = payload['autoCashoutMultiplier'] is num
        ? (payload['autoCashoutMultiplier'] as num).toDouble()
        : null;

    if (amount <= 0) {
      _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': 'invalid_amount'});
      return;
    }
    if (roundId == null) {
      _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': 'no_active_round'});
      return;
    }

    try {
      final result     = await _service.placeRocketBet(roundId, amount, autoCashout);
      if (!mounted) return;
      final betId      = result['bet_id']?.toString();
      final newBalance = _parseInt(result['new_balance']);

      if (betId == null || betId.isEmpty) {
        _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': 'no_bet_id'});
        return;
      }

      HapticFeedback.lightImpact();
      debugPrint('[RocketCrash] bet placed slot=$slotIndex id=$betId');
      _post('BET_ACCEPTED', {
        'slotIndex' : slotIndex,
        'betId'     : betId,
        'amount'    : amount,
        'newBalance': newBalance,
      });

      // Refresh bet feed so other slots are visible
      _sendBetFeed(roundId);

    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] placeBet error: $e');
      _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': _mapError('$e')});
    }
  }

  Future<void> _handleBetDebit(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final amount    = _parseInt(payload['amount']);

    if (amount <= 0) {
      _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': 'invalid_amount'});
      return;
    }
    try {
      final result     = await _service.armBet(amount, slotIndex: slotIndex);
      if (!mounted) return;
      final betId      = result['bet_id']?.toString();
      final newBalance = _parseInt(result['new_balance']);
      if (betId == null || betId.isEmpty) {
        _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': 'no_bet_id'});
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
      _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': _mapError('$e')});
    }
  }

  Future<void> _handleBetRefund(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final betId     = payload['betId']?.toString();

    if (betId == null || betId.isEmpty) {
      _post('REFUND_REJECTED', {'slotIndex': slotIndex, 'code': 'no_bet_id'});
      return;
    }
    if (_settledBetIds.contains(betId)) {
      _post('REFUND_REJECTED', {'slotIndex': slotIndex, 'code': 'already_settled'});
      return;
    }
    try {
      final result         = await _service.refundBet(betId);
      if (!mounted) return;
      _settledBetIds.add(betId);
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
      _post('REFUND_REJECTED', {'slotIndex': slotIndex, 'code': _mapError('$e')});
    }
  }

  Future<void> _handleCashout(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final betId     = payload['betId']?.toString();

    if (betId == null || betId.isEmpty) {
      _post('CASHOUT_REJECTED', {'slotIndex': slotIndex, 'code': 'no_bet_id'});
      return;
    }
    if (_settledBetIds.contains(betId)) {
      _post('CASHOUT_REJECTED', {'slotIndex': slotIndex, 'code': 'already_settled'});
      return;
    }

    try {
      final Map<String, dynamic> result;
      if (_roundId != null) {
        // Server-calculated multiplier — ignores JS-provided value for security.
        result = await _service.cashOutRocketBet(betId);
      } else {
        // Legacy local path: trust client-provided multiplier.
        final multiplier = _parseDouble(payload['multiplier']);
        result = await _service.cashoutLocal(betId, multiplier);
      }
      if (!mounted) return;

      final status = result['status']?.toString();
      if (status == 'lost') {
        _settledBetIds.add(betId);
        _post('CASHOUT_REJECTED', {'slotIndex': slotIndex, 'code': 'round_crashed'});
        return;
      }

      _settledBetIds.add(betId);
      final winAmount  = _parseInt(result['win_amount']);
      final newBalance = _parseInt(result['new_balance']);
      final actualMult = _parseDouble(
          result['cashout_multiplier'] ?? result['multiplier'] ?? payload['multiplier'] ?? 1.0);

      HapticFeedback.mediumImpact();
      debugPrint('[RocketCrash] cashout ok slot=$slotIndex ×$actualMult win=$winAmount');
      _post('CASHOUT_ACCEPTED', {
        'slotIndex' : slotIndex,
        'betId'     : betId,
        'winAmount' : winAmount,
        'multiplier': actualMult,
        'newBalance': newBalance,
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] cashout error: $e');
      _post('CASHOUT_REJECTED', {'slotIndex': slotIndex, 'code': _mapError('$e')});
    }
  }

  void _handleBetLost(Map<String, dynamic> payload) {
    final betId = payload['betId']?.toString();
    if (betId == null || betId.isEmpty) return;
    if (_settledBetIds.contains(betId)) return;
    _settledBetIds.add(betId);
    // Global rounds: settle RPC already marks lost. Legacy only.
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
      _post('WALLET_UPDATED', {'balance': balance});
    } catch (_) {}
  }

  // ── Flutter → Web ─────────────────────────────────────────────────────────

  void _post(String type, Map<String, dynamic> payload) {
    if (!mounted) return;
    debugPrint('[RocketCrash] → $type');
    final message = jsonEncode({'type': type, 'payload': payload});
    final encoded = jsonEncode(message);
    _controller.runJavaScript(
      'window.onSroodMessage && window.onSroodMessage(JSON.parse($encoded));',
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _bettingEndTimer?.cancel();
        _roundChannel?.unsubscribe();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF020818),
        body: SafeArea(
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              WebViewWidget(controller: _controller),
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
            const Text('🚀', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 18),
            const SizedBox(
              width: 38, height: 38,
              child: CircularProgressIndicator(
                color: Color(0xFF00D4FF), strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.isArabic ? 'جاري تحميل اللعبة...' : 'Loading game...',
              style: const TextStyle(
                color: Color(0xFF00D4FF), fontSize: 15, fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1A3A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF1A4AFF).withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🚀', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text('Rocket Crash',
                style: TextStyle(
                  color: Color(0xFF00D4FF), fontSize: 22, fontWeight: FontWeight.w900,
                )),
              const SizedBox(height: 10),
              Text(
                _pageErrorMsg ??
                    (widget.isArabic ? 'تعذر تحميل اللعبة.' : 'Failed to load the game.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 14, height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A6FFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    setState(() {
                      _pageLoaded   = false;
                      _pageError    = false;
                      _pageErrorMsg = null;
                    });
                    _controller.loadFlutterAsset('assets/games/rocket_crash/index.html');
                  },
                  child: Text(widget.isArabic ? 'إعادة المحاولة' : 'Retry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
