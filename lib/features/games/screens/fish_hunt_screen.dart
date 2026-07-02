import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/coin_ui.dart';
import '../models/fish_hunt_models.dart';
import '../services/fish_hunt_service.dart';

/// Srood Fish Hunt — server-authoritative shooting game. The client only
/// renders fish positions, a cannon, and visual feedback; it forwards taps
/// as shots and the hit/miss roll, wallet debit, and payout are decided
/// entirely by `fish_hunt_place_shot`. Nothing here computes a payout.
class FishHuntScreen extends StatefulWidget {
  const FishHuntScreen({
    required this.isArabic,
    this.roomId,
    this.service = const FishHuntService(),
    super.key,
  });

  final bool isArabic;
  final String? roomId;
  final FishHuntService service;

  @override
  State<FishHuntScreen> createState() => _FishHuntScreenState();
}

const List<int> kFishHuntBetAmounts = [
  100,
  500,
  1000,
  5000,
  10000,
  20000,
  100000,
];

enum _FishRarity { common, medium, rare, epic, boss }

_FishRarity _rarityFor(double multiplier) {
  if (multiplier < 3) return _FishRarity.common;
  if (multiplier < 5) return _FishRarity.medium;
  if (multiplier < 7) return _FishRarity.rare;
  if (multiplier < 9) return _FishRarity.epic;
  return _FishRarity.boss;
}

Color _rarityColor(_FishRarity r) {
  switch (r) {
    case _FishRarity.common:
      return const Color(0xFF2DD4BF);
    case _FishRarity.medium:
      return const Color(0xFF38BDF8);
    case _FishRarity.rare:
      return const Color(0xFFA78BFA);
    case _FishRarity.epic:
      return const Color(0xFFFB923C);
    case _FishRarity.boss:
      return const Color(0xFFF43F5E);
  }
}

double _raritySizeScale(_FishRarity r) {
  switch (r) {
    case _FishRarity.common:
      return 0.85;
    case _FishRarity.medium:
      return 1.0;
    case _FishRarity.rare:
      return 1.15;
    case _FishRarity.epic:
      return 1.3;
    case _FishRarity.boss:
      return 1.55;
  }
}

class _FishHuntFishVisual {
  _FishHuntFishVisual({
    required this.fish,
    required this.lane,
    required this.direction,
    required this.speed,
    required this.phase,
  });

  final FishHuntFish fish;
  final int lane;
  final int direction; // 1 = left-to-right, -1 = right-to-left
  final double speed; // lane widths per second
  final double phase;
}

enum _FxType { trail, splash, coin, text }

class _FishHuntFx {
  _FishHuntFx({
    required this.type,
    required this.start,
    required this.from,
    required this.to,
    this.text,
    required this.color,
  });

  final _FxType type;
  final DateTime start;
  final Offset from;
  final Offset to;
  final String? text;
  final Color color;

  static const Map<_FxType, int> _durationsMs = {
    _FxType.trail: 160,
    _FxType.splash: 380,
    _FxType.coin: 650,
    _FxType.text: 900,
  };

  double progress(DateTime now) {
    final ms = now.difference(start).inMilliseconds;
    final dur = _durationsMs[type]!;
    return (ms / dur).clamp(0.0, 1.0);
  }

  bool isExpired(DateTime now) =>
      now.difference(start).inMilliseconds > _durationsMs[type]!;
}

