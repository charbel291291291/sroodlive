import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:srood_live/shared/utils/error_utils.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import 'crash_v2_models.dart';
import 'crash_v2_service.dart';
import 'crash_v2_sound_service.dart';
import 'crash_v2_widgets.dart';

/// Crash Rocket v2 — native Flutter, fully server-authoritative.
///
/// The screen renders server state and sends intents (bet / cancel / cashout)
/// through idempotent RPCs. The flight multiplier shown between server events
/// is a cosmetic projection of the server curve `exp(growthRate * t)` using a
/// server-clock offset; every settlement number comes from the server.
class CrashRocketV2Screen extends StatefulWidget {
  const CrashRocketV2Screen({required this.isArabic, this.roomId, super.key});

  final bool isArabic;
  final String? roomId;

  @override
  State<CrashRocketV2Screen> createState() => _CrashRocketV2ScreenState();
}

class _CrashRocketV2ScreenState extends State<CrashRocketV2Screen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _service = CrashV2Service();
  final CrashV2SoundService _sounds = CrashV2SoundService();

  CrashV2State? _state;
  Object? _loadError;
  bool _reconnecting = false;
  RealtimeChannel? _channel;

  /// serverNow - localNow at last fetch; corrects the local animation clock.
  Duration _serverOffset = Duration.zero;

  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();
  late final AnimationController _crashBurst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  Timer? _frameTimer;
  Timer? _pollTimer;
  Timer? _refreshDebounce;
  bool _fetchInFlight = false;
  bool _fetchQueued = false;

  CrashV2Phase? _lastPhase;
  int _lastCountdownSecond = -1;

  // Panel inputs (slot -> value).
  final Map<int, int> _amounts = {1: 100, 2: 1000};
  final Map<int, double?> _autoCashouts = {1: null, 2: 2.0};
  final Map<int, bool> _busy = {1: false, 2: false};

  bool get _ar => widget.isArabic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_sounds.initialize());
    _subscribe();
    _refresh();
    _frameTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _onFrame(),
    );
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Realtime is the fast path; polling is the safety net.
      if (_reconnecting || _state == null) {
        _refresh();
      } else {
        _scheduleRefresh(const Duration(milliseconds: 1));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _pollTimer?.cancel();
    _refreshDebounce?.cancel();
    _channel?.unsubscribe();
    _ambient.dispose();
    _crashBurst.dispose();
    _sounds.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Rebuild exact state after suspension: clock offset + full snapshot.
      _refresh();
    }
  }

  // ── State sync ─────────────────────────────────────────────────────────────

  void _subscribe() {
    _channel = _service.subscribe(
      roomId: widget.roomId,
      onChange: () => _scheduleRefresh(const Duration(milliseconds: 120)),
      onStatus: (status) {
        if (!mounted) return;
        final dropped =
            status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut;
        setState(() => _reconnecting = dropped);
        if (dropped) _scheduleRefresh(const Duration(seconds: 1));
      },
    );
  }

  void _scheduleRefresh(Duration delay) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(delay, _refresh);
  }

  Future<void> _refresh() async {
    if (_fetchInFlight) {
      _fetchQueued = true;
      return;
    }
    _fetchInFlight = true;
    try {
      final state = await _service.fetchState(roomId: widget.roomId);
      if (!mounted) return;
      setState(() {
        _state = state;
        _loadError = null;
        _serverOffset = state.serverNow.difference(DateTime.now().toUtc());
      });
      _handlePhaseEffects(state);
    } catch (error, stack) {
      debugError('CrashRocketV2Screen._refresh', error, stack);
      if (!mounted) return;
      if (_state == null) setState(() => _loadError = error);
    } finally {
      _fetchInFlight = false;
      if (_fetchQueued) {
        _fetchQueued = false;
        _scheduleRefresh(const Duration(milliseconds: 80));
      }
    }
  }

  DateTime get _serverNow => DateTime.now().toUtc().add(_serverOffset);

  void _handlePhaseEffects(CrashV2State state) {
    final phase = state.round?.phase;
    if (phase == _lastPhase) return;
    switch (phase) {
      case CrashV2Phase.flying:
        _sounds.playLaunch();
        _sounds.startFlight();
      case CrashV2Phase.crashed:
      case CrashV2Phase.settling:
        if (_lastPhase == CrashV2Phase.flying) {
          _sounds.playCrash();
          _crashBurst.forward(from: 0);
          final cashed = state.myBets.any((b) => b.isCashedOut);
          final lost = state.myBets.any((b) => b.status == 'lost');
          if (lost && !cashed) unawaited(HapticFeedback.heavyImpact());
        }
      case CrashV2Phase.completed:
      case CrashV2Phase.waiting:
      case CrashV2Phase.bettingOpen:
      case CrashV2Phase.bettingLocked:
      case null:
        _sounds.stopFlight();
    }
    _lastPhase = phase;
  }

  void _onFrame() {
    final state = _state;
    if (state == null || !mounted) return;
    final round = state.round;
    if (round == null) return;

    // Countdown ticks during betting.
    if (round.phase.isBettingOpen) {
      final remaining = round.bettingCloseAt
          .difference(_serverNow)
          .inMilliseconds;
      final second = (remaining / 1000).ceil();
      if (second != _lastCountdownSecond && second >= 0 && second <= 3) {
        _lastCountdownSecond = second;
        _sounds.playCountdownTick();
      }
    }

    // Phase boundaries reached locally → confirm with the server.
    final crossedClose =
        round.phase.isBettingOpen && _serverNow.isAfter(round.bettingCloseAt);
    if (crossedClose) _scheduleRefresh(const Duration(milliseconds: 150));

    setState(() {}); // drive the multiplier/rocket animation frame
  }

  /// Cosmetic projection of the server multiplier curve for rendering.
  double get _displayMultiplier {
    final state = _state;
    final round = state?.round;
    if (state == null || round == null) return 1.0;
    if (round.phase.isCrashedVisual) {
      return round.crashMultiplier ?? 1.0;
    }
    if (!round.phase.isFlying || round.startedAt == null) return 1.0;
    final t = _serverNow.difference(round.startedAt!).inMilliseconds / 1000.0;
    if (t <= 0) return 1.0;
    final projected = math.exp(state.config.growthRate * t);
    return ((projected * 100).floorToDouble() / 100.0).clamp(
      1.0,
      state.config.maxMultiplier,
    );
  }

  // ── Intents ────────────────────────────────────────────────────────────────

  String _newIdempotencyKey(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-'
      '${math.Random().nextInt(0x7fffffff)}';

  Future<void> _placeBet(int slot) async {
    final state = _state;
    if (state == null || _busy[slot] == true) return;
    final amount = _amounts[slot] ?? state.config.minBet;
    if (amount > state.walletBalance) {
      _toast(_ar ? 'رصيدك غير كافٍ.' : 'Insufficient balance.', error: true);
      return;
    }
    setState(() => _busy[slot] = true);
    _sounds.playTap();
    try {
      final result = await _service.placeBet(
        roomId: widget.roomId,
        slot: slot,
        amount: amount,
        autoCashout: _autoCashouts[slot],
        idempotencyKey: _newIdempotencyKey('bet-$slot'),
      );
      if (!mounted) return;
      _applyBetResult(result);
    } catch (error, stack) {
      debugError('CrashRocketV2Screen._placeBet', error, stack);
      if (mounted) _toast(_betErrorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy[slot] = false);
    }
  }

  Future<void> _cancelBet(CrashV2Bet bet) async {
    if (_busy[bet.slot] == true) return;
    setState(() => _busy[bet.slot] = true);
    _sounds.playTap();
    try {
      final result = await _service.cancelBet(betId: bet.id);
      if (!mounted) return;
      _applyBetResult(result);
      _toast(_ar ? 'أُلغي الرهان.' : 'Bet canceled.');
    } catch (error, stack) {
      debugError('CrashRocketV2Screen._cancelBet', error, stack);
      if (mounted) _toast(_betErrorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy[bet.slot] = false);
    }
  }

  Future<void> _cashOut(CrashV2Bet bet) async {
    if (_busy[bet.slot] == true) return;
    setState(() => _busy[bet.slot] = true);
    try {
      final result = await _service.cashOut(
        betId: bet.id,
        idempotencyKey: _newIdempotencyKey('out-${bet.slot}'),
      );
      if (!mounted) return;
      _applyBetResult(result);
      _sounds.playCashout();
      final payout = result.bet.payout ?? 0;
      final mult = result.bet.cashoutMultiplier;
      if (mult != null && mult >= 10) _sounds.playJackpot();
      _toast(
        _ar
            ? 'تم السحب! ربحت $payout عملة (${mult?.toStringAsFixed(2)}x)'
            : 'Cashed out! Won $payout coins (${mult?.toStringAsFixed(2)}x)',
      );
    } catch (error, stack) {
      debugError('CrashRocketV2Screen._cashOut', error, stack);
      if (mounted) _toast(_betErrorText(error), error: true);
      _scheduleRefresh(const Duration(milliseconds: 120));
    } finally {
      if (mounted) setState(() => _busy[bet.slot] = false);
    }
  }

  void _applyBetResult(({CrashV2Bet bet, int balance}) result) {
    final state = _state;
    if (state == null) return;
    final bets = [...state.myBets]
      ..removeWhere((b) => b.slot == result.bet.slot)
      ..add(result.bet)
      ..sort((a, b) => a.slot.compareTo(b.slot));
    setState(() {
      _state = CrashV2State(
        enabled: state.enabled,
        paused: state.paused,
        maintenanceMessage: state.maintenanceMessage,
        serverNow: state.serverNow,
        walletBalance: result.balance,
        config: state.config,
        players: state.players,
        totalBet: state.totalBet,
        round: state.round,
        myBets: result.bet.status == 'canceled'
            ? (bets..removeWhere((b) => b.id == result.bet.id))
            : bets,
        feed: state.feed,
        history: state.history,
      );
    });
    _scheduleRefresh(const Duration(milliseconds: 300));
  }

  String _betErrorText(Object error) {
    final raw = error.toString();
    String pick(String ar, String en) => _ar ? ar : en;
    if (raw.contains('insufficient_balance')) {
      return pick('رصيدك غير كافٍ.', 'Insufficient balance.');
    }
    if (raw.contains('betting_closed')) {
      return pick(
        'أُغلق باب الرهان لهذه الجولة.',
        'Betting is closed for this round.',
      );
    }
    if (raw.contains('slot_taken')) {
      return pick(
        'هذه الخانة مستخدمة بالفعل.',
        'This bet slot is already used.',
      );
    }
    if (raw.contains('round_crashed')) {
      return pick(
        'انفجر الصاروخ قبل السحب.',
        'The rocket crashed before cashout.',
      );
    }
    if (raw.contains('game_paused')) {
      return pick('اللعبة متوقفة مؤقتًا.', 'The game is paused.');
    }
    if (raw.contains('game_disabled')) {
      return pick(
        'اللعبة غير متاحة حاليًا.',
        'The game is currently unavailable.',
      );
    }
    if (raw.contains('bet_not_cancelable')) {
      return pick(
        'لا يمكن إلغاء الرهان الآن.',
        'This bet can no longer be canceled.',
      );
    }
    return pick(
      'تعذّر تنفيذ العملية. حاول مجددًا.',
      'Action failed. Please try again.',
    );
  }

  void _toast(String message, {bool error = false}) {
    SroodToast.show(
      context,
      message,
      type: error ? SroodToastType.error : SroodToastType.success,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      backgroundColor: CrashV2Palette.bgBottom,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              CrashV2Palette.bgTop,
              CrashV2Palette.bgMid,
              CrashV2Palette.bgBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: state == null
              ? (_loadError != null ? _buildLoadError() : _buildLoading())
              : !state.enabled
              ? _buildDisabled(state)
              : _buildGame(state),
        ),
      ),
    );
  }

  Widget _buildLoading() => const Center(
    child: CircularProgressIndicator(color: CrashV2Palette.electric),
  );

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: CrashV2Palette.textDim,
              size: 42,
            ),
            const SizedBox(height: 14),
            Text(
              _ar
                  ? 'تعذّر تحميل اللعبة. تحقق من الاتصال.'
                  : 'Could not load the game. Check your connection.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _refresh,
              style: FilledButton.styleFrom(
                backgroundColor: CrashV2Palette.purple,
              ),
              child: Text(_ar ? 'إعادة المحاولة' : 'Retry'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                _ar ? 'رجوع' : 'Back',
                style: const TextStyle(color: CrashV2Palette.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisabled(CrashV2State state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.rocket_launch_rounded,
              color: CrashV2Palette.textDim,
              size: 46,
            ),
            const SizedBox(height: 14),
            Text(
              state.maintenanceMessage?.trim().isNotEmpty == true
                  ? state.maintenanceMessage!.trim()
                  : (_ar
                        ? 'صاروخ سرود غير متاح حاليًا. عد لاحقًا!'
                        : 'Crash Rocket is currently unavailable. Check back soon!'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                _ar ? 'رجوع' : 'Back',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGame(CrashV2State state) {
    return Column(
      children: [
        _buildTopBar(state),
        if (_reconnecting) _buildReconnectingBanner(),
        if (state.paused) _buildPausedBanner(state),
        _buildRoundHeader(state),
        Expanded(child: _buildArena(state)),
        _buildBetPanels(state),
      ],
    );
  }

  Widget _closeButton() => IconButton(
    onPressed: () => Navigator.of(context).maybePop(),
    icon: const Icon(Icons.close_rounded, color: Colors.white),
    tooltip: _ar ? 'إغلاق' : 'Close',
  );

  Widget _buildTopBar(CrashV2State state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Row(
        children: [
          _closeButton(),
          // Balance chip.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: CrashV2Palette.panel,
              border: Border.all(color: CrashV2Palette.panelBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  color: CrashV2Palette.gold,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '${state.walletBalance}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // History chips.
          Expanded(
            child: SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                reverse: _ar,
                itemCount: state.history.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) =>
                    HistoryChip(multiplier: state.history[i]),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _showRecentRounds(state),
            icon: const Icon(
              Icons.receipt_long_rounded,
              color: CrashV2Palette.textDim,
              size: 22,
            ),
            tooltip: _ar ? 'الجولات السابقة' : 'Recent rounds',
          ),
          IconButton(
            onPressed: _showHelp,
            icon: const Icon(
              Icons.help_outline_rounded,
              color: CrashV2Palette.textDim,
              size: 22,
            ),
            tooltip: _ar ? 'مساعدة' : 'Help',
          ),
        ],
      ),
    );
  }

  Widget _buildReconnectingBanner() => Container(
    width: double.infinity,
    color: CrashV2Palette.gold.withValues(alpha: 0.14),
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Text(
      _ar ? '...جارٍ إعادة الاتصال' : 'Reconnecting…',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: CrashV2Palette.gold,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _buildPausedBanner(CrashV2State state) => Container(
    width: double.infinity,
    color: CrashV2Palette.red.withValues(alpha: 0.15),
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
    child: Text(
      state.maintenanceMessage?.trim().isNotEmpty == true
          ? state.maintenanceMessage!.trim()
          : (_ar
                ? 'اللعبة متوقفة مؤقتًا للصيانة.'
                : 'Game paused for maintenance.'),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: CrashV2Palette.red,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _buildRoundHeader(CrashV2State state) {
    final round = state.round;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          const Icon(
            Icons.group_rounded,
            color: CrashV2Palette.textDim,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '${state.players}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: _ar ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                '${_ar ? 'إجمالي الرهان' : 'Total Bet'}: ${state.totalBet}   •   '
                '${_ar ? 'جولة' : 'Round'}: ${round?.roundNumber ?? '—'}',
                style: const TextStyle(
                  color: CrashV2Palette.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () {
              final next = !_sounds.muted;
              unawaited(_sounds.setMuted(next));
              setState(() {});
            },
            icon: Icon(
              _sounds.muted
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              color: CrashV2Palette.textDim,
              size: 20,
            ),
            tooltip: _ar ? 'الصوت' : 'Sound',
          ),
        ],
      ),
    );
  }

  Widget _buildArena(CrashV2State state) {
    final round = state.round;
    final phase = round?.phase ?? CrashV2Phase.waiting;
    final multiplier = _displayMultiplier;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 430;
          final activity = _buildActivityList(state);
          final flight = _buildFlightArea(state, phase, multiplier);
          if (!wide) return flight;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 168, child: activity),
              const SizedBox(width: 10),
              Expanded(child: flight),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFlightArea(
    CrashV2State state,
    CrashV2Phase phase,
    double multiplier,
  ) {
    final round = state.round;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CrashV2Palette.panelBorder),
        color: CrashV2Palette.bgBottom.withValues(alpha: 0.4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _ambient,
            builder: (_, _) => CustomPaint(
              painter: StarfieldPainter(progress: _ambient.value),
            ),
          ),
          AnimatedBuilder(
            animation: _crashBurst,
            builder: (_, _) => CustomPaint(
              painter: RocketFlightPainter(
                multiplier: multiplier,
                maxVisualMultiplier: 30,
                crashed: phase.isCrashedVisual,
                crashProgress: _crashBurst.value,
                idle: !phase.isFlying && !phase.isCrashedVisual,
              ),
            ),
          ),
          // Center overlay: multiplier or countdown.
          Center(child: _buildCenterOverlay(state, phase, multiplier)),
          // Betting countdown bar.
          if (phase.isBettingOpen && round != null)
            Positioned(
              left: 14,
              right: 14,
              bottom: 10,
              child: CountdownBar(
                fraction:
                    round.bettingCloseAt.difference(_serverNow).inMilliseconds /
                    math.max(
                      1,
                      round.bettingCloseAt
                          .difference(round.bettingOpenAt)
                          .inMilliseconds,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCenterOverlay(
    CrashV2State state,
    CrashV2Phase phase,
    double multiplier,
  ) {
    switch (phase) {
      case CrashV2Phase.waiting:
        return _bigLabel(
          _ar ? 'استعد...' : 'Get ready…',
          CrashV2Palette.textDim,
        );
      case CrashV2Phase.bettingOpen:
        final remaining = state.round == null
            ? 0
            : math.max(
                0,
                state.round!.bettingCloseAt.difference(_serverNow).inSeconds,
              );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bigLabel(
              _ar ? 'قدّم رهانك' : 'Place your bets',
              CrashV2Palette.green,
            ),
            const SizedBox(height: 4),
            Text(
              '$remaining',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w900,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      case CrashV2Phase.bettingLocked:
        return _bigLabel(
          _ar ? '...انطلاق' : 'Launching…',
          CrashV2Palette.electric,
        );
      case CrashV2Phase.flying:
        return Text(
          '${multiplier.toStringAsFixed(2)}x',
          style: TextStyle(
            color: CrashV2Palette.multiplierColor(multiplier),
            fontSize: 56,
            fontWeight: FontWeight.w900,
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: [
              Shadow(
                color: CrashV2Palette.multiplierColor(
                  multiplier,
                ).withValues(alpha: 0.7),
                blurRadius: 24,
              ),
            ],
          ),
        );
      case CrashV2Phase.crashed:
      case CrashV2Phase.settling:
      case CrashV2Phase.completed:
        final crash = state.round?.crashMultiplier;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bigLabel(_ar ? '!انفجر' : 'Crashed!', CrashV2Palette.red),
            if (crash != null)
              Text(
                '${crash.toStringAsFixed(2)}x',
                style: const TextStyle(
                  color: CrashV2Palette.red,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
          ],
        );
    }
  }

  Widget _bigLabel(String text, Color color) => Text(
    text,
    style: TextStyle(
      color: color,
      fontSize: 20,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.4,
    ),
  );

  Widget _buildActivityList(CrashV2State state) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: CrashV2Palette.panel.withValues(alpha: 0.6),
        border: Border.all(color: CrashV2Palette.panelBorder),
      ),
      padding: const EdgeInsets.all(8),
      child: state.feed.isEmpty
          ? Center(
              child: Text(
                _ar ? 'لا رهانات بعد' : 'No bets yet',
                style: const TextStyle(
                  color: CrashV2Palette.textDim,
                  fontSize: 12,
                ),
              ),
            )
          : ListView.separated(
              itemCount: state.feed.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final entry = state.feed[i];
                final won = entry.payout != null;
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: CrashV2Palette.panelBorder,
                      foregroundImage:
                          entry.avatarUrl?.trim().isNotEmpty == true
                          ? NetworkImage(entry.avatarUrl!)
                          : null,
                      child: const Icon(
                        Icons.person_rounded,
                        size: 14,
                        color: CrashV2Palette.textDim,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            won
                                ? '+${entry.payout} @${entry.multiplier?.toStringAsFixed(2)}x'
                                : '${_ar ? 'رهان' : 'Bet'} ${entry.amount}',
                            maxLines: 1,
                            style: TextStyle(
                              color: won
                                  ? CrashV2Palette.green
                                  : CrashV2Palette.textDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  // ── Bet panels ─────────────────────────────────────────────────────────────

  static const _amountPresets = [100, 500, 1000, 5000, 10000, 50000, 100000];
  static const _autoPresets = [null, 1.5, 2.0, 3.0, 5.0, 10.0, 20.0, 50.0];

  Widget _buildBetPanels(CrashV2State state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildBetPanel(state, 1)),
          const SizedBox(width: 10),
          Expanded(child: _buildBetPanel(state, 2)),
        ],
      ),
    );
  }

  CrashV2Bet? _betForSlot(CrashV2State state, int slot) {
    for (final bet in state.myBets) {
      if (bet.slot == slot && bet.status != 'canceled') return bet;
    }
    return null;
  }

  void _stepAmount(int slot, int direction) {
    final current = _amounts[slot] ?? 100;
    final index = _amountPresets.indexOf(current);
    final nextIndex = (index < 0 ? 0 : index + direction).clamp(
      0,
      _amountPresets.length - 1,
    );
    setState(() => _amounts[slot] = _amountPresets[nextIndex]);
    _sounds.playTap();
  }

  void _stepAuto(int slot, int direction) {
    final current = _autoCashouts[slot];
    final index = _autoPresets.indexOf(current);
    final nextIndex = (index < 0 ? 0 : index + direction).clamp(
      0,
      _autoPresets.length - 1,
    );
    setState(() => _autoCashouts[slot] = _autoPresets[nextIndex]);
    _sounds.playTap();
  }

  Widget _buildBetPanel(CrashV2State state, int slot) {
    final round = state.round;
    final phase = round?.phase ?? CrashV2Phase.waiting;
    final bet = _betForSlot(state, slot);
    final busy = _busy[slot] == true;
    final auto = _autoCashouts[slot];
    final amount = _amounts[slot] ?? state.config.minBet;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: CrashV2Palette.panel,
        border: Border.all(color: CrashV2Palette.panelBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueStepper(
            label: auto == null
                ? (_ar ? 'يدوي' : 'Manual')
                : '${auto.toStringAsFixed(2)} x',
            enabled: bet == null && !busy,
            onMinus: () => _stepAuto(slot, -1),
            onPlus: () => _stepAuto(slot, 1),
          ),
          const SizedBox(height: 8),
          ValueStepper(
            label: '$amount',
            enabled: bet == null && !busy,
            onMinus: () => _stepAmount(slot, -1),
            onPlus: () => _stepAmount(slot, 1),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: _buildPanelAction(state, slot, phase, bet, busy),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelAction(
    CrashV2State state,
    int slot,
    CrashV2Phase phase,
    CrashV2Bet? bet,
    bool busy,
  ) {
    if (busy) {
      return const FilledButton(
        onPressed: null,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // No bet in this slot.
    if (bet == null || bet.status == 'canceled') {
      final canBet = phase.isBettingOpen && !state.paused;
      return FilledButton(
        onPressed: canBet ? () => _placeBet(slot) : null,
        style: FilledButton.styleFrom(
          backgroundColor: CrashV2Palette.electric,
          disabledBackgroundColor: CrashV2Palette.electric.withValues(
            alpha: 0.25,
          ),
          foregroundColor: const Color(0xFF03121F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: FittedBox(
          child: Text(
            _ar ? 'راهن' : 'Bet',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    // Bet placed, betting still open → cancel.
    if (bet.isPlaced && phase.isBettingOpen) {
      return OutlinedButton(
        onPressed: () => _cancelBet(bet),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: CrashV2Palette.red),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: FittedBox(
          child: Text(
            _ar ? 'إلغاء (${bet.amount})' : 'Cancel (${bet.amount})',
            style: const TextStyle(
              color: CrashV2Palette.red,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    // Flying with a live bet → cash out.
    if (bet.isPlaced && phase.isFlying) {
      final projected = (bet.amount * _displayMultiplier).floor();
      return FilledButton(
        onPressed: () => _cashOut(bet),
        style: FilledButton.styleFrom(
          backgroundColor: CrashV2Palette.green,
          foregroundColor: const Color(0xFF052E12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: FittedBox(
          child: Text(
            _ar ? 'اسحب $projected' : 'Cash Out $projected',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    // Waiting for launch with a placed bet.
    if (bet.isPlaced) {
      return FilledButton(
        onPressed: null,
        style: FilledButton.styleFrom(
          disabledBackgroundColor: CrashV2Palette.purple.withValues(
            alpha: 0.35,
          ),
        ),
        child: FittedBox(
          child: Text(
            _ar ? '...في الانتظار' : 'Waiting…',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    // Settled outcomes.
    final won = bet.isCashedOut;
    return FilledButton(
      onPressed: null,
      style: FilledButton.styleFrom(
        disabledBackgroundColor:
            (won ? CrashV2Palette.green : CrashV2Palette.red).withValues(
              alpha: 0.25,
            ),
      ),
      child: FittedBox(
        child: Text(
          won
              ? '+${bet.payout} (${bet.cashoutMultiplier?.toStringAsFixed(2)}x)'
              : (_ar ? 'خسر الرهان' : 'Bet lost'),
          style: TextStyle(
            color: won ? CrashV2Palette.green : CrashV2Palette.red,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // ── Sheets ─────────────────────────────────────────────────────────────────

  Future<void> _showRecentRounds(CrashV2State state) async {
    _sounds.playTap();
    List<Map<String, dynamic>> rounds = const [];
    try {
      rounds = await _service.recentRounds(roomId: widget.roomId, limit: 30);
    } catch (error, stack) {
      debugError('CrashRocketV2Screen._showRecentRounds', error, stack);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: CrashV2Palette.bgMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _ar
                    ? 'الجولات الأخيرة (قابلة للتحقق)'
                    : 'Recent rounds (verifiable)',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _ar
                    ? 'كل جولة تكشف بذرة الخادم بعد انتهائها للتحقق من النتيجة.'
                    : 'Each round reveals its server seed after completion so the result can be verified.',
                style: const TextStyle(
                  color: CrashV2Palette.textDim,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: rounds.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _ar ? 'لا جولات بعد.' : 'No rounds yet.',
                          style: const TextStyle(color: CrashV2Palette.textDim),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: rounds.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: CrashV2Palette.panelBorder),
                        itemBuilder: (_, i) {
                          final r = rounds[i];
                          final mult =
                              double.tryParse('${r['crash_multiplier']}') ?? 0;
                          return Row(
                            children: [
                              HistoryChip(multiplier: mult),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '#${r['public_round_number']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                'seed ✓',
                                style: TextStyle(
                                  color:
                                      (r['server_seed'] ?? '')
                                          .toString()
                                          .isNotEmpty
                                      ? CrashV2Palette.green
                                      : CrashV2Palette.textDim,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHelp() async {
    _sounds.playTap();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: CrashV2Palette.bgMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _ar ? 'كيف تلعب صاروخ سرود' : 'How to play Crash Rocket',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _ar
                    ? '١. ضع رهانك قبل انتهاء العد التنازلي.\n'
                          '٢. يقلع الصاروخ ويرتفع المضاعف.\n'
                          '٣. اسحب قبل الانفجار لتربح رهانك × المضاعف.\n'
                          '٤. يمكنك ضبط سحب تلقائي عند مضاعف محدد.\n'
                          '٥. النتائج عادلة وقابلة للتحقق: تُنشر بصمة البذرة قبل الجولة وتُكشف البذرة بعدها.\n\n'
                          'العملات افتراضية للترفيه فقط وغير قابلة للاستبدال النقدي.'
                    : '1. Place your bet before the countdown ends.\n'
                          '2. The rocket launches and the multiplier climbs.\n'
                          '3. Cash out before the crash to win bet × multiplier.\n'
                          '4. Optionally set an auto cash-out multiplier.\n'
                          '5. Results are provably fair: the seed hash is published before the round and the seed revealed after.\n\n'
                          'Coins are virtual, for entertainment only, and cannot be exchanged for cash.',
                style: const TextStyle(
                  color: CrashV2Palette.textDim,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
