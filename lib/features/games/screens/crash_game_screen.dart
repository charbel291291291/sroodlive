import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../services/crash_game_service.dart';
import 'hungry_cat_webview_screen.dart';
import 'spin_wheel_screen.dart';

class CrashGameScreen extends StatefulWidget {
  const CrashGameScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<CrashGameScreen> createState() => _CrashGameScreenState();
}

class _CrashGameScreenState extends State<CrashGameScreen> {
  late final WebViewController _controller;
  final _service = const CrashGameService();

  bool _loading = true;
  bool _error = false;
  String? _errorMsg;

  // Active real-round polling
  Timer? _pollTimer;
  String? _activeRoundId;
  // Track which betIds we've already reported as cashed-out to the web
  final Set<String> _reportedCashouts = {};

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF08060F))
      ..addJavaScriptChannel(
        'SroodBridge',
        onMessageReceived: (msg) => _onWebMessage(msg.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == false) return;
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = true;
              _errorMsg = e.description;
            });
          },
        ),
      )
      ..loadFlutterAsset('assets/games/crash_rocket/index.html');
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  // ── Web → Flutter ──────────────────────────────────────────────────────────

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
      case 'REQUEST_BALANCE':
        await _sendBalance();
      case 'REQUEST_LAUNCH':
        await _handleLaunch(payload);
      case 'REQUEST_CASHOUT':
        await _handleCashout(payload);
      case 'REQUEST_HISTORY':
        await _sendHistory();
      case 'GAME_CLOSED':
        if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _initGame() async {
    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;
      if (user == null) {
        _post('ERROR', {'code': 'not_authenticated'});
        return;
      }
      final balance = await _service.fetchBalance();
      _post('INIT_GAME', {
        'balance': balance,
        'isArabic': widget.isArabic,
        'userId': user.id,
        'betChips': [100, 500, 1000, 2000, 5000],
      });
    } catch (e) {
      _post('ERROR', {'code': 'init_failed', 'message': '$e'});
    }
  }

  Future<void> _sendBalance() async {
    try {
      final balance = await _service.fetchBalance();
      _post('BALANCE_UPDATE', {'balance': balance});
    } catch (_) {}
  }

  Future<void> _sendHistory() async {
    try {
      final rounds = await _service.getRecentRounds();
      _post('HISTORY_UPDATE', {'rounds': rounds});
    } catch (_) {}
  }

  Future<void> _handleLaunch(Map<String, dynamic> payload) async {
    final bets = payload['bets'] as List<dynamic>? ?? [];

    // Preview round — no server call, just reflect the crash point back
    if (bets.isEmpty) {
      final crashAt = (payload['previewCrashAt'] as num?)?.toDouble() ?? 2.0;
      _post('LAUNCH_PREVIEW', {'crashAt': crashAt});
      return;
    }

    // Real round — call the edge function
    try {
      final betRequests = bets.map((b) {
        final m = b as Map<String, dynamic>;
        final req = <String, dynamic>{
          'bet_amount': m['betAmount'],
          'mode': m['mode'],
        };
        if (m['mode'] == 'auto') {
          req['auto_cashout_multiplier'] = m['autoTarget'];
        }
        return req;
      }).toList();

      final resp = await _service.startRound(betRequests);

      final serverBets = resp['bets'] as List<dynamic>? ?? [];
      final mappedBets = <Map<String, dynamic>>[];
      for (var i = 0; i < bets.length; i++) {
        if (i < serverBets.length) {
          final b = bets[i] as Map<String, dynamic>;
          final sb = serverBets[i] as Map<String, dynamic>;
          mappedBets.add({'slotIndex': b['slotIndex'], 'id': sb['id']});
        }
      }

      _activeRoundId = resp['round_id'] as String?;
      _reportedCashouts.clear();

      _post('LAUNCH_ACCEPTED', {
        'roundId': resp['round_id'],
        'startedAt': resp['started_at'],
        'bets': mappedBets,
      });

      if (_activeRoundId != null) _startPolling(_activeRoundId!);
    } catch (e) {
      _post('LAUNCH_FAILED', {'code': _mapError('$e')});
    }
  }

  Future<void> _handleCashout(Map<String, dynamic> payload) async {
    final betId = payload['betId'] as String?;
    final slotIndex = payload['slotIndex'] as int? ?? 0;
    if (betId == null) return;

    try {
      final resp = await _service.cashOut(betId);
      _post('CASHOUT_RESULT', {
        'slotIndex': slotIndex,
        'status': resp['status'],
        'cashoutMultiplier': resp['cashout_multiplier'],
        'winAmount': resp['win_amount'],
      });
      // If the server says the round already crashed, end it immediately
      if (resp['crash_multiplier'] != null &&
          (resp['status'] == 'crashed' || resp['status'] == 'cashed_out')) {
        _stopPolling();
        if (resp['status'] == 'crashed') {
          _post('ROUND_ENDED', {
            'crashMultiplier': resp['crash_multiplier'],
            'real': true,
          });
        }
      }
    } catch (e) {
      // Restore the slot to running so the user can try again
      _post('CASHOUT_RESULT', {
        'slotIndex': slotIndex,
        'status': 'running',
        'cashoutMultiplier': null,
        'winAmount': 0,
      });
    }
  }

  // ── Polling ────────────────────────────────────────────────────────────────

  void _startPolling(String roundId) {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      _poll(roundId);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _activeRoundId = null;
  }

  Future<void> _poll(String roundId) async {
    try {
      final result = await _service.getRoundResult(roundId);
      if (!mounted) return;

      // Report any newly cashed-out bets (auto-cashout)
      final bets = result['bets'] as List<dynamic>? ?? [];
      for (final b in bets) {
        final bet = b as Map<String, dynamic>;
        final betId = bet['bet_id'] as String?;
        if (betId == null) continue;
        if (bet['status'] == 'cashed_out' &&
            !_reportedCashouts.contains(betId)) {
          _reportedCashouts.add(betId);
          // Find which slot index owns this betId — the web page tracks it
          // We send without slotIndex and let the web side match by betId.
          // Instead we search the armed bets mapping we sent in LAUNCH_ACCEPTED.
          // Simplest: send with slotIndex=-1 and web ignores unknown slots.
          // Better: we pass betId and web matches.
          _post('CASHOUT_RESULT', {
            'betId': betId,
            'slotIndex': -1, // web matches by betId
            'status': 'cashed_out',
            'cashoutMultiplier': bet['cashout_multiplier'],
            'winAmount': bet['win_amount'],
          });
        }
      }

      if (result['status'] == 'crashed') {
        _stopPolling();
        _post('ROUND_ENDED', {
          'crashMultiplier': result['crash_multiplier'],
          'real': true,
        });
      }
    } catch (_) {
      // Network blip — keep polling
    }
  }

  // ── Flutter → Web ──────────────────────────────────────────────────────────

  void _post(String type, Map<String, dynamic> payload) {
    final message = jsonEncode({'type': type, 'payload': payload});
    final encoded = jsonEncode(message);
    _controller.runJavaScript(
      'window.onSroodMessage && window.onSroodMessage(JSON.parse($encoded));',
    );
  }

  // ── Error mapping ──────────────────────────────────────────────────────────

  String _mapError(String e) {
    if (e.contains('insufficient')) return 'insufficient_coins';
    if (e.contains('disabled')) return 'game_disabled';
    if (e.contains('authenticated')) return 'not_authenticated';
    if (e.contains('invalid_bet')) return 'invalid_bet_amount';
    return 'network_error';
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _pollTimer == null, // block back during active real round
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.isArabic
                    ? 'انتظر انتهاء الجولة...'
                    : 'Wait for the current round to end...',
              ),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF08060F),
        body: SafeArea(
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              WebViewWidget(controller: _controller),
              if (_loading) _buildLoading(),
              if (_error) _buildError(),
              if (!_loading && !_error) _buildShortcuts(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: const Color(0xFF08060F),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🚀', style: TextStyle(fontSize: 52)),
            SizedBox(height: 16),
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Color(0xFF8B26D9),
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      color: const Color(0xFF08060F),
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
              const Text('🚀', style: TextStyle(fontSize: 52)),
              const SizedBox(height: 14),
              const Text(
                'Crash Rocket',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMsg ??
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
                      _errorMsg = null;
                    });
                    _controller.loadFlutterAsset(
                      'assets/games/crash_rocket/index.html',
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

  Widget _buildShortcuts() {
    final isArabic = widget.isArabic;
    return Positioned(
      top: 8,
      right: isArabic ? null : 12,
      left: isArabic ? 12 : null,
      child: Column(
        crossAxisAlignment:
            isArabic ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          _Pill(
            emoji: '\u{1F3A1}',
            label: isArabic ? 'عجلة الحظ' : 'Spin Wheel',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SpinWheelScreen(isArabic: isArabic),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _Pill(
            emoji: '\u{1F431}',
            label: isArabic ? 'القط الجائع' : 'Hungry Cat',
            isNew: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HungryCatWebViewScreen(isArabic: isArabic),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shortcut pill ──────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill({
    required this.emoji,
    required this.label,
    required this.onTap,
    this.isNew = false,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1B0D2A).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.7),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B26D9).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (isNew) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0C15A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    color: Color(0xFF12061F),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