class _FishHuntScreenState extends State<FishHuntScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  Timer? _pollTimer;

  bool _loading = true;
  String? _loadError;
  FishHuntState? _state;
  int _betIndex = 0;
  final Set<String> _pendingFishIds = {};
  final Map<String, _FishHuntFishVisual> _visuals = {};
  String? _toastMessage;
  bool _toastIsHit = false;
  Timer? _toastTimer;

  final List<_FishHuntFx> _fx = [];
  double _aimAngle = -pi / 2;
  bool _panelExpanded = true;
  bool _panelAutoCollapsed = false;

  static const int _laneCount = 5;
  final Random _layoutRandom = Random();

  bool get _isArabic => widget.isArabic;
  int get _betAmount => kFishHuntBetAmounts[_betIndex];

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..repeat();
    _loadState();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadState(silent: true);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pollTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadState({bool silent = false}) async {
    if (SupabaseService.requiredClient.auth.currentUser == null) {
      setState(() {
        _loading = false;
        _loadError = 'not_authenticated';
      });
      return;
    }
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final state = await widget.service.fetchState(roomId: widget.roomId);
      if (!mounted) return;
      _syncVisuals(state.fish);
      setState(() {
        _state = state;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _loadError = '$e';
      });
    }
  }

  void _syncVisuals(List<FishHuntFish> fish) {
    final liveIds = fish.map((f) => f.fishId).toSet();
    _visuals.removeWhere((id, _) => !liveIds.contains(id));
    for (final f in fish) {
      final existing = _visuals[f.fishId];
      if (existing != null) {
        _visuals[f.fishId] = _FishHuntFishVisual(
          fish: f,
          lane: existing.lane,
          direction: existing.direction,
          speed: existing.speed,
          phase: existing.phase,
        );
      } else {
        _visuals[f.fishId] = _FishHuntFishVisual(
          fish: f,
          lane: _layoutRandom.nextInt(_laneCount),
          direction: _layoutRandom.nextBool() ? 1 : -1,
          speed: 0.10 + _layoutRandom.nextDouble() * 0.08,
          phase: _layoutRandom.nextDouble() * pi * 2,
        );
      }
    }
  }

  Offset _positionFor(_FishHuntFishVisual v, Size size, double t) {
    final laneHeight = size.height / (_laneCount + 1);
    final y =
        laneHeight * (v.lane + 1) +
        sin(t * 1.4 + v.phase) * (laneHeight * 0.18);
    final cycle = (t * v.speed) % 1.0;
    final progress = v.direction == 1 ? cycle : 1 - cycle;
    final margin = 36.0;
    final x = margin + progress * (size.width - margin * 2);
    return Offset(x, y);
  }

  Offset _cannonPositionFor(Size size) =>
      Offset(size.width / 2, size.height - 36);

  void _pruneExpiredFx() {
    final now = DateTime.now();
    _fx.removeWhere((f) => f.isExpired(now));
  }

  Future<void> _onShoot(
    _FishHuntFishVisual v,
    Offset targetPos,
    Size size,
  ) async {
    final state = _state;
    if (state == null || !state.hasActiveRound) return;
    if (_pendingFishIds.contains(v.fish.fishId)) return;
    if (v.fish.isExpired) return;
    if (state.balance < _betAmount) {
      _showToast(
        _isArabic ? 'رصيد غير كافٍ' : 'Insufficient coins',
        isHit: false,
      );
      return;
    }

    final cannonPos = _cannonPositionFor(size);
    final now = DateTime.now();
    _pruneExpiredFx();
    setState(() {
      _pendingFishIds.add(v.fish.fishId);
      _aimAngle = atan2(
        targetPos.dy - cannonPos.dy,
        targetPos.dx - cannonPos.dx,
      );
      _fx.add(
        _FishHuntFx(
          type: _FxType.trail,
          start: now,
          from: cannonPos,
          to: targetPos,
          color: const Color(0xFFFFE566),
        ),
      );
    });

    try {
      final result = await widget.service.placeShot(
        fishId: v.fish.fishId,
        betAmount: _betAmount,
        roomId: widget.roomId,
      );
      if (!mounted) return;
      final hitNow = DateTime.now();
      // Build on the *current* state (a poll may have refreshed it during the
      // RPC), and only remove the fish when it was actually caught — a missed
      // fish keeps swimming.
      final latest = _state ?? state;
      setState(() {
        _state = FishHuntState(
          roundId: latest.roundId,
          roundStatus: latest.roundStatus,
          fish: result.isHit
              ? latest.fish.where((f) => f.fishId != v.fish.fishId).toList()
              : latest.fish,
          balance: result.newBalance,
          recentShots: latest.recentShots,
          serverNow: latest.serverNow,
        );
        if (result.isHit) _visuals.remove(v.fish.fishId);
        _fx.add(
          _FishHuntFx(
            type: _FxType.splash,
            start: hitNow,
            from: targetPos,
            to: targetPos,
            color: result.isHit ? const Color(0xFF4ADE80) : Colors.white54,
          ),
        );
        if (result.isHit) {
          _fx.add(
            _FishHuntFx(
              type: _FxType.coin,
              start: hitNow,
              from: targetPos,
              to: targetPos,
              color: kCoinGoldMid,
            ),
          );
        }
        _fx.add(
          _FishHuntFx(
            type: _FxType.text,
            start: hitNow,
            from: targetPos,
            to: targetPos,
            text: result.isHit
                ? '+${formatCoinAmount(result.payoutAmount)}'
                : (_isArabic ? 'فاتك' : 'Miss'),
            color: result.isHit ? const Color(0xFF4ADE80) : Colors.white70,
          ),
        );
      });
      _showToast(
        result.isHit
            ? (_isArabic
                  ? '🎯 إصابة! +${formatCoinAmount(result.payoutAmount)}'
                  : '🎯 Hit! +${formatCoinAmount(result.payoutAmount)}')
            : (_isArabic ? 'فاتك السمكة' : 'Missed'),
        isHit: result.isHit,
      );
    } catch (e) {
      if (!mounted) return;
      _showToast(_isArabic ? 'تعذر إطلاق النار' : 'Shot failed', isHit: false);
    } finally {
      if (mounted) {
        setState(() => _pendingFishIds.remove(v.fish.fishId));
      }
    }
  }

  void _showToast(String message, {required bool isHit}) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastIsHit = isHit;
    });
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _toastMessage = null);
    });
  }

  void _handleTap(Offset local, Size size, double t) {
    _FishHuntFishVisual? best;
    Offset bestPos = local;
    double bestDist = double.infinity;
    for (final v in _visuals.values) {
      final pos = _positionFor(v, size, t);
      final dist = (pos - local).distance;
      if (dist < 34 && dist < bestDist) {
        best = v;
        bestPos = pos;
        bestDist = dist;
      }
    }
    if (best != null) _onShoot(best, bestPos, size);
  }

  void _showHelpSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1F3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isArabic ? 'كيف ألعب؟' : 'How to play',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isArabic
                  ? 'اضغط على أي سمكة لإطلاق النار عليها. كل إصابة تدفع وفق مضاعف السمكة. اختر وزن الرهان من الأسفل قبل الإطلاق.'
                  : 'Tap any fish to shoot it. Each hit pays out according to that '
                        'fish\'s multiplier. Pick your wager below before firing.',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showLeaderboardSheet() async {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1F3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: widget.service.fetchLeaderboard(roomId: widget.roomId),
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const [];
            return SizedBox(
              height: 360,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isArabic ? 'لوحة المتصدرين' : 'Leaderboard',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF4ADE80),
                          ),
                        ),
                      )
                    else if (entries.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            _isArabic ? 'لا توجد بيانات بعد' : 'No data yet',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) =>
                              const Divider(color: Colors.white12, height: 16),
                          itemBuilder: (context, i) {
                            final row = entries[i];
                            final net =
                                (row['net_winnings'] as num?)?.toInt() ?? 0;
                            return Row(
                              children: [
                                Text(
                                  '#${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    (row['user_id'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                CoinAmountText(amount: net, fontSize: 13),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360 && _panelExpanded && !_panelAutoCollapsed) {
      // Default the value panel collapsed on very narrow screens so it never
      // competes with the play field for space — but only once, so the user
      // can still expand it manually afterwards.
      _panelAutoCollapsed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _panelExpanded = false);
      });
    }
    return Scaffold(
      backgroundColor: const Color(0xFF021024),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildBody()),
            _buildInstructionBanner(),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final balance = _state?.balance ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            _topIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _isArabic ? 'صيد سرود' : 'Srood Fish Hunt',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  color: const Color(0xFF0E3A5F),
                  border: Border.all(color: const Color(0xFF1F6FA8)),
                ),
                child: CoinAmountText(
                  amount: balance,
                  fontSize: 12,
                  iconSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 4),
            _topIconButton(
              icon: Icons.help_outline_rounded,
              onTap: _showHelpSheet,
            ),
            _topIconButton(
              icon: Icons.emoji_events_rounded,
              onTap: _showLeaderboardSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _topIconButton({required IconData icon, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0E3A5F),
            border: Border.all(color: const Color(0xFF1F6FA8)),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _state == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4ADE80)),
      );
    }
    if (_loadError != null && _state == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white54,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                _isArabic ? 'تعذر تحميل اللعبة' : 'Failed to load',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _loadState(),
                child: Text(_isArabic ? 'إعادة المحاولة' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final state = _state;
    final hasRound = state?.hasActiveRound ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ticker,
            builder: (context, _) {
              final tMs = _ticker.lastElapsedDuration?.inMilliseconds ?? 0;
              final t = tMs / 1000.0;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: hasRound
                        ? (details) =>
                              _handleTap(details.localPosition, size, t)
                        : null,
                    child: CustomPaint(
                      painter: _FishHuntPainter(
                        visuals: _visuals.values.toList(growable: false),
                        t: t,
                        positionFor: _positionFor,
                        pendingIds: _pendingFishIds,
                        cannonPos: _cannonPositionFor(size),
                        aimAngle: _aimAngle,
                        fx: _fx,
                        now: DateTime.now(),
                      ),
                      size: size,
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (!hasRound)
          Center(
            child: Text(
              _isArabic ? 'بانتظار جولة جديدة...' : 'Waiting for round...',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
        _buildValuePanel(),
        if (_toastMessage != null)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color:
                      (_toastIsHit
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF334155))
                          .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _toastMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildValuePanel() {
    final entries = <(_FishRarity, String)>[
      (_FishRarity.common, 'x2'),
      (_FishRarity.medium, 'x3'),
      (_FishRarity.rare, 'x5'),
      (_FishRarity.epic, 'x7'),
      (_FishRarity.boss, 'x11'),
    ];
    return Positioned(
      left: 0,
      top: 8,
      bottom: 8,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _panelExpanded ? 96 : 28,
        decoration: BoxDecoration(
          color: const Color(0xFF03182E).withValues(alpha: 0.85),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
          border: const Border(
            top: BorderSide(color: Color(0xFF1F6FA8)),
            right: BorderSide(color: Color(0xFF1F6FA8)),
            bottom: BorderSide(color: Color(0xFF1F6FA8)),
          ),
        ),
        child: _panelExpanded
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isArabic ? 'قيمة السمك' : 'Fish Value',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _panelExpanded = false),
                          child: const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.chevron_left_rounded,
                              color: Colors.white54,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 6,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _rarityColor(e.$1),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                e.$2,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : InkWell(
                onTap: () => setState(() => _panelExpanded = true),
                child: const Center(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white54,
                    size: 16,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildInstructionBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0E3A5F).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _isArabic
              ? 'اضغط على السمكة للإطلاق • ارفع وزن الرهان لمكافآت أكبر'
              : 'Tap a fish to shoot • Increase wager for bigger rewards',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final balance = _state?.balance ?? 0;
    return Container(
      padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + max(bottomInset, 8.0)),
      decoration: const BoxDecoration(
        color: Color(0xFF03182E),
        border: Border(top: BorderSide(color: Color(0xFF0E3A5F))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: kFishHuntBetAmounts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final amount = kFishHuntBetAmounts[i];
                final selected = i == _betIndex;
                return GestureDetector(
                  onTap: () => setState(() => _betIndex = i),
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 36,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: selected
                          ? const Color(0xFFF5A820)
                          : const Color(0xFF0E3A5F),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFFFE566)
                            : const Color(0xFF1F6FA8),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatCoinAmount(amount),
                        maxLines: 1,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFF3D1F00)
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFF0E3A5F),
                    border: Border.all(color: const Color(0xFF1F6FA8)),
                  ),
                  child: CoinAmountText(
                    amount: balance,
                    fontSize: 13,
                    iconSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [kCoinGoldLight, kCoinGoldMid, kCoinGoldDark],
                      ),
                    ),
                    child: const Icon(
                      Icons.gps_fixed_rounded,
                      color: Color(0xFF3D1F00),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatCoinAmount(_betAmount),
                    style: const TextStyle(
                      color: kCoinGoldLight,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              _stepperButton(
                icon: Icons.remove_rounded,
                onTap: _betIndex > 0 ? () => setState(() => _betIndex--) : null,
              ),
              const SizedBox(width: 6),
              _stepperButton(
                icon: Icons.add_rounded,
                onTap: _betIndex < kFishHuntBetAmounts.length - 1
                    ? () => setState(() => _betIndex++)
                    : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isArabic
                              ? 'الوضع التلقائي قريباً'
                              : 'Auto mode coming soon',
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFF0E3A5F).withValues(alpha: 0.6),
                      border: Border.all(color: const Color(0xFF1F6FA8)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          color: Colors.white38,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isArabic ? 'تلقائي' : 'AUTO',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? const Color(0xFF0E3A5F)
              : const Color(0xFF0E3A5F).withValues(alpha: 0.4),
          border: Border.all(color: const Color(0xFF1F6FA8)),
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white24,
          size: 18,
        ),
      ),
    );
  }
}

class _FishHuntPainter extends CustomPainter {
  _FishHuntPainter({
    required this.visuals,
    required this.t,
    required this.positionFor,
    required this.pendingIds,
    required this.cannonPos,
    required this.aimAngle,
    required this.fx,
    required this.now,
  });

  final List<_FishHuntFishVisual> visuals;
  final double t;
  final Offset Function(_FishHuntFishVisual, Size, double) positionFor;
  final Set<String> pendingIds;
  final Offset cannonPos;
  final double aimAngle;
  final List<_FishHuntFx> fx;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    _paintOcean(canvas, size);
    for (final v in visuals) {
      _paintFish(canvas, v, size);
    }
    _paintFx(canvas);
    _paintCannon(canvas, size);
  }

  void _paintOcean(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0B3D63), Color(0xFF03182E), Color(0xFF010B18)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Soft light rays.
    final rayPaint = Paint()..color = Colors.white.withValues(alpha: 0.04);
    for (int i = 0; i < 4; i++) {
      final baseX = size.width * (0.15 + i * 0.25) + sin(t * 0.2 + i) * 14;
      final path = Path()
        ..moveTo(baseX - 28, 0)
        ..lineTo(baseX + 28, 0)
        ..lineTo(baseX + 70, size.height * 0.65)
        ..lineTo(baseX - 70, size.height * 0.65)
        ..close();
      canvas.drawPath(path, rayPaint);
    }

    // Rising bubbles.
    final bubblePaint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    final rnd = Random(7);
    for (int i = 0; i < 18; i++) {
      final seedX = rnd.nextDouble();
      final seedSpeed = 0.06 + rnd.nextDouble() * 0.08;
      final seedPhase = rnd.nextDouble() * 10;
      final cycle = ((t * seedSpeed) + seedPhase) % 1.0;
      final x = seedX * size.width + sin(t * 0.6 + seedPhase) * 6;
      final y = size.height - cycle * size.height;
      final r = 1.5 + (i % 4) * 0.8;
      canvas.drawCircle(Offset(x, y), r, bubblePaint);
    }

    // Sea floor silhouette.
    final floorPaint = Paint()..color = const Color(0xFF021022);
    final floorPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height - 18)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height - 36,
        size.width * 0.5,
        size.height - 14,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height + 6,
        size.width,
        size.height - 22,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(floorPath, floorPaint);
  }

  void _paintFish(Canvas canvas, _FishHuntFishVisual v, Size size) {
    final pos = positionFor(v, size, t);
    final isPending = pendingIds.contains(v.fish.fishId);
    final rarity = _rarityFor(v.fish.rewardMultiplier);
    final color = isPending ? Colors.white54 : _rarityColor(rarity);
    final scale = _raritySizeScale(rarity);
    final bodyLength = 30.0 * scale;
    final bodyHeight = 16.0 * scale;
    final facingRight = v.direction == 1;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    if (!facingRight) canvas.scale(-1, 1);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: bodyLength * 1.6,
        height: bodyHeight * 1.8,
      ),
      glowPaint,
    );

    final bodyPaint = Paint()
      ..shader =
          LinearGradient(
            colors: [
              color.withValues(alpha: 0.95),
              color.withValues(alpha: 0.55),
            ],
          ).createShader(
            Rect.fromCenter(
              center: Offset.zero,
              width: bodyLength,
              height: bodyHeight,
            ),
          );
    final bodyPath = Path()
      ..moveTo(-bodyLength * 0.5, 0)
      ..quadraticBezierTo(
        -bodyLength * 0.2,
        -bodyHeight * 0.5,
        bodyLength * 0.35,
        -bodyHeight * 0.25,
      )
      ..quadraticBezierTo(
        bodyLength * 0.5,
        0,
        bodyLength * 0.35,
        bodyHeight * 0.25,
      )
      ..quadraticBezierTo(
        -bodyLength * 0.2,
        bodyHeight * 0.5,
        -bodyLength * 0.5,
        0,
      )
      ..close();
    canvas.drawPath(bodyPath, bodyPaint);

    final tailPaint = Paint()..color = color.withValues(alpha: 0.8);
    final tailPath = Path()
      ..moveTo(-bodyLength * 0.5, 0)
      ..lineTo(-bodyLength * 0.78, -bodyHeight * 0.45)
      ..lineTo(-bodyLength * 0.78, bodyHeight * 0.45)
      ..close();
    canvas.drawPath(tailPath, tailPaint);

    canvas.drawCircle(
      Offset(bodyLength * 0.28, -bodyHeight * 0.05),
      1.6,
      Paint()..color = Colors.black87,
    );
    canvas.restore();

    final badgeText =
        'x${v.fish.rewardMultiplier.toStringAsFixed(v.fish.rewardMultiplier >= 10 ? 0 : 1)}';
    final tp = TextPainter(
      text: TextSpan(
        text: badgeText,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final badgeRect = Rect.fromCenter(
      center: pos - Offset(0, bodyHeight * scale * 0.0 + 22 * scale),
      width: tp.width + 10,
      height: tp.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(8)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
    tp.paint(canvas, badgeRect.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintCannon(Canvas canvas, Size size) {
    final recoilFx = fx
        .where((f) => f.type == _FxType.trail && !f.isExpired(now))
        .toList();
    double recoil = 0;
    if (recoilFx.isNotEmpty) {
      final p = recoilFx.last.progress(now);
      recoil = (1 - p) * 6;
    }

    canvas.save();
    canvas.translate(cannonPos.dx, cannonPos.dy);

    // Base.
    final basePaint = Paint()
      ..shader = const RadialGradient(
        colors: [kCoinGoldLight, kCoinGoldMid, kCoinGoldDark],
      ).createShader(const Rect.fromLTWH(-26, -10, 52, 24));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-26, 0, 52, 20),
        const Radius.circular(8),
      ),
      basePaint,
    );

    // Barrel, rotated toward the aim angle.
    canvas.save();
    canvas.rotate(aimAngle + pi / 2);
    final barrelPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFE5E7EB), Color(0xFF6B7280)],
      ).createShader(const Rect.fromLTWH(-7, -38, 14, 38));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-7, -38 + recoil, 14, 38),
        const Radius.circular(6),
      ),
      barrelPaint,
    );
    canvas.restore();
    canvas.restore();
  }

  void _paintFx(Canvas canvas) {
    for (final f in fx) {
      if (f.isExpired(now)) continue;
      final p = f.progress(now);
      switch (f.type) {
        case _FxType.trail:
          final pos = Offset.lerp(f.from, f.to, p)!;
          canvas.drawCircle(
            pos,
            3,
            Paint()..color = f.color.withValues(alpha: 1 - p),
          );
          canvas.drawLine(
            f.from,
            pos,
            Paint()
              ..color = f.color.withValues(alpha: (1 - p) * 0.6)
              ..strokeWidth = 2,
          );
        case _FxType.splash:
          final r = 6 + p * 26;
          canvas.drawCircle(
            f.to,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = f.color.withValues(alpha: 1 - p),
          );
        case _FxType.coin:
          final rnd = Random(f.start.microsecondsSinceEpoch);
          for (int i = 0; i < 5; i++) {
            final angle = rnd.nextDouble() * pi * 2;
            final dist = p * (18 + rnd.nextDouble() * 14);
            final pos =
                f.to +
                Offset(cos(angle), sin(angle)) * dist -
                Offset(0, p * 10);
            canvas.drawCircle(
              pos,
              3.0 * (1 - p) + 1.0,
              Paint()..color = f.color.withValues(alpha: 1 - p),
            );
          }
        case _FxType.text:
          if (f.text == null) continue;
          final tp = TextPainter(
            text: TextSpan(
              text: f.text,
              style: TextStyle(
                color: f.color.withValues(alpha: 1 - p),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final pos = f.to - Offset(tp.width / 2, 30 + p * 20);
          tp.paint(canvas, pos);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FishHuntPainter oldDelegate) => true;
}
