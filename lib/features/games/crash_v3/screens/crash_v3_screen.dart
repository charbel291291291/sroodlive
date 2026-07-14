import 'package:flutter/material.dart';
import '../controllers/crash_v3_controller.dart';
import '../controllers/crash_v3_state.dart';
import '../models/crash_v3_history_item.dart';
import '../models/crash_v3_round.dart';
import '../services/crash_v3_service.dart';
import '../widgets/crash_v3_chart.dart';
import '../widgets/crash_v3_connection_banner.dart';
import '../widgets/crash_v3_dual_bet_panel.dart';
import '../widgets/crash_v3_fairness_sheet.dart';
import '../widgets/crash_v3_header.dart';
import '../widgets/crash_v3_history_strip.dart';
import '../widgets/crash_v3_multiplier.dart';
import '../widgets/crash_v3_my_bets.dart';
import '../widgets/crash_v3_result_overlay.dart';
import '../widgets/crash_v3_rules_sheet.dart';

class CrashV3Screen extends StatefulWidget {
  const CrashV3Screen({super.key});
  @override
  State<CrashV3Screen> createState() => _CrashV3ScreenState();
}

class _CrashV3ScreenState extends State<CrashV3Screen> {
  late final CrashV3Controller controller;
  @override
  void initState() {
    super.initState();
    controller = CrashV3Controller()..addListener(_changed);
    controller.initialize();
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _fairness([CrashV3HistoryItem? item]) async {
    Map<String, dynamic>? data;
    if (item != null) {
      try {
        data = await const CrashV3Service().verifyRound(item.roundId);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }
    if (mounted) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => CrashV3FairnessSheet(data: data),
      );
    }
  }

  Future<void> _history() async {
    final items = await const CrashV3Service().myHistory();
    if (mounted) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => CrashV3MyBets(items: items),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return Scaffold(
      backgroundColor: const Color(0xFF08030F),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: CrashV3Header(
                balance: state.walletBalance,
                connected: state.connected,
                soundEnabled: controller.audio.enabled,
                onSound: () {
                  setState(controller.audio.toggle);
                },
                onFairness: _fairness,
              ),
            ),
            CrashV3ConnectionBanner(
              connected: state.connected,
              onRetry: controller.refresh,
            ),
            if (state.error != null)
              Container(
                width: double.infinity,
                color: const Color(0xFF48102B),
                padding: const EdgeInsets.all(7),
                child: Text(
                  state.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : _body(state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(CrashV3State state) {
    final disabled =
        state.settings?.gameEnabled != true ||
        state.settings?.maintenanceMode == true ||
        state.settings?.emergencyStop == true;
    return LayoutBuilder(
      builder: (_, constraints) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          12,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 20),
          child: Column(
            children: [
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => const CrashV3RulesSheet(),
                    ),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Rules'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _history,
                    icon: const Icon(Icons.history),
                    label: const Text('My bets'),
                  ),
                ],
              ),
              CrashV3HistoryStrip(items: state.history, onTap: _fairness),
              const SizedBox(height: 8),
              SizedBox(
                height: constraints.maxHeight < 650 ? 210 : 270,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CrashV3Chart(multiplier: state.displayMultiplier),
                    ),
                    Center(
                      child: CrashV3Multiplier(
                        value: _shownMultiplier(state),
                        status: disabled
                            ? 'disabled'
                            : state.round?.status.name ?? 'engine offline',
                      ),
                    ),
                    if (state.round?.status == CrashV3RoundStatus.crashed)
                      Positioned.fill(
                        child: CrashV3ResultOverlay(
                          multiplier: state.round!.crashMultiplier ?? 1,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (disabled)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B1738),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    state.settings?.maintenanceMode == true
                        ? 'Game under maintenance'
                        : 'Game safely disabled — engine unavailable',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              CrashV3DualBetPanel(controller: controller, state: state),
            ],
          ),
        ),
      ),
    );
  }

  double _shownMultiplier(CrashV3State state) {
    final round = state.round;
    if (round?.status == CrashV3RoundStatus.crashed ||
        round?.status == CrashV3RoundStatus.settling ||
        round?.status == CrashV3RoundStatus.settled) {
      return round?.crashMultiplier ?? 1;
    }
    return state.displayMultiplier;
  }
}
