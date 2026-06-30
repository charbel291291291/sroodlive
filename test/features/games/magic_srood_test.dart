import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/games/models/hungry_cat_models.dart';
import 'package:srood_live/features/games/screens/magic_srood_screen.dart';
import 'package:srood_live/features/games/services/magic_srood_client_logic.dart';
import 'package:srood_live/features/games/services/magic_srood_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _EmptyConfigMagicSroodService extends MagicSroodService {
  const _EmptyConfigMagicSroodService();

  @override
  Future<List<HungryCatFood>> fetchItemConfig() async => const [];
}

void main() {
  group('MagicSroodService response parsing', () {
    test('rejects malformed active-round responses', () {
      expect(
        () => MagicSroodService.parseActiveRoundResponse({
          'round_id': 'round-1',
          'round_number': 1,
          'status': 'betting',
        }),
        throwsFormatException,
      );
    });

    test('rejects malformed bet responses instead of returning zero', () {
      expect(
        () => MagicSroodService.parseBetResponse({'bet_id': 'bet-1'}),
        throwsFormatException,
      );
      expect(
        () => MagicSroodService.parseBetResponse({
          'bet_id': 'bet-1',
          'new_balance': -1,
        }),
        throwsFormatException,
      );
    });
  });

  group('Magic Srood client state decisions', () {
    test('rolls back only before a newer authoritative balance', () {
      expect(
        shouldRollbackMagicSroodBalance(
          balanceVersionAtStart: 4,
          currentBalanceVersion: 4,
        ),
        isTrue,
      );
      expect(
        shouldRollbackMagicSroodBalance(
          balanceVersionAtStart: 4,
          currentBalanceVersion: 5,
        ),
        isFalse,
      );
    });

    test('same-round resume preserves visible bets without server rows', () {
      final result = reconcileMagicSroodVisibleBets(
        currentRoundId: 'round-1',
        nextRoundId: 'round-1',
        currentBets: const {'spain': 1000},
      );

      expect(result, {'spain': 1000});
    });

    test('same-round resume prefers server exposure', () {
      final result = reconcileMagicSroodVisibleBets(
        currentRoundId: 'round-1',
        nextRoundId: 'round-1',
        currentBets: const {'spain': 1000},
        serverBets: const {'italy': 2000},
      );

      expect(result, {'italy': 2000});
    });

    test('new round clears visible bets', () {
      final result = reconcileMagicSroodVisibleBets(
        currentRoundId: 'round-1',
        nextRoundId: 'round-2',
        currentBets: const {'spain': 1000},
      );

      expect(result, isEmpty);
    });

    test('all unhealthy realtime states request recovery', () {
      expect(
        isMagicSroodRealtimeUnhealthy(RealtimeSubscribeStatus.channelError),
        isTrue,
      );
      expect(
        isMagicSroodRealtimeUnhealthy(RealtimeSubscribeStatus.closed),
        isTrue,
      );
      expect(
        isMagicSroodRealtimeUnhealthy(RealtimeSubscribeStatus.timedOut),
        isTrue,
      );
      expect(
        isMagicSroodRealtimeUnhealthy(RealtimeSubscribeStatus.subscribed),
        isFalse,
      );
    });

    test('maps backend bet rejections to clear feedback', () {
      expect(
        magicSroodBetRejectionMessage('insufficient_coins', isArabic: false),
        'Insufficient coins',
      );
      expect(
        magicSroodBetRejectionMessage('betting_closed', isArabic: false),
        'Betting window has closed',
      );
      expect(
        magicSroodBetRejectionMessage('invalid_food', isArabic: false),
        contains('unavailable'),
      );
    });
  });

  testWidgets(
    'empty config shows maintenance state without small-screen overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: MagicSroodScreen(
            isArabic: false,
            service: _EmptyConfigMagicSroodService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Failed to load'), findsOneWidget);
      expect(find.textContaining('Team configuration'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
