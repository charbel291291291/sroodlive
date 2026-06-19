import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/hungry_cat_models.dart';
import '../services/hungry_cat_game_service.dart';

// ── Fallback display data ────────────────────────────────────────────────────

const _kDefaultFoods = [
  (emoji: '🌽', name: 'Corn',    nameAr: 'ذرة',   mult: 5.0),
  (emoji: '🍅', name: 'Tomato',  nameAr: 'طماطم', mult: 5.0),
  (emoji: '🌶️', name: 'Pepper',  nameAr: 'فلفل',  mult: 5.0),
  (emoji: '🥕', name: 'Carrot',  nameAr: 'جزر',   mult: 5.0),
  (emoji: '🍤', name: 'Shrimp',  nameAr: 'جمبري', mult: 10.0),
  (emoji: '🥩', name: 'Meat',    nameAr: 'لحم',   mult: 15.0),
  (emoji: '🐟', name: 'Fish',    nameAr: 'سمك',   mult: 25.0),
  (emoji: '🍗', name: 'Chicken', nameAr: 'دجاج',  mult: 45.0),
];

const _kBetChips = [100, 500, 1000, 2000, 5000];

enum _Phase { loading, betting, spinning, settled, error }

/// Hungry Cat — real-time shared global round.
///
/// One active round is visible to all connected users simultaneously.
/// All wallet/bet logic lives server-side; this screen only drives UX.
class HungryCatWebviewScreen extends StatefulWidget {
  const HungryCatWebviewScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<HungryCatWebviewScreen> createState() => _HungryCatWebviewScreenState();
}

