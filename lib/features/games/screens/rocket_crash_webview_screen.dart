import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../services/crash_game_service.dart';

/// Rocket Crash — local WebView game with Flutter wallet bridge.
///
/// The round loop (waiting → flying → crashed) runs entirely in JavaScript.
/// Flutter handles only wallet debit/credit via Supabase RPCs.
///
/// Bridge Web → Flutter:
///   GAME_READY, REQUEST_BET_DEBIT, REQUEST_CASHOUT_CREDIT,
///   SET_SOUND_SETTING, GAME_CLOSED
///
/// Bridge Flutter → Web:
///   INIT_GAME, WALLET_UPDATED, BET_ACCEPTED, BET_REJECTED,
///   CASHOUT_ACCEPTED, CASHOUT_REJECTED
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

  // ── Web → Flutter ────────────────────────────────────────────────────

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
      case 'REQUEST_BET_DEBIT':
        await _handleBetDebit(payload);
      case 'REQUEST_CASHOUT_CREDIT':
        await _handleCashoutCredit(payload);
      case 'SET_SOUND_SETTING':
        // No-op: sound pref lives in localStorage on the JS side.
        break;
      case 'GAME_CLOSED':
        if (mounted) Navigator.of(context).maybePop();
    }
  }

  // ── Init ─────────────────────────────────────────────────────────────

  Future<void> _initGame() async {
    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;
      if (user == null) {
        _post('BET_REJECTED', {'code': 'not_authenticated', 'slotIndex': 0});
        return;
      }

      final balance = await _service.fetchBalance();

      _post('INIT_GAME', {
        'balance': balance,
        'locale': widget.isArabic ? 'ar' : 'en',
        'sound': true,
      });
    } catch (e) {
      _post('BET_REJECTED', {'code': 'init_failed', 'slotIndex': 0});
    }
  }

  // ── Wallet handlers ───────────────────────────────────────────────────

  Future<void> _handleBetDebit(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final amount = _parseInt(payload['amount']);

    if (amount <= 0) {
      _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': 'invalid_amount'});
      return;
    }

    try {
      // Use the existing startRound RPC which debits the bet atomically.
      // We pass a single bet for this slot. The betId returned is used for cashout.
      final result = await _service.startRound([
        {'amount': amount, 'mode': 'manual', 'auto_cashout_multiplier': null},
      ]);

      if (!mounted) return;

      final betId = result['bet_id']?.toString() ?? result['bets']?[0]?['id']?.toString();
      final newBalance = _parseInt(result['new_balance'] ?? result['balance']);

      if (betId == null) {
        _post('BET_REJECTED', {'slotIndex': slotIndex, 'code': 'no_bet_id'});
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
      _post('BET_REJECTED', {
        'slotIndex': slotIndex,
        'code': _mapError('$e'),
      });
    }
  }

  Future<void> _handleCashoutCredit(Map<String, dynamic> payload) async {
    final slotIndex = _parseInt(payload['slotIndex']);
    final betId = payload['betId']?.toString();
    final multiplier = _parseDouble(payload['multiplier']);
    final isCancel = payload['cancel'] == true;

    if (betId == null) {
      _post('CASHOUT_REJECTED', {'slotIndex': slotIndex, 'code': 'no_bet_id'});
      return;
    }

    try {
      // For cancel: cashout at 1.0x = full refund.
      // For win: cashout at current multiplier.
      final effectiveMultiplier = isCancel ? 1.0 : multiplier;
      final result = await _service.cashOut(betId);

      if (!mounted) return;

      final winAmount = _parseInt(result['win_amount'] ?? result['payout']);
      final newBalance = _parseInt(result['new_balance'] ?? result['balance']);

      if (!isCancel) HapticFeedback.mediumImpact();

      _post('CASHOUT_ACCEPTED', {
        'slotIndex': slotIndex,
        'betId': betId,
        'winAmount': winAmount,
        'multiplier': effectiveMultiplier,
        'newBalance': newBalance,
      });
    } catch (e) {
      if (!mounted) return;
      _post('CASHOUT_REJECTED', {
        'slotIndex': slotIndex,
        'code': _mapError('$e'),
      });
    }
  }

  // ── Flutter → Web ────────────────────────────────────────────────────

  void _post(String type, Map<String, dynamic> payload) {
    if (!mounted) return;
    final message = jsonEncode({'type': type, 'payload': payload});
    final encoded = jsonEncode(message);
    _controller.runJavaScript(
      'window.onSroodMessage && window.onSroodMessage(JSON.parse($encoded));',
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

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
    if (e.contains('insufficient')) return 'insufficient_coins';
    if (e.contains('not_authenticated')) return 'not_authenticated';
    if (e.contains('game_disabled')) return 'game_disabled';
    return 'network_error';
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
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
            const Text('🚀', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const SizedBox(
              width: 40,
              height: 40,
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
            border: Border.all(color: const Color(0xFF1A4AFF).withValues(alpha: 0.4)),
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
                    _controller.loadFlutterAsset(
                      'assets/games/rocket_crash/index.html',
                    );
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
