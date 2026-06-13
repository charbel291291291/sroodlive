import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../services/hungry_cat_game_service.dart';

/// Hungry Cat Wheel — local-asset WebView mini game.
///
/// Bridge protocol (mirrors the Rocket Crash integration style):
///   Web → Flutter (via the `SroodBridge` JS channel):
///     GAME_READY, REQUEST_BALANCE, REQUEST_SPIN, SPIN_ANIMATION_DONE,
///     GAME_CLOSED, AUDIO_TOGGLE
///   Flutter → Web (via window.onSroodMessage):
///     INIT_GAME, BALANCE_UPDATE, SPIN_ACCEPTED, SPIN_RESULT,
///     SPIN_REJECTED, ERROR
///
/// The WebView never decides money: REQUEST_SPIN goes to the
/// `play_hungry_cat_spin` RPC which settles everything server-side, then the
/// result is handed back for animation only.
class HungryCatWebViewScreen extends StatefulWidget {
  const HungryCatWebViewScreen({
    required this.isArabic,
    this.roomId,
    super.key,
  });

  final bool isArabic;
  final String? roomId;

  @override
  State<HungryCatWebViewScreen> createState() => _HungryCatWebViewScreenState();
}

class _HungryCatWebViewScreenState extends State<HungryCatWebViewScreen> {
  late final WebViewController _controller;
  final HungryCatGameService _service = const HungryCatGameService();

  bool _loading = true;
  bool _error = false;
  String? _errorMessage;
  bool _spinInFlight = false;

