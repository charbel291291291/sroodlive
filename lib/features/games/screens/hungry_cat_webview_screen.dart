import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/hungry_cat_models.dart';
import '../services/hungry_cat_game_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

/// Hungry Cat — automatic betting wheel.
///
/// Round cycle (Flutter-driven clock):
///   BETTING  10 s  → user taps food cards via PLACE_BET
///   LOCKED    4 s  → bets closed, spin animation runs in HTML
///   RESULT    3 s  → winner shown, balance updated
///   → next round starts automatically
///
/// Security: all coin deduction, winner selection, and payout happen inside
/// Supabase RPCs. The Flutter client drives the clock and bridge only.
///
/// Bridge (Web → Flutter):  GAME_READY, PLACE_BET, CLEAR_BETS,
///                           REQUEST_HISTORY, GAME_CLOSED
/// Bridge (Flutter → Web):  INIT_GAME, ROUND_STARTED, ROUND_TICK,
///                           BET_ACCEPTED, BET_REJECTED, BETS_CLEARED,
///                           SPIN_STARTED, ROUND_RESULT, BALANCE_UPDATE,
///                           HISTORY_UPDATE, ERROR
class HungryCatWebviewScreen extends StatefulWidget {
  const HungryCatWebviewScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<HungryCatWebviewScreen> createState() =>
      _HungryCatWebviewScreenState();
}

enum _Phase { init, betting, locked, settling, result }

class _HungryCatWebviewScreenState extends State<HungryCatWebviewScreen> {
  late final WebViewController _controller;
  final _service = const HungryCatGameService();

  bool _pageLoaded = false;
  bool _pageError = false;
  String? _pageErrorMsg;

  _Phase _phase = _Phase.init;
  String? _roundId;
  int _bettingSecsLeft = 10;
  static const int _bettingDuration = 10;

