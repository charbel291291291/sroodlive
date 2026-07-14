import 'package:flutter/material.dart';
import '../controllers/crash_v3_controller.dart';
import '../controllers/crash_v3_state.dart';
import '../models/crash_v3_round.dart';
import 'crash_v3_bet_panel.dart';

class CrashV3DualBetPanel extends StatelessWidget {
  const CrashV3DualBetPanel({
    required this.controller,
    required this.state,
    super.key,
  });
  final CrashV3Controller controller;
  final CrashV3State state;
  @override
  Widget build(BuildContext context) {
    final settings = state.settings;
    if (settings == null) return const SizedBox.shrink();
    final canBet = state.round?.status == CrashV3RoundStatus.betting;
    final panels = [
      for (var slot = 1; slot <= 2; slot++)
        CrashV3BetPanel(
          slot: slot,
          minimum: settings.minimumBet,
          maximum: settings.maximumBet,
          pending: state.pendingSlots.contains(slot),
          canBet: canBet,
          currentBet: state.bets
              .where((bet) => bet.slotNumber == slot)
              .firstOrNull,
          onBet: (amount, auto) => controller.placeBet(
            slot: slot,
            amount: amount,
            autoCashout: auto,
          ),
          onCashout: () {
            final bet = state.bets
                .where((bet) => bet.slotNumber == slot)
                .firstOrNull;
            if (bet != null) controller.cashout(bet);
          },
        ),
    ];
    return LayoutBuilder(
      builder: (_, constraints) => constraints.maxWidth >= 700
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: panels[0]),
                const SizedBox(width: 12),
                Expanded(child: panels[1]),
              ],
            )
          : Column(
              children: [panels[0], const SizedBox(height: 10), panels[1]],
            ),
    );
  }
}
