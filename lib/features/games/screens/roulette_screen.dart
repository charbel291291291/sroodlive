import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/coin_ui.dart';
import '../models/roulette_models.dart';
import '../services/roulette_service.dart';

/// Srood Roulette — server-authoritative table game. The client only shows
/// round state and forwards bets; the winning number, wallet debit/credit,
/// and every payout are decided entirely by the round-engine RPCs.
class RouletteScreen extends StatefulWidget {
  const RouletteScreen({
    required this.isArabic,
    this.roomId,
    this.service = const RouletteService(),
    super.key,
  });

  final bool isArabic;
  final String? roomId;
  final RouletteService service;

  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

const List<int> kRouletteRedNumbers = [
  1,
  3,
  5,
  7,
  9,
  12,
  14,
  16,
  18,
  19,
  21,
  23,
  25,
  27,
  30,
  32,
  34,
  36,
];

// Standard European roulette wheel sequence, used only for the decorative
// wheel visual — bet resolution stays entirely server-side.
const List<int> _kWheelSequence = [
  0,
  32,
  15,
  19,
  4,
  21,
  2,
  25,
  17,
  34,
  6,
  27,
  13,
  36,
  11,
  30,
  8,
  23,
  10,
  5,
  24,
  16,
  33,
  1,
  20,
  14,
  31,
  9,
  22,
  18,
  29,
  7,
  28,
  12,
  35,
  3,
  26,
];

bool _isRed(int n) => kRouletteRedNumbers.contains(n);

// No backend data source for a live "top winners" leaderboard yet — keep this
// off until one exists rather than shipping a fake/static strip.
const bool kShowTopWinnersPlaceholder = false;

/// Bet zones that pay out for a given winning number, used to highlight the
/// winning zone(s) on the board after settlement. Mirrors the multiplier
/// logic in the `roulette_place_bet` RPC — display-only, no payout math.
Set<String> _winningZonesFor(int n) {
  final zones = <String>{};
  if (n == 0) {
    zones.add('straight_zero');
    return zones;
  }
  if (n >= 1 && n <= 12) zones.add('low');
  if (n >= 13 && n <= 24) zones.add('mid');
  if (n >= 25 && n <= 36) zones.add('high');
  zones.add(_isRed(n) ? 'red' : 'black');
  zones.add(n.isEven ? 'even' : 'odd');
  return zones;
}

class _RouletteScreenState extends State<RouletteScreen>
    with SingleTickerProviderStateMixin {
  Timer? _pollTimer;
  Timer? _clockTimer;

  bool _loading = true;
  String? _loadError;
  RouletteState? _state;
  int _betIndex = 0;
  final Set<String> _pendingZones = {};
  String? _toastMessage;
  bool _toastIsError = false;
  Timer? _toastTimer;
  DateTime _now = DateTime.now();

  // Short-lived highlight on the zone the user most recently bet, so the tap
  // gets an immediate visual pulse/glow independent of the poll refresh.
  String? _flashZone;
  Timer? _flashTimer;

  // Tracks which settled round we've already shown a result banner/burst for,
  // so repeated 2s polls of the same settled round don't re-trigger it.
  String? _resultShownForRoundId;
  bool _resultIsWin = false;
  int _resultWinAmount = 0;
  bool _burstActive = false;
  Timer? _burstTimer;

  late final AnimationController _wheelController;

  bool get _isArabic => widget.isArabic;
  int get _betAmount => kRouletteBetAmounts[_betIndex];

  // Smooth 0..1 oscillation driven by the 250ms clock tick; used for the
  // urgent last-seconds glow and the just-placed-bet flash.
  double get _pulse =>
      0.5 + 0.5 * math.sin(_now.millisecondsSinceEpoch / 170.0);

  @override
  void initState() {
    super.initState();
    _loadState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadState(silent: true);
    });
    _clockTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      // _now only drives the open-betting countdown and its urgency pulse —
      // skip the whole-screen rebuild in every other round phase.
      if (_state?.round?.status != 'betting_open') return;
      setState(() => _now = DateTime.now());
    });
    _wheelController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _toastTimer?.cancel();
    _flashTimer?.cancel();
    _burstTimer?.cancel();
    _wheelController.dispose();
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
      setState(() {
        _state = state;
        _loading = false;
        _loadError = null;
      });
      _maybeShowRoundResult(state);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _loadError = '$e';
      });
    }
  }

  Future<void> _onBetZone(String zone) async {
    final state = _state;
    if (state == null || !state.canBet) return;
    if (_pendingZones.contains(zone)) return;
    if (state.balance < _betAmount) {
      _showToast(
        _isArabic ? 'رصيد غير كافٍ' : 'Insufficient coins',
        isError: true,
      );
      return;
    }

    _flashTimer?.cancel();
    setState(() {
      _pendingZones.add(zone);
      _flashZone = zone;
    });
    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _flashZone = null);
    });
    try {
      final result = await widget.service.placeBet(
        roundId: state.round!.roundId,
        betZone: zone,
        betAmount: _betAmount,
      );
      if (!mounted) return;
      _showToast(
        _isArabic
            ? 'راهنت ${formatCoinAmount(result.betAmount)}'
            : 'Bet placed: ${formatCoinAmount(result.betAmount)}',
        isError: false,
      );
      await _loadState(silent: true);
    } catch (e) {
      if (!mounted) return;
      final errStr = '$e'.toLowerCase();
      if (errStr.contains('betting_closed') ||
          errStr.contains('round_not_found')) {
        _showToast(
          _isArabic
              ? 'انتهت الجولة، جارٍ التحديث...'
              : 'Round closed, refreshing…',
          isError: true,
        );
        await _loadState(silent: true);
      } else if (errStr.contains('insufficient_coins')) {
        _showToast(
          _isArabic ? 'رصيد غير كافٍ' : 'Insufficient coins',
          isError: true,
        );
      } else if (errStr.contains('invalid_bet_amount') ||
          errStr.contains('invalid_bet_zone')) {
        _showToast(_isArabic ? 'رهان غير صالح' : 'Invalid bet', isError: true);
      } else if (errStr.contains('not_authenticated')) {
        _showToast(
          _isArabic ? 'يرجى تسجيل الدخول' : 'Please sign in',
          isError: true,
        );
      } else {
        _showToast(_isArabic ? 'تعذر الرهان' : 'Bet failed', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _pendingZones.remove(zone));
      }
    }
  }

  // Shows the win/loss banner (and coin burst on a win) exactly once per
  // newly-settled round that the user had a bet in.
  void _maybeShowRoundResult(RouletteState state) {
    final round = state.round;
    if (round == null || round.status != 'settled') return;
    if (round.roundId == _resultShownForRoundId) return;
    if (state.myBets.isEmpty) return;

    var won = 0;
    var anyWon = false;
    for (final b in state.myBets) {
      if (b.status == 'won') {
        anyWon = true;
        won += b.payoutAmount;
      }
    }

    setState(() {
      _resultShownForRoundId = round.roundId;
      _resultIsWin = anyWon;
      _resultWinAmount = won;
      _burstActive = anyWon;
    });
    if (anyWon) {
      _burstTimer?.cancel();
      _burstTimer = Timer(const Duration(milliseconds: 1100), () {
        if (!mounted) return;
        setState(() => _burstActive = false);
      });
    }
  }

  void _showToast(String message, {required bool isError}) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastIsError = isError;
    });
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _toastMessage = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0620),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildBody()),
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
              _isArabic ? 'روليت سرود' : 'Srood Roulette',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: const Color(0xFF241239),
              border: Border.all(color: const Color(0xFF6D28D9)),
            ),
            child: CoinAmountText(amount: balance, fontSize: 13, iconSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _state == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFA78BFA)),
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
    final round = state?.round;
    final showResultBanner =
        round != null &&
        round.status == 'settled' &&
        round.roundId == _resultShownForRoundId;

    return Stack(
      children: [
        ListView(
          // Extra bottom padding guarantees the last bet row (Even/Odd) can
          // always scroll clear of the fixed chip selector on small phones.
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 28),
          children: [
            _buildWheelAndStatus(round),
            const SizedBox(height: 8),
            _buildRecentResults(state?.recentResults ?? const []),
            const SizedBox(height: 10),
            if (showResultBanner) ...[
              _buildResultBanner(),
              const SizedBox(height: 10),
            ],
            _buildBetGrid(state),
            if (_toastMessage != null) ...[
              const SizedBox(height: 10),
              _buildToast(),
            ],
            if (state != null && state.myBets.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildMyBets(state.myBets),
            ],
          ],
        ),
        if (_burstActive)
          IgnorePointer(
            child: Center(child: _CoinBurst(active: _burstActive)),
          ),
      ],
    );
  }

  Widget _buildResultBanner() {
    final win = _resultIsWin;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: win ? const Color(0xFF14532D) : const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: win ? const Color(0xFF4ADE80) : Colors.white24,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            win
                ? Icons.celebration_rounded
                : Icons.sentiment_dissatisfied_rounded,
            color: win ? const Color(0xFF4ADE80) : Colors.white54,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            win
                ? (_isArabic
                      ? 'ربحت +${formatCoinAmount(_resultWinAmount)}'
                      : 'You won +${formatCoinAmount(_resultWinAmount)}')
                : (_isArabic ? 'لا ربح هذه الجولة' : 'No win this round'),
            style: TextStyle(
              color: win ? const Color(0xFF4ADE80) : Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToast() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:
            (_toastIsError ? const Color(0xFF7F1D1D) : const Color(0xFF14532D))
                .withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _toastMessage!,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  ({String label, Color color, int? number, bool urgent, bool closingSoon})
  _statusInfo(RouletteRound? round) {
    if (round == null) {
      return (
        label: _isArabic ? 'بانتظار جولة جديدة...' : 'Waiting for round...',
        color: Colors.white54,
        number: null,
        urgent: false,
        closingSoon: false,
      );
    }
    switch (round.status) {
      case 'betting_open':
        final secs = round.bettingClosesAt.difference(_now).inSeconds;
        final remaining = secs > 0 ? secs : 0;
        final urgent = remaining > 0 && remaining <= 3;
        final closingSoon = remaining > 3 && remaining <= 5;
        return (
          label: closingSoon
              ? (_isArabic
                    ? 'يغلق قريباً — $remainingث'
                    : 'Closing soon — ${remaining}s')
              : (_isArabic
                    ? 'الرهان مفتوح — $remainingث'
                    : 'Betting open — ${remaining}s'),
          color: urgent
              ? const Color(0xFFEF4444)
              : (closingSoon
                    ? const Color(0xFFF5A820)
                    : const Color(0xFF4ADE80)),
          number: null,
          urgent: urgent,
          closingSoon: closingSoon,
        );
      case 'locked':
        return (
          label: _isArabic ? 'الرهان مغلق' : 'Betting closed',
          color: const Color(0xFFF5A820),
          number: null,
          urgent: false,
          closingSoon: false,
        );
      case 'spinning':
        return (
          label: _isArabic ? 'العجلة تدور...' : 'Spinning...',
          color: const Color(0xFFA78BFA),
          number: null,
          urgent: false,
          closingSoon: false,
        );
      case 'settled':
        final n = round.winningNumber;
        return (
          label: n == null
              ? (_isArabic ? 'انتهت الجولة' : 'Round settled')
              : (_isArabic ? 'الرقم الفائز: $n' : 'Winning number: $n'),
          color: const Color(0xFF38BDF8),
          number: n,
          urgent: false,
          closingSoon: false,
        );
      default:
        return (
          label: round.status,
          color: Colors.white54,
          number: null,
          urgent: false,
          closingSoon: false,
        );
    }
  }

  Widget _buildWheelAndStatus(RouletteRound? round) {
    final info = _statusInfo(round);
    final spinning = round?.status == 'spinning';
    // Extra glow intensity that breathes when the round is in its urgent
    // last seconds; steady otherwise.
    final glowBoost = info.urgent ? _pulse : 0.0;
    return Column(
      children: [
        SizedBox(
          height: 138,
          width: 138,
          child: AnimatedBuilder(
            animation: _wheelController,
            builder: (context, child) {
              final turns = spinning
                  ? _wheelController.value * 6
                  : _wheelController.value * 0.35;
              return Transform.rotate(angle: turns * 2 * math.pi, child: child);
            },
            child: CustomPaint(
              size: const Size(138, 138),
              painter: _RouletteWheelPainter(
                glowColor: info.color,
                glowBoost: glowBoost,
              ),
              child: Center(
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1B0F30),
                    border: Border.all(
                      color: const Color(0xFFD4AF37),
                      width: 2,
                    ),
                  ),
                  child: Text(
                    info.number != null ? '${info.number}' : '',
                    style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Overlap the badge onto the wheel so it reads as one connected unit.
        Transform.translate(
          offset: const Offset(0, -12),
          child: _buildStatusCapsule(info, glowBoost),
        ),
      ],
    );
  }

  Widget _buildStatusCapsule(
    ({String label, Color color, int? number, bool urgent, bool closingSoon})
    info,
    double glowBoost,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF150A26),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: info.color.withValues(alpha: 0.85),
          width: info.urgent ? 2 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: info.color.withValues(alpha: 0.45 + 0.35 * glowBoost),
            blurRadius: 14 + 8 * glowBoost,
            spreadRadius: 1 + glowBoost,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            info.urgent || info.closingSoon
                ? Icons.timelapse_rounded
                : Icons.casino_rounded,
            color: info.color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              info.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: info.color,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentResults(List<int> recent) {
    if (recent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 4),
          child: Text(
            _isArabic ? 'آخر النتائج' : 'Last results',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final n = recent[i];
              final color = n == 0
                  ? const Color(0xFF16A34A)
                  : (_isRed(n)
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF1F2937));
              return Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  '$n',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
        if (kShowTopWinnersPlaceholder) ...[
          const SizedBox(height: 8),
          _buildTopWinnersPlaceholder(),
        ],
      ],
    );
  }

  // TODO(roulette): wire this to a real top-winners feed once the backend
  // exposes one; kept behind kShowTopWinnersPlaceholder until then.
  Widget _buildTopWinnersPlaceholder() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF13091F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E1A4D)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            color: Color(0xFFD4AF37),
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            _isArabic ? 'أفضل الفائزين — قريباً' : 'Top winners — coming soon',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  int _myBetFor(RouletteState? state, String zone) {
    if (state == null) return 0;
    var total = 0;
    for (final b in state.myBets) {
      if (b.betZone == zone) total += b.betAmount;
    }
    return total;
  }

  int _totalBetFor(RouletteState? state, String zone) {
    if (state == null) return 0;
    for (final z in state.zoneTotals) {
      if (z.betZone == zone) return z.totalAmount;
    }
    return 0;
  }

  int _myBetsTotal(RouletteState? state) {
    if (state == null) return 0;
    var total = 0;
    for (final b in state.myBets) {
      total += b.betAmount;
    }
    return total;
  }

  // Sum of amount*multiplier across bets still pending (i.e. not yet lost) —
  // a display-only estimate, the RPC decides the real payout.
  int _potentialWin(RouletteState? state) {
    if (state == null) return 0;
    var total = 0;
    for (final b in state.myBets) {
      if (b.status == 'lost') continue;
      total += (b.betAmount * b.payoutMultiplier).round();
    }
    return total;
  }

  Widget _buildBetGrid(RouletteState? state) {
    final canBet = state?.canBet ?? false;
    final round = state?.round;
    final winningZones =
        (round?.status == 'settled' && round?.winningNumber != null)
        ? _winningZonesFor(round!.winningNumber!)
        : const <String>{};
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF13091F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2E1A4D)),
      ),
      child: Column(
        children: [
          _buildBoardHeader(state),
          const SizedBox(height: 8),
          _zoneRow(state, canBet, winningZones, [
            _zoneSpec('straight_zero', '0', const Color(0xFF16A34A)),
          ]),
          const SizedBox(height: 6),
          _zoneRow(state, canBet, winningZones, [
            _zoneSpec(
              'low',
              _isArabic ? '1-12 (x3)' : '1-12 (x3)',
              const Color(0xFF334155),
            ),
            _zoneSpec(
              'mid',
              _isArabic ? '13-24 (x3)' : '13-24 (x3)',
              const Color(0xFF334155),
            ),
            _zoneSpec(
              'high',
              _isArabic ? '25-36 (x3)' : '25-36 (x3)',
              const Color(0xFF334155),
            ),
          ]),
          const SizedBox(height: 6),
          _zoneRow(state, canBet, winningZones, [
            _zoneSpec(
              'red',
              _isArabic ? 'أحمر (x2)' : 'Red (x2)',
              const Color(0xFFDC2626),
            ),
            _zoneSpec(
              'black',
              _isArabic ? 'أسود (x2)' : 'Black (x2)',
              const Color(0xFF1F2937),
            ),
          ]),
          const SizedBox(height: 6),
          _zoneRow(state, canBet, winningZones, [
            _zoneSpec(
              'even',
              _isArabic ? 'زوجي (x2)' : 'Even (x2)',
              const Color(0xFF334155),
            ),
            _zoneSpec(
              'odd',
              _isArabic ? 'فردي (x2)' : 'Odd (x2)',
              const Color(0xFF334155),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildBoardHeader(RouletteState? state) {
    final canBet = state?.canBet ?? false;
    final myTotal = _myBetsTotal(state);
    final potentialWin = _potentialWin(state);
    final betCount = state?.myBets.length ?? 0;
    return Row(
      children: [
        Icon(
          Icons.grid_view_rounded,
          size: 15,
          color: canBet ? const Color(0xFFA78BFA) : Colors.white38,
        ),
        const SizedBox(width: 6),
        Text(
          _isArabic ? 'الطاولة' : 'Table',
          style: TextStyle(
            color: canBet ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        if (betCount > 0) ...[
          Text(
            _isArabic
                ? 'محتمل ${formatCoinAmount(potentialWin)}'
                : 'Potential ${formatCoinAmount(potentialWin)}',
            style: const TextStyle(
              color: Color(0xFFFFE566),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF241239),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: myTotal > 0
                  ? const Color(0xFFFFE566)
                  : const Color(0xFF3B2A5C),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                betCount > 0
                    ? (_isArabic
                          ? 'رهاناتي ($betCount)'
                          : 'My bets ($betCount)')
                    : (_isArabic ? 'رهاناتي' : 'My bets'),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              CoinAmountText(amount: myTotal, fontSize: 12, iconSize: 14),
            ],
          ),
        ),
      ],
    );
  }

  ({String zone, String label, Color color}) _zoneSpec(
    String zone,
    String label,
    Color color,
  ) => (zone: zone, label: label, color: color);

  Widget _zoneRow(
    RouletteState? state,
    bool canBet,
    Set<String> winningZones,
    List<({String zone, String label, Color color})> specs,
  ) {
    return Row(
      children: specs
          .map(
            (s) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildZoneButton(
                  state,
                  canBet,
                  s.zone,
                  s.label,
                  s.color,
                  winningZones.contains(s.zone),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildZoneButton(
    RouletteState? state,
    bool canBet,
    String zone,
    String label,
    Color color,
    bool isWinningZone,
  ) {
    final myBet = _myBetFor(state, zone);
    final totalBet = _totalBetFor(state, zone);
    final isPending = _pendingZones.contains(zone);
    final hasMyBet = myBet > 0;
    final isFlashing = _flashZone == zone;
    // Border/glow ramps up briefly right after a bet lands on this zone, and
    // stays gold-lit on the winning zone(s) once a round settles.
    final borderColor = isFlashing || isWinningZone
        ? const Color(0xFFFFF6B0)
        : (hasMyBet ? const Color(0xFFFFE566) : Colors.white24);
    final glowing = hasMyBet || isFlashing || isWinningZone;
    return AnimatedScale(
      scale: isFlashing || isWinningZone ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: InkWell(
        onTap: canBet && !isPending ? () => _onBetZone(zone) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: canBet ? 0.95 : 0.35),
                color.withValues(alpha: canBet ? 0.65 : 0.22),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: glowing ? 2 : 1),
            boxShadow: glowing
                ? [
                    BoxShadow(
                      color: const Color(0xFFFFE566).withValues(
                        alpha: (isFlashing || isWinningZone) ? 0.75 : 0.45,
                      ),
                      blurRadius: (isFlashing || isWinningZone) ? 16 : 10,
                      spreadRadius: (isFlashing || isWinningZone) ? 1.5 : 0.5,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isPending)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    if (totalBet > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          formatCoinAmount(totalBet),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                            fontSize: 9,
                          ),
                        ),
                      ),
                  ],
                ),
              if (hasMyBet && !isPending)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: _MiniChip(amount: myBet),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyBets(List<RouletteBet> bets) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B0F30),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isArabic ? 'رهاناتي' : 'My bets',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ...bets.map(
            (b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      b.betZone,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  CoinAmountText(
                    amount: b.betAmount,
                    fontSize: 12,
                    iconSize: 13,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    b.status,
                    style: TextStyle(
                      color: switch (b.status) {
                        'won' => const Color(0xFF4ADE80),
                        'lost' => Colors.white38,
                        _ => const Color(0xFFF5A820),
                      },
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        10,
        10,
        10 + (bottomInset > 8 ? bottomInset : 8),
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1B0F30),
        border: Border(top: BorderSide(color: Color(0xFF2E1A4D))),
      ),
      child: SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          // Symmetric horizontal padding leaves room for the selected chip's
          // scale-up so the first/last chip is never clipped at the edge.
          padding: const EdgeInsets.symmetric(horizontal: 6),
          clipBehavior: Clip.none,
          itemCount: kRouletteBetAmounts.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final amount = kRouletteBetAmounts[i];
            final selected = i == _betIndex;
            return Center(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _betIndex = i);
                },
                child: AnimatedScale(
                  scale: selected ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutBack,
                  child: _CasinoChip(amount: amount, selected: selected),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Small badge showing the current user's stake on a bet zone, styled like a
/// stacked casino chip.
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 2, 6, 2),
      decoration: BoxDecoration(
        color: const Color(0xFF2E1065),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFE566), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Two overlapping discs read as a small chip stack.
          SizedBox(
            width: 15,
            height: 12,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 1,
                  child: _disc(const Color(0xFF6D28D9)),
                ),
                Positioned(
                  left: 5,
                  top: 0,
                  child: _disc(const Color(0xFFA78BFA)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 3),
          Text(
            formatCoinAmount(amount),
            style: const TextStyle(
              color: Color(0xFFFFE566),
              fontWeight: FontWeight.w800,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _disc(Color color) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(color: const Color(0xFFFFE566), width: 0.8),
    ),
  );
}

/// Casino-style poker-chip button used in the bottom bet-amount selector.
class _CasinoChip extends StatelessWidget {
  const _CasinoChip({required this.amount, required this.selected});

  final int amount;
  final bool selected;

  static const List<Color> _rim = [
    Color(0xFFD4AF37),
    Color(0xFFA78BFA),
    Color(0xFF38BDF8),
    Color(0xFFF97316),
    Color(0xFF4ADE80),
    Color(0xFFDC2626),
  ];

  @override
  Widget build(BuildContext context) {
    final rimColor = _rim[kRouletteBetAmounts.indexOf(amount) % _rim.length];
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: selected
              ? [const Color(0xFF3B1F6E), const Color(0xFF1B0F30)]
              : [const Color(0xFF241239), const Color(0xFF150A26)],
        ),
        border: Border.all(
          color: selected ? const Color(0xFFEDE9FE) : rimColor,
          width: selected ? 3 : 2,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: rimColor.withValues(alpha: 0.7),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: rimColor.withValues(alpha: 0.6),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatCoinAmount(amount),
              maxLines: 1,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFEDE9FE),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight coin-burst shown briefly over the board on a win — a few
/// short-lived dots animating outward and fading, no external package.
class _CoinBurst extends StatefulWidget {
  const _CoinBurst({required this.active});

  final bool active;

  @override
  State<_CoinBurst> createState() => _CoinBurstState();
}

class _CoinBurstState extends State<_CoinBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _count = 10;
  final List<double> _angles = List.generate(
    _count,
    (i) => (2 * math.pi / _count) * i,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final distance = 70 * t;
        final opacity = 1 - t;
        return SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final angle in _angles)
                Transform.translate(
                  offset: Offset(
                    math.cos(angle) * distance,
                    math.sin(angle) * distance,
                  ),
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFD4AF37),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Decorative roulette-wheel painter for the header above the bet board.
class _RouletteWheelPainter extends CustomPainter {
  const _RouletteWheelPainter({required this.glowColor, this.glowBoost = 0.0});

  final Color glowColor;
  final double glowBoost;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    final glow = Paint()
      ..color = glowColor.withValues(alpha: 0.3 + 0.35 * glowBoost)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 + 8 * glowBoost);
    canvas.drawCircle(center, radius, glow);

    final rim = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFFD4AF37), Color(0xFF6D28D9), Color(0xFFD4AF37)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, rim);

    final track = Paint()..color = const Color(0xFF150A26);
    canvas.drawCircle(center, radius - 8, track);

    final count = _kWheelSequence.length;
    for (var i = 0; i < count; i++) {
      final n = _kWheelSequence[i];
      final startAngle = (2 * math.pi / count) * i - math.pi / 2;
      final sweep = 2 * math.pi / count;
      final segColor = n == 0
          ? const Color(0xFF16A34A)
          : (_isRed(n) ? const Color(0xFFDC2626) : const Color(0xFF111827));
      final segPaint = Paint()..color = segColor;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 10),
        startAngle,
        sweep,
        true,
        segPaint,
      );
    }

    final innerRing = Paint()
      ..color = const Color(0xFF0B0620)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius - 26, innerRing);

    final hub = Paint()..color = const Color(0xFF1B0F30);
    canvas.drawCircle(center, radius - 30, hub);
  }

  @override
  bool shouldRepaint(covariant _RouletteWheelPainter oldDelegate) {
    return oldDelegate.glowColor != glowColor ||
        oldDelegate.glowBoost != glowBoost;
  }
}