  Timer? _countdown;
  Timer? _phaseDelay;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF08030F),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF08030F))
      ..addJavaScriptChannel(
        'SroodBridge',
        onMessageReceived: (msg) => _onWebMessage(msg.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _pageLoaded = true);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == false) return;
            if (!mounted) return;
            setState(() {
              _pageLoaded = true;
              _pageError = true;
              _pageErrorMsg = e.description;
            });
          },
        ),
      )
      ..loadFlutterAsset('assets/games/hungry_cat/index.html');
  }

  @override
  void dispose() {
    _stopTimers();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    ));
    super.dispose();
  }

  void _stopTimers() {
    _countdown?.cancel();
    _phaseDelay?.cancel();
  }

  // ── Web → Flutter ────────────────────────────────────────────────────────────

  Future<void> _onWebMessage(String raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String? ?? '';
    final payload = (msg['payload'] as Map<String, dynamic>?) ?? {};

    switch (type) {
      case 'GAME_READY':
        await _initGame();
      case 'PLACE_BET':
        await _handlePlaceBet(payload);
      case 'CLEAR_BETS':
        await _handleClearBets(payload);
      case 'REQUEST_HISTORY':
        await _sendHistory();
      case 'GAME_CLOSED':
        if (mounted) Navigator.of(context).maybePop();
    }
  }

  // ── Init ─────────────────────────────────────────────────────────────────────

  Future<void> _initGame() async {
    final isArabic = context.isArabic;
    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;
      if (user == null) {
        _post('ERROR', {'code': 'not_authenticated'});
        return;
      }

      final enabled = await _service.isGameEnabled();
      if (!enabled) {
        _post('ERROR', {'code': 'game_disabled'});
        return;
      }

      final foods = await _service.fetchFoodConfig();
      final balance = await _service.fetchCoinBalance();
      List<HungryCatHistoryEntry> history;
      try {
        history = await _service.fetchRecentRounds();
      } catch (_) {
        history = [];
      }

      _post('INIT_GAME', {
        'isArabic': isArabic,
        'balance': balance,
        'betChips': [100, 500, 1000, 2000, 5000],
        'foods': foods.map((f) => f.toBridgeJson()).toList(),
        'latestResults': history.map((h) => h.toBridgeJson()).toList(),
      });

      // Start the first round after a brief delay so the HTML can render.
      _phaseDelay = Timer(const Duration(milliseconds: 600), _startNextRound);
    } catch (e) {
      _post('ERROR', {'code': 'init_failed', 'message': '$e'});
    }
  }

  // ── Round lifecycle ──────────────────────────────────────────────────────────

  Future<void> _startNextRound() async {
    if (!mounted) return;
    try {
      final round = await _service.startRound();
      if (!mounted) return;
      _roundId = round.roundId;
      _bettingSecsLeft = _bettingDuration;
      _phase = _Phase.betting;
      _post('ROUND_STARTED', {'roundId': round.roundId});
      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      // Retry after 3 s (e.g., game_disabled, network blip).
      _phaseDelay = Timer(const Duration(seconds: 3), _startNextRound);
    }
  }

  void _startCountdown() {
    _countdown?.cancel();
    _post('ROUND_TICK', {'secondsLeft': _bettingSecsLeft});
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_phase != _Phase.betting) {
        t.cancel();
        return;
      }
      _bettingSecsLeft--;
      _post('ROUND_TICK', {'secondsLeft': _bettingSecsLeft});
      if (_bettingSecsLeft <= 0) {
        t.cancel();
        _transitionToLocked();
      }
    });
  }

  void _transitionToLocked() {
    if (!mounted) return;
    _phase = _Phase.locked;
    _post('SPIN_STARTED', {'roundId': _roundId});
    _phaseDelay = Timer(const Duration(seconds: 4), _settleRound);
  }

  Future<void> _settleRound() async {
    if (!mounted || _roundId == null) return;
    _phase = _Phase.settling;
    try {
      final result = await _service.settleRound(roundId: _roundId!);
      if (!mounted) return;
      if (result.userWinAmount > 0) HapticFeedback.mediumImpact();
      _post('ROUND_RESULT', result.toBridgeJson());
      _phase = _Phase.result;
      _phaseDelay = Timer(const Duration(seconds: 3), _startNextRound);
    } catch (e) {
      if (!mounted) return;
      _post('ERROR', {'code': 'settle_failed'});
      _phase = _Phase.result;
      _phaseDelay = Timer(const Duration(seconds: 3), _startNextRound);
    }
  }

  // ── Bet handlers ─────────────────────────────────────────────────────────────

  Future<void> _handlePlaceBet(Map<String, dynamic> payload) async {
    if (_phase != _Phase.betting) {
      _post('BET_REJECTED', {'code': 'betting_closed'});
      return;
    }
    final roundId = payload['roundId'] as String?;
    final foodId = payload['foodId'] as String?;
    final amount = _parseInt(payload['amount']);

    if (roundId == null || foodId == null || amount <= 0) {
      _post('BET_REJECTED', {'code': 'invalid_bet'});
      return;
    }
    if (roundId != _roundId) {
      _post('BET_REJECTED', {'code': 'round_mismatch'});
      return;
    }

    try {
      final result = await _service.placeBet(
        roundId: roundId,
        foodId: foodId,
        amount: amount,
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _post('BET_ACCEPTED', {
        'roundId': roundId,
        'foodId': foodId,
        'amount': amount,
        'newBalance': result['new_balance'],
      });
    } catch (e) {
      if (!mounted) return;
      _post('BET_REJECTED', {
        'code': _mapBetError('$e'),
        'foodId': foodId,
      });
    }
  }

  Future<void> _handleClearBets(Map<String, dynamic> payload) async {
    if (_phase != _Phase.betting || _roundId == null) return;
    final roundId = payload['roundId'] as String?;
    if (roundId != _roundId) return;

    try {
      final result = await _service.refundRoundBets(roundId: _roundId!);
      if (!mounted) return;
      _post('BETS_CLEARED', {
        'refundedAmount': result['refunded_amount'],
        'newBalance': result['new_balance'],
      });
    } catch (e) {
      if (!mounted) return;
      _post('ERROR', {'code': 'refund_failed'});
    }
  }

  Future<void> _sendHistory() async {
    try {
      final history = await _service.fetchRecentRounds();
      if (!mounted) return;
      _post('HISTORY_UPDATE', {
        'results': history.map((h) => h.toBridgeJson()).toList(),
      });
    } catch (_) {}
  }

  // ── Flutter → Web ────────────────────────────────────────────────────────────

  void _post(String type, Map<String, dynamic> payload) {
    if (!mounted) return;
    final message = jsonEncode({'type': type, 'payload': payload});
    final encoded = jsonEncode(message);
    _controller.runJavaScript(
      'window.onSroodMessage && window.onSroodMessage(JSON.parse($encoded));',
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  String _mapBetError(String e) {
    if (e.contains('insufficient_coins')) return 'insufficient_coins';
    if (e.contains('betting_closed')) return 'betting_closed';
    if (e.contains('round_not_found')) return 'round_not_found';
    if (e.contains('invalid_food')) return 'invalid_food';
    return 'network_error';
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) => _stopTimers(),
      child: Scaffold(
        backgroundColor: const Color(0xFF08030F),
        body: SafeArea(
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              WebViewWidget(controller: _controller),
              if (!_pageLoaded) _buildLoading(),
              if (_pageError) _buildError(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: const Color(0xFF08030F),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐱', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Color(0xFFF0C15A),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              context.isArabic ? 'جاري تحميل اللعبة...' : 'Loading game...',
              style: const TextStyle(
                color: Color(0xFFF0C15A),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      color: const Color(0xFF08030F),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF1B102A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF4A3470)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🐱', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text(
                'Hungry Cat',
                style: TextStyle(
                  color: Color(0xFFF0C15A),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _pageErrorMsg ??
                    (context.isArabic
                        ? 'تعذر تحميل اللعبة.'
                        : 'Failed to load the game.'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFD8CFEA),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _pageLoaded = false;
                      _pageError = false;
                      _pageErrorMsg = null;
                    });
                    _controller.loadFlutterAsset(
                        'assets/games/hungry_cat/index.html');
                  },
                  child: Text(context.isArabic ? 'إعادة المحاولة' : 'Retry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
