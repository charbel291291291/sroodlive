import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:srood_live/shared/utils/error_utils.dart';
import 'package:srood_live/shared/widgets/coin_ui.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/hungry_cat_models.dart';
import '../services/hungry_cat_game_service.dart';

// ── Theme ────────────────────────────────────────────────────────────────────
const _kSkyTop = Color(0xFF3FC2EE);
const _kSkyBot = Color(0xFF28A8D8);
const _kWoodDark = Color(0xFF6B3E1A);
const _kWoodMed = Color(0xFF9B6B35);
const _kWoodLight = Color(0xFFC89455);
const _kCream = Color(0xFFFFF8EC);
const _kCreamDark = Color(0xFFF0E0C0);
const _kBrown = Color(0xFF5C3A1A);
const _kGoldCoin = Color(0xFFF5A820);
const _kGoldLight = Color(0xFFFFD45A);
const _kRedRound = Color(0xFFFF2222);
const _kGreenWin = Color(0xFF3BBB55);
const _kGreenDark = Color(0xFF2A9940);

// ── Fallback food data ───────────────────────────────────────────────────────
const _kDefaultFoods = [
  (emoji: '🐔', name: 'Chicken', nameAr: 'دجاج', mult: 45.0),
  (emoji: '🍅', name: 'Tomato', nameAr: 'طماطم', mult: 5.0),
  (emoji: '🐐', name: 'Goat', nameAr: 'ماعز', mult: 15.0),
  (emoji: '🫑', name: 'Pepper', nameAr: 'فلفل', mult: 5.0),
  (emoji: '🐟', name: 'Fish', nameAr: 'سمك', mult: 25.0),
  (emoji: '🥕', name: 'Carrot', nameAr: 'جزر', mult: 5.0),
  (emoji: '🍤', name: 'Shrimp', nameAr: 'جمبري', mult: 10.0),
  (emoji: '🌽', name: 'Corn', nameAr: 'ذرة', mult: 5.0),
];

const _kBetChips = [100, 1000, 5000, 10000, 20000, 100000];

enum _Phase { loading, betting, spinning, settled, error }

class HungryCatWebviewScreen extends StatefulWidget {
  const HungryCatWebviewScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<HungryCatWebviewScreen> createState() => _HungryCatWebviewScreenState();
}

