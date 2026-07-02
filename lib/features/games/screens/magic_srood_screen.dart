import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:srood_live/shared/utils/error_utils.dart';
import 'package:srood_live/shared/widgets/coin_ui.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/hungry_cat_models.dart';
import '../services/game_sound_service.dart';
import '../services/magic_srood_client_logic.dart';
import '../services/magic_srood_service.dart';

// ── Theme ─────────────────────────────────────────────────────────────────────
const _kGold = Color(0xFFFFCC00);
const _kGoldLight = Color(0xFFFFE566);
const _kGoldDark = Color(0xFFB8860B);
const _kGoldDim = Color(0xFF7A5C00);
const _kCream = Color(0xFFFFF8E0);
const _kRedAccent = Color(0xFFFF3333);
const _kBlueGlow = Color(0xFF00AAFF);
const _kGreenWin = Color(0xFF22CC55);
const _kTextDim = Color(0xFF8A7A50);

// Visual placeholders only. They are never valid betting configuration.
const _kDefaultItems = [
  (id: 'spain', name: 'Spain', nameAr: 'إسبانيا', icon: '🇪🇸', mult: 2.0),
  (id: 'italy', name: 'Italy', nameAr: 'إيطاليا', icon: '🇮🇹', mult: 3.0),
  (
    id: 'portugal',
    name: 'Portugal',
    nameAr: 'البرتغال',
    icon: '🇵🇹',
    mult: 12.0,
  ),
  (
    id: 'argentina',
    name: 'Argentina',
    nameAr: 'الأرجنتين',
    icon: '🇦🇷',
    mult: 200.0,
  ),
  (id: 'germany', name: 'Germany', nameAr: 'ألمانيا', icon: '🇩🇪', mult: 40.0),
  (id: 'england', name: 'England', nameAr: 'إنجلترا', icon: '🇬🇧', mult: 40.0),
  (id: 'brazil', name: 'Brazil', nameAr: 'البرازيل', icon: '🇧🇷', mult: 160.0),
  (id: 'france', name: 'France', nameAr: 'فرنسا', icon: '🇫🇷', mult: 16.0),
];

const _kBetChips = [100, 1000, 5000, 10000, 20000, 100000];

enum _Phase { loading, betting, spinning, settled, error }

class MagicSroodScreen extends StatefulWidget {
  const MagicSroodScreen({
    required this.isArabic,
    this.service = const MagicSroodService(),
    super.key,
  });
  final bool isArabic;
  final MagicSroodService service;

  @override
  State<MagicSroodScreen> createState() => _MagicSroodScreenState();
}

