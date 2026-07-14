import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/games/crash_v3/models/crash_v3_bet.dart';
import 'package:srood_live/features/games/crash_v3/widgets/crash_v3_bet_panel.dart';

void main() {
  for (final width in [320.0, 390.0, 430.0, 768.0]) {
    testWidgets('bet panel has no overflow at $width px', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CrashV3BetPanel(
                slot: 1,
                minimum: 100,
                maximum: 100000,
                pending: false,
                canBet: true,
                currentBet: null,
                onBet: (_, _) {},
                onCashout: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
    });
  }
  testWidgets('accepted bet renders cash-out action', (tester) async {
    const bet = CrashV3Bet(
      id: 'b',
      roundId: 'r',
      slotNumber: 1,
      betAmount: 100,
      status: 'accepted',
      payoutAmount: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrashV3BetPanel(
            slot: 1,
            minimum: 100,
            maximum: 1000,
            pending: false,
            canBet: false,
            currentBet: bet,
            onBet: (_, _) {},
            onCashout: () {},
          ),
        ),
      ),
    );
    expect(find.text('CASH OUT'), findsOneWidget);
  });
}