  @override
  void initState() {
    super.initState();
    // Black navigation bar so no grey bar shows beneath the WebView.
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
        onMessageReceived: (message) => _onWebMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = true;
              _errorMessage = error.description;
            });
          },
        ),
      )
      ..loadFlutterAsset('assets/games/hungry_cat/index.html');
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    ));
    super.dispose();
  }

  // ── Web → Flutter ───────────────────────────────────────────────────────────

  Future<void> _onWebMessage(String raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (msg['type'] as String?) {
      case 'GAME_READY':
        await _initGame();
      case 'REQUEST_BALANCE':
        await _sendBalance();
      case 'PLAY_SPIN':
        await _handleSpinRequest(msg['payload'] as Map<String, dynamic>?);
      case 'REQUEST_HISTORY':
        await _sendHistory();
      case 'SPIN_ANIMATION_DONE':
        break;
      case 'GAME_CLOSED':
        if (mounted) Navigator.of(context).maybePop();
      case 'AUDIO_TOGGLE':
        // Sound state lives inside the web game; nothing to persist app-side.
        break;
    }
  }

  Future<void> _initGame() async {
    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;
      if (user == null) {
        _postToWeb('ERROR', {'code': 'missing_user'});
        return;
      }

      final enabled = await _service.isGameEnabled();
      if (!enabled) {
        _postToWeb('ERROR', {'code': 'game_disabled'});
        return;
      }

      final profile = await client
          .from('profiles')
          .select('display_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      final balance = await _service.fetchCoinBalance();
      final foods = await _service.fetchFoodConfig();
      // Fetch the user's latest 20 spins so the history banner is populated
      // immediately without a second round-trip from the web side.
      List<Map<String, dynamic>> latestResults;
      try {
        final history = await _service.fetchRecentSpins();
        latestResults = history.map((h) => h.toBridgeJson()).toList();
      } catch (_) {
        latestResults = [];
      }

      _postToWeb('INIT_GAME', {
        'userId': user.id,
        'displayName': profile?['display_name'] ?? 'Player',
        'avatarUrl': profile?['avatar_url'],
        'roomId': widget.roomId,
        'balance': balance,
        'isArabic': widget.isArabic,
        'betChips': const [100, 500, 1000, 2000, 5000],
        'foods': foods.map((f) => f.toBridgeJson()).toList(),
        'latestResults': latestResults,
      });
    } catch (e) {
      _postToWeb('ERROR', {'code': 'init_failed', 'message': '$e'});
    }
  }

  Future<void> _sendBalance() async {
    try {
      final balance = await _service.fetchCoinBalance();
      _postToWeb('BALANCE_UPDATE', {'balance': balance});
    } catch (_) {}
  }

  Future<void> _sendHistory() async {
    try {
      final history = await _service.fetchRecentSpins();
      _postToWeb('HISTORY_UPDATE', {
        'results': history.map((h) => h.toBridgeJson()).toList(),
      });
    } catch (_) {}
  }

  Future<void> _handleSpinRequest(Map<String, dynamic>? payload) async {
    if (payload == null) return;

    // Block duplicate spins: one in flight at a time.
    if (_spinInFlight) {
      _postToWeb('SPIN_REJECTED', {'code': 'spin_in_progress'});
      return;
    }

    final betAmount = payload['betAmount'] is int
        ? payload['betAmount'] as int
        : int.tryParse('${payload['betAmount']}') ?? 0;
    final clientSpinId =
        payload['clientSpinId'] as String? ?? _generateUuidV4();

    if (betAmount <= 0) {
      _postToWeb('SPIN_REJECTED', {'code': 'invalid_bet_amount'});
      return;
    }

    _spinInFlight = true;
    HapticFeedback.lightImpact();
    _postToWeb('SPIN_ACCEPTED', {'clientSpinId': clientSpinId});

    try {
      final result = await _service.playSpin(
        betAmount: betAmount,
        clientSpinId: clientSpinId,
        roomId: widget.roomId,
      );
      // Haptic on win: heavy for legendary/epic, medium otherwise.
      if (result.rarity == 'legendary') {
        HapticFeedback.heavyImpact();
      } else if (result.rarity == 'epic' || result.rarity == 'rare') {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
      _postToWeb('SPIN_RESULT', result.toBridgeJson());
    } catch (e) {
      final code = _mapErrorCode('$e');
      _postToWeb('SPIN_REJECTED', {'code': code});
    } finally {
      _spinInFlight = false;
    }
  }

  String _mapErrorCode(String error) {
    if (error.contains('insufficient_coins')) return 'insufficient_coins';
    if (error.contains('game_disabled')) return 'game_disabled';
    if (error.contains('invalid_bet_amount')) return 'invalid_bet_amount';
    if (error.contains('invalid_food_config')) return 'invalid_food_config';
    if (error.contains('not_authenticated')) return 'missing_user';
    return 'network_error';
  }

  // ── Flutter → Web ───────────────────────────────────────────────────────────

  void _postToWeb(String type, Map<String, dynamic> payload) {
    final message = jsonEncode({'type': type, 'payload': payload});
    final encoded = jsonEncode(message); // escape as a JS string literal
    _controller.runJavaScript(
      'window.onSroodMessage && window.onSroodMessage(JSON.parse($encoded));',
    );
  }

  String _generateUuidV4() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Don't let a back-gesture interrupt an unsettled spin silently — the
      // RPC is atomic so funds are safe either way, but warn the user.
      canPop: !_spinInFlight,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _spinInFlight) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.isArabic
                    ? 'انتظر انتهاء الدورة الحالية...'
                    : 'Wait for the current spin to finish...',
              ),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF08030F),
        body: SafeArea(
          bottom: false, // Web handles bottom inset via env(safe-area-inset-bottom)
          child: Stack(
            fit: StackFit.expand,
            children: [
              WebViewWidget(controller: _controller),
              if (_loading) _buildLoading(),
              if (_error) _buildError(),
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
              widget.isArabic ? 'جاري تحميل اللعبة...' : 'Loading game...',
              style: const TextStyle(
                color: Color(0xFF7A6890),
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
                'Hungry Cat Wheel',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage ??
                    (widget.isArabic
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
                      _loading = true;
                      _error = false;
                      _errorMessage = null;
                    });
                    _controller
                        .loadFlutterAsset('assets/games/hungry_cat/index.html');
                  },
                  child: Text(
                    widget.isArabic ? 'إعادة المحاولة' : 'Retry',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