class _MagicSroodScreenState extends State<MagicSroodScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _service = widget.service;
  late final GameSoundService _sounds;

  List<HungryCatFood> _items = [];
  int _balance = 0;
  List<HungryCatHistoryEntry> _history = [];

  _Phase _phase = _Phase.loading;
  String? _roundId;
  int _roundNumber = 0;
  DateTime? _bettingEndsAt;
  Duration _clockOffset = Duration.zero;
  int _secsLeft = 0;

  String? _winItemId;
  String? _winItemIcon;
  String? _winItemName;
  double? _winMult;

  Map<String, int> _betsByItem = {};
  Map<String, int> _itemPendingCounts = {};
  int _betSeq = 0;
  int _lastAppliedBalanceSeq = 0;
  int _authoritativeBalanceVersion = 0;
  int _betAmount = 100;

  int? _balanceBeforeSpin;
  int? _spinDelta;

  int _highlighted = 0;
  bool _settling = false;
  bool _waitingForResult = false;
  String? _errorMsg;
  bool _reconnecting = false;
  bool _placingBet = false;
  bool _loadingGame = false;
  bool _configAvailable = false;

  Map<String, int> _teamTotals = {};
  bool _followPrevious = false;
  int _selectedTab = 0; // 0=My Bets, 1=All Users, 2=Popularity
  String? _prevWinnerId;

  // Inline warning shown near chips instead of covering the balance row.
  String? _betWarning;
  Timer? _betWarningTimer;

  // Slot-machine display for last round results
  final List<String> _slotNums = ['?', '?', '?', '?', '?', '?'];

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _breathCtrl;
  late Animation<double> _breathAnim;
  late AnimationController _progressCtrl;
  late AnimationController _coinCtrl;
  late AnimationController _resultSlideCtrl;
  late Animation<Offset> _resultSlideAnim;
  late AnimationController _slotCtrl;

  RealtimeChannel? _channel;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _countdownTimer;
  Timer? _resultPollTimer;
  Timer? _balanceDebounceTimer;
  Timer? _autoAdvanceTimer;

  static bool _globalMuted = false;
  bool get _muted => _globalMuted;
  bool get _ar => widget.isArabic;
  bool get _isCompactWidth => MediaQuery.sizeOf(context).width < 380;

  double _responsiveFont(double normal, double compact) {
    return _isCompactWidth ? compact : normal;
  }

  bool get _hasBets => _betsByItem.isNotEmpty;
  bool get _hasActiveBets =>
      _hasBets && (_phase == _Phase.betting || _phase == _Phase.spinning);
  int get _totalBetAmount => _betsByItem.values.fold(0, (s, v) => s + v);
  int get _displayCount =>
      _items.isEmpty ? _kDefaultItems.length : _items.length;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sounds = GameSoundService(
      tag: 'MagicSroodSounds',
      tickAsset: 'assets/sounds/coin_rain.wav',
      preloadEvent: 'bet',
      events: const {
        'bet': GameSound('assets/sounds/lucky_bag_open.mp3'),
        'spin': GameSound('assets/sounds/lucky_bag_open.mp3'),
        'win': GameSound('assets/sounds/lucky_bag_win.wav'),
        'lose': GameSound('assets/sounds/lucky_bag_open.mp3'),
      },
    );
    _sounds.init();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.40,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _breathAnim = Tween<double>(
      begin: 0.97,
      end: 1.03,
    ).animate(CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut));

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _coinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _resultSlideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _resultSlideAnim =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
          CurvedAnimation(parent: _resultSlideCtrl, curve: Curves.easeOutCubic),
        );

    _slotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
    _betWarningTimer?.cancel();
    _channel?.unsubscribe();
    _pulseCtrl.dispose();
    _breathCtrl.dispose();
    _progressCtrl.dispose();
    _coinCtrl.dispose();
    _resultSlideCtrl.dispose();
    _slotCtrl.dispose();
    _sounds.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadGame(showLoading: false);
    }
  }

  // ── Data ─────────────────────────────────────────────────────────────────────

  Future<void> _loadGame({bool showLoading = true}) async {
    if (_loadingGame) return;
    _loadingGame = true;
    if (showLoading) {
      setState(() {
        _phase = _Phase.loading;
        _errorMsg = null;
        _configAvailable = false;
      });
    } else {
      setState(() => _configAvailable = false);
    }
    try {
      List<HungryCatFood> serverItems;
      try {
        serverItems = await _service.fetchItemConfig();
      } catch (e, st) {
        debugError('[MagicSrood] loadConfig', e, st);
        _showConfigUnavailable();
        return;
      }
      if (!mounted) return;
      if (serverItems.isEmpty) {
        _showConfigUnavailable();
        return;
      }
      setState(() {
        _items = serverItems;
        _configAvailable = true;
      });

      // Config is authoritative; remaining account data can load in parallel.
      final results = await Future.wait([
        _service.fetchCoinBalance(),
        _service.getGlobalHistory(),
      ]);
      if (!mounted) return;
      _balance = results[0] as int;
      _authoritativeBalanceVersion++;
      _history = (results[1] as List<HungryCatHistoryEntry>).take(20).toList();

      // Get round last — minimises time between round creation and betting start
      final round = await _service.getOrCreateRound();
      if (!mounted) return;
      final isSameRound = _roundId == round.roundId;
      final serverBets = await _service.getMyRoundBets(round.roundId);
      if (!mounted) return;
      _applyRound(round, preserveBets: isSameRound, serverBets: serverBets);
      _subscribeToRound(round.roundId);
    } catch (e, st) {
      debugError('[MagicSrood] loadGame', e, st);
      if (!mounted) return;
      if (showLoading) {
        setState(() {
          _phase = _Phase.error;
          _errorMsg = '$e';
        });
      } else {
        setState(() => _reconnecting = true);
      }
    } finally {
      _loadingGame = false;
    }
  }

  void _showConfigUnavailable() {
    if (!mounted) return;
    setState(() {
      _items = [];
      _configAvailable = false;
      _phase = _Phase.error;
      _errorMsg = _ar
          ? 'إعدادات الفرق غير متاحة حالياً. حاول مرة أخرى لاحقاً.'
          : 'Team configuration is currently unavailable. Please try again later.';
    });
  }

  void _applyRound(
    HungryCatGlobalRound round, {
    bool preserveBets = false,
    Map<String, int>? serverBets,
  }) {
    final previousRoundId = _roundId;
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
    _winItemId = null;
    _winItemIcon = null;
    _winItemName = null;
    _winMult = null;
    if (!preserveBets) {
      _itemPendingCounts = {};
      _betSeq = 0;
      _lastAppliedBalanceSeq = 0;
    }
    _betsByItem = reconcileMagicSroodVisibleBets(
      currentRoundId: previousRoundId,
      nextRoundId: round.roundId,
      currentBets: _betsByItem,
      serverBets: serverBets,
    );
    _balanceBeforeSpin = null;
    _spinDelta = null;

    _teamTotals = {};

    if (round.isSettled) {
      _winItemId = round.winningFoodId;
      _winItemIcon = round.winningFoodIcon;
      _winItemName = round.winningFoodName;
      _winMult = round.winningMultiplier;
      _prevWinnerId = round.winningFoodId;
      _updateSlotDisplay(round.winningMultiplier);
      setState(() => _phase = _Phase.settled);
      _startAutoAdvance(delay: 4);
    } else {
      final left = round.bettingEndsAt.difference(
        DateTime.now().toUtc().add(_clockOffset),
      );
      _secsLeft = left.inSeconds.clamp(0, 30);
      setState(() => _phase = _Phase.betting);
      _startCountdown();
      _loadTeamTotals();
      if (_followPrevious && _prevWinnerId != null) _autoFollowPrevious();
    }
  }

  void _autoFollowPrevious() {
    final idx = _items.indexWhere((f) => f.foodId == _prevWinnerId);
    if (idx < 0) return;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _phase == _Phase.betting) _tapItem(idx);
    });
  }

  void _updateSlotDisplay(double? mult) {
    if (mult == null) return;
    final s = mult.truncateToDouble() == mult
        ? mult.toInt().toString()
        : mult.toStringAsFixed(1);
    final digits = s.padLeft(6, ' ').characters.toList();
    setState(() {
      for (int i = 0; i < 6; i++) {
        _slotNums[i] = i < digits.length ? digits[i].trim() : '0';
      }
    });
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = _bettingEndsAt!
          .difference(DateTime.now().toUtc().add(_clockOffset))
          .inSeconds;
      if (left <= 0) {
        t.cancel();
        setState(() => _secsLeft = 0);
        _triggerSettle();
      } else {
        if (left <= 5) _sounds.playTick();
        setState(() => _secsLeft = left);
      }
    });
  }

  // ── Realtime ─────────────────────────────────────────────────────────────────

  void _subscribeToRound(String roundId) {
    _reconnectTimer?.cancel();
    _channel?.unsubscribe();
    setState(() => _reconnecting = false);
    _channel = SupabaseService.requiredClient
        .channel('msrood_$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'magic_srood_global_rounds',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roundId,
          ),
          callback: _onRoundUpdate,
        )
        .subscribe((status, [err]) {
          if (!mounted) return;
          if (isMagicSroodRealtimeUnhealthy(status)) {
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
      _reconnectAttempts = 0;
      _loadGame();
      return;
    }
    _reconnectTimer = Timer(Duration(seconds: _reconnectAttempts * 2), () {
      if (mounted) _subscribeToRound(roundId);
    });
  }

  void _onRoundUpdate(PostgresChangePayload payload) {
    if (!mounted) return;
    final row = payload.newRecord;
    if (row['status'] != 'settled') return;
    final foodId = row['winning_food_id']?.toString();
    final foodIcon = row['winning_food_icon']?.toString();
    final foodName = row['winning_food_name']?.toString();
    final rawMult = row['winning_multiplier'];
    final mult = rawMult is num
        ? rawMult.toDouble()
        : double.tryParse(rawMult?.toString() ?? '');
    if (foodId == null ||
        foodId.isEmpty ||
        mult == null ||
        !mult.isFinite ||
        mult <= 0) {
      debugPrint('[MagicSrood] Ignoring malformed settled-round update');
      return;
    }
    if (_winItemId == null) _applyWinner(foodId, foodIcon, foodName, mult);
  }

  // ── Betting ──────────────────────────────────────────────────────────────────

  Future<void> _tapItem(int index) async {
    if (_phase != _Phase.betting ||
        _placingBet ||
        !_configAvailable ||
        _items.isEmpty ||
        index >= _items.length) {
      return;
    }
    final foodId = _idAt(index);
    final teamIcon = _iconAt(index);
    final betAmount = _betAmount;
    if (_balance < betAmount) {
      _showBetWarning(_ar ? 'رصيد غير كافٍ' : 'Insufficient coins');
      return;
    }
    _betSeq++;
    final mySeq = _betSeq;
    final balanceVersionAtStart = _authoritativeBalanceVersion;
    HapticFeedback.lightImpact();
    setState(() {
      _placingBet = true;
      _balance -= betAmount;
      _itemPendingCounts[foodId] = (_itemPendingCounts[foodId] ?? 0) + 1;
    });
    try {
      final result = await _service.placeGlobalBet(
        roundId: _roundId!,
        foodId: foodId,
        amount: betAmount,
      );
      if (!mounted) return;
      HapticFeedback.selectionClick();
      _sounds.playEvent('bet');
      setState(() {
        if (mySeq >= _lastAppliedBalanceSeq) {
          _lastAppliedBalanceSeq = mySeq;
          _balance = result.newBalance;
          _authoritativeBalanceVersion++;
        }
        _betsByItem[foodId] = (_betsByItem[foodId] ?? 0) + betAmount;
        _decrementPending(foodId);
      });
      _showSnack(
        '$teamIcon ${_ar ? 'تم الرهان' : 'Bet placed'}: ${_formatCoins(betAmount)} 🪙',
        type: SroodToastType.success,
      );
      _scheduleDebouncedBalanceRefresh();
      _loadTeamTotals();
    } on PostgrestException catch (e, st) {
      if (!mounted) return;
      _rollbackFailedBet(
        foodId: foodId,
        amount: betAmount,
        balanceVersionAtStart: balanceVersionAtStart,
      );
      // Log the real Supabase error for debugging
      debugPrint('[MagicSrood] Bet RPC ERROR');
      debugPrint('  code   : ${e.code}');
      debugPrint('  message: ${e.message}');
      debugPrint('  details: ${e.details}');
      debugPrint('  hint   : ${e.hint}');
      debugPrint(
        '  payload: roundId=$_roundId foodId=$foodId amount=$betAmount userId=${SupabaseService.requiredClient.auth.currentUser?.id}',
      );
      debugPrintStack(stackTrace: st, label: 'MagicSrood._tapItem');
      // Build a combined lookup string from all Postgres error fields
      final errStr = '${e.code} ${e.message} ${e.details} ${e.hint}'
          .toLowerCase();
      if (errStr.contains('duplicate_bet')) {
        _showSnack(
          _ar ? 'تم تسجيل هذا الرهان مسبقاً' : 'This bet was already recorded',
          type: SroodToastType.info,
        );
        return;
      }
      if (errStr.contains('betting_still_open')) {
        _showSnack(
          _ar
              ? 'الرهان ما زال مفتوحاً. حاول مجدداً'
              : 'Betting is still open. Please try again.',
          type: SroodToastType.info,
        );
        return;
      }
      if (errStr.contains('betting_closed')) {
        _showSnack(
          _ar ? 'انتهت الجولة، جارٍ التحديث...' : 'Round closed, refreshing…',
          type: SroodToastType.info,
        );
        _loadGame();
        return;
      }
      _showSnack(
        _ar ? _friendlyAr(errStr) : _friendly(errStr),
        type: _toastType(errStr),
      );
    } catch (e, st) {
      if (!mounted) return;
      _rollbackFailedBet(
        foodId: foodId,
        amount: betAmount,
        balanceVersionAtStart: balanceVersionAtStart,
      );
      debugPrint('[MagicSrood] Bet unexpected ERROR: $e');
      debugPrintStack(stackTrace: st, label: 'MagicSrood._tapItem');
      final errStr = '$e'.toLowerCase();
      if (errStr.contains('betting_closed')) {
        _showSnack(
          _ar ? 'انتهت الجولة، جارٍ التحديث...' : 'Round closed, refreshing…',
          type: SroodToastType.info,
        );
        _loadGame();
        return;
      }
      _showSnack(
        _ar ? _friendlyAr(errStr) : _friendly(errStr),
        type: _toastType(errStr),
      );
    } finally {
      if (mounted) {
        setState(() => _placingBet = false);
      }
    }
  }

  void _rollbackFailedBet({
    required String foodId,
    required int amount,
    required int balanceVersionAtStart,
  }) {
    setState(() {
      if (shouldRollbackMagicSroodBalance(
        balanceVersionAtStart: balanceVersionAtStart,
        currentBalanceVersion: _authoritativeBalanceVersion,
      )) {
        _balance += amount;
      }
      _decrementPending(foodId);
    });
    unawaited(_refreshBalance());
  }

  void _decrementPending(String id) {
    final p = (_itemPendingCounts[id] ?? 1) - 1;
    if (p <= 0) {
      _itemPendingCounts.remove(id);
    } else {
      _itemPendingCounts[id] = p;
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
    final requestedAtVersion = _authoritativeBalanceVersion;
    try {
      final bal = await _service.fetchCoinBalance();
      if (mounted && _authoritativeBalanceVersion == requestedAtVersion) {
        setState(() {
          _balance = bal;
          _authoritativeBalanceVersion++;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadTeamTotals() async {
    if (_roundId == null) return;
    try {
      final t = await _service.getTeamBetTotals(_roundId!);
      if (mounted) setState(() => _teamTotals = t);
    } catch (_) {}
  }

  // ── Settle ───────────────────────────────────────────────────────────────────

  Future<void> _triggerSettle() async {
    if (_settling || _phase != _Phase.betting) return;
    _settling = true;
    _balanceBeforeSpin = _balance;
    setState(() => _phase = _Phase.spinning);
    _sounds.playEvent('spin');
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
    } catch (e) {
      debugPrint('[MagicSrood] settle RPC: $e');
    }
  }

  void _startResultPoll() {
    _resultPollTimer?.cancel();
    final pollRoundId = _roundId;
    if (pollRoundId == null) return;
    _schedulePoll(pollRoundId, attempt: 0);
  }

  void _schedulePoll(String pollRoundId, {required int attempt}) {
    final ms = switch (attempt) {
      0 || 1 || 2 || 3 => 500,
      4 || 5 => 1000,
      6 || 7 => 2000,
      _ => 4000,
    };
    _resultPollTimer = Timer(Duration(milliseconds: ms), () async {
      if (!mounted || _winItemId != null || _phase != _Phase.spinning) return;
      try {
        final round = await _service.settleGlobalRound(pollRoundId);
        if (!mounted) return;
        if (round.isSettled && _winItemId == null) {
          _applyWinner(
            round.winningFoodId,
            round.winningFoodIcon,
            round.winningFoodName,
            round.winningMultiplier,
          );
          return;
        }
      } catch (e) {
        debugPrint('[MagicSrood] poll $attempt: $e');
      }
      if (!mounted || _winItemId != null || _phase != _Phase.spinning) return;
      _schedulePoll(pollRoundId, attempt: attempt + 1);
    });
  }

  void _applyWinner(String? id, String? icon, String? name, double? mult) {
    _winItemId = id;
    _winItemIcon = icon;
    _winItemName = name;
    _winMult = mult;
    _prevWinnerId = id;
  }

  // ── Spin animation ────────────────────────────────────────────────────────────

  Future<void> _runFreeSpin() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    final settlingAfter = DateTime.now().add(const Duration(seconds: 6));
    while (mounted && _winItemId == null && _phase == _Phase.spinning) {
      if (DateTime.now().isAfter(deadline)) {
        if (mounted) {
          setState(() {
            _phase = _Phase.error;
            _errorMsg = _ar ? 'تأخر في النتيجة' : 'Result timeout';
          });
        }
        return;
      }
      if (!_waitingForResult && DateTime.now().isAfter(settlingAfter)) {
        if (mounted) setState(() => _waitingForResult = true);
      }
      await Future.delayed(const Duration(milliseconds: 48));
      if (!mounted || _phase != _Phase.spinning) return;
      setState(() => _highlighted = (_highlighted + 1) % _displayCount);
    }
    if (!mounted || _phase != _Phase.spinning) return;
    _resultPollTimer?.cancel();
    _waitingForResult = false;
    final target = _findWinnerIndex();
    await _runLandingAnimation(target);
    if (!mounted) return;

    final won = _betsByItem.containsKey(_winItemId);
    if (won) {
      _sounds.playEvent('win');
      HapticFeedback.heavyImpact();
      _coinCtrl.reset();
      _coinCtrl.forward();
    } else if (_hasBets) {
      _sounds.playEvent('lose');
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
    _updateSlotDisplay(_winMult);
    _resultSlideCtrl.reset();
    _resultSlideCtrl.forward();
    setState(() => _phase = _Phase.settled);

    final settledRoundId = _roundId;
    final prevBal = _balanceBeforeSpin;
    _service
        .fetchCoinBalance()
        .then((b) {
          if (!mounted || _roundId != settledRoundId) return;
          setState(() {
            _balance = b;
            _authoritativeBalanceVersion++;
            _spinDelta = b - (prevBal ?? _balance);
          });
        })
        .catchError((Object _) {});
    _service
        .getGlobalHistory()
        .then((h) {
          if (mounted && _roundId == settledRoundId) {
            setState(() => _history = h.take(20).toList());
          }
        })
        .catchError((Object _) {});
    _startAutoAdvance(delay: 4);
  }

  Future<void> _runLandingAnimation(int target) async {
    final n = _displayCount;
    for (int r = 0; r < n * 2; r++) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 48));
      if (!mounted) return;
      setState(() => _highlighted = (_highlighted + 1) % n);
    }
    final dist = (target - _highlighted + n) % n;
    final steps = dist == 0 ? n : dist;
    for (int i = 0; i < steps; i++) {
      if (!mounted) return;
      final t = i / steps;
      final ms = (55 + t * t * 365).toInt();
      await Future.delayed(Duration(milliseconds: ms));
      if (!mounted) return;
      if (i >= steps - 4) HapticFeedback.selectionClick();
      setState(() => _highlighted = (_highlighted + 1) % n);
    }
  }

  int _findWinnerIndex() {
    if (_winItemId == null) return _highlighted;
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].foodId == _winItemId) return i;
    }
    return _highlighted;
  }

  Future<void> _loadNextRound() async {
    if (!mounted) return;
    try {
      final round = await _service.getOrCreateRound();
      if (!mounted) return;
      _subscribeToRound(round.roundId);
      _applyRound(round);
    } catch (e) {
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

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _iconAt(int i) => i < _items.length
      ? _items[i].icon
      : _kDefaultItems[i % _kDefaultItems.length].icon;
  String _nameAt(int i) {
    if (i < _items.length) {
      if (_ar) {
        final id = _items[i].foodId;
        final d = _kDefaultItems.where((x) => x.id == id).firstOrNull;
        if (d != null) return d.nameAr;
      }
      return _items[i].name;
    }
    final d = _kDefaultItems[i % _kDefaultItems.length];
    return _ar ? d.nameAr : d.name;
  }

  String _multLabelAt(int i) {
    final m = i < _items.length
        ? _items[i].multiplier
        : _kDefaultItems[i % _kDefaultItems.length].mult;
    final v = m.truncateToDouble() == m
        ? m.toInt().toString()
        : m.toStringAsFixed(1);
    return 'x$v';
  }

  String _rarityAt(int i) {
    if (i < _items.length) return _items[i].rarity;
    final multiplier = _kDefaultItems[i % _kDefaultItems.length].mult;
    if (multiplier >= 100) return 'legendary';
    if (multiplier >= 30) return 'epic';
    if (multiplier >= 10) return 'rare';
    if (multiplier >= 3) return 'uncommon';
    return 'common';
  }

  String _idAt(int i) => i < _items.length
      ? _items[i].foodId
      : _kDefaultItems[i % _kDefaultItems.length].id;

  // Delegates to the shared formatter so every coin label in the app is
  // identical (avoids "1.0M" vs "1M" drift that the old inline version had).
  String _formatCoins(int v) => formatCoinAmount(v);

  String _friendly(String e) {
    final rejection = magicSroodBetRejectionMessage(e, isArabic: false);
    if (rejection != null) return rejection;
    if (e.contains('insufficient') ||
        e.contains('not enough') ||
        e.contains('balance')) {
      return 'Insufficient coins';
    }
    if (e.contains('game_disabled') || e.contains('game is disabled')) {
      return 'Game is currently disabled';
    }
    if (e.contains('betting_closed') ||
        e.contains('round_not_found') ||
        e.contains('no active round')) {
      return 'Betting window has closed';
    }
    if (e.contains('invalid_food')) {
      return 'This team is unavailable. Please refresh the game.';
    }
    if (e.contains('duplicate') ||
        e.contains('already placed') ||
        e.contains('unique')) {
      return 'You already placed a bet on this team';
    }
    if (e.contains('not_authenticated') ||
        e.contains('jwt') ||
        e.contains('unauthorized') ||
        e.contains('42501')) {
      return 'Session expired — please log in again';
    }
    if (e.contains('socket') ||
        e.contains('network') ||
        e.contains('connection') ||
        e.contains('timeout')) {
      return 'Connection error — check your internet';
    }
    if (e.contains('invalid_bet_amount') ||
        e.contains('invalid_amount') ||
        e.contains('min_bet') ||
        e.contains('max_bet')) {
      return 'Invalid bet amount';
    }
    if (e.contains('round_locked') || e.contains('locked')) {
      return 'Round is locked — please wait for the next one';
    }
    if (e.contains('42p01') ||
        e.contains('does not exist') ||
        e.contains('undefined function')) {
      return 'Game feature unavailable — contact support';
    }
    return 'Something went wrong. Please try again.';
  }

  String _friendlyAr(String e) {
    final rejection = magicSroodBetRejectionMessage(e, isArabic: true);
    if (rejection != null) return rejection;
    if (e.contains('insufficient') ||
        e.contains('not enough') ||
        e.contains('balance')) {
      return 'رصيد غير كافٍ';
    }
    if (e.contains('game_disabled') || e.contains('game is disabled')) {
      return 'اللعبة معطّلة حالياً';
    }
    if (e.contains('betting_closed') ||
        e.contains('round_not_found') ||
        e.contains('no active round')) {
      return 'انتهى وقت الرهان';
    }
    if (e.contains('invalid_food')) {
      return 'هذا الفريق غير متاح. حدّث اللعبة وحاول مجدداً';
    }
    if (e.contains('duplicate') ||
        e.contains('already placed') ||
        e.contains('unique')) {
      return 'لقد راهنت على هذا الفريق مسبقاً';
    }
    if (e.contains('not_authenticated') ||
        e.contains('jwt') ||
        e.contains('unauthorized') ||
        e.contains('42501')) {
      return 'انتهت جلستك — سجّل الدخول مجدداً';
    }
    if (e.contains('socket') ||
        e.contains('network') ||
        e.contains('connection') ||
        e.contains('timeout')) {
      return 'خطأ في الاتصال بالإنترنت';
    }
    if (e.contains('invalid_bet_amount') ||
        e.contains('invalid_amount') ||
        e.contains('min_bet') ||
        e.contains('max_bet')) {
      return 'مبلغ الرهان غير صالح';
    }
    if (e.contains('round_locked') || e.contains('locked')) {
      return 'الجولة مقفلة — انتظر الجولة التالية';
    }
    if (e.contains('42p01') ||
        e.contains('does not exist') ||
        e.contains('undefined function')) {
      return 'الميزة غير متاحة — تواصل مع الدعم';
    }
    return 'حدث خطأ. حاول مجدداً.';
  }

  SroodToastType _toastType(String e) {
    if (e.contains('insufficient') ||
        e.contains('not enough') ||
        e.contains('balance') ||
        e.contains('invalid_bet_amount') ||
        e.contains('invalid_amount') ||
        e.contains('min_bet') ||
        e.contains('max_bet') ||
        e.contains('invalid_food')) {
      return SroodToastType.warning;
    }
    if (e.contains('game_disabled') ||
        e.contains('round_locked') ||
        e.contains('locked') ||
        e.contains('duplicate') ||
        e.contains('already placed')) {
      return SroodToastType.info;
    }
    return SroodToastType.error;
  }

  void _showSnack(String msg, {SroodToastType type = SroodToastType.error}) {
    if (!mounted) return;
    SroodToast.show(context, msg, type: type);
  }

  /// Shows a compact inline warning near the bet chips instead of a bottom
  /// toast that would cover the balance row.
  void _showBetWarning(String msg) {
    if (!mounted) return;
    _betWarningTimer?.cancel();
    setState(() => _betWarning = msg);
    _betWarningTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _betWarning = null);
    });
  }

  Future<bool> _showLeaveDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF2A1A00),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: _kGoldDark),
            ),
            title: Text(
              _ar ? 'مغادرة اللعبة؟' : 'Leave game?',
              style: const TextStyle(
                color: _kGold,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              _ar
                  ? 'الرهانات المعلقة ستظل صالحة.'
                  : 'Your pending bets remain valid.',
              style: const TextStyle(color: _kTextDim),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  _ar ? 'البقاء' : 'Stay',
                  style: const TextStyle(color: _kTextDim),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  _ar ? 'مغادرة' : 'Leave',
                  style: const TextStyle(
                    color: _kRedAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_hasActiveBets,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final confirmed = await _showLeaveDialog();
        if (confirmed && mounted) nav.pop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF05040D),
                      Color(0xFF05040D),
                      Color(0xFF5A3100),
                      Color(0xFF271000),
                    ],
                    stops: [0.0, 0.19, 0.42, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _StadiumLightPainter()),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  if (_phase == _Phase.loading || _phase == _Phase.error)
                    Expanded(child: _buildMainArena())
                  else ...[
                    _buildGameActions(),
                    _buildRoundLabel(),
                    Expanded(child: _buildMainArena()),
                    _buildHistoryStrip(),
                    _buildBottomControls(),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
            if (_reconnecting) _buildReconnectOverlay(),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    const maxCoins = 1000000;
    final progress = (_balance / maxCoins).clamp(0.0, 1.0);
    final todayWin = (_spinDelta != null && _spinDelta! > 0) ? _spinDelta! : 0;
    return Container(
      color: const Color(0xFF05040D),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF242331),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white70,
                        size: 34,
                      ),
                    ),
                  ),
                ),
                const Text(
                  'UEFA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _refreshBalance,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const AppCoinIcon(size: 18),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _formatCoins(_balance),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white38,
                            size: 18,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 118,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              _kGold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _isCompactWidth ? 104 : 140,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: const Color(0xFF242331),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        color: todayWin > 0 ? _kGreenWin : Colors.white38,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatCoins(todayWin),
                            maxLines: 1,
                            style: TextStyle(
                              color: todayWin > 0 ? _kGreenWin : Colors.white60,
                              fontSize: _responsiveFont(14, 12),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGameActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 0),
      child: Row(
        children: [
          _mkBtn(
            _muted ? Icons.music_off_rounded : Icons.music_note_rounded,
            () => setState(() {
              _globalMuted = !_globalMuted;
              _sounds.muted = _globalMuted;
            }),
          ),
          const Spacer(),
          _mkBtn(Icons.more_vert_rounded, () {}),
        ],
      ),
    );
  }

  // ── Round label ───────────────────────────────────────────────────────────────

  Widget _buildRoundLabel() {
    if (_phase == _Phase.loading || _phase == _Phase.error) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        _ar ? 'الجولة الحالية $_roundNumber' : 'Current Round $_roundNumber',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _kCream,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
        ),
      ),
    );
  }

  Widget _mkBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black54,
        border: Border.all(color: _kGoldDark.withValues(alpha: 0.7)),
      ),
      child: Icon(icon, color: _kGold, size: 16),
    ),
  );

  // ── Main arena ────────────────────────────────────────────────────────────────
  //
  // Layout matches the reference screenshot:
  //   Row 1 (flex 22): [Brazil 6]          [Argentina 3]
  //   Row 2 (flex 34): [Germany 4] [CENTER] [England 5]
  //                    [Portugal 2][CENTER] [France 7]
  //   Row 3 (same H):  [Spain 0]            [Italy 1]
  //
  // All 4 card rows share the same computed height so every card square is
  // identical.  The equation is:
  //   arenaH = 4×cardH + 4 (gap below top) + 5 (mid spacer) + 4 (gap above bot)
  //   cardH  = (arenaH − 13) / 4

  Widget _buildMainArena() {
    if (_phase == _Phase.loading) return _buildLoading();
    if (_phase == _Phase.error) return _buildError();

    final n = _displayCount;
    if (n < 8) {
      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.2,
        ),
        itemCount: n,
        itemBuilder: (_, i) => _countryCard(i),
      );
    }

    return LayoutBuilder(
      builder: (context, cs) {
        // Clamp so the layout is safe on tiny or very tall screens.
        final cardH = ((cs.maxHeight - 13.0) / 4.0).clamp(52.0, 120.0);
        final midH = cardH * 2 + 5;

        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
              child: Column(
                children: [
                  // ── Top row ─────────────────────────────────────────────────
                  SizedBox(
                    height: cardH,
                    child: Row(
                      children: [
                        Expanded(child: _countryCard(6)), // Brazil
                        const SizedBox(width: 6),
                        Expanded(child: _countryCard(3)), // Argentina
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // ── Middle: side columns + center panel ─────────────────────
                  SizedBox(
                    height: midH,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left column — Germany (top) + Portugal (bottom)
                        Expanded(
                          flex: 32,
                          child: Column(
                            children: [
                              Expanded(child: _countryCard(4)), // Germany
                              const SizedBox(height: 5),
                              Expanded(child: _countryCard(2)), // Portugal
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(flex: 32, child: _buildCenterPanel()),
                        const SizedBox(width: 5),
                        // Right column — England (top) + France (bottom)
                        Expanded(
                          flex: 32,
                          child: Column(
                            children: [
                              Expanded(child: _countryCard(5)), // England
                              const SizedBox(height: 5),
                              Expanded(child: _countryCard(7)), // France
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // ── Bottom row ───────────────────────────────────────────────
                  SizedBox(
                    height: cardH,
                    child: Row(
                      children: [
                        Expanded(child: _countryCard(0)), // Spain
                        const SizedBox(width: 6),
                        Expanded(child: _countryCard(1)), // Italy
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Coin burst overlay
            if (_phase == _Phase.settled)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _coinCtrl,
                    builder: (context, child) => _coinCtrl.value > 0
                        ? CustomPaint(
                            painter: _GoldBurstPainter(_coinCtrl.value),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            // Round result card (slides up from bottom when settled)
            if (_phase == _Phase.settled && _winItemId != null)
              Positioned(
                bottom: 4,
                left: 12,
                right: 12,
                child: _buildResultCard(),
              ),
          ],
        );
      },
    );
  }

  // ── Center panel ──────────────────────────────────────────────────────────────

  Widget _buildCenterPanel() {
    final betting = _phase == _Phase.betting;
    final spinning = _phase == _Phase.spinning;
    final urgent = betting && _secsLeft <= 10;
    const totalSecs = 30.0;
    final timerProg = betting ? (_secsLeft / totalSecs).clamp(0.0, 1.0) : 0.0;
    final accent = urgent
        ? _kRedAccent
        : spinning
        ? _kGoldLight
        : _kGold;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A2200), Color(0xFF1A0C00)],
        ),
        border: Border.all(color: _kGoldDark, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _kGold.withValues(alpha: 0.18),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final diameter = (constraints.biggest.shortestSide * 0.65).clamp(
              48.0,
              86.0,
            );
            return Center(
              child: SizedBox.square(
                dimension: diameter,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: spinning ? null : timerProg,
                        strokeWidth: 4,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _breathAnim,
                      builder: (_, child) => Transform.scale(
                        scale: urgent ? _breathAnim.value : 1.0,
                        child: child,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sports_soccer_rounded,
                            color: accent,
                            size: diameter * 0.34,
                          ),
                          if (betting)
                            Text(
                              '$_secsLeft',
                              maxLines: 1,
                              style: TextStyle(
                                color: accent,
                                fontSize: diameter * 0.21,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _countryCard(int index) {
    if (index >= _displayCount) return const SizedBox.shrink();
    final isActive = index == _highlighted;
    final isSpinning = _phase == _Phase.spinning;
    final itemId = _idAt(index);
    final isWinner =
        _phase == _Phase.settled && _winItemId != null && _winItemId == itemId;
    final isSelected = _betsByItem.containsKey(itemId);
    final betAmt = _betsByItem[itemId] ?? 0;
    final isBusy = (_itemPendingCounts[itemId] ?? 0) > 0;
    final canTap =
        _phase == _Phase.betting &&
        _configAvailable &&
        _items.isNotEmpty &&
        !_placingBet;
    final isPrevWinner = _prevWinnerId == itemId && _phase == _Phase.betting;

    double opacity = 1.0;
    if (isSpinning && !isActive) opacity = 0.45;
    if (_phase == _Phase.settled && _winItemId != null && !isWinner) {
      opacity = 0.25;
    }

    Widget card = AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) => Transform.scale(
        scale: isWinner
            ? _pulseAnim.value
            : (isActive && isSpinning ? 1.06 : 1.0),
        child: child,
      ),
      child: _MagicCountryBadgeCard(
        icon: _iconAt(index),
        name: _nameAt(index),
        multLabel: _multLabelAt(index),
        rarity: _rarityAt(index),
        isActive: isActive,
        isWinner: isWinner,
        isSelected: isSelected,
        isDisabled: !canTap && !isSpinning && !isWinner,
        isBusy: isBusy,
        betAmount: betAmt,
        teamTotal: _teamTotals[itemId] ?? 0,
        isPrevWinner: isPrevWinner,
        formatCoins: formatCoinAmount,
        isSpinning: isSpinning,
        isArabic: _ar,
        selectedTab: _selectedTab,
      ),
    );

    if (canTap) {
      card = GestureDetector(onTap: () => _tapItem(index), child: card);
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: opacity,
      child: card,
    );
  }

  Widget _buildResultCard() {
    final icon = _winItemIcon ?? '⚽';
    final name = _winItemName ?? '';
    final mult = _winMult != null
        ? (_winMult!.truncateToDouble() == _winMult
              ? 'x${_winMult!.toInt()}'
              : 'x$_winMult')
        : '';
    final won = _spinDelta != null && _spinDelta! > 0;

    return SlideTransition(
      position: _resultSlideAnim,
      child: FadeTransition(
        opacity: _resultSlideCtrl,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: EdgeInsets.symmetric(
            horizontal: _isCompactWidth ? 10 : 16,
            vertical: _isCompactWidth ? 7 : 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFF3A2500), Color(0xFF2A1800)],
            ),
            border: Border.all(color: won ? _kGreenWin : _kGoldDark, width: 2),
            boxShadow: [
              BoxShadow(
                color: (won ? _kGreenWin : _kGoldDark).withValues(alpha: 0.4),
                blurRadius: 12,
              ),
            ],
          ),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 28)),
              SizedBox(width: _isCompactWidth ? 6 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _kGold,
                        fontWeight: FontWeight.w900,
                        fontSize: _responsiveFont(14, 12),
                      ),
                    ),
                    if (mult.isNotEmpty)
                      Text(
                        mult,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _kGoldLight,
                          fontWeight: FontWeight.w900,
                          fontSize: _responsiveFont(18, 15),
                        ),
                      ),
                  ],
                ),
              ),
              if (_hasBets && _spinDelta != null) ...[
                SizedBox(width: _isCompactWidth ? 4 : 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: won ? _kGreenWin : _kRedAccent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _isCompactWidth ? 92 : 140,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: CoinAmountText(
                        amount: won ? _spinDelta! : _totalBetAmount,
                        prefix: won ? '+' : '-',
                        fontSize: _responsiveFont(13, 11),
                        color: Colors.white,
                      ),
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

  // ── History strip ─────────────────────────────────────────────────────────────

  Widget _buildHistoryStrip() {
    if (_history.isEmpty) return const SizedBox(height: 4);
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.black45,
            child: Text(
              _ar ? 'النتيجة:' : 'Result:',
              style: const TextStyle(
                color: _kGold,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: _history.length,
                itemBuilder: (ctx, i) {
                  final h = _history[i];
                  final isNew = i == 0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 3,
                        ),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2A1A00),
                          border: Border.all(
                            color: _kGoldDark.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            h.foodIcon,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      if (isNew)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: _kRedAccent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 6,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom controls ───────────────────────────────────────────────────────────

  Widget _buildBottomControls() {
    final active = _phase == _Phase.betting;
    final gap = _isCompactWidth ? 4.0 : 8.0;
    return Container(
      margin: EdgeInsets.fromLTRB(
        _isCompactWidth ? 4 : 8,
        2,
        _isCompactWidth ? 4 : 8,
        0,
      ),
      padding: EdgeInsets.fromLTRB(4, _isCompactWidth ? 4 : 6, 4, gap),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.black.withValues(alpha: 0.16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tabs with icons
          _buildBetTabs(),
          const SizedBox(height: 4),
          // Tab content (My Bets status / All Users / Popularity)
          _buildTabContent(active),
          SizedBox(height: gap),
          // Inline warning (e.g. insufficient coins) — sits above chips so it
          // never covers the balance row below.
          _buildBetWarning(),
          // Chips row
          _buildChips(!active),
          SizedBox(height: gap),
          // Follow Previous — centered like image B
          _buildFollowToggle(),
          SizedBox(height: gap),
          // Balance row — two columns like image B
          _buildBalanceRow(),
        ],
      ),
    );
  }

  Widget _buildBetTabs() {
    final tabs = _ar
        ? [
            ('رهاناتي', Icons.person_rounded),
            ('الكل', Icons.people_rounded),
            ('الشعبية', Icons.sports_soccer_rounded),
          ]
        : [
            ('My Bets', Icons.person_rounded),
            ("All Users' Bets", Icons.people_rounded),
            ('Popularity', Icons.sports_soccer_rounded),
          ];
    return Row(
      children: tabs.asMap().entries.map((e) {
        final sel = e.key == _selectedTab;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedTab = e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: sel
                    ? const LinearGradient(
                        colors: [Color(0xFF7A5C00), _kGoldDark],
                      )
                    : null,
                color: sel ? null : Colors.black26,
                border: Border.all(
                  color: sel
                      ? _kGold.withValues(alpha: 0.6)
                      : _kGoldDark.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(e.value.$2, color: sel ? _kGold : _kTextDim, size: 13),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      e.value.$1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: sel ? _kGold : _kTextDim,
                        fontSize: 10,
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTabContent(bool active) {
    if (_selectedTab == 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: _buildBetStatus(active),
      );
    }
    // All Users or Popularity: show per-team totals
    final teams = _items.isEmpty ? <HungryCatFood>[] : _items;
    if (teams.isEmpty || _teamTotals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Text(
          _ar ? 'لا توجد رهانات بعد' : 'No bets yet',
          style: const TextStyle(color: _kTextDim, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      );
    }
    final sorted = [...teams];
    if (_selectedTab == 2) {
      sorted.sort(
        (a, b) =>
            (_teamTotals[b.foodId] ?? 0).compareTo(_teamTotals[a.foodId] ?? 0),
      );
    }
    final total = _teamTotals.values.fold(0, (s, v) => s + v);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: sorted.length,
        itemBuilder: (_, i) {
          final t = _teamTotals[sorted[i].foodId] ?? 0;
          if (t == 0) return const SizedBox.shrink();
          final pct = total > 0 ? (t / total * 100).round() : 0;
          return Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kGoldDark.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sorted[i].icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  '$pct%',
                  style: const TextStyle(
                    color: _kGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFollowToggle() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _followPrevious = !_followPrevious);
      },
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: _isCompactWidth ? 5 : 8,
        runSpacing: 2,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _followPrevious ? _kGold : Colors.white24,
              border: Border.all(
                color: _followPrevious ? _kGoldLight : Colors.white30,
              ),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: _followPrevious
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _isCompactWidth ? 205 : 280),
            child: Text(
              _ar ? 'تتبع الاختيار السابق' : 'Follow Previous Choice',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _followPrevious ? _kGold : Colors.white60,
                fontSize: _responsiveFont(12, 11),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBetStatus(bool active) {
    final pending = _itemPendingCounts.values.fold(0, (s, c) => s + c);
    if (pending > 0) {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kGold),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _ar ? 'جارٍ الإرسال...' : 'Placing bet...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kGold,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    }
    if (_betsByItem.isNotEmpty) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 3,
        children: _betsByItem.entries.map((e) {
          final icon =
              _items
                  .where((f) => f.foodId == e.key)
                  .map((f) => f.icon)
                  .firstOrNull ??
              '⚽';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _kGoldDark.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kGoldDark.withValues(alpha: 0.7)),
            ),
            child: Text(
              '$icon ${_formatCoins(e.value)}🪙',
              style: const TextStyle(
                color: _kCream,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }).toList(),
      );
    }
    if (active) {
      return Text(
        _ar
            ? 'اختر المبلغ ثم اضغط على الفريق 👆'
            : 'Choose wager > choose team 👆',
        style: const TextStyle(color: Color(0xFFB8A060), fontSize: 11),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildChips(bool locked) {
    // Compact screens: two rows of 3 chips so nothing is clipped.
    if (_isCompactWidth) {
      const row1 = [100, 1000, 5000];
      const row2 = [10000, 20000, 100000];
      Widget row(List<int> chips) => CoinChipRow(
        chips: chips,
        selected: _betAmount,
        balance: _balance,
        locked: locked,
        chipSize: 46,
        spacing: 4,
        onSelect: (v) => setState(() => _betAmount = v),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [row(row1), const SizedBox(height: 4), row(row2)],
      );
    }
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

  /// Inline warning banner shown directly above chips instead of a bottom
  /// toast that would obscure the balance row.
  Widget _buildBetWarning() {
    if (_betWarning == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFFFAA00),
            size: 14,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              _betWarning!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFFCC44),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow() {
    final todayWin = (_spinDelta != null && _spinDelta! > 0) ? _spinDelta! : 0;
    // Two-column layout matching image B: [My Balance] [arrow] [Today's rewards]
    return Row(
      children: [
        // Left: My Balance
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _ar ? 'رصيدي' : 'My Balance',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: _responsiveFont(11, 10),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CoinAmountText(
                    amount: _balance,
                    fontSize: _responsiveFont(15, 13),
                    iconSize: 16,
                    color: _kGold,
                  ),
                ],
              ),
            ],
          ),
        ),
        // Center: arrow button
        GestureDetector(
          onTap: _refreshBalance,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFCC9900), Color(0xFF8A6400)],
              ),
              boxShadow: [
                BoxShadow(color: _kGold.withValues(alpha: 0.4), blurRadius: 8),
              ],
            ),
            child: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
        // Right: Today's rewards
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _ar ? 'جوائز اليوم' : "Today's rewards",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: _responsiveFont(11, 10),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              CoinAmountText(
                amount: todayWin,
                fontSize: _responsiveFont(15, 13),
                iconSize: 16,
                color: todayWin > 0 ? _kGreenWin : Colors.white60,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Reconnect overlay ─────────────────────────────────────────────────────────

  Widget _buildReconnectOverlay() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: Colors.black54,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1A00),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kGoldDark, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: _kGold,
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _ar ? 'إعادة الاتصال...' : 'Reconnecting…',
                    style: const TextStyle(
                      color: _kGold,
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

  // ── Loading / Error ───────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: AnimatedBuilder(
        animation: _breathAnim,
        builder: (_, snap) => Transform.scale(
          scale: _breathAnim.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚽', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: _kGold, strokeWidth: 3),
              const SizedBox(height: 14),
              Text(
                _ar ? 'جارٍ التحميل...' : 'Loading...',
                style: const TextStyle(
                  color: _kGold,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
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
            const Text('⚽', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(
              _ar ? 'تعذّر تحميل اللعبة' : 'Failed to load',
              style: const TextStyle(
                color: _kGold,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMsg ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
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
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [_kGoldDark, _kGoldDim],
                  ),
                  border: Border.all(color: _kGold, width: 2),
                ),
                child: Text(
                  _ar ? 'إعادة المحاولة' : 'Retry',
                  style: const TextStyle(
                    color: _kGold,
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

// ── Team badge widget ─────────────────────────────────────────────────────────

class _MagicCountryBadgeCard extends StatelessWidget {
  const _MagicCountryBadgeCard({
    required this.icon,
    required this.name,
    required this.multLabel,
    required this.rarity,
    required this.isActive,
    required this.isWinner,
    required this.isSelected,
    required this.isDisabled,
    required this.isBusy,
    required this.betAmount,
    required this.teamTotal,
    required this.isPrevWinner,
    required this.formatCoins,
    required this.isSpinning,
    required this.isArabic,
    required this.selectedTab,
  });

  final String icon, name, multLabel, rarity;
  final bool isActive,
      isWinner,
      isSelected,
      isDisabled,
      isBusy,
      isPrevWinner,
      isSpinning,
      isArabic;
  final int betAmount, teamTotal;
  final String Function(int) formatCoins;

  /// 0 = My Bets, 1 = All Users, 2 = Popularity
  final int selectedTab;

  int get _stars {
    switch (rarity.toLowerCase()) {
      case 'legendary':
        return 5;
      case 'epic':
        return 4;
      case 'rare':
        return 3;
      case 'uncommon':
        return 2;
    }
    final value = double.tryParse(multLabel.replaceFirst('x', '')) ?? 1;
    if (value >= 100) return 5;
    if (value >= 30) return 4;
    if (value >= 10) return 3;
    if (value >= 3) return 2;
    return 1;
  }

  Color get _rarityColor {
    switch (rarity.toLowerCase()) {
      case 'legendary':
        return const Color(0xFF55EEFF);
      case 'epic':
        return const Color(0xFFFF8A35);
      case 'rare':
        return const Color(0xFF399CFF);
      case 'uncommon':
        return const Color(0xFF45E6A1);
      default:
        return _kGold;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show the pill that matches the active tab.
    // tab 0 = My Bets → show betAmount only
    // tab 1 = All Users → show teamTotal only
    // tab 2 = Popularity → no pills on the card
    final showMyBetPill = selectedTab == 0 && betAmount > 0;
    final showTeamPill = selectedTab == 1 && teamTotal > 0;
    final hasExposure = showMyBetPill || showTeamPill;
    final spotlight = isActive && isSpinning;
    final accent = isWinner
        ? _kGreenWin
        : isSelected
        ? _kBlueGlow
        : spotlight
        ? _kGoldLight
        : _rarityColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 108 || constraints.maxHeight < 96;
        // Estimate the square side that AspectRatio(1) will produce so we
        // know whether even the short country name will fit.
        final pillH = compact ? 15.0 : 19.0;
        final squareSize = (constraints.maxHeight - 2.0 - pillH).clamp(
          30.0,
          constraints.maxWidth,
        );
        // Below 60 px the name won't be readable — show flag + multiplier only.
        final hideLabel = squareSize < 60;
        final radius = compact ? 11.0 : 15.0;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: isDisabled ? 0.58 : 1,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFFC52F),
                            Color(0xFFD88708),
                            Color(0xFF6E3400),
                          ],
                          stops: [0, 0.52, 1],
                        ),
                        border: Border.all(
                          color: accent,
                          width: isSelected || isWinner || spotlight ? 3 : 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(
                              alpha: isSelected || isWinner || _stars >= 4
                                  ? 0.62
                                  : 0.24,
                            ),
                            blurRadius: compact ? 8 : 14,
                            spreadRadius: isSelected || isWinner ? 1.5 : 0,
                          ),
                          const BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 5,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius - 2),
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0x12FFFFFF),
                                      Color(0x22000000),
                                      Color(0x66000000),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: -8,
                              top: -9,
                              child: Transform.rotate(
                                angle: -0.55,
                                child: Container(
                                  width: compact ? 34 : 46,
                                  height: compact ? 14 : 18,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0),
                                        Colors.white.withValues(alpha: 0.5),
                                        Colors.white.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: compact ? 3 : 5,
                              left: 5,
                              right: 5,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  List.generate(_stars, (_) => '★').join(),
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: _kCream,
                                    fontSize: compact ? 8 : 11,
                                    height: 1,
                                    shadows: const [
                                      Shadow(
                                        color: Color(0xFF5B2500),
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              // Tighter margins on compact cards give the
                              // flag + name column enough room to breathe.
                              top: compact ? 8 : 18,
                              bottom: compact ? 10 : 20,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Container(
                                        width: compact ? 34 : 50,
                                        height: compact ? 34 : 50,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const RadialGradient(
                                            colors: [
                                              Color(0xFFFFF7CF),
                                              Color(0xFFDCA52B),
                                              Color(0xFF6A3500),
                                            ],
                                          ),
                                          border: Border.all(
                                            color: _kCream,
                                            width: compact ? 1.5 : 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: accent.withValues(
                                                alpha: 0.5,
                                              ),
                                              blurRadius: compact ? 5 : 10,
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          icon,
                                          style: TextStyle(
                                            fontSize: compact ? 19 : 28,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!hideLabel) ...[
                                    SizedBox(height: compact ? 1 : 3),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: compact ? 7.5 : 10,
                                          fontWeight: FontWeight.w900,
                                          shadows: const [
                                            Shadow(
                                              color: Colors.black,
                                              blurRadius: 3,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Positioned(
                              right: compact ? 3 : 5,
                              bottom: compact ? 2 : 4,
                              child: Text(
                                multLabel,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 10 : 15,
                                  fontWeight: FontWeight.w900,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0xFF190800),
                                      offset: Offset(1, 1),
                                      blurRadius: 1,
                                    ),
                                    Shadow(
                                      color: Color(0xFF190800),
                                      offset: Offset(-1, -1),
                                      blurRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Winner/prev-winner badge lives at the top-left
                            // corner so it never competes with the multiplier
                            // label at bottom-right or the country name below
                            // the flag.
                            if (isPrevWinner || isWinner)
                              Positioned(
                                left: compact ? 3 : 4,
                                top: compact ? 3 : 5,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 3 : 5,
                                    vertical: compact ? 1 : 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isWinner
                                        ? _kGreenWin
                                        : const Color(0xCC3D2A00),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isWinner
                                          ? _kGreenWin
                                          : _kGoldLight.withValues(alpha: 0.8),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Icon(
                                    isWinner
                                        ? Icons.workspace_premium_rounded
                                        : Icons.emoji_events_rounded,
                                    color: isWinner
                                        ? Colors.white
                                        : _kGoldLight,
                                    size: compact ? 9 : 12,
                                  ),
                                ),
                              ),
                            if (isBusy)
                              Positioned.fill(
                                child: ColoredBox(
                                  color: const Color(0x77000000),
                                  child: Center(
                                    child: SizedBox.square(
                                      dimension: compact ? 17 : 22,
                                      child: const CircularProgressIndicator(
                                        color: _kGoldLight,
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Always reserve fixed height for bet pills so the Expanded
              // square above never resizes when a bet is placed.
              const SizedBox(height: 2),
              SizedBox(
                height: compact ? 15 : 19,
                child: hasExposure
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (showMyBetPill)
                            Flexible(
                              child: _CountryBetPill(
                                icon: Icons.person_rounded,
                                amount: formatCoins(betAmount),
                                color: _kBlueGlow,
                                compact: compact,
                              ),
                            ),
                          if (showMyBetPill && showTeamPill)
                            SizedBox(width: compact ? 2 : 3),
                          if (showTeamPill)
                            Flexible(
                              child: _CountryBetPill(
                                icon: Icons.groups_rounded,
                                amount: formatCoins(teamTotal),
                                color: _kGold,
                                compact: compact,
                              ),
                            ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CountryBetPill extends StatelessWidget {
  const _CountryBetPill({
    required this.icon,
    required this.amount,
    required this.color,
    required this.compact,
  });

  final IconData icon;
  final String amount;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 72),
      padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: const Color(0xCC160B02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: compact ? 8 : 11),
          SizedBox(width: compact ? 1 : 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                amount,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 7 : 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _TeamBadge extends StatelessWidget {
  const _TeamBadge({
    required this.icon,
    required this.name,
    required this.multLabel,
    // width/height kept for API compatibility but ignored — card fills its parent
    required this.width,
    required this.height,
    required this.isActive,
    required this.isWinner,
    required this.isSelected,
    required this.isBusy,
    required this.betAmount,
    required this.teamTotal,
    required this.isPrevWinner,
    required this.formatCoins,
    required this.isSpinning,
    required this.isArabic,
  });

  final String icon, name, multLabel;
  final double width, height;
  final bool isActive,
      isWinner,
      isSelected,
      isBusy,
      isSpinning,
      isArabic,
      isPrevWinner;
  final int betAmount, teamTotal;
  final String Function(int) formatCoins;

  @override
  Widget build(BuildContext context) {
    final spotlight = isActive && isSpinning;
    final multNum = double.tryParse(multLabel.replaceAll('x', '')) ?? 1.0;
    final stars =
        (multNum >= 100
                ? 5
                : multNum >= 30
                ? 4
                : multNum >= 10
                ? 3
                : multNum >= 5
                ? 2
                : 1)
            .clamp(1, 5);

    // ── Color scheme — same slots as _GameGridCard ────────────────────────────
    final Color accent;
    final List<Color>
    iconColors; // icon box gradient — same as data.colors in _GameGridCard
    final Color glowColor; // boxShadow glow — same as data.glowColor
    final double cardBgAlpha1, cardBgAlpha2;

    if (isWinner) {
      accent = _kGreenWin;
      iconColors = [const Color(0xFF00DD55), const Color(0xFF007730)];
      glowColor = _kGreenWin;
      cardBgAlpha1 = 0.18;
      cardBgAlpha2 = 0.30;
    } else if (spotlight) {
      accent = _kGoldLight;
      iconColors = [const Color(0xFFFFDD44), const Color(0xFFAA7700)];
      glowColor = _kGold;
      cardBgAlpha1 = 0.22;
      cardBgAlpha2 = 0.35;
    } else if (isSelected) {
      accent = _kBlueGlow;
      iconColors = [const Color(0xFF22AAFF), const Color(0xFF005599)];
      glowColor = _kBlueGlow;
      cardBgAlpha1 = 0.20;
      cardBgAlpha2 = 0.32;
    } else if (isPrevWinner) {
      accent = _kGold;
      iconColors = [const Color(0xFFCC9900), const Color(0xFF7A5C00)];
      glowColor = _kGold;
      cardBgAlpha1 = 0.14;
      cardBgAlpha2 = 0.25;
    } else {
      accent = _kGoldDark;
      iconColors = [const Color(0xFF5A3C00), const Color(0xFF2A1800)];
      glowColor = _kGoldDark;
      cardBgAlpha1 = 0.18;
      cardBgAlpha2 = 0.28;
    }

    const br = BorderRadius.all(Radius.circular(22));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: br,
        // Semi-transparent gradient — exact _GameGridCard pattern
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            iconColors[0].withValues(alpha: cardBgAlpha1),
            iconColors[1].withValues(alpha: cardBgAlpha2),
          ],
        ),
        border: Border.all(color: iconColors[0].withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(
              alpha: isSelected || isWinner ? 0.25 : 0.12,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // ── Ghost flag background — exact _GameGridCard pattern ──
            Positioned(
              right: -12,
              bottom: -14,
              child: Text(
                icon,
                style: TextStyle(
                  fontSize: 72,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),

            // ── Content — mirrors _GameGridCard Column structure ──
            LayoutBuilder(
              builder: (_, cs) {
                final aH = cs.maxHeight.isInfinite ? 100.0 : cs.maxHeight;
                final aW = cs.maxWidth.isInfinite ? 150.0 : cs.maxWidth;
                final s = (aH / 115.0).clamp(0.55, 1.0);
                final compact = aW < 130 || aH < 92;
                final contentPadding = (compact ? 6.0 : 10.0) * s;
                final iconSz = (aW * (compact ? 0.29 : 0.34) * s).clamp(
                  compact ? 24.0 : 32.0,
                  compact ? 40.0 : 52.0,
                );
                final nameColor = isWinner
                    ? _kGreenWin
                    : isSelected
                    ? _kBlueGlow
                    : Colors.white;

                return Padding(
                  padding: EdgeInsets.all(contentPadding),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Icon box — the signature _GameGridCard element ──
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: iconSz,
                        height: iconSz,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14 * s),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: iconColors,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: glowColor.withValues(alpha: 0.38),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            icon,
                            style: TextStyle(
                              fontSize: iconSz * 0.55,
                              shadows: const [
                                Shadow(color: Colors.black45, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SizedBox(width: (compact ? 4 : 8) * s),

                      // ── Right column: badge → name → sub-info ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Multiplier pill — _GameGridCard "badge" pattern
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: (compact ? 5 : 7) * s,
                                vertical: (compact ? 1 : 2) * s,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                color: iconColors[0].withValues(alpha: 0.28),
                                border: Border.all(
                                  color: iconColors[0].withValues(alpha: 0.55),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  multLabel,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: (aW * 0.11 * s).clamp(8.0, 15.0),
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: (compact ? 1 : 4) * s),
                            // Country name — _GameGridCard "title" pattern
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: nameColor,
                                fontSize: (aW * 0.115 * s).clamp(9.0, 15.0),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: compact ? 0 : 2 * s),
                            // Stars + people count — _GameGridCard "subtitle" pattern
                            Row(
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      List.generate(stars, (_) => '★').join(),
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: accent.withValues(alpha: 0.85),
                                        fontSize: (aW * 0.085 * s).clamp(
                                          6.0,
                                          11.0,
                                        ),
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                                if (teamTotal > 0) ...[
                                  SizedBox(width: (compact ? 2 : 5) * s),
                                  Icon(
                                    Icons.people_rounded,
                                    color: Colors.white.withValues(alpha: 0.50),
                                    size: (aW * 0.08 * s).clamp(6.0, 11.0),
                                  ),
                                  SizedBox(width: s),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        formatCoins(teamTotal),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.55,
                                          ),
                                          fontSize: (aW * 0.08 * s).clamp(
                                            6.0,
                                            10.0,
                                          ),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ── Bet badge — top-right pill ──
            if (betAmount > 0)
              Positioned(
                top: 5,
                right: 5,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 64),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFE040), Color(0xFFCC9900)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: _kGold.withValues(alpha: 0.55),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatCoins(betAmount),
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xFF1A0800),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Busy overlay ──
            if (isBusy)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _kGold,
                      ),
                    ),
                  ),
                ),
              ),

            // ── WIN! banner — full-width top strip ──
            if (isWinner)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00BB44), Color(0xFF008833)],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      isArabic ? '✨ فاز!' : '✨ WIN!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),

            // ── Spotlight pulse ring (spinning highlight) ──
            if (spotlight)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: br,
                    border: Border.all(
                      color: _kGoldLight.withValues(alpha: 0.6),
                      width: 2,
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

// ── Stadium light rays painter ────────────────────────────────────────────────

class _StadiumLightPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    // 4 subtle rays from top-center
    for (int i = 0; i < 4; i++) {
      final angle = (-0.6 + i * 0.4) * math.pi / 4;
      final path = Path()
        ..moveTo(size.width / 2, 0)
        ..lineTo(
          size.width / 2 + math.sin(angle - 0.05) * size.height * 1.2,
          size.height,
        )
        ..lineTo(
          size.width / 2 + math.sin(angle + 0.05) * size.height * 1.2,
          size.height,
        )
        ..close();
      paint.color = const Color(0xFFFFCC00).withValues(alpha: 0.025);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StadiumLightPainter old) => false;
}

// ── Gold burst painter ────────────────────────────────────────────────────────

class _GoldBurstPainter extends CustomPainter {
  const _GoldBurstPainter(this.progress);
  final double progress;

  static final _rng = math.Random(99);
  static final _particles = List.generate(
    24,
    (i) => (
      angle: _rng.nextDouble() * math.pi * 2,
      speed: 0.3 + _rng.nextDouble() * 0.7,
      size: 4.0 + _rng.nextDouble() * 7,
    ),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final ease = Curves.easeOut.transform(progress);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = size.shortestSide * 0.45;
    final paint = Paint()..color = _kGold.withValues(alpha: (1 - ease) * 0.85);
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
  bool shouldRepaint(_GoldBurstPainter old) => old.progress != progress;
}

// ── Sound service ─────────────────────────────────────────────────────────────

// Two players instead of five — keeps concurrent ExoPlayer pipeline count low.
// _tick: dedicated, loaded once (fires every second during countdown).
// _event: shared for bet / spin / win / lose (these never overlap each other).
