import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../services/crash_game_service.dart';

/// Rocket Crash — local WebView game with Flutter wallet bridge.
///
/// JS drives the entire round loop (waiting → flying → crashed).
/// Flutter handles ONLY atomic wallet operations via Supabase RPCs.
///
/// Security: all coin deduction and credit happen inside Supabase RPC
/// functions with SQL-side validation.  The frontend never updates wallet
/// balances directly.
///
/// ── Bridge Web → Flutter ──────────────────────────────────────────────
///   GAME_READY              page loaded; request init
///   REQUEST_BET_DEBIT       arm a slot: deduct coins, create bet record
///   REQUEST_BET_REFUND      cancel a slot: refund full amount
///   REQUEST_CASHOUT_CREDIT  cash out: credit bet × multiplier
///   REQUEST_BET_LOST        rocket crashed before cashout: mark bet lost
///   REQUEST_WALLET_REFRESH  refresh balance from DB
///   SET_SOUND_SETTING       persist sound pref (JS handles localStorage)
///   GAME_CLOSED             pop the screen
///
/// ── Bridge Flutter → Web ──────────────────────────────────────────────
///   INIT_GAME               balance, locale, sound
///   WALLET_UPDATED          new balance after any operation
///   BET_ACCEPTED            bet_id, amount, newBalance
///   BET_REJECTED            code
///   REFUND_ACCEPTED         refunded_amount, newBalance
///   REFUND_REJECTED         code
///   CASHOUT_ACCEPTED        winAmount, multiplier, newBalance
///   CASHOUT_REJECTED        code
///   SOUND_SETTING_UPDATED   enabled bool (echo back to JS if needed)
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
  bool _pageError = false;
  String? _pageErrorMsg;

  // Guards against duplicate cashout/refund calls for the same betId.
  final Set<String> _settledBetIds = {};

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
      ..loadFlutterAsset('assets/games/rocket_crash/index.html');
  }

  @override
  void dispose() {
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

    final type = msg['type'] as String? ?? '';
    final payload = (msg['payload'] as Map<String, dynamic>?) ?? {};

    debugPrint('[RocketCrash] ← $type');

    switch (type) {
      case 'GAME_READY':
        await _initGame();
      case 'REQUEST_BET_DEBIT':
        await _handleBetDebit(payload);
      case 'REQUEST_BET_REFUND':
        await _handleBetRefund(payload);
      case 'REQUEST_CASHOUT_CREDIT':
        await _handleCashout(payload);
      case 'REQUEST_BET_LOST':
        _handleBetLost(payload); // fire-and-forget; UI is already updated
      case 'REQUEST_WALLET_REFRESH':
        await _refreshBalance();
      case 'SET_SOUND_SETTING':
        break; // sound pref stored in JS localStorage; no Flutter action needed
      case 'GAME_CLOSED':
        if (mounted) Navigator.of(context).maybePop();
    }
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _initGame() async {
    final user = SupabaseService.requiredClient.auth.currentUser;
    if (user == null) {
      debugPrint('[RocketCrash] init: no authenticated user');
      // JS will retry GAME_READY; nothing to send yet
      return;
    }
    try {
      final balance = await _service.fetchBalance();
      _post('INIT_GAME', {
        'balance': balance,
        'locale': widget.isArabic ? 'ar' : 'en',
        'sound': true,
      });
    } catch (e) {
      debugPrint('[RocketCrash] init error: $e');
      // Send INIT_GAME with 0 balance so JS knows wallet is connected
      // but has a problem — JS will display 0 and prevent betting
      _post('INIT_GAME', {
        'balance': 0,
        'locale': widget.isArabic ? 'ar' : 'en',
        'sound': true,
        'error': 'wallet_error',
      });
    }
  }

  // ── Wallet handlers ───────────────────────────────────────────────────────

  Future<void> _handleBetDebit(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final amount = _parseInt(payload['amount']);

    if (amount <= 0) {
      _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': 'invalid_amount'});
      return;
    }

    try {
      final result = await _service.armBet(amount, slotIndex: slotIndex);
      if (!mounted) return;

      final betId = result['bet_id']?.toString();
      final newBalance = _parseInt(result['new_balance']);

      if (betId == null || betId.isEmpty) {
        _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': 'no_bet_id'});
        return;
      }

      HapticFeedback.lightImpact();
      debugPrint('[RocketCrash] bet armed slot=$slotIndex betId=$betId');
      _post('BET_ACCEPTED', {
        'slotIndex': slotIndex,
        'betId': betId,
        'amount': amount,
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
    final betId = payload['betId']?.toString();

    if (betId == null || betId.isEmpty) {
      _post('REFUND_REJECTED', {'slotIndex': slotIndex, 'code': 'no_bet_id'});
      return;
    }
    if (_settledBetIds.contains(betId)) {
      _post('REFUND_REJECTED',
          {'slotIndex': slotIndex, 'code': 'already_settled'});
      return;
    }

    try {
      final result = await _service.refundBet(betId);
      if (!mounted) return;
      _settledBetIds.add(betId);

      final newBalance = _parseInt(result['new_balance']);
      final refundedAmount = _parseInt(result['refunded_amount']);

      debugPrint('[RocketCrash] refund ok slot=$slotIndex amt=$refundedAmount');
      _post('REFUND_ACCEPTED', {
        'slotIndex': slotIndex,
        'betId': betId,
        'refundedAmount': refundedAmount,
        'newBalance': newBalance,
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] refund error: $e');
      _post('REFUND_REJECTED',
          {'slotIndex': slotIndex, 'code': _mapError('$e')});
    }
  }

  Future<void> _handleCashout(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final betId = payload['betId']?.toString();
    final multiplier = _parseDouble(payload['multiplier']);

    if (betId == null || betId.isEmpty) {
      _post('CASHOUT_REJECTED',
          {'slotIndex': slotIndex, 'code': 'no_bet_id'});
      return;
    }
    // Idempotency guard: reject if we already settled this bet.
    if (_settledBetIds.contains(betId)) {
      _post('CASHOUT_REJECTED',
          {'slotIndex': slotIndex, 'code': 'already_settled'});
      return;
    }

    try {
      final result = await _service.cashoutLocal(betId, multiplier);
      if (!mounted) return;
      _settledBetIds.add(betId);

      final winAmount = _parseInt(result['win_amount']);
      final newBalance = _parseInt(result['new_balance']);
      final actualMult = _parseDouble(result['multiplier'] ?? multiplier);

      HapticFeedback.mediumImpact();
      debugPrint(
          '[RocketCrash] cashout ok slot=$slotIndex ×$actualMult win=$winAmount');
      _post('CASHOUT_ACCEPTED', {
        'slotIndex': slotIndex,
        'betId': betId,
        'winAmount': winAmount,
        'multiplier': actualMult,
        'newBalance': newBalance,
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RocketCrash] cashout error: $e');
      _post('CASHOUT_REJECTED',
          {'slotIndex': slotIndex, 'code': _mapError('$e')});
    }
  }

  void _handleBetLost(Map<String, dynamic> payload) {
    final betId = payload['betId']?.toString();
    final crashMult = _parseDouble(payload['crashMultiplier'] ?? 1.0);
    if (betId == null || betId.isEmpty) return;
    if (_settledBetIds.contains(betId)) return;
    _settledBetIds.add(betId);
    // Fire-and-forget: mark the DB record but don't block the UI.
    _service.markBetLost(betId, crashMult).catchError((e) {
      debugPrint('[RocketCrash] markBetLost error: $e');
    });
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

  String _mapError(String e) {
    if (e.contains('insufficient_coins')) return 'insufficient_coins';
    if (e.contains('not_authenticated')) return 'not_authenticated';
    if (e.contains('already_settled')) return 'already_settled';
    if (e.contains('bet_not_found')) return 'bet_not_found';
    if (e.contains('not_refundable')) return 'not_refundable';
    return 'network_error';
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Reset system nav bar color when leaving.
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
            const Text('🚀', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 18),
            const SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                color: Color(0xFF00D4FF),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.isArabic ? 'جاري تحميل اللعبة...' : 'Loading game...',
              style: const TextStyle(
                color: Color(0xFF00D4FF),
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
      color: const Color(0xFF020818),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1A3A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: const Color(0xFF1A4AFF).withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🚀', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text(
                'Rocket Crash',
                style: TextStyle(
                  color: Color(0xFF00D4FF),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _pageErrorMsg ??
                    (widget.isArabic
                        ? 'تعذر تحميل اللعبة.'
                        : 'Failed to load the game.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A6FFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _pageLoaded = false;
                      _pageError = false;
                      _pageErrorMsg = null;
                    });
                    _controller
                        .loadFlutterAsset('assets/games/rocket_crash/index.html');
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
