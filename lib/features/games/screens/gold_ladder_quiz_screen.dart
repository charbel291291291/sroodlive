import 'dart:convert';
import 'package:srood_live/shared/utils/error_utils.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../services/gold_ladder_quiz_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

/// Gold Ladder Quiz — original trivia mini game.
///
/// Bridge protocol:
///   Web → Flutter (SroodBridge JS channel):
///     GAME_READY, START_RUN, ANSWER_QUESTION, USE_POWER, CASHOUT_RUN, GAME_CLOSED
///   Flutter → Web (window.onSroodMessage):
///     INIT_GAME, RUN_STARTED, ANSWER_RESULT, POWER_RESULT, CASHOUT_RESULT, ERROR
///
/// Security: the correct answer is never sent to the WebView before the user
/// answers. It is only included in ANSWER_RESULT after the RPC validates the
/// answer server-side.
class GoldLadderQuizScreen extends StatefulWidget {
  const GoldLadderQuizScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<GoldLadderQuizScreen> createState() => _GoldLadderQuizScreenState();
}

class _GoldLadderQuizScreenState extends State<GoldLadderQuizScreen> {
  late final WebViewController _controller;
  final _service = const GoldLadderQuizService();

  bool _loading = true;
  bool _error = false;
  String? _errorMessage;
  bool _actionInFlight = false;

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
            setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == false) return;
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = true;
              _errorMessage = e.description;
            });
          },
        ),
      )
      ..loadFlutterAsset('assets/games/gold_ladder_quiz/index.html');
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    ));
    super.dispose();
  }

  // ── Web → Flutter ────────────────────────────────────────────────────────────

  Future<void> _onWebMessage(String raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e, st) {
      debugError('GoldLadderQuizScreen._onWebMessage', e, st);
      return;
    }

    final type = msg['type'] as String? ?? '';
    final payload = (msg['payload'] as Map<String, dynamic>?) ?? {};

    switch (type) {
      case 'GAME_READY':
        await _initGame();
      case 'START_RUN':
        await _handleStartRun(payload);
      case 'ANSWER_QUESTION':
        await _handleAnswer(payload);
      case 'USE_POWER':
        await _handlePower(payload);
      case 'CASHOUT_RUN':
        await _handleCashout(payload);
      case 'GAME_CLOSED':
        if (mounted) Navigator.of(context).maybePop();
    }
  }

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

      final profile = await client
          .from('profiles')
          .select('display_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      final balance = await _service.fetchCoinBalance();
      final winners = await _service.fetchRecentWinners();

      _post('INIT_GAME', {
        'userId': user.id,
        'displayName': profile?['display_name'] ?? 'Player',
        'balance': balance,
        'isArabic': isArabic,
        'entryFees': [100, 500, 1000],
        'recentWinners': winners.map((w) => w.toBridgeJson()).toList(),
      });
    } catch (e) {
      _post('ERROR', {'code': 'init_failed', 'message': '$e'});
    }
  }

  Future<void> _handleStartRun(Map<String, dynamic> payload) async {
    if (_actionInFlight) return;
    final entryFee = payload['entryFee'] is int
        ? payload['entryFee'] as int
        : int.tryParse('${payload['entryFee']}') ?? 0;

    _actionInFlight = true;
    try {
      final run = await _service.startRun(entryFee: entryFee);
      HapticFeedback.lightImpact();
      _post('RUN_STARTED', run.toBridgeJson());
    } catch (e) {
      _post('ERROR', {'code': _mapError('$e'), 'message': '$e'});
    } finally {
      _actionInFlight = false;
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    if (_actionInFlight) return;
    final runId = payload['runId'] as String?;
    final questionId = payload['questionId'] as String?;
    final selectedOption = payload['selectedOption'] as String?;
    if (runId == null || questionId == null || selectedOption == null) return;

    _actionInFlight = true;
    try {
      final result = await _service.answerQuestion(
        runId: runId,
        questionId: questionId,
        selectedOption: selectedOption,
      );
      if (result.isCompleted) {
        HapticFeedback.heavyImpact();
      } else if (result.correct) {
        HapticFeedback.mediumImpact();
      } else if (result.isEliminated) {
        HapticFeedback.lightImpact();
      }
      _post('ANSWER_RESULT', result.toBridgeJson());
    } catch (e) {
      _post('ERROR', {'code': _mapError('$e')});
    } finally {
      _actionInFlight = false;
    }
  }

  Future<void> _handlePower(Map<String, dynamic> payload) async {
    if (_actionInFlight) return;
    final runId = payload['runId'] as String?;
    final questionId = payload['questionId'] as String?;
    final powerType = payload['powerType'] as String?;
    if (runId == null || questionId == null || powerType == null) return;

    _actionInFlight = true;
    try {
      final result = await _service.usePower(
        runId: runId,
        questionId: questionId,
        powerType: powerType,
      );
      _post('POWER_RESULT', result.toBridgeJson());
    } catch (e) {
      _post('ERROR', {'code': _mapError('$e')});
    } finally {
      _actionInFlight = false;
    }
  }

  Future<void> _handleCashout(Map<String, dynamic> payload) async {
    if (_actionInFlight) return;
    final runId = payload['runId'] as String?;
    if (runId == null) return;

    _actionInFlight = true;
    try {
      final result = await _service.cashoutRun(runId: runId);
      HapticFeedback.lightImpact();
      _post('CASHOUT_RESULT', {
        'cashoutAmount': result['cashout_amount'],
        'newBalance': result['new_balance'],
      });
    } catch (e) {
      _post('ERROR', {'code': _mapError('$e')});
    } finally {
      _actionInFlight = false;
    }
  }

  // ── Flutter → Web ────────────────────────────────────────────────────────────

  void _post(String type, Map<String, dynamic> payload) {
    final message = jsonEncode({'type': type, 'payload': payload});
    final encoded = jsonEncode(message);
    _controller.runJavaScript(
      'window.onSroodMessage && window.onSroodMessage(JSON.parse($encoded));',
    );
  }

  String _mapError(String e) {
    if (e.contains('insufficient_coins')) return 'insufficient_coins';
    if (e.contains('invalid_entry_fee')) return 'invalid_entry_fee';
    if (e.contains('game_disabled')) return 'game_disabled';
    if (e.contains('not_authenticated')) return 'not_authenticated';
    if (e.contains('run_not_found')) return 'run_not_found';
    if (e.contains('run_not_active')) return 'run_not_active';
    if (e.contains('power_not_available')) return 'power_not_available';
    if (e.contains('insufficient_questions')) return 'insufficient_questions';
    return 'network_error';
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_actionInFlight,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _actionInFlight) {
          SroodToast.show(
            context,
            context.isArabic
                ? 'انتظر انتهاء العملية الحالية...'
                : 'Wait for the current action to finish...',
            type: SroodToastType.info,
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF08030F),
        body: SafeArea(
          bottom: false,
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
            const Text('🏆', style: TextStyle(fontSize: 56)),
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
              const Text('🏆', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text(
                'Gold Ladder Quiz',
                style: TextStyle(
                  color: Color(0xFFF0C15A),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage ??
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
                      _loading = true;
                      _error = false;
                      _errorMessage = null;
                    });
                    _controller.loadFlutterAsset(
                        'assets/games/gold_ladder_quiz/index.html');
                  },
                  child: Text(
                    context.isArabic ? 'إعادة المحاولة' : 'Retry',
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
