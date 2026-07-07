import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/games/models/crash_rocket_models.dart';
import 'package:srood_live/features/games/widgets/crash_rocket_widgets.dart';

void main() {
  group('Srood Rocket models', () {
    test('parses authoritative state defensively', () {
      final state = SroodRocketState.fromJson({
        'server_now': '2026-07-06T10:00:00Z',
        'wallet_balance': '12500',
        'round': {
          'id': 'round-1',
          'room_id': null,
          'status': 'flying',
          'round_number': 42,
          'starts_at': '2026-07-06T09:59:50Z',
          'betting_closes_at': '2026-07-06T09:59:58Z',
          'fly_started_at': '2026-07-06T09:59:58Z',
          'crash_seed_hash': 'hash',
        },
        'my_bets': [
          {
            'id': 'bet-1',
            'round_id': 'round-1',
            'bet_slot': 1,
            'amount': 1000,
            'status': 'placed',
          },
        ],
        'public_feed': const [],
        'history': [
          {'crash_multiplier': '2.45'},
        ],
      });

      expect(state.round.phase, SroodRocketPhase.flying);
      expect(state.walletBalance, 12500);
      expect(state.myBets.single.slot, 1);
      expect(state.history.single, 2.45);
    });

    test('rejects state without a valid round', () {
      expect(
        () => SroodRocketState.fromJson({
          'server_now': '2026-07-06T10:00:00Z',
          'round': null,
        }),
        throwsFormatException,
      );
    });

    test('merges server placement and cashout events by bet id', () {
      final state = SroodRocketState.fromJson({
        'server_now': '2026-07-06T10:00:00Z',
        'wallet_balance': 5000,
        'round': {
          'id': 'round-2',
          'status': 'flying',
          'round_number': 43,
          'starts_at': '2026-07-06T10:00:00Z',
          'betting_closes_at': '2026-07-06T10:00:05Z',
        },
        'my_bets': const [],
        'public_feed': [
          {
            'bet_id': 'bet-9',
            'user_id': 'user-1',
            'payout_amount': 20000,
            'cashout_multiplier': 2,
          },
          {
            'bet_id': 'bet-9',
            'user_id': 'user-1',
            'display_name': 'Charbel',
            'amount': 10000,
            'avatar_url': 'https://example.com/avatar.png',
          },
        ],
        'history': const [],
      });

      expect(state.feed, hasLength(1));
      expect(state.feed.single.name, 'Charbel');
      expect(state.feed.single.amount, 10000);
      expect(state.feed.single.multiplier, 2);
      expect(state.feed.single.payout, 20000);
    });
  });

  test('result colors follow the four multiplier ranges', () {
    expect(rocketResultColor(1.17), const Color(0xFF42A5FF));
    expect(rocketResultColor(2), const Color(0xFF45D483));
    expect(rocketResultColor(4.99), const Color(0xFF45D483));
    expect(rocketResultColor(5), const Color(0xFFFF5A6F));
    expect(rocketResultColor(9.99), const Color(0xFFFF5A6F));
    expect(rocketResultColor(10), const Color(0xFFFFCC55));
  });

  test('migration enforces the server-authoritative contract', () {
    final sql = File(
      'supabase/migrations/20260706143040_srood_rocket_server_authoritative.sql',
    ).readAsStringSync().toLowerCase();

    for (final object in const [
      'crash_rocket_rounds',
      'crash_rocket_round_secrets',
      'crash_rocket_bets',
      'crash_rocket_round_events',
      'get_active_crash_rocket_round',
      'place_crash_rocket_bet',
      'cashout_crash_rocket_bet',
      'advance_crash_rocket_round',
      'settle_crash_rocket_round',
    ]) {
      expect(sql, contains(object));
    }
    expect(sql, contains('for update'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('unique (user_id, client_bet_id)'));
    expect(sql, contains('unique (user_id, client_cashout_id)'));
    expect(sql, contains('enable row level security'));
    expect(sql, contains('revoke all on public.crash_rocket_round_secrets'));
    expect(
      sql,
      isNot(contains('grant select on public.crash_rocket_round_secrets')),
    );
    expect(sql, contains("'crash_rocket_cashout'"));
  });

  test('dedicated Rocket sound assets are present', () {
    for (final name in const [
      'ambient',
      'cashout',
      'crash',
      'flight',
      'jackpot',
      'launch',
      'tap',
      'threshold',
      'tick',
    ]) {
      final asset = File('assets/sounds/rocket_$name.wav');
      expect(asset.existsSync(), isTrue, reason: asset.path);
      expect(asset.lengthSync(), greaterThan(1000), reason: asset.path);
    }
  });

  for (final size in const [Size(320, 568), Size(720, 1604)]) {
    testWidgets('both bet panels have no overflow at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final slot in const [1, 2])
                  Expanded(
                    child: SroodRocketBetPanel(
                      slot: slot,
                      amount: 100000,
                      autoCashout: slot == 1 ? 2 : 3,
                      phase: SroodRocketPhase.bettingOpen,
                      bet: null,
                      busy: false,
                      currentMultiplier: 1,
                      compact: size.width < 700,
                      onAmountDown: () {},
                      onAmountUp: () {},
                      onAmountSelected: (_) {},
                      onAutoChanged: (_) {},
                      onAction: () {},
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('PLACE BET'), findsNWidgets(2));
      expect(find.text('BET 1'), findsOneWidget);
      expect(find.text('BET 2'), findsOneWidget);
      expect(find.text('100K'), findsWidgets);
    });
  }
}
