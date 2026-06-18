import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/hungry_cat_models.dart';
import '../services/hungry_cat_game_service.dart';

// ── Fallback food definitions (used when DB returns fewer than 8 items) ────────
// These are display-only; all money / multiplier logic lives in the backend.

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

enum _Phase { loading, idle, spinning, result }

/// Hungry Cat — native Flutter radial wheel game.
///
/// Economy is 100% server-side via `play_hungry_cat_spin` RPC.
/// The client only drives the visual animation after getting the result.
class HungryCatWebviewScreen extends StatefulWidget {
  const HungryCatWebviewScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<HungryCatWebviewScreen> createState() => _HungryCatWebviewScreenState();
}

class _HungryCatWebviewScreenState extends State<HungryCatWebviewScreen>
    with SingleTickerProviderStateMixin {
  final _service = const HungryCatGameService();

  // Data
  List<HungryCatFood>          _foods   = [];
  int                          _balance = 0;
  List<HungryCatHistoryEntry>  _history = [];

  // Game state
  _Phase               _phase      = _Phase.loading;
  int                  _betAmount  = 100;
  int                  _highlighted = 0; // currently lit bubble index
  HungryCatSpinResult? _lastResult;
  String?              _errorMsg;

  // Pulse animation for the winning bubble
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  bool get _ar => widget.isArabic;

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
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<void> _loadGame() async {
    setState(() { _phase = _Phase.loading; _errorMsg = null; });
    try {
      final foods   = await _service.fetchFoodConfig();
      final balance = await _service.fetchCoinBalance();
      List<HungryCatHistoryEntry> history;
      try { history = await _service.fetchRecentSpins(); }
      catch (_) { history = []; }

      if (!mounted) return;
      setState(() {
        _foods   = foods.take(8).toList();
        _balance = balance;
        _history = history.take(12).toList();
        _phase   = _Phase.idle;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase    = _Phase.loading; // stays loading to show retry
        _errorMsg = '$e';
      });
    }
  }

  // ── Spin logic ────────────────────────────────────────────────────────────────

  Future<void> _spin() async {
    if (_phase != _Phase.idle) return;
    if (_balance < _betAmount) {
      _showSnack(_ar ? 'رصيد غير كافٍ' : 'Insufficient coins');
      return;
    }

    setState(() { _phase = _Phase.spinning; _lastResult = null; });
    HapticFeedback.lightImpact();

    // Generate a simple client-side spin id (no uuid package needed)
    final clientId = '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999999)}';

    HungryCatSpinResult result;
    try {
      result = await _service.playSpin(
        betAmount:    _betAmount,
        clientSpinId: clientId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
      _showSnack(_ar
          ? 'حدث خطأ. حاول مجدداً.'
          : _friendlyError('$e'));
      return;
    }
    if (!mounted) return;

    // Find which bubble slot corresponds to the winning food
    final winningIndex = _findWinningIndex(result);

    // Run the spin animation — modifies _highlighted
    await _runSpinAnimation(winningIndex);
    if (!mounted) return;

    // Pulse the winner 2-3 times
    for (int i = 0; i < 3; i++) {
      await _pulseCtrl.forward();
      await _pulseCtrl.reverse();
    }
    if (!mounted) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _lastResult = result;
      _balance    = result.newBalance;
      _history    = [
        HungryCatHistoryEntry(
          foodIcon:     result.foodIcon,
          foodName:     result.foodName,
          multiplier:   result.multiplier,
          rarity:       result.rarity,
          rewardAmount: result.rewardAmount,
          betAmount:    result.betAmount,
        ),
        ..._history,
      ].take(12).toList();
      _phase = _Phase.result;
    });

    // Auto-reset to idle after 2.5s
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    setState(() { _phase = _Phase.idle; _lastResult = null; });
  }

  // Eased spin: fast start → gradual slowdown → stop on winner
  Future<void> _runSpinAnimation(int winningIndex) async {
    final n = _displayFoodCount;
    // 4-6 full loops + distance to winner
    final fullLoops = 4 + (DateTime.now().millisecondsSinceEpoch % 3).toInt();
    final distToWinner = (winningIndex - _highlighted + n) % n;
    final totalSteps   = fullLoops * n + (distToWinner == 0 ? n : distToWinner);

    for (int i = 0; i < totalSteps; i++) {
      final progress = i / totalSteps;
      final ms = _stepDelay(progress);
      await Future.delayed(Duration(milliseconds: ms));
      if (!mounted) return;
      setState(() => _highlighted = (_highlighted + 1) % n);
    }
    // _highlighted should now == winningIndex
  }

  int _stepDelay(double progress) {
    // 0..0.4 → 50ms, 0.4..0.7 → 50→150ms, 0.7..1.0 → 150→300ms
    if (progress < 0.40) return 50;
    if (progress < 0.70) {
      return 50 + ((progress - 0.40) / 0.30 * 100).toInt();
    }
    return 150 + ((progress - 0.70) / 0.30 * 150).toInt();
  }

  int _findWinningIndex(HungryCatSpinResult result) {
    // 1. Match by foodId
    for (int i = 0; i < _foods.length; i++) {
      if (_foods[i].foodId == result.foodId) return i;
    }
    // 2. Match by multiplier (closest)
    double best = double.maxFinite;
    int idx = 0;
    for (int i = 0; i < _foods.length; i++) {
      final diff = (_foods[i].multiplier - result.multiplier).abs();
      if (diff < best) { best = diff; idx = i; }
    }
    return idx;
  }

  // ── Display helpers ───────────────────────────────────────────────────────────

  int get _displayFoodCount => _foods.isEmpty ? _kDefaultFoods.length : _foods.length;

  String _emojiAt(int i) {
    if (i < _foods.length) return _foods[i].icon;
    return _kDefaultFoods[i % _kDefaultFoods.length].emoji;
  }

  String _labelAt(int i) {
    final mult = i < _foods.length
        ? _foods[i].multiplier
        : _kDefaultFoods[i % _kDefaultFoods.length].mult;
    final intMult = mult.truncateToDouble() == mult ? mult.toInt() : mult;
    return _ar ? '${intMult}x' : '${intMult}x';
  }

  // ── UI ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08030F),
      body: SafeArea(
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
          const Text('🐱', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _ar ? 'القط الجائع' : 'Hungry Cat',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1A0A), Color(0xFF3D2610)],
              ),
              border: Border.all(color: const Color(0xFFF0C15A).withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text(
                  _formatCoins(_balance),
                  style: const TextStyle(
                    color: Color(0xFFF0C15A),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_phase == _Phase.loading && _foods.isEmpty) {
      return _errorMsg != null ? _buildError() : _buildLoading();
    }
    return Column(
      children: [
        Expanded(child: _buildWheelArea()),
        _buildHistoryStrip(),
        _buildBetSelector(),
        _buildSpinButton(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildWheelArea() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final radius   = size * 0.34;
        final catSize  = size * 0.22;
        final bubSize  = size * 0.195;
        final center   = Offset(size / 2, size / 2);
        final n        = _displayFoodCount;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              // ── Decorative glow ring ──────────────────────────────────────
              Positioned.fill(
                child: CustomPaint(painter: _RingPainter(radius: radius)),
              ),

              // ── Food bubbles ──────────────────────────────────────────────
              for (int i = 0; i < n; i++) ...[
                _positionedBubble(i, n, center, radius, bubSize),
              ],

              // ── Center cat ────────────────────────────────────────────────
              Positioned(
                left:  center.dx - catSize / 2,
                top:   center.dy - catSize / 2,
                width: catSize,
                height: catSize,
                child: _buildCatCenter(catSize),
              ),

              // ── Result overlay ────────────────────────────────────────────
              if (_phase == _Phase.result && _lastResult != null)
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
    final angle = -math.pi / 2 + i * 2 * math.pi / n;
    final left  = center.dx + math.cos(angle) * radius - bubSize / 2;
    final top   = center.dy + math.sin(angle) * radius - bubSize / 2;

    final isActive = i == _highlighted;
    final isWinner = _phase == _Phase.result &&
        _lastResult != null &&
        i == _highlighted;

    return Positioned(
      left: left, top: top,
      width: bubSize, height: bubSize + 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) {
              final scale = isWinner ? _pulseAnim.value : 1.0;
              return Transform.scale(scale: scale, child: child);
            },
            child: _HungryCatBubble(
              emoji:    _emojiAt(i),
              size:     bubSize,
              isActive: isActive,
              isWinner: isWinner,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _labelAt(i),
            style: TextStyle(
              color: isActive
                  ? const Color(0xFFF0C15A)
                  : Colors.white.withValues(alpha: 0.65),
              fontSize: bubSize * 0.2,
              fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatCenter(double size) {
    final spinning = _phase == _Phase.spinning;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            const Color(0xFF3D1C7E),
            const Color(0xFF1A0533),
          ],
        ),
        border: Border.all(
          color: spinning
              ? const Color(0xFFF0C15A).withValues(alpha: 0.7)
              : const Color(0xFF6D28D9).withValues(alpha: 0.6),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: spinning ? 0.5 : 0.25),
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
    final r  = _lastResult!;
    final won = r.rewardAmount > r.betAmount;
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
              gradient: LinearGradient(
                colors: won
                    ? [const Color(0xFF2A1A00), const Color(0xFF3D2610)]
                    : [const Color(0xFF1A0533), const Color(0xFF2D0D5E)],
              ),
              border: Border.all(
                color: won
                    ? const Color(0xFFF0C15A)
                    : const Color(0xFF6D28D9),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (won ? const Color(0xFFF0C15A) : const Color(0xFF8B5CF6))
                      .withValues(alpha: 0.35),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.foodIcon, style: const TextStyle(fontSize: 36)),
                const SizedBox(height: 6),
                Text(
                  r.foodName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  won
                      ? (_ar ? '🎉 ربحت ${_formatCoins(r.rewardAmount)} 🪙' : '🎉 Won ${_formatCoins(r.rewardAmount)} 🪙')
                      : (_ar ? 'حاول مجدداً!' : 'Better luck next time!'),
                  style: TextStyle(
                    color: won ? const Color(0xFFF0C15A) : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── History strip ─────────────────────────────────────────────────────────────

  Widget _buildHistoryStrip() {
    if (_history.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 54,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        reverse: true, // newest at left
        itemCount: _history.length,
        itemBuilder: (ctx, i) {
          final h = _history[i];
          final won = h.rewardAmount > h.betAmount;
          return Container(
            margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
            width: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: won
                  ? const Color(0xFFF0C15A).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: won
                    ? const Color(0xFFF0C15A).withValues(alpha: 0.5)
                    : Colors.white12,
              ),
            ),
            child: Center(
              child: Text(h.foodIcon, style: const TextStyle(fontSize: 22)),
            ),
          );
        },
      ),
    );
  }

  // ── Bet selector ──────────────────────────────────────────────────────────────

  Widget _buildBetSelector() {
    final disabled = _phase == _Phase.spinning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ar ? 'الرهان' : 'Bet Amount',
            style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _kBetChips.map((chip) {
                final selected = chip == _betAmount;
                return GestureDetector(
                  onTap: disabled ? null : () => setState(() => _betAmount = chip),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: selected
                          ? const LinearGradient(
                              colors: [Color(0xFFF0C15A), Color(0xFFD4A017)],
                            )
                          : null,
                      color: selected ? null : Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFF0C15A)
                            : Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected)
                          const Text('🪙', style: TextStyle(fontSize: 13)),
                        if (selected) const SizedBox(width: 4),
                        Text(
                          _formatCoins(chip),
                          style: TextStyle(
                            color: selected ? const Color(0xFF1A0533) : Colors.white70,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Spin button ───────────────────────────────────────────────────────────────

  Widget _buildSpinButton() {
    final canSpin = _phase == _Phase.idle && _balance >= _betAmount;
    final spinning = _phase == _Phase.spinning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: GestureDetector(
        onTap: canSpin ? _spin : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: canSpin
                ? const LinearGradient(
                    colors: [Color(0xFFF0C15A), Color(0xFFD4A017)],
                  )
                : null,
            color: canSpin ? null : Colors.white.withValues(alpha: 0.06),
            boxShadow: canSpin
                ? [const BoxShadow(
                    color: Color(0x55F0C15A), blurRadius: 18, offset: Offset(0, 6))]
                : null,
          ),
          alignment: Alignment.center,
          child: spinning
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                    color: Color(0xFFF0C15A), strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🎰', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(
                      canSpin
                          ? (_ar ? 'العب مقابل ${_formatCoins(_betAmount)} 🪙' : 'Spin for ${_formatCoins(_betAmount)} 🪙')
                          : (_balance < _betAmount
                              ? (_ar ? 'رصيد غير كافٍ' : 'Insufficient coins')
                              : (_ar ? 'انتظر...' : 'Please wait...')),
                      style: TextStyle(
                        color: canSpin ? const Color(0xFF1A0533) : Colors.white38,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ── Loading / Error ───────────────────────────────────────────────────────────

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
            _ar ? 'جاري التحميل...' : 'Loading...',
            style: const TextStyle(color: Color(0xFFF0C15A), fontSize: 15, fontWeight: FontWeight.w700),
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
              _ar ? 'تعذر تحميل اللعبة' : 'Failed to load',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
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

  // ── Utilities ─────────────────────────────────────────────────────────────────

  String _formatCoins(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    return '$v';
  }

  String _friendlyError(String e) {
    if (e.contains('insufficient_coins')) return 'Insufficient coins';
    if (e.contains('game_disabled'))      return 'Game is currently disabled';
    if (e.contains('duplicate'))          return 'Duplicate request, please try again';
    return 'Something went wrong. Please try again.';
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

// ── Option bubble widget ──────────────────────────────────────────────────────

class _HungryCatBubble extends StatelessWidget {
  const _HungryCatBubble({
    required this.emoji,
    required this.size,
    required this.isActive,
    required this.isWinner,
  });

  final String emoji;
  final double size;
  final bool   isActive;
  final bool   isWinner;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: isActive
              ? [const Color(0xFF3D2610), const Color(0xFF2A1A00)]
              : [const Color(0xFF1E0D3E), const Color(0xFF130826)],
        ),
        border: Border.all(
          color: isWinner
              ? const Color(0xFFF0C15A)
              : isActive
                  ? const Color(0xFFF0C15A).withValues(alpha: 0.85)
                  : const Color(0xFF4A1C8C).withValues(alpha: 0.55),
          width: isActive ? 2.5 : 1.5,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFFF0C15A).withValues(alpha: isWinner ? 0.7 : 0.45),
                  blurRadius: isWinner ? 20 : 12,
                  spreadRadius: isWinner ? 3 : 0,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size * 0.44)),
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
