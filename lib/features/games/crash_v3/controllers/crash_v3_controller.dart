import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/crash_v3_bet.dart';
import '../models/crash_v3_round.dart';
import '../services/crash_v3_audio_service.dart';
import '../services/crash_v3_clock_service.dart';
import '../services/crash_v3_realtime_service.dart';
import '../services/crash_v3_service.dart';
import 'crash_v3_state.dart';

class CrashV3Controller extends ChangeNotifier with WidgetsBindingObserver {
  CrashV3Controller({this._service = const CrashV3Service()});
  final CrashV3Service _service;
  final _clock = CrashV3ClockService();
  final _realtime = CrashV3RealtimeService();
  final audio = CrashV3AudioService();
  CrashV3State state = const CrashV3State();
  Timer? _frameTimer, _resyncTimer, _reloadDebounce;
  bool _disposed = false;
  final Map<int, String> _betKeys = {};
  final Map<String, String> _cashoutKeys = {};
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    await refresh();
    _realtime.subscribe(
      onChange: _scheduleRefresh,
      onStatus: (status) {
        state = state.copyWith(
          connected: status == RealtimeSubscribeStatus.subscribed,
        );
        notifyListeners();
        if (status == RealtimeSubscribeStatus.subscribed) unawaited(refresh());
      },
    );
    _frameTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _animate(),
    );
    _resyncTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> refresh() async {
    final sentAt = DateTime.now().toUtc();
    try {
      final snapshot = await _service.getState();
      final receivedAt = DateTime.now().toUtc();
      _clock.update(
        sentAt: sentAt,
        receivedAt: receivedAt,
        serverTime: snapshot.serverTime,
      );
      final balance = await _service.walletBalance();
      if (_disposed) return;
      state = state.copyWith(
        loading: false,
        round: snapshot.round,
        settings: snapshot.settings,
        bets: snapshot.bets,
        history: snapshot.history,
        walletBalance: balance,
        clearError: true,
      );
      notifyListeners();
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(loading: false, error: error.toString());
      notifyListeners();
    }
  }

  void _scheduleRefresh() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(refresh()),
    );
  }

  void _animate() {
    final round = state.round;
    if (round == null ||
        round.status != CrashV3RoundStatus.flying ||
        round.flightStartedAt == null) {
      return;
    }
    final settings = state.settings;
    final elapsed = math.max(
      0,
      _clock.now.difference(round.flightStartedAt!).inMilliseconds / 1000,
    );
    final value = math.min(
      settings?.maximumMultiplier ?? 1000,
      (math.exp(round.growthRate * elapsed) * 100).floor() / 100,
    );
    if (value != state.displayMultiplier) {
      state = state.copyWith(displayMultiplier: value);
      notifyListeners();
    }
  }

  Future<void> placeBet({
    required int slot,
    required int amount,
    double? autoCashout,
  }) async {
    final round = state.round;
    if (round == null || state.pendingSlots.contains(slot)) return;
    state = state.copyWith(
      pendingSlots: {...state.pendingSlots, slot},
      clearError: true,
    );
    notifyListeners();
    final key = _betKeys.putIfAbsent(slot, () => _idempotency('bet', slot));
    try {
      await _service.placeBet(
        roundId: round.id,
        slot: slot,
        amount: amount,
        autoCashout: autoCashout,
        idempotencyKey: key,
      );
      _betKeys.remove(slot);
      await audio.cue();
      await refresh();
    } catch (error) {
      state = state.copyWith(error: error.toString());
    } finally {
      state = state.copyWith(
        pendingSlots: {...state.pendingSlots}..remove(slot),
      );
      notifyListeners();
    }
  }

  Future<void> cashout(CrashV3Bet bet) async {
    if (state.pendingSlots.contains(bet.slotNumber)) return;
    state = state.copyWith(
      pendingSlots: {...state.pendingSlots, bet.slotNumber},
    );
    notifyListeners();
    final key = _cashoutKeys.putIfAbsent(
      bet.id,
      () => _idempotency('cashout', bet.slotNumber),
    );
    try {
      await _service.cashout(bet, idempotencyKey: key);
      _cashoutKeys.remove(bet.id);
      await audio.cue();
      await refresh();
    } catch (error) {
      state = state.copyWith(error: error.toString());
    } finally {
      state = state.copyWith(
        pendingSlots: {...state.pendingSlots}..remove(bet.slotNumber),
      );
      notifyListeners();
    }
  }

  String _idempotency(String action, int slot) =>
      '${DateTime.now().microsecondsSinceEpoch}-$action-$slot-${identityHashCode(this)}';
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _resyncTimer?.cancel();
    _reloadDebounce?.cancel();
    unawaited(_realtime.dispose());
    unawaited(audio.dispose());
    super.dispose();
  }
}
