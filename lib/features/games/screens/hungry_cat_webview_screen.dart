import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    with SingleTickerProviderStateMixin {
  final _service = const HungryCatGameService();

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
  String? _selectedFoodId;
  int     _betAmount = 100;
  bool    _betPlaced = false;
  bool    _betBusy   = false; // true while API call is in flight

  // ── Animation ────────────────────────────────────────────────────────────
  int  _highlighted = 0;
  bool _settling    = false; // guard: only settle once per round

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Realtime ─────────────────────────────────────────────────────────────
  RealtimeChannel? _channel;

  // ── Misc ─────────────────────────────────────────────────────────────────
  Timer?  _countdownTimer;
  String? _errorMsg;
  bool    _reconnecting = false;

  bool get _ar => widget.isArabic;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
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
    _countdownTimer?.cancel();
    _channel?.unsubscribe();
    _pulseCtrl.dispose();
    super.dispose();
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

      _foods   = foods.take(8).toList();
      _balance = balance;
      _history = history.take(20).toList();

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
    _settling      = false;
    _winFoodId     = null;
    _winFoodIcon   = null;
    _winFoodName   = null;
    _winMult       = null;
    _betPlaced     = false;
    _betBusy       = false;
    _selectedFoodId = null;

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
        setState(() => _secsLeft = left);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Realtime
  // ─────────────────────────────────────────────────────────────────────────

  void _subscribeToRound(String roundId) {
    _channel?.unsubscribe();
    _reconnecting = false;

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
          setState(() => _reconnecting = status == RealtimeSubscribeStatus.channelError);
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
  // Betting — tap food = immediate bet
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _tapFood(int index) async {
    if (_phase != _Phase.betting) return;
    if (_betPlaced || _betBusy) return;
    if (index >= _foods.length) return;

    if (_balance < _betAmount) {
      _showSnack(_ar ? 'رصيد غير كافٍ' : 'Insufficient coins');
      return;
    }

    final foodId   = _foods[index].foodId;
    final foodName = _foods[index].name;

    debugPrint('[HungryCat] bet tap food=$foodId amount=$_betAmount');
    HapticFeedback.lightImpact();

    setState(() {
      _selectedFoodId = foodId;
      _betBusy        = true;
    });

    try {
      final result = await _service.placeGlobalBet(
        roundId: _roundId!,
        foodId:  foodId,
        amount:  _betAmount,
      );
      if (!mounted) return;

      debugPrint('[HungryCat] bet placed betId=${result.betId}');
      debugPrint('[HungryCat] wallet updated coins=${result.newBalance}');

      setState(() {
        _balance   = result.newBalance;
        _betPlaced = true;
        _betBusy   = false;
      });
      _showSnack(_ar
          ? '✅ تم الرهان على $foodName!'
          : '✅ Bet placed on $foodName!');
    } catch (e) {
      debugPrint('[HungryCat] bet failed reason=$e');
      if (!mounted) return;
      setState(() {
        _selectedFoodId = null;
        _betBusy        = false;
      });
      _showSnack(_ar ? _friendlyErrorAr('$e') : _friendlyError('$e'));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Settling
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _triggerSettle() async {
    if (_settling || _phase != _Phase.betting) return;
    _settling = true;
    setState(() => _phase = _Phase.spinning);

    _runFreeSpin();

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
      debugPrint('[HungryCat] settle failed: $e\n$st');
      // Realtime will still deliver the result.
    }
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
    while (mounted && _winFoodId == null && _phase == _Phase.spinning) {
      await Future.delayed(const Duration(milliseconds: 70));
      if (!mounted || _phase != _Phase.spinning) return;
      setState(() => _highlighted = (_highlighted + 1) % _displayFoodCount);
    }
    if (!mounted || _phase != _Phase.spinning) return;

    final target = _findWinnerIndex();
    await _runLandingAnimation(target);
    if (!mounted) return;

    HapticFeedback.mediumImpact();
    for (int i = 0; i < 3; i++) {
      if (!mounted) break;
      await _pulseCtrl.forward();
      await _pulseCtrl.reverse();
    }
    if (!mounted) return;

    final newBalance = await _service.fetchCoinBalance();
    if (!mounted) return;
    debugPrint('[HungryCat] payout amount=${newBalance - _balance}');
    debugPrint('[HungryCat] wallet updated coins=$newBalance');
    _balance = newBalance;

    try {
      final hist = await _service.getGlobalHistory();
      if (mounted) _history = hist.take(20).toList();
    } catch (_) {}
    if (!mounted) return;

    setState(() => _phase = _Phase.settled);
    await Future.delayed(const Duration(seconds: 3));
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

  String _labelAt(int i) {
    final mult = i < _foods.length
        ? _foods[i].multiplier
        : _kDefaultFoods[i % _kDefaultFoods.length].mult;
    final v = mult.truncateToDouble() == mult ? mult.toInt().toString() : mult.toString();
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
    if (e.contains('duplicate_bet'))       return 'You already bet this round';
    return 'Something went wrong. Please try again.';
  }

  String _friendlyErrorAr(String e) {
    if (e.contains('insufficient_coins'))  return 'رصيد غير كافٍ';
    if (e.contains('game_disabled'))       return 'اللعبة معطّلة حالياً';
    if (e.contains('betting_closed'))      return 'انتهى وقت الرهان';
    if (e.contains('round_not_found'))     return 'لم يُوجد الجولة — جارٍ التحديث';
    if (e.contains('invalid_food'))        return 'اختيار طعام غير صالح';
    if (e.contains('not_authenticated'))   return 'يرجى تسجيل الدخول من جديد';
    if (e.contains('duplicate_bet'))       return 'رهنت بالفعل في هذه الجولة';
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
        _buildBottomControls(),
        const SizedBox(height: 16),
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
        label = _ar
            ? 'الرهان مفتوح • $_secsLeft ث'
            : 'Betting open • ${_secsLeft}s';
        bg = const Color(0xFF1A3D1A);
        fg = const Color(0xFF4ADE80);
      case _Phase.spinning:
        label = _ar ? '🎰 جارٍ الدوران...' : '🎰 Spinning...';
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
        label = _ar
            ? '🏆 الفائز: $icon $name $mult'
            : '🏆 Winner: $icon $name $mult';
        bg = const Color(0xFF2A1A00);
        fg = const Color(0xFFF0C15A);
      default:
        return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
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
          Text(
            label,
            style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // ── Wheel area ────────────────────────────────────────────────────────────

  Widget _buildWheelArea() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size    = math.min(constraints.maxWidth, constraints.maxHeight);
        final radius  = size * 0.34;
        final catSize = size * 0.22;
        final bubSize = size * 0.195;
        final center  = Offset(size / 2, size / 2);
        final n       = _displayFoodCount;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _RingPainter(radius: radius)),
              ),
              for (int i = 0; i < n; i++)
                _positionedBubble(i, n, center, radius, bubSize),
              Positioned(
                left:   center.dx - catSize / 2,
                top:    center.dy - catSize / 2,
                width:  catSize,
                height: catSize,
                child:  _buildCatCenter(catSize),
              ),
              if (_phase == _Phase.settled && _winFoodId != null)
                Positioned.fill(child: _buildResultOverlay()),
            ],
          ),
        );
      },
    );
  }

  Widget _positionedBubble(
    int i, int n, Offset center, double radius, double bubSize,
  ) {
    final angle    = -math.pi / 2 + i * 2 * math.pi / n;
    final left     = center.dx + math.cos(angle) * radius - bubSize / 2;
    final top      = center.dy + math.sin(angle) * radius - bubSize / 2;
    final isActive = i == _highlighted;
    final isWinner = _phase == _Phase.settled && _winFoodId != null
        && i == _findWinnerIndex();
    final isSelected = _foods.isNotEmpty
        && i < _foods.length
        && _foods[i].foodId == _selectedFoodId;

    // Tappable only during betting when no bet is placed/busy yet
    final canTap = _phase == _Phase.betting
        && i < _foods.length
        && !_betPlaced
        && !_betBusy;

    final bubble = AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) {
        final scale = isWinner ? _pulseAnim.value : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: _HungryCatBubble(
        emoji:      _emojiAt(i),
        size:       bubSize,
        isActive:   isActive,
        isWinner:   isWinner,
        isSelected: isSelected,
        isBusy:     isSelected && _betBusy,
      ),
    );

    final label = Text(
      _labelAt(i),
      style: TextStyle(
        color: isSelected
            ? const Color(0xFF34D399)
            : isActive
                ? const Color(0xFFF0C15A)
                : Colors.white.withValues(alpha: 0.65),
        fontSize: bubSize * 0.20,
        fontWeight: (isActive || isSelected) ? FontWeight.w900 : FontWeight.w600,
      ),
    );

    Widget child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [bubble, const SizedBox(height: 2), label],
    );

    if (canTap) {
      child = GestureDetector(
        onTap: () => _tapFood(i),
        child: child,
      );
    }

    return Positioned(
      left:   left,
      top:    top,
      width:  bubSize,
      height: bubSize + 24,
      child:  child,
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

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1A00), Color(0xFF3D2610)],
              ),
              border: Border.all(color: const Color(0xFFF0C15A), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF0C15A).withValues(alpha: 0.35),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 38)),
                const SizedBox(height: 6),
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
                const SizedBox(height: 4),
                Text(
                  _betPlaced
                      ? (_ar ? '🎉 راجع رصيدك!' : '🎉 Check your balance!')
                      : (_ar ? 'رهان في الجولة القادمة!' : 'Bet next round!'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
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
    if (_phase != _Phase.betting) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBetStatus(),
          const SizedBox(height: 8),
          _buildBetChips(),
        ],
      ),
    );
  }

  Widget _buildBetStatus() {
    if (_betBusy) {
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
            _ar ? 'جارٍ الرهان...' : 'Placing bet...',
            style: const TextStyle(
              color: Color(0xFFF0C15A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
    if (_betPlaced) {
      return Text(
        _ar
            ? '✅ تم الرهان على ${_foodName(_selectedFoodId!)} • ${_formatCoins(_betAmount)} 🪙'
            : '✅ Bet placed on ${_foodName(_selectedFoodId!)} • ${_formatCoins(_betAmount)} 🪙',
        style: const TextStyle(
          color: Color(0xFF34D399),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Text(
      _ar ? 'اضغط على طعام للمراهنة 👆' : 'Tap a food to bet 👆',
      style: const TextStyle(color: Colors.white54, fontSize: 12),
    );
  }

  Widget _buildBetChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _kBetChips.map((chip) {
          final sel = chip == _betAmount;
          final locked = _betPlaced || _betBusy;
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

class _HungryCatBubble extends StatelessWidget {
  const _HungryCatBubble({
    required this.emoji,
    required this.size,
    required this.isActive,
    required this.isWinner,
    required this.isSelected,
    required this.isBusy,
  });

  final String emoji;
  final double size;
  final bool   isActive;
  final bool   isWinner;
  final bool   isSelected;
  final bool   isBusy;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = isWinner
        ? const Color(0xFFF0C15A)
        : isSelected
            ? const Color(0xFF34D399)
            : isActive
                ? const Color(0xFFF0C15A).withValues(alpha: 0.85)
                : const Color(0xFF4A1C8C).withValues(alpha: 0.55);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
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
          width: (isActive || isSelected) ? 2.5 : 1.5,
        ),
        boxShadow: (isActive || isSelected || isWinner)
            ? [
                BoxShadow(
                  color: (isWinner || isSelected
                          ? const Color(0xFFF0C15A)
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
          Text(emoji, style: TextStyle(fontSize: size * 0.44)),
          if (isBusy)
            SizedBox(
              width: size * 0.55,
              height: size * 0.55,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF34D399),
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
    canvas.drawCircle(
      center, radius + 14,
      Paint()
        ..color = const Color(0xFF4C1D95).withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28,
    );
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = const Color(0xFF6D28D9).withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.radius != radius;
}