class _HungryCatWebviewScreenState extends State<HungryCatWebviewScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _service = const HungryCatGameService();
  late final _HungryCatSounds _sounds;

  // ── Foods / balance / history ────────────────────────────────────────────
  List<HungryCatFood>         _foods   = [];
  int                         _balance = 0;
  List<HungryCatHistoryEntry> _history = [];

  // ── Round state ──────────────────────────────────────────────────────────
  _Phase              _phase       = _Phase.loading;
  String?             _roundId;
  int                 _roundNumber = 0;
  DateTime?           _bettingEndsAt;
  Duration            _clockOffset = Duration.zero; // serverNow − localNow
  int                 _secsLeft    = 0;

  // winner (populated when round settles)
  String? _winFoodId;
  String? _winFoodIcon;
  String? _winFoodName;
  double? _winMult;

  // ── User bet state ───────────────────────────────────────────────────────
  /// Confirmed bet totals per food (sum of all successful bets this round).
  Map<String, int> _betsByFood         = {};
  /// In-flight bet count per food — nonzero while RPCs are pending.
  /// Drives the spinner indicator on the bubble; never blocks new taps.
  Map<String, int> _foodPendingCounts  = {};
  /// Monotonically increasing counter, incremented on every outgoing bet.
  int              _betSeq             = 0;
  /// The highest sequence number whose server balance has been applied to
  /// _balance.  Ensures out-of-order responses never show a stale higher
  /// balance overwriting a more-recent lower one.
  int              _lastAppliedBalanceSeq = 0;
  int              _betAmount          = 100;

  // ── Spin payout delta ────────────────────────────────────────────────────
  int? _balanceBeforeSpin; // snapshot taken at settle trigger
  int? _spinDelta;         // newBalance - _balanceBeforeSpin after animation

  // ── Animation ────────────────────────────────────────────────────────────
  int  _highlighted = 0;
  bool _settling    = false; // guard: only settle once per round

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Realtime ─────────────────────────────────────────────────────────────
  RealtimeChannel? _channel;
  int              _reconnectAttempts = 0;
  Timer?           _reconnectTimer;

  // ── Misc ─────────────────────────────────────────────────────────────────
  Timer?  _countdownTimer;
  Timer?  _resultPollTimer;       // fallback poll when realtime + settle RPC both lag
  Timer?  _balanceDebounceTimer;  // debounce server balance check after bets
  bool    _waitingForResult = false; // true while spinning beyond ~5s
  String? _errorMsg;
  bool    _reconnecting = false;

  bool get _ar => widget.isArabic;
  bool get _hasBets => _betsByFood.isNotEmpty;
  int  get _totalBetAmount =>
      _betsByFood.values.fold(0, (sum, v) => sum + v);

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
      duration: const Duration(milliseconds: 500),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
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
    _channel?.unsubscribe();
    _pulseCtrl.dispose();
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
  // Init / round loading
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadGame() async {
    setState(() { _phase = _Phase.loading; _errorMsg = null; });
    try {
      final results = await Future.wait<dynamic>([
        _service.fetchFoodConfig(),
        _service.fetchCoinBalance(),
        _service.getOrCreateRound(),
        _service.getGlobalHistory(),
      ]);

      if (!mounted) return;

      final foods   = results[0] as List<HungryCatFood>;
      final balance = results[1] as int;
      final round   = results[2] as HungryCatGlobalRound;
      final history = results[3] as List<HungryCatHistoryEntry>;

      _foods   = foods.toList();
      _balance = balance;
      _history = history.take(20).toList();
      debugPrint('[HungryCat] foods loaded count=${_foods.length}');

      _applyRound(round);
      _subscribeToRound(round.roundId);
    } catch (e, st) {
      debugPrint('[HungryCat] loadGame failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase    = _Phase.error;
        _errorMsg = _friendlyError('$e');
      });
    }
  }

  /// Applies a freshly loaded or arrived round to local state.
  void _applyRound(HungryCatGlobalRound round) {
    _countdownTimer?.cancel();

    _roundId       = round.roundId;
    _roundNumber   = round.roundNumber;
    _bettingEndsAt = round.bettingEndsAt;
    _clockOffset   = round.serverNow.difference(DateTime.now().toUtc());
    _resultPollTimer?.cancel();
    _resultPollTimer        = null;
    _waitingForResult       = false;
    _settling               = false;
    _winFoodId              = null;
    _winFoodIcon            = null;
    _winFoodName            = null;
    _winMult                = null;
    _betsByFood             = {};
    _foodPendingCounts      = {};
    _betSeq                 = 0;
    _lastAppliedBalanceSeq  = 0;
    _balanceBeforeSpin      = null;
    _spinDelta              = null;

    debugPrint('[HungryCat] round loaded roundId=$_roundId roundNumber=$_roundNumber');

    if (round.isSettled) {
      _winFoodId   = round.winningFoodId;
      _winFoodIcon = round.winningFoodIcon;
      _winFoodName = round.winningFoodName;
      _winMult     = round.winningMultiplier;
      setState(() => _phase = _Phase.settled);
      Future.delayed(const Duration(seconds: 3), _loadNextRound);
    } else {
      final now  = DateTime.now().toUtc().add(_clockOffset);
      final left = round.bettingEndsAt.difference(now);
      _secsLeft  = left.inSeconds.clamp(0, 9999);
      setState(() => _phase = _Phase.betting);
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      final now  = DateTime.now().toUtc().add(_clockOffset);
      final left = _bettingEndsAt!.difference(now).inSeconds;
      if (left <= 0) {
        t.cancel();
        setState(() => _secsLeft = 0);
        _triggerSettle();
      } else {
        // Play tick sound for last 5 seconds
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
          event:  PostgresChangeEvent.update,
          schema: 'public',
          table:  'hungry_cat_global_rounds',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'id',
            value:  roundId,
          ),
          callback: _onRoundUpdate,
        )
        .subscribe((status, [err]) {
          if (!mounted) return;
          if (status == RealtimeSubscribeStatus.channelError) {
            setState(() => _reconnecting = true);
            _scheduleReconnect(roundId);
          } else {
            setState(() => _reconnecting = false);
            _reconnectAttempts = 0;
          }
        });
  }

  void _scheduleReconnect(String roundId) {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    if (_reconnectAttempts > 3) {
      debugPrint('[HungryCat] realtime reconnect failed after 3 attempts — reloading game');
      _reconnectAttempts = 0;
      _loadGame();
      return;
    }
    final delaySecs = _reconnectAttempts * 2;
    debugPrint('[HungryCat] realtime reconnect attempt=$_reconnectAttempts in ${delaySecs}s');
    _reconnectTimer = Timer(Duration(seconds: delaySecs), () {
      if (!mounted) return;
      _subscribeToRound(roundId);
    });
  }

  void _onRoundUpdate(PostgresChangePayload payload) {
    if (!mounted) return;
    final row = payload.newRecord;
    if (row['status'] != 'settled') return;

    final foodId   = row['winning_food_id']?.toString();
    final foodIcon = row['winning_food_icon']?.toString();
    final foodName = row['winning_food_name']?.toString();
    final mult     = row['winning_multiplier'] == null
        ? null
        : (row['winning_multiplier'] as num).toDouble();

    debugPrint('[HungryCat] result roundId=$_roundId winningFood=$foodId');

    if (_winFoodId == null) {
      _applyWinner(foodId, foodIcon, foodName, mult);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Betting — every tap fires an independent RPC, no blocking.
  //
  // SQL design: place_hungry_cat_global_bet is a pure INSERT — each call
  // adds a new row to hungry_cat_global_bets.  Multiple taps on the same
  // food create multiple rows, all evaluated independently on settle.
  // The wallet uses FOR UPDATE so concurrent deductions serialize at the DB.
  //
  // Client-side balance tracking uses a sequence number (_betSeq) so that
  // out-of-order RPC responses never display a stale (higher) balance on top
  // of a more recent (lower) one.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _tapFood(int index) async {
    if (_phase != _Phase.betting) return;
    if (index >= _foods.length) return;

    final food      = _foods[index];
    final betAmount = _betAmount; // capture at tap time (chip may change mid-flight)

    // Advisory client-side check — fast feedback for clearly empty wallets.
    // Server always re-validates; this does not block legitimate rapid taps.
    if (_balance < betAmount) {
      _showSnack(_ar ? 'رصيد غير كافٍ' : 'Insufficient coins');
      return;
    }

    _betSeq++;
    final mySeq    = _betSeq;
    final tapAt    = DateTime.now();
    debugPrint('[HungryCatBet] tap seq=$mySeq food=${food.foodId} name=${food.name} roundId=$_roundId amount=$betAmount');
    debugPrint('[HungryCatPerf] tap received seq=$mySeq at ${tapAt.millisecondsSinceEpoch}ms');
    HapticFeedback.lightImpact();

    // Optimistic update: subtract immediately so the user sees the balance
    // change before the RPC round-trip completes (~300-600ms saved).
    setState(() {
      _balance = _balance - betAmount;
      _foodPendingCounts[food.foodId] =
          (_foodPendingCounts[food.foodId] ?? 0) + 1;
    });

    final reqStart = DateTime.now();
    debugPrint('[HungryCatPerf] bet request start seq=$mySeq at ${reqStart.millisecondsSinceEpoch}ms');

    try {
      final result = await _service.placeGlobalBet(
        roundId: _roundId!,
        foodId:  food.foodId,
        amount:  betAmount,
      );
      if (!mounted) return;

      final reqEnd = DateTime.now();
      debugPrint('[HungryCatBet] confirmed seq=$mySeq betId=${result.betId} newBalance=${result.newBalance}');
      debugPrint('[HungryCatPerf] bet request end seq=$mySeq duration=${reqEnd.difference(reqStart).inMilliseconds}ms');

      _sounds.playBetPlaced();
      setState(() {
        // Replace the optimistic balance with the server's authoritative value.
        // Sequence guard prevents an earlier slow response from overwriting a
        // more-recent one that already applied a lower balance.
        if (mySeq >= _lastAppliedBalanceSeq) {
          _lastAppliedBalanceSeq = mySeq;
          _balance = result.newBalance;
        }
        _betsByFood[food.foodId] =
            (_betsByFood[food.foodId] ?? 0) + betAmount;
        _decrementPending(food.foodId);
      });
      // Debounced server-side balance check: fires 750ms after the last
      // confirmed bet to correct any drift from rapid out-of-order responses.
      _scheduleDebouncedBalanceRefresh();
    } catch (e) {
      final errStr = '$e';
      debugPrint('[HungryCatBet] failed seq=$mySeq food=${food.foodId} error=$errStr');
      if (!mounted) return;
      // Undo the optimistic subtract — the bet didn't land.
      setState(() {
        _balance = _balance + betAmount;
        _decrementPending(food.foodId);
      });

      // duplicate_bet: backend unique constraint is active; bet not placed.
      // Refresh balance silently; do NOT block future taps on this food.
      if (errStr.contains('duplicate_bet')) {
        debugPrint('[HungryCatBet] duplicate_bet from server — refreshing balance (constraint active on live DB)');
        _refreshBalance();
        return;
      }

      // Suppress transient states that aren't actionable by the user.
      if (errStr.contains('betting_closed') ||
          errStr.contains('betting_still_open')) {
        return;
      }

      _showSnack(_ar ? _friendlyErrorAr(errStr) : _friendlyError(errStr));
    }
  }

  void _decrementPending(String foodId) {
    final pending = (_foodPendingCounts[foodId] ?? 1) - 1;
    if (pending <= 0) {
      _foodPendingCounts.remove(foodId);
    } else {
      _foodPendingCounts[foodId] = pending;
    }
  }

  void _scheduleDebouncedBalanceRefresh() {
    _balanceDebounceTimer?.cancel();
    _balanceDebounceTimer = Timer(const Duration(milliseconds: 750), _refreshBalance);
  }

  Future<void> _refreshBalance() async {
    final start = DateTime.now();
    debugPrint('[HungryCatPerf] balance refresh start at ${start.millisecondsSinceEpoch}ms');
    try {
      final bal = await _service.fetchCoinBalance();
      if (!mounted) return;
      final end = DateTime.now();
      debugPrint('[HungryCatPerf] balance refresh end duration=${end.difference(start).inMilliseconds}ms newBalance=$bal');
      setState(() => _balance = bal);
    } catch (_) {
      // best-effort; balance will correct on next successful bet or post-result fetch
    }
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

    // Start fallback poll immediately — fires every 4s to check if the round
    // has been settled server-side (covers realtime lag and RPC failures).
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
      // Poll fallback and realtime subscription will deliver the result.
    }
  }

  /// Polls by re-calling settle (idempotent) every 4 s as a fallback for
  /// missed realtime events.  getOrCreateRound() must NOT be used here — it
  /// creates a new betting round once the current one ends, so it would always
  /// return isSettled=false.  settleGlobalRound is idempotent: if the round is
  /// already settled it returns the winner immediately; if still open it throws
  /// betting_still_open (harmless, we keep polling).
  // Adaptive result poll: fires at 500 ms for the first few attempts, then
  // backs off to 4 s.  Using one-shot Timers rather than periodic so the
  // delay is measured from the END of the previous network call, not its start.
  void _startResultPoll() {
    _resultPollTimer?.cancel();
    final pollRoundId = _roundId;
    if (pollRoundId == null) return;
    _schedulePollAttempt(pollRoundId, attempt: 0);
  }

  void _schedulePollAttempt(String pollRoundId, {required int attempt}) {
    // 500 ms × 4 attempts → 1 s × 2 → 2 s × 2 → 4 s thereafter
    final delayMs = switch (attempt) {
      0 || 1 || 2 || 3 => 500,
      4 || 5           => 1000,
      6 || 7           => 2000,
      _                => 4000,
    };
    _resultPollTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (!mounted || _winFoodId != null || _phase != _Phase.spinning) return;
      final pollStart = DateTime.now();
      debugPrint('[HungryCatPerf] result poll start attempt=$attempt at ${pollStart.millisecondsSinceEpoch}ms');
      try {
        final round = await _service.settleGlobalRound(pollRoundId);
        final pollEnd = DateTime.now();
        debugPrint('[HungryCatPerf] result poll end attempt=$attempt duration=${pollEnd.difference(pollStart).inMilliseconds}ms');
        if (!mounted) return;
        if (round.isSettled && _winFoodId == null) {
          debugPrint('[HungryCat] poll settled round winFood=${round.winningFoodId}');
          _applyWinner(
            round.winningFoodId,
            round.winningFoodIcon,
            round.winningFoodName,
            round.winningMultiplier,
          );
          return; // winner found — stop polling
        }
      } catch (e) {
        // betting_still_open → keep polling; other errors → log and continue
        debugPrint('[HungryCat] result poll attempt=$attempt: $e');
      }
      if (!mounted || _winFoodId != null || _phase != _Phase.spinning) return;
      _schedulePollAttempt(pollRoundId, attempt: attempt + 1);
    });
  }

  void _applyWinner(
    String? foodId, String? foodIcon, String? foodName, double? mult,
  ) {
    _winFoodId   = foodId;
    _winFoodIcon = foodIcon;
    _winFoodName = foodName;
    _winMult     = mult;
    // _runFreeSpin polls _winFoodId and transitions to landing.
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Spin animation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _runFreeSpin() async {
    // Hard timeout: 30s. After 6s with no result we show "Settling result…"
    // so the user knows we're still working, not stuck.
    final deadline      = DateTime.now().add(const Duration(seconds: 30));
    final settlingAfter = DateTime.now().add(const Duration(seconds: 6));

    while (mounted && _winFoodId == null && _phase == _Phase.spinning) {
      final now = DateTime.now();
      if (now.isAfter(deadline)) {
        debugPrint('[HungryCat] spin timeout — no winner after 30s');
        _resultPollTimer?.cancel();
        if (mounted) {
          setState(() {
            _waitingForResult = false;
            _phase    = _Phase.error;
            _errorMsg = _ar
                ? 'تأخر في تحميل النتيجة. اضغط إعادة المحاولة.'
                : 'Result is taking too long. Tap Retry to reload.';
          });
        }
        return;
      }
      // After 6s without a result, show "Settling…" label in the phase bar.
      if (!_waitingForResult && now.isAfter(settlingAfter)) {
        if (mounted) setState(() => _waitingForResult = true);
      }
      await Future.delayed(const Duration(milliseconds: 70));
      if (!mounted || _phase != _Phase.spinning) return;
      setState(() => _highlighted = (_highlighted + 1) % _displayFoodCount);
    }
    if (!mounted || _phase != _Phase.spinning) return;

    _resultPollTimer?.cancel();
    _resultPollTimer  = null;
    _waitingForResult = false;

    final target = _findWinnerIndex();
    await _runLandingAnimation(target);
    if (!mounted) return;

    final wonBetOnWinner = _betsByFood.containsKey(_winFoodId);
    if (wonBetOnWinner) {
      _sounds.playWin();
    } else if (_hasBets) {
      _sounds.playLose();
    }

    HapticFeedback.mediumImpact();
    for (int i = 0; i < 3; i++) {
      if (!mounted) break;
      await _pulseCtrl.forward();
      await _pulseCtrl.reverse();
    }
    if (!mounted) return;

    // Show the result screen immediately — no balance fetch blocking the render.
    final resultAt = DateTime.now();
    debugPrint('[HungryCatPerf] result rendered at ${resultAt.millisecondsSinceEpoch}ms');
    setState(() => _phase = _Phase.settled); // _spinDelta stays null until balance arrives

    // Capture round id so background callbacks don't update a new round's state.
    final settledRoundId = _roundId;
    final balanceBeforeSpin = _balanceBeforeSpin;

    // Balance and history fetched in parallel; UI updates when each arrives.
    final balStart = DateTime.now();
    debugPrint('[HungryCatPerf] balance refresh start (post-result) at ${balStart.millisecondsSinceEpoch}ms');
    _service.fetchCoinBalance().then((newBalance) {
      if (!mounted || _roundId != settledRoundId) return;
      final balEnd = DateTime.now();
      final delta  = newBalance - (balanceBeforeSpin ?? _balance);
      debugPrint('[HungryCat] payout amount=$delta');
      debugPrint('[HungryCat] wallet updated coins=$newBalance');
      debugPrint('[HungryCatPerf] balance refresh end (post-result) duration=${balEnd.difference(balStart).inMilliseconds}ms');
      setState(() {
        _balance   = newBalance;
        _spinDelta = delta;
      });
    }).catchError((Object e) {
      debugPrint('[HungryCat] balance fetch after result: $e');
    });

    _service.getGlobalHistory().then((hist) {
      if (mounted && _roundId == settledRoundId) {
        setState(() => _history = hist.take(20).toList());
      }
    }).catchError((Object _) {});

    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    _loadNextRound();
  }

  Future<void> _runLandingAnimation(int target) async {
    final n    = _displayFoodCount;
    final dist = (target - _highlighted + n) % n;
    final steps = dist == 0 ? n : dist;

    for (int i = 0; i < steps; i++) {
      if (!mounted) return;
      final progress = i / steps;
      final ms = (70 + progress * 230).toInt();
      await Future.delayed(Duration(milliseconds: ms));
      if (!mounted) return;
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
      if (diff < best) { best = diff; idx = i; }
    }
    return idx;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Next round
  // ─────────────────────────────────────────────────────────────────────────

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

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  int get _displayFoodCount => _foods.isEmpty ? _kDefaultFoods.length : _foods.length;

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

  String _foodName(String foodId) {
    for (final f in _foods) {
      if (f.foodId == foodId) return f.name;
    }
    return foodId;
  }

  String _friendlyError(String e) {
    if (e.contains('insufficient_coins'))  return 'Insufficient coins';
    if (e.contains('game_disabled'))       return 'Game is currently disabled';
    if (e.contains('betting_closed'))      return 'Betting window has closed';
    if (e.contains('round_not_found'))     return 'Round not found — refreshing';
    if (e.contains('invalid_food'))        return 'Invalid food selection';
    if (e.contains('not_authenticated'))   return 'Please log in again';
    return 'Something went wrong. Please try again.';
  }

  String _friendlyErrorAr(String e) {
    if (e.contains('insufficient_coins'))  return 'رصيد غير كافٍ';
    if (e.contains('game_disabled'))       return 'اللعبة معطّلة حالياً';
    if (e.contains('betting_closed'))      return 'انتهى وقت الرهان';
    if (e.contains('round_not_found'))     return 'لم يُوجد الجولة — جارٍ التحديث';
    if (e.contains('invalid_food'))        return 'اختيار طعام غير صالح';
    if (e.contains('not_authenticated'))   return 'يرجى تسجيل الدخول من جديد';
    return 'حدث خطأ. حاول مجدداً.';
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatCoins(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    return '$v';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08030F),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 2),
          const Text('🐱', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _ar ? 'القط الجائع' : 'Hungry Cat',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (_roundNumber > 0)
                  Text(
                    _ar ? 'جولة #$_roundNumber' : 'Round #$_roundNumber',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (_reconnecting)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFF0C15A),
                ),
              ),
            ),
          _buildBalanceChip(),
        ],
      ),
    );
  }

  Widget _buildBalanceChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1A0A), Color(0xFF3D2610)],
        ),
        border: Border.all(
          color: const Color(0xFFF0C15A).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text(
            _formatCoins(_balance),
            style: const TextStyle(
              color: Color(0xFFF0C15A),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_phase == _Phase.loading) return _buildLoading();
    if (_phase == _Phase.error)   return _buildError();
    return Column(
      children: [
        _buildPhaseBar(),
        Expanded(child: _buildWheelArea()),
        _buildHistoryStrip(),
        SafeArea(
          top: false,
          child: _buildBottomControls(),
        ),
      ],
    );
  }

  // ── Phase label bar ───────────────────────────────────────────────────────

  Widget _buildPhaseBar() {
    String label;
    Color  bg;
    Color  fg;

    switch (_phase) {
      case _Phase.betting:
        final urgent = _secsLeft <= 5;
        label = _ar
            ? '${urgent ? '⚠️ ' : ''}الرهان مفتوح • $_secsLeft ث'
            : '${urgent ? '⚠️ ' : ''}Betting closes in ${_secsLeft}s';
        bg = urgent ? const Color(0xFF3D0A0A) : const Color(0xFF0D2B0D);
        fg = urgent ? const Color(0xFFFF5555) : const Color(0xFF4ADE80);
      case _Phase.spinning:
        label = _waitingForResult
            ? (_ar ? '⏳ جارٍ احتساب النتيجة...' : '⏳ Settling result...')
            : (_ar ? '🎰 جارٍ الدوران...' : '🎰 Spinning...');
        bg = const Color(0xFF1A1A3D);
        fg = const Color(0xFFA78BFA);
      case _Phase.settled:
        final icon = _winFoodIcon ?? '🍽️';
        final name = _winFoodName ?? '';
        final mult = _winMult != null
            ? (_winMult!.truncateToDouble() == _winMult
                ? '${_winMult!.toInt()}x'
                : '${_winMult}x')
            : '';
        if (_hasBets) {
          if (_spinDelta == null) {
            // Balance fetch still in flight — show winner without payout yet.
            label = _ar
                ? '🏆 $icon $name $mult'
                : '🏆 $icon $name $mult';
            bg = const Color(0xFF2A1A00);
            fg = const Color(0xFFF0C15A);
          } else {
            final won = _spinDelta! > 0;
            label = won
                ? (_ar
                    ? '🏆 $icon $name $mult • ربحت ${_formatCoins(_spinDelta!)} 🪙'
                    : '🏆 $icon $name $mult • Won +${_formatCoins(_spinDelta!)} 🪙')
                : (_ar
                    ? '❌ $icon $name $mult • خسرت ${_formatCoins(_totalBetAmount)} 🪙'
                    : '❌ $icon $name $mult • Lost -${_formatCoins(_totalBetAmount)} 🪙');
            bg = won ? const Color(0xFF0D2B0D) : const Color(0xFF2A1A00);
            fg = won ? const Color(0xFF4ADE80) : const Color(0xFFF0C15A);
          }
        } else {
          label = _ar
              ? '🏆 الفائز: $icon $name $mult'
              : '🏆 Winner: $icon $name $mult';
          bg = const Color(0xFF2A1A00);
          fg = const Color(0xFFF0C15A);
        }
      default:
        return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_phase == _Phase.spinning)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              ),
            ),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fg,
                fontSize: _phase == _Phase.betting && _secsLeft <= 5 ? 14 : 13,
                fontWeight: _phase == _Phase.betting && _secsLeft <= 5
                    ? FontWeight.w900
                    : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Wheel area ────────────────────────────────────────────────────────────

  Widget _buildWheelArea() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // Use the full available width/height; keep the wheel square.
        final size    = math.min(constraints.maxWidth, constraints.maxHeight);
        // orbit radius: 37% of size leaves safe padding on all sides.
        final radius  = size * 0.37;
        final catSize = size * 0.22;
        // bubble size: small enough to not overlap with 8 items.
        // Arc spacing per item = 2π*radius/8 ≈ 0.29*size; bubSize < that.
        final bubSize = size * 0.20;
        final center  = Offset(size / 2, size / 2);
        final n       = _displayFoodCount;

        return Center(
          child: SizedBox(
            width:  size,
            height: size,
            child:  Stack(
              clipBehavior: Clip.none, // allow slight label overflow without hard-clip
              children: [
                // Decorative ring behind the food items
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RingPainter(radius: radius),
                  ),
                ),
                // Food bubbles arranged in a circle
                for (int i = 0; i < n; i++)
                  _positionedBubble(i, n, center, radius, bubSize),
                // Cat face — exactly at center
                Positioned(
                  left:   center.dx - catSize / 2,
                  top:    center.dy - catSize / 2,
                  width:  catSize,
                  height: catSize,
                  child:  _buildCatCenter(catSize),
                ),
                // Result overlay (only during settled phase)
                if (_phase == _Phase.settled && _winFoodId != null)
                  Positioned.fill(child: _buildResultOverlay()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _positionedBubble(
    int i, int n, Offset center, double radius, double bubSize,
  ) {
    // Circular positioning: start at top (−π/2) and step evenly
    final angle = -math.pi / 2 + i * 2 * math.pi / n;
    final cx    = center.dx + math.cos(angle) * radius;
    final cy    = center.dy + math.sin(angle) * radius;

    final isActive = i == _highlighted;
    final isWinner = _phase == _Phase.settled && _winFoodId != null
        && i == _findWinnerIndex();
    final foodId     = i < _foods.length ? _foods[i].foodId : '';
    final pending    = foodId.isNotEmpty
        ? (_foodPendingCounts[foodId] ?? 0) : 0;
    // isBusy shows a spinner on the bubble when bets are in-flight,
    // but does NOT block tapping — canTap is independent of isBusy.
    final isBusy     = pending > 0;
    final isSelected = _betsByFood.containsKey(foodId) && foodId.isNotEmpty;
    final betAmount  = _betsByFood[foodId] ?? 0;

    // Always tappable during betting phase — no per-food blocking.
    final canTap = _phase == _Phase.betting && i < _foods.length;

    Widget bubble = AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) {
        final scale = isWinner ? _pulseAnim.value : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: _HungryCatBubble(
        emoji:       _emojiAt(i),
        multLabel:   _multLabelAt(i),
        size:        bubSize,
        isActive:    isActive,
        isWinner:    isWinner,
        isSelected:  isSelected,
        isBusy:      isBusy,
        betAmount:   betAmount,
        formatCoins: _formatCoins,
      ),
    );

    if (canTap) {
      bubble = GestureDetector(onTap: () => _tapFood(i), child: bubble);
    }

    return Positioned(
      // Center the bubble circle on the orbit point
      left:   cx - bubSize / 2,
      top:    cy - bubSize / 2,
      width:  bubSize,
      height: bubSize,
      child:  bubble,
    );
  }

  Widget _buildCatCenter(double size) {
    final spinning = _phase == _Phase.spinning;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF3D1C7E), Color(0xFF1A0533)],
        ),
        border: Border.all(
          color: spinning
              ? const Color(0xFFF0C15A).withValues(alpha: 0.7)
              : const Color(0xFF6D28D9).withValues(alpha: 0.6),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6)
                .withValues(alpha: spinning ? 0.5 : 0.25),
            blurRadius: spinning ? 24 : 12,
          ),
        ],
      ),
      child: Center(
        child: Text(
          spinning ? '😸' : '🐱',
          style: TextStyle(fontSize: size * 0.52),
        ),
      ),
    );
  }

  Widget _buildResultOverlay() {
    final icon = _winFoodIcon ?? '🍽️';
    final name = _winFoodName ?? '';
    final mult = _winMult != null
        ? (_winMult!.truncateToDouble() == _winMult
            ? '${_winMult!.toInt()}x'
            : '${_winMult}x')
        : '';
    final won = _spinDelta != null && _spinDelta! > 0;

    return IgnorePointer(
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: won
                  ? [const Color(0xFF0D2B0D), const Color(0xFF1A3D1A)]
                  : [const Color(0xFF2A1A00), const Color(0xFF3D2610)],
            ),
            border: Border.all(
              color: won
                  ? const Color(0xFF4ADE80)
                  : const Color(0xFFF0C15A),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (won
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFF0C15A))
                    .withValues(alpha: 0.35),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 38)),
              const SizedBox(height: 4),
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              if (mult.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  mult,
                  style: const TextStyle(
                    color: Color(0xFFF0C15A),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (_hasBets && _spinDelta != null) ...[
                Text(
                  _spinDelta! > 0
                      ? (_ar
                          ? '🎉 ربحت ${_formatCoins(_spinDelta!)} 🪙'
                          : '🎉 Won +${_formatCoins(_spinDelta!)} 🪙')
                      : (_ar
                          ? '❌ خسرت ${_formatCoins(_totalBetAmount)} 🪙'
                          : '❌ Lost -${_formatCoins(_totalBetAmount)} 🪙'),
                  style: TextStyle(
                    color: won
                        ? const Color(0xFF34D399)
                        : const Color(0xFFFF6B6B),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ] else if (!_hasBets) ...[
                Text(
                  _ar ? 'راهن في الجولة القادمة!' : 'Bet next round!',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── History strip ─────────────────────────────────────────────────────────

  Widget _buildHistoryStrip() {
    if (_history.isEmpty) return const SizedBox(height: 6);
    return SizedBox(
      height: 50,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: _history.length,
        itemBuilder: (ctx, i) {
          final h   = _history[i];
          final big = h.multiplier >= 20;
          return Container(
            margin: const EdgeInsets.only(right: 7, top: 4, bottom: 4),
            width: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: big
                  ? const Color(0xFFF0C15A).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: big
                    ? const Color(0xFFF0C15A).withValues(alpha: 0.5)
                    : Colors.white12,
              ),
            ),
            child: Center(
              child: Text(h.foodIcon, style: const TextStyle(fontSize: 20)),
            ),
          );
        },
      ),
    );
  }

  // ── Bottom controls ───────────────────────────────────────────────────────

  Widget _buildBottomControls() {
    final active = _phase == _Phase.betting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBetStatus(),
          const SizedBox(height: 8),
          _buildBetChips(locked: !active),
        ],
      ),
    );
  }

  Widget _buildBetStatus() {
    final totalPending = _foodPendingCounts.values
        .fold(0, (sum, c) => sum + c);

    if (totalPending > 0) {
      final label = totalPending == 1
          ? (_ar ? 'جارٍ إرسال الرهان...' : 'Placing bet...')
          : (_ar ? 'جارٍ إرسال $totalPending رهانات...'
                 : 'Placing $totalPending bets...');
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFFF0C15A),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFF0C15A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    if (_betsByFood.isNotEmpty) {
      final summary = _betsByFood.entries.map((e) {
        final name = _foodName(e.key);
        return '${_emojiForFoodId(e.key)} $name: ${_formatCoins(e.value)}🪙';
      }).join('  ');
      return Text(
        '✅ $summary',
        style: const TextStyle(
          color: Color(0xFF34D399),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    if (_phase == _Phase.betting) {
      return Text(
        _ar ? 'اضغط على طعام للمراهنة 👆' : 'Tap a food to bet 👆',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      );
    }

    return const SizedBox.shrink();
  }

  String _emojiForFoodId(String foodId) {
    for (final f in _foods) {
      if (f.foodId == foodId) return f.icon;
    }
    return '🍽️';
  }

  Widget _buildBetChips({required bool locked}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _kBetChips.map((chip) {
          final sel = chip == _betAmount;
          return GestureDetector(
            onTap: locked ? null : () => setState(() => _betAmount = chip),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: sel && !locked
                    ? const LinearGradient(
                        colors: [Color(0xFFF0C15A), Color(0xFFD4A017)],
                      )
                    : null,
                color: sel && !locked ? null : Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: sel && !locked
                      ? const Color(0xFFF0C15A)
                      : Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: Text(
                '${sel && !locked ? '🪙 ' : ''}${_formatCoins(chip)}',
                style: TextStyle(
                  color: sel && !locked
                      ? const Color(0xFF1A0533)
                      : Colors.white.withValues(alpha: locked ? 0.3 : 0.7),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Loading / Error ───────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🐱', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 18),
          const CircularProgressIndicator(
            color: Color(0xFFF0C15A), strokeWidth: 3,
          ),
          const SizedBox(height: 14),
          Text(
            _ar ? 'جارٍ التحميل...' : 'Loading...',
            style: const TextStyle(
              color: Color(0xFFF0C15A), fontSize: 15, fontWeight: FontWeight.w700,
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
            const Text('🐱', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            Text(
              _ar ? 'تعذّر تحميل اللعبة' : 'Failed to load',
              style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMsg ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6D28D9),
                foregroundColor: Colors.white,
              ),
              child: Text(_ar ? 'إعادة المحاولة' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bubble widget ─────────────────────────────────────────────────────────────
//
// All text (multiplier + bet badge) lives INSIDE the circle so the Positioned
// height = bubSize and bottom-row items never overflow the wheel Stack.

class _HungryCatBubble extends StatelessWidget {
  const _HungryCatBubble({
    required this.emoji,
    required this.multLabel,
    required this.size,
    required this.isActive,
    required this.isWinner,
    required this.isSelected,
    required this.isBusy,
    required this.betAmount,
    required this.formatCoins,
  });

  final String   emoji;
  final String   multLabel;
  final double   size;
  final bool     isActive;
  final bool     isWinner;
  final bool     isSelected;
  final bool     isBusy;
  final int      betAmount;
  final String Function(int) formatCoins;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = isWinner
        ? const Color(0xFF4ADE80)
        : isSelected
            ? const Color(0xFF34D399)
            : isActive
                ? const Color(0xFFF0C15A).withValues(alpha: 0.85)
                : const Color(0xFF4A1C8C).withValues(alpha: 0.55);

    final double labelFontSize = (size * 0.175).clamp(9.0, 14.0);
    final double emojiFontSize = (size * 0.36).clamp(18.0, 30.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width:  size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: (isActive || isSelected)
              ? [const Color(0xFF3D2610), const Color(0xFF2A1A00)]
              : [const Color(0xFF1E0D3E), const Color(0xFF130826)],
        ),
        border: Border.all(
          color: borderColor,
          width: (isActive || isSelected || isWinner) ? 2.5 : 1.5,
        ),
        boxShadow: (isActive || isSelected || isWinner)
            ? [
                BoxShadow(
                  color: (isWinner
                          ? const Color(0xFF4ADE80)
                          : isSelected
                              ? const Color(0xFF34D399)
                              : const Color(0xFFF0C15A))
                      .withValues(alpha: isWinner ? 0.7 : 0.45),
                  blurRadius: isWinner ? 20 : 12,
                  spreadRadius: isWinner ? 3 : 0,
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Emoji + multiplier stacked vertically inside the circle
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: TextStyle(fontSize: emojiFontSize)),
              Text(
                multLabel,
                style: TextStyle(
                  color: isWinner
                      ? const Color(0xFF4ADE80)
                      : isActive
                          ? const Color(0xFFF0C15A)
                          : Colors.white.withValues(alpha: 0.70),
                  fontSize: labelFontSize,
                  fontWeight: (isActive || isSelected || isWinner)
                      ? FontWeight.w900
                      : FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),

          // Busy spinner overlay
          if (isBusy)
            SizedBox(
              width:  size * 0.6,
              height: size * 0.6,
              child:  const CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF34D399),
              ),
            ),

          // Bet badge — gold pill at top-right of the circle
          if (betAmount > 0)
            Positioned(
              top:   size * 0.04,
              right: size * 0.04,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF0C15A), Color(0xFFD4A017)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  formatCoins(betAmount),
                  style: TextStyle(
                    color: const Color(0xFF1A0533),
                    fontSize: (size * 0.13).clamp(8.0, 11.0),
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Ring painter ──────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.radius});
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Outer halo glow band
    canvas.drawCircle(
      center, radius + 16,
      Paint()
        ..color = const Color(0xFF4C1D95).withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 32,
    );
    // Precise orbit ring
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = const Color(0xFF6D28D9).withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Inner ambient glow
    canvas.drawCircle(
      center, radius - 18,
      Paint()
        ..color = const Color(0xFF2E1065).withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 36,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.radius != radius;
}

// ── Sound service ─────────────────────────────────────────────────────────────
//
// Audio file paths (place files here to activate each sound):
//   assets/sounds/hcat_bet.wav          — played when a bet is confirmed
//   assets/sounds/hcat_tick.wav         — played each second during last-5 countdown
//   assets/sounds/hcat_spin.wav         — played when spinning begins
//   assets/sounds/hcat_win.wav          — played on win result
//   assets/sounds/hcat_lose.wav         — played on lose result
//
// Fallbacks (already bundled in the app):
//   bet   → assets/sounds/lucky_bag_open.mp3
//   win   → assets/sounds/lucky_bag_win.wav
//   (all others → silent no-op when file missing)

class _HungryCatSounds {
  final AudioPlayer _bet   = AudioPlayer();
  final AudioPlayer _tick  = AudioPlayer();
  final AudioPlayer _spin  = AudioPlayer();
  final AudioPlayer _win   = AudioPlayer();
  final AudioPlayer _lose  = AudioPlayer();

  /// Attempt to load each audio player. Any individual failure is silenced.
  Future<void> init() async {
    await _tryLoad(_bet,  'assets/sounds/hcat_bet.wav',
        fallback: 'assets/sounds/lucky_bag_open.mp3');
    await _tryLoad(_tick,  'assets/sounds/hcat_tick.wav');
    await _tryLoad(_spin,  'assets/sounds/hcat_spin.wav',
        fallback: 'assets/sounds/lucky_bag_open.mp3');
    await _tryLoad(_win,   'assets/sounds/hcat_win.wav',
        fallback: 'assets/sounds/lucky_bag_win.wav');
    await _tryLoad(_lose,  'assets/sounds/hcat_lose.wav');
  }

  Future<void> _tryLoad(AudioPlayer player, String path, {String? fallback}) async {
    try {
      await player.setAsset(path);
    } catch (_) {
      if (fallback != null) {
        try { await player.setAsset(fallback); } catch (_) {}
      }
    }
  }

  void _play(AudioPlayer player) {
    try {
      player.seek(Duration.zero);
      player.play();
    } catch (_) {}
  }

  void playBetPlaced()    => _play(_bet);
  void playCountdownTick() => _play(_tick);
  void playSpinStart()    => _play(_spin);
  void playWin()          => _play(_win);
  void playLose()         => _play(_lose);

  void dispose() {
    _bet.dispose();
    _tick.dispose();
    _spin.dispose();
    _win.dispose();
    _lose.dispose();
  }
}
