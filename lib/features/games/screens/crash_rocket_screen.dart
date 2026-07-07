import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/coin_ui.dart';
import '../models/crash_rocket_models.dart';
import '../services/crash_rocket_service.dart';
import '../services/crash_rocket_sound_service.dart';
import '../widgets/crash_rocket_widgets.dart';

class CrashRocketScreen extends StatefulWidget {
  const CrashRocketScreen({
    required this.isArabic,
    this.roomId,
    this.service = const CrashRocketService(),
    super.key,
  });

  final bool isArabic;
  final String? roomId;
  final CrashRocketService service;

  @override
  State<CrashRocketScreen> createState() => _CrashRocketScreenState();
}

class _CrashRocketScreenState extends State<CrashRocketScreen>
    with WidgetsBindingObserver {
  SroodRocketState? _state;
  String? _error;
  bool _loading = true;
  bool _muted = false;
  final _busy = <int>{};
  final _sounds = CrashRocketSoundService();
  final _amounts = <int, int>{1: 1000, 2: 1000};
  final _auto = <int, double>{1: 2, 2: 3};
  RealtimeChannel? _channel;
  Timer? _ticker;
  Timer? _refreshTimer;
  Duration _serverOffset = Duration.zero;
  int _generation = 0;
  int _lastCountdownTick = -1;
  bool _playedFiveXSound = false;
  bool _playedTenXSound = false;

  bool get _ar => widget.isArabic;
  DateTime get _serverNow => DateTime.now().toUtc().add(_serverOffset);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_sounds.initialize());
    _load();
    _ticker = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _updateRoundAudio();
      if (mounted && _state?.round.phase == SroodRocketPhase.flying) {
        setState(() {});
      }
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _ticker?.cancel();
    _refreshTimer?.cancel();
    _channel?.unsubscribe();
    unawaited(_sounds.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = _state == null;
        _error = null;
      });
    }
    try {
      final state = await widget.service.fetchState(roomId: widget.roomId);
      if (!mounted || generation != _generation) return;
      _apply(state);
      _subscribe(generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = _friendly(error);
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final state = await widget.service.fetchState(roomId: widget.roomId);
      if (mounted) _apply(state);
    } catch (_) {}
  }

  void _apply(SroodRocketState state) {
    final previousRound = _state?.round;
    _serverOffset = state.serverNow.difference(DateTime.now().toUtc());
    setState(() {
      _state = state;
      _loading = false;
      _error = null;
    });
    _handleRoundAudio(previousRound, state.round);
  }

  void _handleRoundAudio(SroodRocketRound? previous, SroodRocketRound current) {
    if (previous?.id != current.id) {
      _lastCountdownTick = -1;
      _playedFiveXSound = false;
      _playedTenXSound = false;
      _sounds.stopFlight();
    }
    if (previous?.phase == current.phase && previous?.id == current.id) return;
    switch (current.phase) {
      case SroodRocketPhase.flying:
        _sounds.playLaunch();
        _sounds.startFlight();
      case SroodRocketPhase.crashed:
        _sounds.playCrash();
      case SroodRocketPhase.settled:
        _sounds.stopFlight();
      case SroodRocketPhase.waiting:
      case SroodRocketPhase.bettingOpen:
        _sounds.stopFlight();
    }
  }

  void _updateRoundAudio() {
    final round = _state?.round;
    if (round == null || _muted) return;
    if (round.phase == SroodRocketPhase.bettingOpen) {
      final value = _countdown;
      if (value > 0 && value <= 3 && value != _lastCountdownTick) {
        _lastCountdownTick = value;
        _sounds.playTick();
      }
      return;
    }
    if (round.phase != SroodRocketPhase.flying) return;
    final multiplier = _displayMultiplier;
    if (multiplier >= 10 && !_playedTenXSound) {
      _playedTenXSound = true;
      _sounds.playThreshold(premium: true);
    } else if (multiplier >= 5 && !_playedFiveXSound) {
      _playedFiveXSound = true;
      _sounds.playThreshold(premium: false);
    }
  }

  void _subscribe(int generation) {
    _channel?.unsubscribe();
    _channel = widget.service.subscribe(
      roomId: widget.roomId,
      onChange: _refresh,
      onStatus: (status) {
        if (!mounted || generation != _generation) return;
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.timedOut) {
          Future<void>.delayed(const Duration(seconds: 1), _load);
        }
      },
    );
  }

  int get _countdown {
    final end = _state?.round.bettingClosesAt;
    if (end == null) return 0;
    return math.max(0, end.difference(_serverNow).inMilliseconds ~/ 1000 + 1);
  }

  double get _displayMultiplier {
    final round = _state?.round;
    if (round == null) return 1;
    if (round.crashMultiplier != null) return round.crashMultiplier!;
    if (round.phase != SroodRocketPhase.flying || round.flyStartedAt == null) {
      return 1;
    }
    final seconds = math.max(
      0.0,
      _serverNow.difference(round.flyStartedAt!).inMilliseconds / 1000,
    );
    return math.exp(.09 * seconds);
  }

  SroodRocketBet? _bet(int slot) {
    for (final bet in _state?.myBets ?? const <SroodRocketBet>[]) {
      if (bet.slot == slot) return bet;
    }
    return null;
  }

  Future<void> _act(int slot) async {
    if (_busy.contains(slot)) return;
    final state = _state;
    if (state == null) return;
    setState(() => _busy.add(slot));
    try {
      final existing = _bet(slot);
      if (state.round.phase == SroodRocketPhase.flying &&
          existing?.status == 'placed') {
        final result = await widget.service.cashout(
          betId: existing!.id,
          clientCashoutId: _requestId('cashout-$slot'),
        );
        if (!mounted || _state?.round.id != existing.roundId) return;
        HapticFeedback.heavyImpact();
        _sounds.playCashout();
        await _refresh();
        _show(
          _ar
              ? 'تم السحب عند ${result.bet.cashoutMultiplier?.toStringAsFixed(2)}x'
              : 'Cashed out at ${result.bet.cashoutMultiplier?.toStringAsFixed(2)}x',
        );
      } else if (state.round.phase == SroodRocketPhase.bettingOpen &&
          existing == null) {
        final roundId = state.round.id;
        await widget.service.placeBet(
          roomId: widget.roomId,
          slot: slot,
          amount: _amounts[slot]!,
          autoCashout: _auto[slot],
          clientBetId: _requestId('bet-$slot'),
        );
        if (!mounted || _state?.round.id != roundId) return;
        HapticFeedback.mediumImpact();
        _sounds.playTap();
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        _show(_friendly(error), error: true);
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy.remove(slot));
    }
  }

  String _requestId(String action) =>
      '${action}_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 20)}';

  String _friendly(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('insufficient_balance')) {
      return _ar ? 'الرصيد غير كافٍ' : 'Insufficient coin balance';
    }
    if (value.contains('betting_closed')) {
      return _ar ? 'انتهى وقت الرهان' : 'Betting is closed';
    }
    if (value.contains('round_crashed') || value.contains('bet_not_cashable')) {
      return _ar ? 'انتهت الجولة قبل السحب' : 'The round ended before cashout';
    }
    return _ar ? 'تعذّر الاتصال باللعبة' : 'Game connection failed';
  }

  void _show(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? const Color(0xFF8F2436)
            : const Color(0xFF126A5A),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rocketInk,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: rocketBlue))
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : _buildGame(),
      ),
    );
  }

  Widget _buildGame() {
    final state = _state!;
    return Column(
      children: [
        _buildHeader(state),
        _buildHistory(state.history),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final feedWidth = constraints.maxWidth < 380 ? 104.0 : 126.0;
              return Row(
                children: [
                  SizedBox(
                    width: feedWidth,
                    child: _buildFeed(state.feed, phase: state.round.phase),
                  ),
                  Expanded(
                    child: SroodRocketScene(
                      phase: state.round.phase,
                      multiplier: _displayMultiplier,
                      countdown: _countdown,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        _buildBetConsole(state),
      ],
    );
  }

  Widget _buildBetConsole(SroodRocketState state) {
    Widget panelFor(int slot, {required bool compact}) => SroodRocketBetPanel(
      key: ValueKey('rocket-bet-$slot'),
      slot: slot,
      amount: _amounts[slot]!,
      autoCashout: _auto[slot]!,
      phase: state.round.phase,
      bet: _bet(slot),
      busy: _busy.contains(slot),
      currentMultiplier: _displayMultiplier,
      onAmountDown: () => setState(() {
        _sounds.playTap();
        _amounts[slot] = math.max(100, _amounts[slot]! - 500);
      }),
      onAmountUp: () => setState(() {
        _sounds.playTap();
        _amounts[slot] = math.min(1000000, _amounts[slot]! + 500);
      }),
      onAmountSelected: (value) => setState(() {
        _sounds.playTap();
        _amounts[slot] = value;
      }),
      onAutoChanged: (value) => setState(() {
        _sounds.playTap();
        _auto[slot] = value;
      }),
      onAction: () => _act(slot),
      compact: compact,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 6 : 10,
            5,
            compact ? 6 : 10,
            compact ? 7 : 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: panelFor(1, compact: compact)),
              SizedBox(width: compact ? 6 : 10),
              Expanded(child: panelFor(2, compact: compact)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(SroodRocketState state) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SROOD ROCKET',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              Text(
                '#${state.round.roundNumber}',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ),
        CoinAmountBadge(amount: state.walletBalance, compact: true),
        IconButton(
          tooltip: _muted ? 'Sound on' : 'Mute',
          onPressed: () {
            setState(() => _muted = !_muted);
            unawaited(_sounds.setMuted(_muted));
          },
          icon: Icon(
            _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          ),
        ),
        IconButton(
          tooltip: _ar ? 'القواعد' : 'Rules',
          onPressed: _showRules,
          icon: const Icon(Icons.help_outline_rounded),
        ),
      ],
    ),
  );

  void _showRules() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111528),
        title: Text(_ar ? 'قواعد صاروخ سرود' : 'Srood Rocket rules'),
        content: Text(
          _ar
              ? 'ضع رهانك قبل الإقلاع. اسحب أثناء الطيران قبل الانفجار. يحدد الخادم النتيجة ومبلغ الربح.'
              : 'Place up to two bets before launch. Cash out while flying before the crash. The server decides every result and payout.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_ar ? 'حسناً' : 'Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory(List<double> history) => SizedBox(
    height: 36,
    child: ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      scrollDirection: Axis.horizontal,
      itemCount: history.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (_, i) {
        final color = rocketResultColor(history[i]);
        return Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 8),
            ],
          ),
          child: Text(
            '${history[i].toStringAsFixed(2)}x',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      },
    ),
  );

  Widget _buildFeed(
    List<SroodRocketFeedEntry> feed, {
    required SroodRocketPhase phase,
  }) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF10162B), Color(0xFF080B17)],
      ),
    ),
    child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      itemCount: feed.length,
      itemBuilder: (_, i) {
        final entry = feed[i];
        final won = entry.payout != null;
        final lost =
            !won &&
            (phase == SroodRocketPhase.crashed ||
                phase == SroodRocketPhase.settled);
        final statusColor = won
            ? (entry.multiplier ?? 0) >= 5
                  ? rocketGold
                  : const Color(0xFF45D483)
            : lost
            ? const Color(0xFFFF5A6F)
            : rocketBlue;
        final detail = won
            ? '${formatCoinAmount(entry.amount)} at '
                  '${entry.multiplier?.toStringAsFixed(2) ?? '--'}x'
            : '${formatCoinAmount(entry.amount)}  '
                  '${lost ? 'Lost' : 'Running'}';
        final result = won
            ? 'Won ${formatCoinAmount(entry.payout!)}'
            : lost
            ? 'Crashed'
            : 'Active';
        return Container(
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: statusColor.withValues(alpha: 0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: const Color(0xFF202A48),
                backgroundImage: entry.avatarUrl == null
                    ? null
                    : NetworkImage(entry.avatarUrl!),
                child: entry.avatarUrl == null
                    ? const Icon(Icons.person, size: 14)
                    : null,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8,
                        height: 1.15,
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      result,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8,
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.rocket_launch_rounded, color: rocketGold, size: 46),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