class _HungryCatWebviewScreenState extends State<HungryCatWebviewScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _service = const HungryCatGameService();
  late final _HungryCatSounds _sounds;

  List<HungryCatFood> _foods = [];
  int _balance = 0;
  List<HungryCatHistoryEntry> _history = [];

  _Phase _phase = _Phase.loading;
  String? _roundId;
  int _roundNumber = 0;
  DateTime? _bettingEndsAt;
  Duration _clockOffset = Duration.zero;
  int _secsLeft = 0;

  String? _winFoodId;
  String? _winFoodIcon;
  String? _winFoodName;
  double? _winMult;

  Map<String, int> _betsByFood = {};
  Map<String, int> _foodPendingCounts = {};
  int _betSeq = 0;
  int _lastAppliedBalanceSeq = 0;
  int _betAmount = 100;

  int? _balanceBeforeSpin;
  int? _spinDelta;

  int _highlighted = 0;
  bool _settling = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _breathCtrl;
  late Animation<double> _breathAnim;
  late AnimationController _progressCtrl;
  late AnimationController _coinCtrl;
  late AnimationController _resultSlideCtrl;
  late Animation<Offset> _resultSlideAnim;

  RealtimeChannel? _channel;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  Timer? _countdownTimer;
  Timer? _resultPollTimer;
  Timer? _balanceDebounceTimer;
  Timer? _autoAdvanceTimer;
  bool _waitingForResult = false;
  String? _errorMsg;
  bool _reconnecting = false;

  static bool _globalMuted = false;
  bool get _muted => _globalMuted;

  bool get _ar => widget.isArabic;
  bool get _hasBets => _betsByFood.isNotEmpty;
  int get _totalBetAmount => _betsByFood.values.fold(0, (s, v) => s + v);

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sounds = _HungryCatSounds();
    _sounds.init();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.42,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _breathAnim = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut));

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _coinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _resultSlideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _resultSlideAnim =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _resultSlideCtrl, curve: Curves.easeOutCubic),
        );

    _loadGame();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _resultPollTimer?.cancel();
    _balanceDebounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _channel?.unsubscribe();
    _pulseCtrl.dispose();
    _breathCtrl.dispose();
    _progressCtrl.dispose();
    _coinCtrl.dispose();
    _resultSlideCtrl.dispose();
    _sounds.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[HungryCat] app resumed — refreshing round');
      _loadGame();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data loading
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadGame() async {
    setState(() {
      _phase = _Phase.loading;
      _errorMsg = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _service.fetchFoodConfig(),
        _service.fetchCoinBalance(),
        _service.getOrCreateRound(),
        _service.getGlobalHistory(),
      ]);
      if (!mounted) return;

      final round = results[2] as HungryCatGlobalRound;
      final isSameRound = _roundId == round.roundId;
      _foods = (results[0] as List<HungryCatFood>).toList();
      _balance = results[1] as int;
      _history = (results[3] as List<HungryCatHistoryEntry>).take(20).toList();
      debugPrint('[HungryCat] foods=${_foods.length}');

      _applyRound(round);
      if (isSameRound) {
        _lastAppliedBalanceSeq = math.max(_lastAppliedBalanceSeq, _betSeq);
      }
      _subscribeToRound(round.roundId);
    } catch (e, st) {
      debugError('[HungryCat] loadGame', e, st);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMsg = _friendlyError('$e');
      });
    }
  }

  void _applyRound(HungryCatGlobalRound round) {
    final isNewRound = _roundId != round.roundId;
    _countdownTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _progressCtrl.stop();

    _roundId = round.roundId;
    _roundNumber = round.roundNumber;
    _bettingEndsAt = round.bettingEndsAt;
    _clockOffset = round.serverNow.difference(DateTime.now().toUtc());
    _resultPollTimer?.cancel();
    _resultPollTimer = null;
    _waitingForResult = false;
    _settling = false;
    if (isNewRound) {
      _winFoodId = null;
      _winFoodIcon = null;
      _winFoodName = null;
      _winMult = null;
      _betsByFood = {};
      _foodPendingCounts = {};
      _betSeq = 0;
      _lastAppliedBalanceSeq = 0;
      _balanceBeforeSpin = null;
      _spinDelta = null;
    }

    debugPrint(
      '[HungryCat] round loaded roundId=$_roundId roundNumber=$_roundNumber',
    );

    if (round.isSettled) {
      _winFoodId = round.winningFoodId;
      _winFoodIcon = round.winningFoodIcon;
      _winFoodName = round.winningFoodName;
      _winMult = round.winningMultiplier;
      setState(() => _phase = _Phase.settled);
      _startAutoAdvance(delay: 3);
    } else {
      final now = DateTime.now().toUtc().add(_clockOffset);
      final left = round.bettingEndsAt.difference(now);
      _secsLeft = left.inSeconds.clamp(0, 9999);
      setState(() => _phase = _Phase.betting);
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final now = DateTime.now().toUtc().add(_clockOffset);
      final left = _bettingEndsAt!.difference(now).inSeconds;
      if (left <= 0) {
        t.cancel();
        setState(() => _secsLeft = 0);
        _triggerSettle();
      } else {
        if (left <= 5) _sounds.playCountdownTick();
        setState(() => _secsLeft = left);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Realtime
  // ─────────────────────────────────────────────────────────────────────────

  void _subscribeToRound(String roundId) {
    _reconnectTimer?.cancel();
    _channel?.unsubscribe();
    setState(() => _reconnecting = false);

    _channel = SupabaseService.requiredClient
        .channel('hcat_global_$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'hungry_cat_global_rounds',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roundId,
          ),
          callback: _onRoundUpdate,
        )
        .subscribe((status, [err]) {
          if (!mounted) return;
          final unhealthy =
              status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.timedOut;
          if (unhealthy) {
            setState(() => _reconnecting = true);
            _scheduleReconnect(roundId);
          } else if (status == RealtimeSubscribeStatus.subscribed) {
            setState(() => _reconnecting = false);
            _reconnectAttempts = 0;
          }
        });
  }

  void _scheduleReconnect(String roundId) {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    if (_reconnectAttempts > 3) {
      debugPrint('[HungryCat] realtime reconnect failed 3x — reloading');
      _reconnectAttempts = 0;
      _loadGame();
      return;
    }
    final delaySecs = _reconnectAttempts * 2;
    _reconnectTimer = Timer(Duration(seconds: delaySecs), () {
      if (!mounted) return;
      _subscribeToRound(roundId);
    });
  }

  void _onRoundUpdate(PostgresChangePayload payload) {
    if (!mounted) return;
    final row = payload.newRecord;
    if (row['status'] != 'settled') return;

    final foodId = row['winning_food_id']?.toString();
    final foodIcon = row['winning_food_icon']?.toString();
    final foodName = row['winning_food_name']?.toString();
    final mult = row['winning_multiplier'] == null
        ? null
        : (row['winning_multiplier'] as num).toDouble();

    debugPrint('[HungryCat] result winningFood=$foodId');
    if (_winFoodId == null) _applyWinner(foodId, foodIcon, foodName, mult);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Betting
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _tapFood(int index) async {
    if (_phase != _Phase.betting) return;
    if (index >= _foods.length) return;

    final food = _foods[index];
    final betAmount = _betAmount;

    if (_balance < betAmount) {
      _showSnack(
        _ar ? 'رصيد غير كافٍ' : 'Insufficient coins',
        type: SroodToastType.warning,
      );
      return;
    }

    _betSeq++;
    final mySeq = _betSeq;
    // Capture round identity before any await.  If the round changes while
    // the RPC is in-flight, the response belongs to the old round and must
    // not mutate current UI state.
    final requestRoundId = _roundId;
    final tapAt = DateTime.now();
    debugPrint(
      '[HungryCatBet] tap seq=$mySeq food=${food.foodId} roundId=$requestRoundId amount=$betAmount',
    );
    debugPrint(
      '[HungryCatPerf] tap received seq=$mySeq at ${tapAt.millisecondsSinceEpoch}ms',
    );
    HapticFeedback.lightImpact();

    setState(() {
      _balance -= betAmount;
      _foodPendingCounts[food.foodId] =
          (_foodPendingCounts[food.foodId] ?? 0) + 1;
    });

    final reqStart = DateTime.now();
    debugPrint(
      '[HungryCatPerf] bet request start seq=$mySeq at ${reqStart.millisecondsSinceEpoch}ms',
    );

    try {
      final result = await _service.placeGlobalBet(
        roundId: requestRoundId!,
        foodId: food.foodId,
        amount: betAmount,
      );
      if (!mounted) return;

      // Stale-response guard: the round changed while the RPC was in-flight.
      // Discard local bet state and fetch the authoritative balance instead.
      if (_roundId != requestRoundId) {
        debugPrint(
          '[HungryCat] stale bet response ignored seq=$mySeq '
          'requestRound=$requestRoundId currentRound=$_roundId',
        );
        setState(() => _decrementPending(food.foodId));
        _refreshBalance();
        return;
      }

      final reqEnd = DateTime.now();
      debugPrint(
        '[HungryCatBet] confirmed seq=$mySeq betId=${result.betId} newBalance=${result.newBalance}',
      );
      debugPrint(
        '[HungryCatPerf] bet request end seq=$mySeq duration=${reqEnd.difference(reqStart).inMilliseconds}ms',
      );

      HapticFeedback.selectionClick();
      _sounds.playBetPlaced();
      setState(() {
        if (mySeq >= _lastAppliedBalanceSeq) {
          _lastAppliedBalanceSeq = mySeq;
          _balance = result.newBalance;
        }
        _betsByFood[food.foodId] = (_betsByFood[food.foodId] ?? 0) + betAmount;
        _decrementPending(food.foodId);
      });
      _scheduleDebouncedBalanceRefresh();
    } catch (e) {
      final errStr = '$e';
      debugPrint(
        '[HungryCatBet] failed seq=$mySeq food=${food.foodId} error=$errStr',
      );
      if (!mounted) return;

      // Stale-error guard: round changed — don't roll back optimistic balance
      // for the old round; fetch authoritative balance instead.
      if (_roundId != requestRoundId) {
        debugPrint(
          '[HungryCat] stale bet error ignored seq=$mySeq '
          'requestRound=$requestRoundId currentRound=$_roundId',
        );
        setState(() => _decrementPending(food.foodId));
        _refreshBalance();
        return;
      }

      setState(() {
        if (mySeq > _lastAppliedBalanceSeq) {
          _balance += betAmount;
        }
        _decrementPending(food.foodId);
      });

      if (errStr.contains('duplicate_bet')) {
        _refreshBalance();
        return;
      }
      if (errStr.contains('betting_closed') ||
          errStr.contains('betting_still_open')) {
        return;
      }

      _showSnack(
        _ar ? _friendlyErrorAr(errStr) : _friendlyError(errStr),
        type: _toastTypeForError(errStr),
      );
    }
  }

  void _decrementPending(String foodId) {
    final p = (_foodPendingCounts[foodId] ?? 1) - 1;
    if (p <= 0) {
      _foodPendingCounts.remove(foodId);
    } else {
      _foodPendingCounts[foodId] = p;
    }
  }

  void _scheduleDebouncedBalanceRefresh() {
    _balanceDebounceTimer?.cancel();
    _balanceDebounceTimer = Timer(
      const Duration(milliseconds: 750),
      _refreshBalance,
    );
  }

  Future<void> _refreshBalance() async {
    final refreshSeq = _betSeq;
    try {
      final bal = await _service.fetchCoinBalance();
      if (!mounted) return;
      setState(() {
        if (refreshSeq >= _lastAppliedBalanceSeq) {
          _lastAppliedBalanceSeq = refreshSeq;
          _balance = bal;
        }
      });
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Settling
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _triggerSettle() async {
    if (_settling || _phase != _Phase.betting) return;
    _settling = true;
    _balanceBeforeSpin = _balance;
    setState(() => _phase = _Phase.spinning);
    _sounds.playSpinStart();
    _runFreeSpin();
    _startResultPoll();

    try {
      final result = await _service.settleGlobalRound(_roundId!);
      if (!mounted) return;
      _applyWinner(
        result.winningFoodId,
        result.winningFoodIcon,
        result.winningFoodName,
        result.winningMultiplier,
      );
    } catch (e, st) {
      debugPrint('[HungryCat] settle RPC failed: $e\n$st');
    }
  }

  void _startResultPoll() {
    _resultPollTimer?.cancel();
    final pollRoundId = _roundId;
    if (pollRoundId == null) return;
    _schedulePollAttempt(pollRoundId, attempt: 0);
  }

  void _schedulePollAttempt(String pollRoundId, {required int attempt}) {
    final delayMs = switch (attempt) {
      0 || 1 || 2 || 3 => 500,
      4 || 5 => 1000,
      6 || 7 => 2000,
      _ => 4000,
    };
    _resultPollTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (!mounted || _winFoodId != null || _phase != _Phase.spinning) return;
      try {
        final round = await _service.settleGlobalRound(pollRoundId);
        if (!mounted) return;
        if (round.isSettled && _winFoodId == null) {
          _applyWinner(
            round.winningFoodId,
            round.winningFoodIcon,
            round.winningFoodName,
            round.winningMultiplier,
          );
          return;
        }
      } catch (e) {
        debugPrint('[HungryCat] poll attempt=$attempt: $e');
      }
      if (!mounted || _winFoodId != null || _phase != _Phase.spinning) return;
      _schedulePollAttempt(pollRoundId, attempt: attempt + 1);
    });
  }

  void _applyWinner(
    String? foodId,
    String? foodIcon,
    String? foodName,
    double? mult,
  ) {
    _winFoodId = foodId;
    _winFoodIcon = foodIcon;
    _winFoodName = foodName;
    _winMult = mult;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Spin animation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _runFreeSpin() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    final settlingAfter = DateTime.now().add(const Duration(seconds: 6));

    while (mounted && _winFoodId == null && _phase == _Phase.spinning) {
      final now = DateTime.now();
      if (now.isAfter(deadline)) {
        debugPrint('[HungryCat] spin timeout');
        _resultPollTimer?.cancel();
        if (mounted) {
          setState(() {
            _waitingForResult = false;
            _phase = _Phase.error;
            _errorMsg = _ar
                ? 'تأخر في تحميل النتيجة. اضغط إعادة المحاولة.'
                : 'Result is taking too long. Tap Retry.';
          });
        }
        return;
      }
      if (!_waitingForResult && now.isAfter(settlingAfter)) {
        if (mounted) setState(() => _waitingForResult = true);
      }
      await Future.delayed(const Duration(milliseconds: 48));
      if (!mounted || _phase != _Phase.spinning) return;
      setState(() => _highlighted = (_highlighted + 1) % _displayFoodCount);
    }
    if (!mounted || _phase != _Phase.spinning) return;

    _resultPollTimer?.cancel();
    _resultPollTimer = null;
    _waitingForResult = false;

    final target = _findWinnerIndex();
    await _runLandingAnimation(target);
    if (!mounted) return;

    final wonBetOnWinner = _betsByFood.containsKey(_winFoodId);
    if (wonBetOnWinner) {
      _sounds.playWin();
      HapticFeedback.heavyImpact();
      _coinCtrl.reset();
      _coinCtrl.forward();
    } else if (_hasBets) {
      _sounds.playLose();
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.mediumImpact();
    }

    for (int i = 0; i < 6; i++) {
      if (!mounted) break;
      await _pulseCtrl.forward();
      await _pulseCtrl.reverse();
    }
    if (!mounted) return;

    _resultSlideCtrl.reset();
    _resultSlideCtrl.forward();

    setState(() => _phase = _Phase.settled);

    final settledRoundId = _roundId;
    final balanceBeforeSpin = _balanceBeforeSpin;

    _service
        .fetchCoinBalance()
        .then((newBalance) {
          if (!mounted || _roundId != settledRoundId) return;
          final delta = newBalance - (balanceBeforeSpin ?? _balance);
          debugPrint('[HungryCat] payout=$delta wallet=$newBalance');
          setState(() {
            _balance = newBalance;
            _spinDelta = delta;
          });
        })
        .catchError((Object e) {
          debugPrint('[HungryCat] balance fetch: $e');
        });

    _service
        .getGlobalHistory()
        .then((hist) {
          if (mounted && _roundId == settledRoundId) {
            setState(() => _history = hist.take(20).toList());
          }
        })
        .catchError((Object _) {});

    _startAutoAdvance(delay: 4);
  }

  Future<void> _runLandingAnimation(int target) async {
    final n = _displayFoodCount;

    // Two extra full rotations at high speed for drama
    for (int r = 0; r < n * 2; r++) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 48));
      if (!mounted) return;
      setState(() => _highlighted = (_highlighted + 1) % n);
    }

    // Slow deceleration to winner (quadratic ease-out: 55ms → 420ms)
    final dist = (target - _highlighted + n) % n;
    final steps = dist == 0 ? n : dist;
    for (int i = 0; i < steps; i++) {
      if (!mounted) return;
      final t = i / steps;
      final ms = (55 + t * t * 365).toInt();
      await Future.delayed(Duration(milliseconds: ms));
      if (!mounted) return;
      // Haptic tick on last 4 steps so user feels it slowing down
      if (i >= steps - 4) HapticFeedback.selectionClick();
      setState(() => _highlighted = (_highlighted + 1) % n);
    }
  }

  int _findWinnerIndex() {
    if (_winFoodId == null) return _highlighted;
    for (int i = 0; i < _foods.length; i++) {
      if (_foods[i].foodId == _winFoodId) return i;
    }
    double best = double.maxFinite;
    int idx = 0;
    final m = _winMult ?? 0;
    for (int i = 0; i < _foods.length; i++) {
      final diff = (_foods[i].multiplier - m).abs();
      if (diff < best) {
        best = diff;
        idx = i;
      }
    }
    return idx;
  }

  Future<void> _loadNextRound() async {
    if (!mounted) return;
    try {
      final round = await _service.getOrCreateRound();
      if (!mounted) return;
      _subscribeToRound(round.roundId);
      _applyRound(round);
    } catch (e, st) {
      debugPrint('[HungryCat] nextRound failed: $e\n$st');
      await Future.delayed(const Duration(seconds: 2));
      _loadNextRound();
    }
  }

  void _startAutoAdvance({int delay = 4}) {
    _autoAdvanceTimer?.cancel();
    _progressCtrl.duration = Duration(seconds: delay);
    _progressCtrl.reset();
    _progressCtrl.forward();
    _autoAdvanceTimer = Timer(Duration(seconds: delay), () {
      if (mounted) _loadNextRound();
    });
  }

  void _skipToNextRound() {
    _autoAdvanceTimer?.cancel();
    _progressCtrl.stop();
    HapticFeedback.lightImpact();
    _loadNextRound();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  int get _displayFoodCount =>
      _foods.isEmpty ? _kDefaultFoods.length : _foods.length;

  String _emojiAt(int i) {
    if (i < _foods.length) return _foods[i].icon;
    return _kDefaultFoods[i % _kDefaultFoods.length].emoji;
  }

  String _multLabelAt(int i) {
    final mult = i < _foods.length
        ? _foods[i].multiplier
        : _kDefaultFoods[i % _kDefaultFoods.length].mult;
    final v = mult.truncateToDouble() == mult
        ? mult.toInt().toString()
        : mult.toStringAsFixed(1);
    return '${v}x';
  }

  String _emojiForFoodId(String foodId) {
    for (final f in _foods) {
      if (f.foodId == foodId) return f.icon;
    }
    return '🍽️';
  }

  String _friendlyError(String e) {
    if (e.contains('insufficient_coins')) return 'Insufficient coins';
    if (e.contains('game_disabled')) return 'Game is currently disabled';
    if (e.contains('betting_closed')) return 'Betting window has closed';
    if (e.contains('round_not_found')) return 'Round not found — refreshing';
    if (e.contains('invalid_food')) return 'Invalid food selection';
    if (e.contains('not_authenticated')) return 'Please log in again';
    return 'Something went wrong. Please try again.';
  }

  String _friendlyErrorAr(String e) {
    if (e.contains('insufficient_coins')) return 'رصيد غير كافٍ';
    if (e.contains('game_disabled')) return 'اللعبة معطّلة حالياً';
    if (e.contains('betting_closed')) return 'انتهى وقت الرهان';
    if (e.contains('round_not_found')) return 'لم يُوجد الجولة';
    if (e.contains('invalid_food')) return 'اختيار طعام غير صالح';
    if (e.contains('not_authenticated')) return 'يرجى تسجيل الدخول من جديد';
    return 'حدث خطأ. حاول مجدداً.';
  }

  SroodToastType _toastTypeForError(String e) {
    if (e.contains('insufficient_coins')) return SroodToastType.warning;
    if (e.contains('game_disabled')) return SroodToastType.info;
    if (e.contains('betting_closed')) return SroodToastType.info;
    if (e.contains('not_authenticated')) return SroodToastType.warning;
    return SroodToastType.error;
  }

  void _showSnack(String msg, {SroodToastType type = SroodToastType.error}) {
    if (!mounted) return;
    SroodToast.show(context, msg, type: type);
  }

  String _formatCoins(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    }
    return '$v';
  }

  Future<bool> _showLeaveDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: _kCream,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              _ar ? 'مغادرة اللعبة؟' : 'Leave game?',
              style: const TextStyle(
                color: _kBrown,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              _ar
                  ? 'الرهانات المعلقة ستظل صالحة.'
                  : 'Your pending bets remain valid.',
              style: const TextStyle(color: _kWoodMed),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  _ar ? 'البقاء' : 'Stay',
                  style: const TextStyle(color: _kWoodMed),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  _ar ? 'مغادرة' : 'Leave',
                  style: const TextStyle(
                    color: _kRedRound,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_hasBets && _phase != _Phase.spinning,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final confirmed = await _showLeaveDialog();
        if (confirmed && mounted) nav.pop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Sky blue background
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_kSkyTop, _kSkyBot],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
            if (_reconnecting) _buildReconnectOverlay(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.30),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Current Round
          Expanded(
            child: Text(
              _ar
                  ? 'الجولة الحالية $_roundNumber'
                  : 'Current Round $_roundNumber',
              style: const TextStyle(
                color: _kRedRound,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: Colors.white54, blurRadius: 4)],
              ),
            ),
          ),
          // Mute button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _globalMuted = !_globalMuted;
                _sounds.muted = _globalMuted;
              });
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // RULE button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _kCream,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kWoodMed, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              _ar ? 'القواعد >' : 'RULE >',
              style: const TextStyle(
                color: _kBrown,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_phase == _Phase.loading) return _buildLoading();
    if (_phase == _Phase.error) return _buildError();

    return Column(
      children: [
        Expanded(child: _buildWheelArea()),
        _buildHistoryStrip(),
        _buildBottomControls(),
        _buildStatsBar(),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Wheel ─────────────────────────────────────────────────────────────────

  Widget _buildWheelArea() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final radius = size * 0.37;
        final catSize = size * 0.24;
        final bubSize = size * 0.21;
        final center = Offset(size / 2, size / 2);
        final n = _displayFoodCount;

        return Stack(
          children: [
            Center(
              child: RepaintBoundary(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Wooden wheel frame
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _WheelFramePainter(radius: radius, n: n),
                        ),
                      ),
                      // Food bubbles
                      for (int i = 0; i < n; i++)
                        _positionedBubble(i, n, center, radius, bubSize),
                      // Center cat
                      Positioned(
                        left: center.dx - catSize / 2,
                        top: center.dy - catSize / 2,
                        width: catSize,
                        height: catSize,
                        child: _buildCatCenter(catSize),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Coin burst on win
            if (_phase == _Phase.settled)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _coinCtrl,
                  builder: (_, snap) => _coinCtrl.value > 0
                      ? CustomPaint(painter: _CoinBurstPainter(_coinCtrl.value))
                      : const SizedBox.shrink(),
                ),
              ),
            // Result card
            if (_phase == _Phase.settled && _winFoodId != null)
              Positioned(
                bottom: 0,
                left: 16,
                right: 16,
                child: _buildResultCard(),
              ),
            // Auto-advance bar
            if (_phase == _Phase.settled)
              Positioned(
                bottom: _winFoodId != null ? 108 : 4,
                left: 32,
                right: 32,
                child: _buildAutoAdvanceBar(),
              ),
          ],
        );
      },
    );
  }

  Widget _positionedBubble(
    int i,
    int n,
    Offset center,
    double radius,
    double bubSize,
  ) {
    final angle = -math.pi / 2 + i * 2 * math.pi / n;
    final cx = center.dx + math.cos(angle) * radius;
    final cy = center.dy + math.sin(angle) * radius;
    final isSpinning = _phase == _Phase.spinning;
    final isActive = i == _highlighted;
    final isWinner =
        _phase == _Phase.settled &&
        _winFoodId != null &&
        i == _findWinnerIndex();
    final foodId = i < _foods.length ? _foods[i].foodId : '';
    final isSelected = _betsByFood.containsKey(foodId) && foodId.isNotEmpty;
    final betAmount = _betsByFood[foodId] ?? 0;
    final canTap = _phase == _Phase.betting && i < _foods.length;

    // Dim non-active bubbles during spin; dim non-winner after settle
    double opacity = 1.0;
    if (isSpinning && !isActive) opacity = 0.50;
    if (_phase == _Phase.settled && _winFoodId != null && !isWinner) {
      opacity = 0.30;
    }

    Widget bubble = AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) => Transform.scale(
        scale: isWinner
            ? _pulseAnim.value
            : (isActive && isSpinning ? 1.30 : 1.0),
        child: child,
      ),
      child: Semantics(
        label: '${_emojiAt(i)} ${_multLabelAt(i)}',
        button: canTap,
        child: _HungryCatBubble(
          emoji: _emojiAt(i),
          multLabel: _multLabelAt(i),
          size: bubSize,
          isActive: isActive,
          isWinner: isWinner,
          isSelected: isSelected,
          betAmount: betAmount,
          formatCoins: _formatCoins,
          isArabic: _ar,
          isSpinning: isSpinning,
        ),
      ),
    );

    if (canTap) {
      bubble = GestureDetector(onTap: () => _tapFood(i), child: bubble);
    }

    return Positioned(
      left: cx - bubSize / 2,
      top: cy - bubSize / 2,
      width: bubSize,
      height: bubSize,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 100),
        opacity: opacity,
        child: bubble,
      ),
    );
  }

  Widget _buildCatCenter(double size) {
    final spinning = _phase == _Phase.spinning;
    final betting = _phase == _Phase.betting;
    final settled = _phase == _Phase.settled;

    final String catEmoji = spinning
        ? '😸'
        : settled
        ? '😻'
        : '🐱';
    final bool urgent = betting && _secsLeft <= 5;

    return AnimatedBuilder(
      animation: _breathAnim,
      builder: (_, child) => Transform.scale(
        scale: spinning ? 1.0 : _breathAnim.value,
        child: child,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [_kWoodLight, _kWoodMed, _kWoodDark],
            stops: const [0.0, 0.6, 1.0],
          ),
          border: Border.all(color: urgent ? _kGoldCoin : _kWoodDark, width: 3),
          boxShadow: [
            BoxShadow(
              color: (spinning ? _kGoldCoin : Colors.black).withValues(
                alpha: 0.3,
              ),
              blurRadius: spinning ? 16 : 8,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(catEmoji, style: TextStyle(fontSize: size * 0.32)),
            const SizedBox(height: 2),
            if (betting)
              _CountdownBadge(seconds: _secsLeft, urgent: urgent)
            else if (spinning)
              Column(
                children: [
                  if (_waitingForResult)
                    _CenterLabel(
                      text: _ar ? 'جارٍ الاحتساب...' : 'The result is\ncoming',
                      size: size,
                    )
                  else
                    _CenterLabel(
                      text: _ar ? 'جارٍ الدوران...' : 'Spinning...',
                      size: size,
                    ),
                ],
              )
            else if (settled && _winFoodId != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _winFoodIcon ?? '',
                  style: TextStyle(fontSize: size * 0.22),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final icon = _winFoodIcon ?? '🍽️';
    final name = _winFoodName ?? '';
    final mult = _winMult != null
        ? (_winMult!.truncateToDouble() == _winMult
              ? '${_winMult!.toInt()}x'
              : '${_winMult}x')
        : '';
    final won = _spinDelta != null && _spinDelta! > 0;

    return SlideTransition(
      position: _resultSlideAnim,
      child: FadeTransition(
        opacity: _resultSlideCtrl,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _kCream,
            border: Border.all(color: won ? _kGreenWin : _kWoodMed, width: 2),
            boxShadow: [
              BoxShadow(
                color: (won ? _kGreenWin : _kWoodMed).withValues(alpha: 0.4),
                blurRadius: 12,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: _kBrown,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  if (mult.isNotEmpty)
                    Text(
                      mult,
                      style: const TextStyle(
                        color: _kGoldCoin,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                ],
              ),
              if (_hasBets && _spinDelta != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: won ? _kGreenWin : _kRedRound,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    won
                        ? (_ar
                              ? '+${_formatCoins(_spinDelta!)} 🪙'
                              : '+${_formatCoins(_spinDelta!)} 🪙')
                        : (_ar
                              ? '-${_formatCoins(_totalBetAmount)} 🪙'
                              : '-${_formatCoins(_totalBetAmount)} 🪙'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAutoAdvanceBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _progressCtrl,
          builder: (_, snap) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progressCtrl.value,
              backgroundColor: Colors.white30,
              valueColor: AlwaysStoppedAnimation<Color>(_kWoodMed),
              minHeight: 3,
            ),
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _skipToNextRound,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: _kCream.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kWoodMed),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.skip_next_rounded, color: _kBrown, size: 15),
                const SizedBox(width: 3),
                Text(
                  _ar ? 'تخطي' : 'Skip',
                  style: const TextStyle(
                    color: _kBrown,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── History strip ─────────────────────────────────────────────────────────

  Widget _buildHistoryStrip() {
    if (_history.isEmpty) return const SizedBox(height: 4);
    return SizedBox(
      height: 44,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: _history.length,
        itemBuilder: (ctx, i) {
          final h = _history[i];
          final big = h.multiplier >= 20;
          return Container(
            margin: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
            width: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: big
                  ? _kGoldCoin.withValues(alpha: 0.25)
                  : _kCream.withValues(alpha: 0.5),
              border: Border.all(
                color: big ? _kGoldCoin : _kWoodMed.withValues(alpha: 0.5),
              ),
            ),
            child: Center(
              child: Text(h.foodIcon, style: const TextStyle(fontSize: 18)),
            ),
          );
        },
      ),
    );
  }

  // ── Bottom controls ───────────────────────────────────────────────────────

  Widget _buildBottomControls() {
    final active = _phase == _Phase.betting;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFC8562A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kWoodDark, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bet status line
          if (_betsByFood.isNotEmpty || _foodPendingCounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildBetStatus(),
            ),
          // Hint text when no bets
          if (_betsByFood.isEmpty && _foodPendingCounts.isEmpty && active)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _ar
                    ? 'اختر مبلغ الرهان ثم اضغط على الطعام 👆'
                    : 'Choose wager amount > choose food 👆',
                style: TextStyle(
                  color: _kCream.withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          // Chip row
          _buildBetChips(locked: !active),
        ],
      ),
    );
  }

  Widget _buildBetStatus() {
    final totalPending = _foodPendingCounts.values.fold(0, (s, c) => s + c);

    if (totalPending > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kGoldCoin),
          ),
          const SizedBox(width: 6),
          Text(
            _ar ? 'جارٍ الإرسال...' : 'Placing bet...',
            style: const TextStyle(
              color: _kCream,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    if (_betsByFood.isNotEmpty) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: _betsByFood.entries
            .map(
              (e) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kGoldCoin.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kGoldCoin.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_emojiForFoodId(e.key)} ',
                      style: const TextStyle(fontSize: 11),
                    ),
                    CoinAmountText(
                      amount: e.value,
                      fontSize: 11,
                      iconSize: 12,
                      color: _kCream,
                      gap: 2,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBetChips({required bool locked}) {
    return CoinChipRow(
      chips: _kBetChips,
      selected: _betAmount,
      balance: _balance,
      locked: locked,
      chipSize: 54,
      spacing: 5,
      onSelect: (v) => setState(() => _betAmount = v),
    );
  }

  // ── Stats bar ─────────────────────────────────────────────────────────────

  Widget _buildStatsBar() {
    final todayWin = (_spinDelta != null && _spinDelta! > 0) ? _spinDelta! : 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      decoration: BoxDecoration(
        color: _kCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kWoodMed, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _CoinStatCell(
              label: _ar ? 'الربح اليوم' : "Today's Winning",
              amount: todayWin,
              valueColor: todayWin > 0 ? _kGreenWin : _kBrown,
            ),
            _VertDivider(),
            _StatCell(
              label: _ar ? 'سجلاتي' : 'MY Record',
              value: '---',
              valueColor: _kWoodMed,
            ),
            _VertDivider(),
            _CoinStatCell(
              label: _ar ? 'رصيدي' : 'Coins Balance',
              amount: _balance,
              valueColor: _kBrown,
            ),
          ],
        ),
      ),
    );
  }

  // ── Reconnect overlay ─────────────────────────────────────────────────────

  Widget _buildReconnectOverlay() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: _kCream,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kWoodMed, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: _kWoodMed,
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _ar ? 'إعادة الاتصال...' : 'Reconnecting…',
                    style: const TextStyle(
                      color: _kBrown,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Loading / Error ───────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _breathAnim,
            builder: (_, snap) => Transform.scale(
              scale: _breathAnim.value,
              child: const Text('🐱', style: TextStyle(fontSize: 64)),
            ),
          ),
          const SizedBox(height: 20),
          const CircularProgressIndicator(color: _kCream, strokeWidth: 3),
          const SizedBox(height: 14),
          Text(
            _ar ? 'جارٍ التحميل...' : 'Loading...',
            style: const TextStyle(
              color: _kCream,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐱', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(
              _ar ? 'تعذّر تحميل اللعبة' : 'Failed to load',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMsg ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _loadGame,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _kCream,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _kWoodMed, width: 2),
                ),
                child: Text(
                  _ar ? 'إعادة المحاولة' : 'Retry',
                  style: const TextStyle(
                    color: _kBrown,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.seconds, required this.urgent});
  final int seconds;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: urgent ? _kRedRound : _kGoldCoin,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${seconds}s',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _CenterLabel extends StatelessWidget {
  const _CenterLabel({required this.text, required this.size});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _kCream,
          fontSize: (size * 0.09).clamp(9.0, 11.0),
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

// Variant of _StatCell that shows a coin icon + amount using AppCoinIcon.
class _CoinStatCell extends StatelessWidget {
  const _CoinStatCell({
    required this.label,
    required this.amount,
    required this.valueColor,
  });
  final String label;
  final int amount;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CoinAmountText(
              amount: amount,
              fontSize: 13,
              iconSize: 14,
              color: valueColor,
              gap: 3,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kWoodMed,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.valueColor,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kWoodMed,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: _kWoodMed.withValues(alpha: 0.3));
  }
}

// ── Bubble widget ─────────────────────────────────────────────────────────────

class _HungryCatBubble extends StatelessWidget {
  const _HungryCatBubble({
    required this.emoji,
    required this.multLabel,
    required this.size,
    required this.isActive,
    required this.isWinner,
    required this.isSelected,
    required this.betAmount,
    required this.formatCoins,
    required this.isArabic,
    required this.isSpinning,
  });

  final String emoji;
  final String multLabel;
  final double size;
  final bool isActive;
  final bool isWinner;
  final bool isSelected;
  final int betAmount;
  final String Function(int) formatCoins;
  final bool isArabic;
  final bool isSpinning;

  @override
  Widget build(BuildContext context) {
    final raw = multLabel.endsWith('x')
        ? multLabel.substring(0, multLabel.length - 1)
        : multLabel;
    final label = isArabic ? '$raw مرات' : '$raw times';

    final double emojiFontSize = (size * 0.34).clamp(14.0, 26.0);
    final double labelFontSize = (size * 0.165).clamp(9.0, 13.0);

    // Spotlight effect: very bright gold when spinning-active
    final bool spotlight = isActive && isSpinning;

    Color borderColor = _kWoodMed;
    Color shadowColor = Colors.transparent;
    double borderWidth = 2.5;
    double shadowBlur = 0;
    double spreadR = 0;

    if (isWinner) {
      borderColor = _kGreenWin;
      shadowColor = _kGreenWin.withValues(alpha: 0.80);
      shadowBlur = 24;
      spreadR = 4;
      borderWidth = 4.0;
    } else if (spotlight) {
      borderColor = _kGoldLight;
      shadowColor = _kGoldCoin.withValues(alpha: 0.90);
      shadowBlur = 22;
      spreadR = 3;
      borderWidth = 3.5;
    } else if (isSelected) {
      borderColor = _kGreenWin;
      shadowColor = _kGreenWin.withValues(alpha: 0.4);
      shadowBlur = 10;
      borderWidth = 3;
    } else if (isActive) {
      borderColor = _kGoldCoin;
      shadowColor = _kGoldCoin.withValues(alpha: 0.5);
      shadowBlur = 12;
      borderWidth = 3;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isWinner ? _kGreenDark : _kWoodDark,
        boxShadow: shadowBlur > 0
            ? [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: shadowBlur,
                  spreadRadius: spreadR,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.07),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: isWinner
                  ? [const Color(0xFFEEFFEE), const Color(0xFFBBEEBB)]
                  : spotlight
                  ? [const Color(0xFFFFFDE0), const Color(0xFFFFE060)]
                  : isActive
                  ? [const Color(0xFFFFFBE8), const Color(0xFFFFEFAA)]
                  : [_kCream, _kCreamDark],
            ),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(emoji, style: TextStyle(fontSize: emojiFontSize)),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isWinner ? _kGreenDark : _kBrown,
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ],
              ),

              // Shimmer sweep on winner
              if (isWinner)
                Positioned.fill(child: ClipOval(child: _ShimmerOverlay())),

              // Bet badge
              if (betAmount > 0)
                Positioned(
                  top: size * 0.02,
                  right: size * 0.02,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kGoldLight, _kGoldCoin],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      formatCoins(betAmount),
                      style: TextStyle(
                        color: _kBrown,
                        fontSize: (size * 0.13).clamp(8.0, 11.0),
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),

              // WIN! crown badge above the bubble when winner
              if (isWinner)
                Positioned(
                  top: -(size * 0.18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _kGreenWin,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: _kGreenWin.withValues(alpha: 0.7),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Text(
                      isArabic ? '✨ فاز!' : '✨ WIN!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (size * 0.135).clamp(9.0, 13.0),
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
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

// ── Shimmer overlay ───────────────────────────────────────────────────────────

class _ShimmerOverlay extends StatefulWidget {
  @override
  State<_ShimmerOverlay> createState() => _ShimmerOverlayState();
}

class _ShimmerOverlayState extends State<_ShimmerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, snap) => CustomPaint(painter: _ShimmerPainter(_ctrl.value)),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  const _ShimmerPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final x = -size.width + size.width * 2.5 * progress;
    final gradient = LinearGradient(
      colors: [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: 0.35),
        Colors.white.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.5, 1.0],
      transform: const GradientRotation(math.pi / 4),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = gradient.createShader(
          Rect.fromLTWH(x, 0, size.width, size.height),
        ),
    );
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.progress != progress;
}

// ── Coin burst ────────────────────────────────────────────────────────────────

class _CoinBurstPainter extends CustomPainter {
  const _CoinBurstPainter(this.progress);
  final double progress;

  static final _rng = math.Random(42);
  static final _particles = List.generate(
    20,
    (i) => (
      angle: _rng.nextDouble() * math.pi * 2,
      speed: 0.3 + _rng.nextDouble() * 0.7,
      size: 4.0 + _rng.nextDouble() * 6,
    ),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final ease = Curves.easeOut.transform(progress);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = size.shortestSide * 0.45;
    final paint = Paint()
      ..color = _kGoldCoin.withValues(alpha: (1 - ease) * 0.9);
    for (final p in _particles) {
      final r = maxR * ease * p.speed;
      canvas.drawCircle(
        Offset(cx + math.cos(p.angle) * r, cy + math.sin(p.angle) * r),
        p.size * (1 - ease * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CoinBurstPainter old) => old.progress != progress;
}

// ── Wooden wheel frame painter ────────────────────────────────────────────────

class _WheelFramePainter extends CustomPainter {
  const _WheelFramePainter({required this.radius, required this.n});
  final double radius;
  final int n;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final innerR = radius * 0.27;

    // Outer ring shadow
    canvas.drawCircle(
      center,
      radius + 6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14,
    );

    // Spokes (drawn first so rings paint over the ends)
    final spokePaint = Paint()
      ..strokeWidth = size.width * 0.028
      ..strokeCap = StrokeCap.butt;

    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / n;
      final end = Offset(
        center.dx + math.cos(angle) * (radius - 2),
        center.dy + math.sin(angle) * (radius - 2),
      );
      final start = Offset(
        center.dx + math.cos(angle) * (innerR + 2),
        center.dy + math.sin(angle) * (innerR + 2),
      );

      // Dark shadow spoke
      canvas.drawLine(
        start,
        end,
        spokePaint..color = _kWoodDark.withValues(alpha: 0.7),
      );

      // Light highlight spoke
      canvas.drawLine(
        Offset(start.dx + 1, start.dy + 1),
        Offset(end.dx + 1, end.dy + 1),
        Paint()
          ..color = _kWoodLight.withValues(alpha: 0.4)
          ..strokeWidth = size.width * 0.012
          ..strokeCap = StrokeCap.butt,
      );
    }

    // Outer wooden ring - dark base
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _kWoodDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.055,
    );
    // Outer ring - medium highlight
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _kWoodMed
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.032,
    );
    // Outer ring - light edge
    canvas.drawCircle(
      center,
      radius - size.width * 0.014,
      Paint()
        ..color = _kWoodLight.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.008,
    );

    // Inner circle fill (where cat sits)
    canvas.drawCircle(
      center,
      innerR,
      Paint()
        ..color = _kWoodMed
        ..style = PaintingStyle.fill,
    );
    // Inner ring dark border
    canvas.drawCircle(
      center,
      innerR,
      Paint()
        ..color = _kWoodDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.022,
    );
    // Inner ring light edge
    canvas.drawCircle(
      center,
      innerR - size.width * 0.01,
      Paint()
        ..color = _kWoodLight.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.007,
    );

    // Decorative dots on outer ring at each spoke
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / n;
      final x = center.dx + math.cos(angle) * radius;
      final y = center.dy + math.sin(angle) * radius;
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = _kWoodDark);
      canvas.drawCircle(
        Offset(x, y),
        3,
        Paint()..color = _kCream.withValues(alpha: 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_WheelFramePainter old) =>
      old.radius != radius || old.n != n;
}

// ── Sound service ─────────────────────────────────────────────────────────────

// Two players instead of five — keeps concurrent ExoPlayer pipeline count low.
// _tick: dedicated, loaded once (fires every second during countdown).
// _event: shared for bet / spin / win / lose (these never overlap each other).
class _HungryCatSounds {
  final AudioPlayer _tick = AudioPlayer();
  final AudioPlayer _event = AudioPlayer();

  bool muted = false;

  String? _loadedEventPath;
  DateTime? _lastTickAt;

  Future<void> init() async {
    debugPrint('[HungryCatSounds] init — 2 players');
    await _tryLoad(_tick, 'assets/sounds/hcat_tick.wav');
    await _tryLoad(
      _event,
      'assets/sounds/hcat_bet.wav',
      fallback: 'assets/sounds/lucky_bag_open.mp3',
    );
    _loadedEventPath = 'assets/sounds/hcat_bet.wav';
  }

  Future<void> _tryLoad(
    AudioPlayer player,
    String path, {
    String? fallback,
  }) async {
    try {
      await player.setAsset(path);
      debugPrint('[HungryCatSounds] loaded $path');
    } catch (_) {
      if (fallback != null) {
        try {
          await player.setAsset(fallback);
        } catch (_) {}
      }
    }
  }

  void playCountdownTick() {
    if (muted) return;
    final now = DateTime.now();
    if (_lastTickAt != null &&
        now.difference(_lastTickAt!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastTickAt = now;
    if (_tick.processingState == ProcessingState.loading ||
        _tick.processingState == ProcessingState.buffering) {
      return;
    }
    try {
      unawaited(_tick.seek(Duration.zero).then((_) => _tick.play()));
    } catch (_) {}
  }

  void playBetPlaced() => _playEvent(
    'assets/sounds/hcat_bet.wav',
    fallback: 'assets/sounds/lucky_bag_open.mp3',
  );
  void playSpinStart() => _playEvent(
    'assets/sounds/hcat_spin.wav',
    fallback: 'assets/sounds/lucky_bag_open.mp3',
  );
  void playWin() => _playEvent(
    'assets/sounds/hcat_win.wav',
    fallback: 'assets/sounds/lucky_bag_win.wav',
  );
  void playLose() => _playEvent('assets/sounds/hcat_lose.wav');

  void _playEvent(String path, {String? fallback}) {
    if (muted) return;
    unawaited(_doPlayEvent(path, fallback: fallback));
  }

  Future<void> _doPlayEvent(String path, {String? fallback}) async {
    try {
      if (_loadedEventPath != path) {
        await _tryLoad(_event, path, fallback: fallback);
        _loadedEventPath = path;
      } else {
        await _event.seek(Duration.zero);
      }
      await _event.play();
      debugPrint('[HungryCatSounds] play $path');
    } catch (e) {
      debugPrint('[HungryCatSounds] error playing $path: $e');
    }
  }

  void dispose() {
    debugPrint('[HungryCatSounds] dispose — 2 players');
    _tick.dispose();
    _event.dispose();
  }
}
