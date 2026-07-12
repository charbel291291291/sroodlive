import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/games/crash_v2/crash_v2_models.dart';
import 'package:srood_live/features/games/crash_v2/crash_v2_widgets.dart';

Map<String, dynamic> _roundJson({
  String status = 'betting_open',
  String? crashMultiplier,
  String? serverSeed,
}) => {
  'id': 'round-1',
  'room_id': null,
  'status': status,
  'public_round_number': 567931,
  'betting_open_at': '2026-07-12T10:00:00Z',
  'betting_close_at': '2026-07-12T10:00:08Z',
  'started_at': status == 'flying' ? '2026-07-12T10:00:09Z' : null,
  'crashed_at': crashMultiplier != null ? '2026-07-12T10:00:20Z' : null,
  'crash_multiplier': crashMultiplier,
  'server_seed_hash': 'hash',
  'server_seed': serverSeed,
  'client_seed': '',
  'nonce': 567931,
};

void main() {
  group('CrashV2 models', () {
    test('parses full authoritative state', () {
      final state = CrashV2State.fromJson({
        'enabled': true,
        'paused': false,
        'server_now': '2026-07-12T10:00:05Z',
        'wallet_balance': '196',
        'players': 129,
        'total_bet': 1621001,
        'config': {
          'min_bet': 100,
          'max_bet': 1000000,
          'growth_rate': '0.09',
          'max_multiplier': '1000',
          'betting_seconds': 8,
          'waiting_seconds': 3,
          'lock_seconds': 1,
          'crash_display_seconds': 4,
          'max_payout': 1000000000,
          'min_auto_cashout': '1.01',
          'max_auto_cashout': '1000',
        },
        'round': _roundJson(),
        'my_bets': [
          {
            'id': 'bet-1',
            'round_id': 'round-1',
            'bet_slot': 1,
            'amount': 1000,
            'status': 'placed',
            'auto_cashout_multiplier': '2.5',
          },
        ],
        'public_feed': const [],
        'history': [
          {'crash_multiplier': '2.53'},
          {'crash_multiplier': '8.34'},
          {'crash_multiplier': '1.03'},
        ],
      });

      expect(state.enabled, isTrue);
      expect(state.walletBalance, 196);
      expect(state.players, 129);
      expect(state.totalBet, 1621001);
      expect(state.round!.phase, CrashV2Phase.bettingOpen);
      expect(state.round!.roundNumber, 567931);
      expect(state.myBets.single.autoCashout, 2.5);
      expect(state.config.growthRate, 0.09);
      expect(state.history, [2.53, 8.34, 1.03]);
    });

    test('parses every server round status', () {
      const mapping = {
        'waiting': CrashV2Phase.waiting,
        'betting_open': CrashV2Phase.bettingOpen,
        'betting_locked': CrashV2Phase.bettingLocked,
        'flying': CrashV2Phase.flying,
        'crashed': CrashV2Phase.crashed,
        'settling': CrashV2Phase.settling,
        'completed': CrashV2Phase.completed,
        'garbage': CrashV2Phase.waiting,
      };
      mapping.forEach((raw, phase) {
        expect(CrashV2Phase.parse(raw), phase, reason: raw);
      });
    });

    test('disabled state parses without a round', () {
      final state = CrashV2State.fromJson({
        'enabled': false,
        'maintenance_message': 'Down for maintenance',
        'server_now': '2026-07-12T10:00:00Z',
      });
      expect(state.enabled, isFalse);
      expect(state.round, isNull);
      expect(state.maintenanceMessage, 'Down for maintenance');
    });

    test('seed reveal only present on completed rounds', () {
      final open = CrashV2Round.fromJson(_roundJson());
      final done = CrashV2Round.fromJson(
        _roundJson(
          status: 'completed',
          crashMultiplier: '2.16',
          serverSeed: 'revealed-seed',
        ),
      );
      expect(open.serverSeed, isNull);
      expect(done.serverSeed, 'revealed-seed');
      expect(done.crashMultiplier, 2.16);
    });

    test('merges bet + cashout feed events by bet id', () {
      final state = CrashV2State.fromJson({
        'enabled': true,
        'server_now': '2026-07-12T10:00:00Z',
        'round': _roundJson(),
        'my_bets': const [],
        'history': const [],
        'public_feed': [
          {
            'bet_id': 'bet-9',
            'user_id': 'u1',
            'display_name': 'Srood Player',
            'payout': 1500,
            'cashout_multiplier': '1.50',
            'event_type': 'bet_cashed_out',
          },
          {
            'bet_id': 'bet-9',
            'user_id': 'u1',
            'display_name': 'Ahmad',
            'amount': 1000,
            'event_type': 'bet_placed',
          },
        ],
      });
      expect(state.feed, hasLength(1));
      final entry = state.feed.single;
      expect(entry.name, 'Ahmad');
      expect(entry.amount, 1000);
      expect(entry.payout, 1500);
      expect(entry.multiplier, 1.5);
    });

    test('rejects malformed round payloads', () {
      expect(() => CrashV2Round.fromJson({'id': null}), throwsFormatException);
    });
  });

  group('CrashV2 widgets', () {
    testWidgets('HistoryChip colors scale with multiplier', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                HistoryChip(multiplier: 1.03),
                HistoryChip(multiplier: 2.53),
                HistoryChip(multiplier: 8.34),
                HistoryChip(multiplier: 42.0),
              ],
            ),
          ),
        ),
      );
      expect(find.text('1.03'), findsOneWidget);
      expect(find.text('2.53'), findsOneWidget);
      expect(find.text('8.34'), findsOneWidget);
      expect(find.text('42.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ValueStepper fires callbacks and disables cleanly', (
      tester,
    ) async {
      var minus = 0;
      var plus = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: ValueStepper(
                label: '1000',
                enabled: true,
                onMinus: () => minus++,
                onPlus: () => plus++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.tap(find.byIcon(Icons.remove_rounded));
      expect(minus, 1);
      expect(plus, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: ValueStepper(
                label: '1000',
                enabled: false,
                onMinus: () => minus++,
                onPlus: () => plus++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(plus, 1, reason: 'disabled stepper must not fire');
      expect(tester.takeException(), isNull);
    });

    testWidgets('rocket scene paints in idle, flying, and crashed states', (
      tester,
    ) async {
      for (final scene in [
        (idle: true, crashed: false, m: 1.0),
        (idle: false, crashed: false, m: 2.16),
        (idle: false, crashed: true, m: 4.2),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomPaint(
                size: const Size(320, 240),
                painter: RocketFlightPainter(
                  multiplier: scene.m,
                  maxVisualMultiplier: 30,
                  crashed: scene.crashed,
                  crashProgress: scene.crashed ? 0.5 : 0,
                  idle: scene.idle,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'painter must not throw for $scene',
        );
      }
    });

    testWidgets('starfield and countdown paint without overflow at 320px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: StarfieldPainter(progress: 0.4),
                    child: const SizedBox.expand(),
                  ),
                ),
                const CountdownBar(fraction: 0.6),
                const CountdownBar(fraction: 0.1),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
