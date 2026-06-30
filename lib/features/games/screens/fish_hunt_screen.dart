import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/coin_ui.dart';
import '../models/fish_hunt_models.dart';
import '../services/fish_hunt_service.dart';

/// Srood Fish Hunt — server-authoritative shooting game. The client only
/// renders fish positions and forwards taps; the hit/miss roll, wallet
/// debit, and payout are decided entirely by `fish_hunt_place_shot`.
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

class _FishHuntScreenState extends State<FishHuntScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  Timer? _pollTimer;

  bool _loading = true;
  String? _loadError;
  FishHuntState? _state;
  int _betAmount = kFishHuntBetAmounts.first;
  final Set<String> _pendingFishIds = {};
  final Map<String, _FishHuntFishVisual> _visuals = {};
  String? _toastMessage;
  bool _toastIsHit = false;
  Timer? _toastTimer;

  static const int _laneCount = 5;
  final Random _layoutRandom = Random();

  bool get _isArabic => widget.isArabic;

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

  Future<void> _onShoot(_FishHuntFishVisual v) async {
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

    setState(() => _pendingFishIds.add(v.fish.fishId));
    try {
      final result = await widget.service.placeShot(
        fishId: v.fish.fishId,
        betAmount: _betAmount,
        roomId: widget.roomId,
      );
      if (!mounted) return;
      setState(() {
        _state = FishHuntState(
          roundId: state.roundId,
          roundStatus: state.roundStatus,
          fish: state.fish.where((f) => f.fishId != v.fish.fishId).toList(),
          balance: result.newBalance,
          recentShots: state.recentShots,
          serverNow: state.serverNow,
        );
        _visuals.remove(v.fish.fishId);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF021024),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
            _buildBetBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final balance = _state?.balance ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Text(
              _isArabic ? 'صيد سرود' : 'Srood Fish Hunt',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: const Color(0xFF0E3A5F),
              border: Border.all(color: const Color(0xFF1F6FA8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppCoinIcon(size: 16),
                const SizedBox(width: 6),
                Text(
                  formatCoinAmount(balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF03182E), Color(0xFF021024)],
            ),
          ),
        ),
        if (!hasRound)
          Center(
            child: Text(
              _isArabic ? 'بانتظار جولة جديدة...' : 'Waiting for round...',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          )
        else
          AnimatedBuilder(
            animation: _ticker,
            builder: (context, _) {
              final t = _ticker.lastElapsedDuration?.inMilliseconds ?? 0;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) =>
                        _handleTap(details.localPosition, size, t / 1000.0),
                    child: CustomPaint(
                      painter: _FishHuntPainter(
                        visuals: _visuals.values.toList(growable: false),
                        t: t / 1000.0,
                        positionFor: _positionFor,
                        pendingIds: _pendingFishIds,
                      ),
                      size: size,
                    ),
                  );
                },
              );
            },
          ),
        if (_toastMessage != null)
          Positioned(
            top: 12,
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

  void _handleTap(Offset local, Size size, double t) {
    _FishHuntFishVisual? best;
    double bestDist = double.infinity;
    for (final v in _visuals.values) {
      final pos = _positionFor(v, size, t);
      final dist = (pos - local).distance;
      if (dist < 34 && dist < bestDist) {
        best = v;
        bestDist = dist;
      }
    }
    if (best != null) _onShoot(best);
  }

  Widget _buildBetBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF03182E),
        border: Border(top: BorderSide(color: Color(0xFF0E3A5F))),
      ),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: kFishHuntBetAmounts.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final amount = kFishHuntBetAmounts[i];
            final selected = amount == _betAmount;
            return GestureDetector(
              onTap: () => setState(() => _betAmount = amount),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
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
                child: Text(
                  formatCoinAmount(amount),
                  style: TextStyle(
                    color: selected ? const Color(0xFF3D1F00) : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          },
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
  });

  final List<_FishHuntFishVisual> visuals;
  final double t;
  final Offset Function(_FishHuntFishVisual, Size, double) positionFor;
  final Set<String> pendingIds;

  @override
  void paint(Canvas canvas, Size size) {
    for (final v in visuals) {
      final pos = positionFor(v, size, t);
      final isPending = pendingIds.contains(v.fish.fishId);
      final radius = 22.0 + (v.fish.rewardMultiplier.clamp(1, 50)) * 0.3;

      final glowPaint = Paint()
        ..color = (isPending ? Colors.white : const Color(0xFF38BDF8))
            .withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(pos, radius + 6, glowPaint);

      final bodyPaint = Paint()
        ..color = isPending ? const Color(0xFF94A3B8) : const Color(0xFF0EA5E9);
      canvas.drawCircle(pos, radius, bodyPaint);

      final textSpan = TextSpan(
        text: 'x${v.fish.rewardMultiplier.toStringAsFixed(0)}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _FishHuntPainter oldDelegate) => true;
}
