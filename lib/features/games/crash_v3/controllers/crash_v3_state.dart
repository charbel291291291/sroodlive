import '../models/crash_v3_bet.dart';
import '../models/crash_v3_history_item.dart';
import '../models/crash_v3_round.dart';
import '../models/crash_v3_settings.dart';

class CrashV3State {
  const CrashV3State({
    this.loading = true,
    this.connected = false,
    this.pendingSlots = const {},
    this.bets = const [],
    this.history = const [],
    this.walletBalance = 0,
    this.displayMultiplier = 1,
    this.error,
    this.round,
    this.settings,
  });
  final bool loading, connected;
  final Set<int> pendingSlots;
  final List<CrashV3Bet> bets;
  final List<CrashV3HistoryItem> history;
  final int walletBalance;
  final double displayMultiplier;
  final String? error;
  final CrashV3Round? round;
  final CrashV3Settings? settings;
  CrashV3State copyWith({
    bool? loading,
    bool? connected,
    Set<int>? pendingSlots,
    List<CrashV3Bet>? bets,
    List<CrashV3HistoryItem>? history,
    int? walletBalance,
    double? displayMultiplier,
    String? error,
    bool clearError = false,
    CrashV3Round? round,
    CrashV3Settings? settings,
  }) => CrashV3State(
    loading: loading ?? this.loading,
    connected: connected ?? this.connected,
    pendingSlots: pendingSlots ?? this.pendingSlots,
    bets: bets ?? this.bets,
    history: history ?? this.history,
    walletBalance: walletBalance ?? this.walletBalance,
    displayMultiplier: displayMultiplier ?? this.displayMultiplier,
    error: clearError ? null : error ?? this.error,
    round: round ?? this.round,
    settings: settings ?? this.settings,
  );
}
