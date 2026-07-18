// BackpackV2Screen (M5): loading/empty/loaded/error states, owned/equipped
// tabs, slot filtering, equip/unequip flows, snapshot preservation on
// recoverable error, duplicate-mutation prevention, server-authoritative
// equipped state, RTL, and large text scaling. See
// docs/backpack_v2/M5_FLAG_GATED_UI_REPORT.md for the full scenario map.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/backpack_v2/controllers/backpack_v2_controller.dart';
import 'package:srood_live/features/backpack_v2/controllers/backpack_v2_state.dart';
import 'package:srood_live/features/backpack_v2/exceptions/backpack_v2_exception.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_equip_result.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_equipped_item.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_inventory_snapshot.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_owned_item.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_slot_type.dart';
import 'package:srood_live/features/backpack_v2/presentation/backpack_v2_item_card.dart';
import 'package:srood_live/features/backpack_v2/presentation/backpack_v2_screen.dart';
import 'package:srood_live/features/backpack_v2/repositories/backpack_v2_repository.dart';

BackpackV2OwnedItem _ownedItem(
  String ownershipId, {
  String itemType = 'avatar_frame',
  bool isEquippable = true,
  bool isExpiredFlag = false,
  DateTime? expiresAt,
}) => BackpackV2OwnedItem.fromJson({
  'ownership_id': ownershipId,
  'item_id': 'item-$ownershipId',
  'code': 'code_$ownershipId',
  'name': 'Item $ownershipId',
  'item_type': itemType,
  'rarity': 'legendary',
  'acquired_at': '2026-07-01T10:00:00Z',
  'expires_at': expiresAt?.toIso8601String(),
  'is_equippable': isEquippable,
  'is_expired': isExpiredFlag,
});

BackpackV2EquippedItem _equippedItem(
  String ownershipId, {
  String slotType = 'avatar_frame',
}) => BackpackV2EquippedItem.fromJson({
  'slot_type': slotType,
  'ownership_id': ownershipId,
  'item_id': 'item-$ownershipId',
  'code': 'code_$ownershipId',
  'name': 'Item $ownershipId',
  'rarity': 'legendary',
  'equipped_at': '2026-07-02T10:00:00Z',
});

class FakeBackpackV2Repository implements BackpackV2Repository {
  int equipCalls = 0;
  int unequipCalls = 0;
  BackpackV2InventorySnapshot nextSnapshot =
      const BackpackV2InventorySnapshot();
  Object? nextLoadError;
  Object? nextEquipError;
  Object? nextUnequipError;

  /// When set, [loadInventory]/[refreshInventory] block until completed —
  /// used to hold the controller in a `loading`/`refreshing` state.
  Completer<void>? loadGate;

  /// When set, [equipItem]/[unequipSlot] block until completed — used to
  /// hold the controller in `equipping`/`unequipping` for pending-state
  /// assertions.
  Completer<void>? mutationGate;

  @override
  Future<List<BackpackV2OwnedItem>> loadOwnedItems() async =>
      nextSnapshot.ownedItems;

  @override
  Future<List<BackpackV2EquippedItem>> loadEquippedItems() async =>
      nextSnapshot.equippedBySlot.values.toList();

  @override
  Future<BackpackV2InventorySnapshot> loadInventory() async {
    if (loadGate != null) await loadGate!.future;
    if (nextLoadError != null) throw nextLoadError!;
    return nextSnapshot;
  }

  @override
  Future<BackpackV2InventorySnapshot> refreshInventory() => loadInventory();

  @override
  Future<BackpackV2EquipResult> equipItem(String ownershipId) async {
    equipCalls++;
    if (mutationGate != null) await mutationGate!.future;
    if (nextEquipError != null) throw nextEquipError!;
    return const BackpackV2EquipResult(
      slotType: BackpackV2SlotType.avatarFrame,
      code: 'code',
    );
  }

  @override
  Future<bool> unequipSlot(BackpackV2SlotType slot) async {
    unequipCalls++;
    if (mutationGate != null) await mutationGate!.future;
    if (nextUnequipError != null) throw nextUnequipError!;
    return true;
  }
}

Widget wrap(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: child,
    ),
  );
}

void main() {
  // Scenario: loading state
  testWidgets('shows a loading indicator before the first snapshot arrives', (
    tester,
  ) async {
    final repo = FakeBackpackV2Repository()..loadGate = Completer<void>();
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: false, controller: controller)),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(BackpackV2ItemCard), findsNothing);

    repo.loadGate!.complete();
    await tester.pumpAndSettle();
  });

  // Scenario: empty state (owned tab)
  testWidgets('shows the empty state when the owned tab has zero items', (
    tester,
  ) async {
    final controller = BackpackV2Controller(
      repository: FakeBackpackV2Repository(),
    );

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: false, controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No items in your backpack yet'), findsOneWidget);
  });

  // Scenario: empty state (equipped tab)
  testWidgets('shows the empty state when the equipped tab has zero items', (
    tester,
  ) async {
    final repo = FakeBackpackV2Repository()
      ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: [_ownedItem('own-1')],
        equippedItems: const [],
      );
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: false, controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Equipped'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing is equipped right now'), findsOneWidget);
  });

  // Scenario: loaded owned view
  testWidgets('renders owned item cards once the snapshot loads', (
    tester,
  ) async {
    final repo = FakeBackpackV2Repository()
      ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: [_ownedItem('own-1'), _ownedItem('own-2')],
        equippedItems: const [],
      );
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: false, controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackpackV2ItemCard), findsNWidgets(2));
  });

  // Scenario: loaded equipped view
  testWidgets('equipped tab shows only items present in equippedBySlot', (
    tester,
  ) async {
    final repo = FakeBackpackV2Repository()
      ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: [_ownedItem('own-1'), _ownedItem('own-2')],
        equippedItems: [_equippedItem('own-1')],
      );
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: false, controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Equipped'));
    await tester.pumpAndSettle();

    expect(find.byType(BackpackV2ItemCard), findsOneWidget);
  });

  // Scenario: slot filtering
  testWidgets('slot filter narrows the owned list to the selected slot', (
    tester,
  ) async {
    final repo = FakeBackpackV2Repository()
      ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: [
          _ownedItem('own-1', itemType: 'avatar_frame'),
          _ownedItem('own-2', itemType: 'badge'),
        ],
        equippedItems: const [],
      );
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: false, controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackpackV2ItemCard), findsNWidgets(2));

    // The slot filter chip and the "badge"-type item card both render the
    // literal text "badge" (chip label vs. item-type label), so a plain
    // find.text would be ambiguous — the filter chip is the only widget
    // whose GestureDetector wraps that text (the item card isn't wrapped in
    // a GestureDetector at all), so scope through that ancestor type.
    await tester.tap(find.widgetWithText(GestureDetector, 'badge'));
    await tester.pumpAndSettle();

    expect(find.byType(BackpackV2ItemCard), findsOneWidget);
  });

  // Scenario: expired item display
  testWidgets('an expired item shows the Expired badge', (tester) async {
    final repo = FakeBackpackV2Repository()
      ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: [
          // resolveExpirationState treats a null expiresAt as permanent
          // regardless of isExpiredFlag (see
          // backpack_v2_expiration_state.dart) — a real expired row always
          // has expires_at set, so the fixture must too.
          _ownedItem(
            'own-1',
            isExpiredFlag: true,
            expiresAt: DateTime.utc(2020, 1, 1),
          ),
        ],
        equippedItems: const [],
      );
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: false, controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Expired'), findsOneWidget);
  });

  // Scenario: unavailable item display
  testWidgets(
    'a non-equippable item shows the Unavailable badge and disables Equip',
    (tester) async {
      final repo = FakeBackpackV2Repository()
        ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
          ownedItems: [_ownedItem('own-1', isEquippable: false)],
          equippedItems: const [],
        );
      final controller = BackpackV2Controller(repository: repo);

      await tester.pumpWidget(
        wrap(BackpackV2Screen(isArabic: false, controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unavailable'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    },
  );

  // Scenario: equip success
  testWidgets('tapping Equip calls controller.equip with the ownership id', (
    tester,
  ) async {
    final repo = FakeBackpackV2Repository()
      ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: [_ownedItem('own-1')],
        equippedItems: const [],
      );
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: false, controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Equip'));
    await tester.pumpAndSettle();

    expect(repo.equipCalls, 1);
  });

  // Scenario: equip rejection preserves the existing snapshot
  testWidgets(
    'a rejected equip preserves the existing snapshot and shows an inline error banner',
    (tester) async {
      final repo = FakeBackpackV2Repository()
        ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
          ownedItems: [_ownedItem('own-1')],
          equippedItems: const [],
        )
        ..nextEquipError = const BackpackV2Exception(
          BackpackV2ErrorCategory.equipEligibility,
          'item_not_equippable',
        );
      final controller = BackpackV2Controller(repository: repo);

      await tester.pumpWidget(
        wrap(BackpackV2Screen(isArabic: false, controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equip'));
      await tester.pumpAndSettle();

      expect(find.byType(BackpackV2ItemCard), findsOneWidget);
      expect(
        find.text('This item cannot be equipped right now'),
        findsOneWidget,
      );
    },
  );

  // Scenario: unequip success
  testWidgets(
    'tapping Unequip calls controller.unequip with the item\'s slot',
    (tester) async {
      final repo = FakeBackpackV2Repository()
        ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
          ownedItems: [_ownedItem('own-1')],
          equippedItems: [_equippedItem('own-1')],
        );
      final controller = BackpackV2Controller(repository: repo);

      await tester.pumpWidget(
        wrap(BackpackV2Screen(isArabic: false, controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unequip'));
      await tester.pumpAndSettle();

      expect(repo.unequipCalls, 1);
    },
  );

  // Scenario: unequip rejection preserves the existing snapshot
  testWidgets(
    'a rejected unequip preserves the existing snapshot and shows an inline error banner',
    (tester) async {
      final repo = FakeBackpackV2Repository()
        ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
          ownedItems: [_ownedItem('own-1')],
          equippedItems: [_equippedItem('own-1')],
        )
        ..nextUnequipError = const BackpackV2Exception(
          BackpackV2ErrorCategory.network,
          'socketexception',
        );
      final controller = BackpackV2Controller(repository: repo);

      await tester.pumpWidget(
        wrap(BackpackV2Screen(isArabic: false, controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unequip'));
      await tester.pumpAndSettle();

      expect(find.byType(BackpackV2ItemCard), findsOneWidget);
      expect(
        find.text('Network connection issue. Please try again.'),
        findsOneWidget,
      );
    },
  );

  // Scenario: refresh preservation — the item list stays visible while a
  // refresh is in flight, instead of being replaced by a full-screen spinner.
  testWidgets('the item list stays visible while a refresh is in flight', (
    tester,
  ) async {
    final repo = FakeBackpackV2Repository()
      ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: [_ownedItem('own-1')],
        equippedItems: const [],
      );
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: false, controller: controller)),
    );
    await tester.pumpAndSettle();

    repo.loadGate = Completer<void>();
    final refreshFuture = controller.refresh();
    await tester.pump();

    expect(find.byType(BackpackV2ItemCard), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    repo.loadGate!.complete();
    await refreshFuture;
    await tester.pumpAndSettle();
  });

  // Scenario: retry after a recoverable error re-triggers a refresh
  testWidgets(
    "the inline error banner's retry button calls controller.refresh",
    (tester) async {
      final repo = FakeBackpackV2Repository()
        ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
          ownedItems: [_ownedItem('own-1')],
          equippedItems: const [],
        )
        ..nextEquipError = const BackpackV2Exception(
          BackpackV2ErrorCategory.network,
          'socketexception',
        );
      final controller = BackpackV2Controller(repository: repo);

      await tester.pumpWidget(
        wrap(BackpackV2Screen(isArabic: false, controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equip'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      repo.nextEquipError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(controller.state.hasError, isFalse);
    },
  );

  // Scenario: authentication error with no prior snapshot shows a
  // full-screen message, not the item list.
  testWidgets(
    'an authentication error with no snapshot shows a full-screen auth message',
    (tester) async {
      final repo = FakeBackpackV2Repository()
        ..nextLoadError = const BackpackV2Exception(
          BackpackV2ErrorCategory.authentication,
          'not_authenticated',
        );
      final controller = BackpackV2Controller(repository: repo);

      await tester.pumpWidget(
        wrap(BackpackV2Screen(isArabic: false, controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Please sign in to view your backpack'), findsOneWidget);
      expect(find.byType(BackpackV2ItemCard), findsNothing);
    },
  );

  // Scenario: permission error with no prior snapshot shows a full-screen
  // message, not the item list.
  testWidgets(
    'a permission error with no snapshot shows a full-screen permission message',
    (tester) async {
      final repo = FakeBackpackV2Repository()
        ..nextLoadError = const BackpackV2Exception(
          BackpackV2ErrorCategory.permission,
          'permission_denied',
        );
      final controller = BackpackV2Controller(repository: repo);

      await tester.pumpWidget(
        wrap(BackpackV2Screen(isArabic: false, controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission to access this'),
        findsOneWidget,
      );
      expect(find.byType(BackpackV2ItemCard), findsNothing);
    },
  );

  // Scenario: duplicate-mutation prevention — the pending item's own button
  // disables while its mutation is in flight, without disabling siblings.
  testWidgets(
    'the Equip button disables itself while its own mutation is pending, '
    'without disabling unrelated items',
    (tester) async {
      final repo = FakeBackpackV2Repository()
        ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
          ownedItems: [_ownedItem('own-1'), _ownedItem('own-2')],
          equippedItems: const [],
        )
        ..mutationGate = Completer<void>();
      final controller = BackpackV2Controller(repository: repo);

      await tester.pumpWidget(
        wrap(BackpackV2Screen(isArabic: false, controller: controller)),
      );
      await tester.pumpAndSettle();

      unawaited(controller.equip('own-1'));
      await tester.pump();

      final buttons = tester.widgetList<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(buttons.first.onPressed, isNull);
      expect(buttons.last.onPressed, isNotNull);

      repo.mutationGate!.complete();
      await tester.pumpAndSettle();
    },
  );

  // Scenario: server-authoritative equipped state — the equipped checkmark
  // only reflects the controller's confirmed snapshot, never a local guess
  // made right after tapping Equip but before the server confirms it.
  testWidgets(
    'the equipped indicator does not appear until the server-confirmed '
    'refresh completes',
    (tester) async {
      final repo = FakeBackpackV2Repository()
        ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
          ownedItems: [_ownedItem('own-1')],
          equippedItems: const [],
        )
        ..mutationGate = Completer<void>();
      final controller = BackpackV2Controller(repository: repo);

      await tester.pumpWidget(
        wrap(BackpackV2Screen(isArabic: false, controller: controller)),
      );
      await tester.pumpAndSettle();

      unawaited(controller.equip('own-1'));
      await tester.pump();

      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      // The fake repository's equipItem doesn't itself mutate state — it
      // only unblocks once the gate completes. The post-equip refresh()
      // re-reads whatever nextSnapshot currently holds, so update it here to
      // stand in for the server confirming the equip, mirroring how a real
      // equip_backpack_item_v2 RPC would change what get_my_backpack_v2
      // returns on the next call.
      repo.nextSnapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: [_ownedItem('own-1')],
        equippedItems: [_equippedItem('own-1')],
      );
      repo.mutationGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    },
  );

  // Scenario: RTL rendering
  testWidgets('renders without error under RTL Arabic direction', (
    tester,
  ) async {
    final repo = FakeBackpackV2Repository()
      ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: [_ownedItem('own-1')],
        equippedItems: const [],
      );
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: true, controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // MaterialApp/WidgetsApp installs its own outer Directionality (ltr,
    // from the default test locale) above the screen, so a plain
    // find.byType(Directionality).first finds that one instead of the
    // screen's own explicit rtl wrapper. Scope the search to a descendant
    // of BackpackV2Screen to find the screen's own Directionality.
    final directionality = tester.widget<Directionality>(
      find
          .descendant(
            of: find.byType(BackpackV2Screen),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });

  // Scenario: large text scaling
  testWidgets('renders without overflow under a large text scale factor', (
    tester,
  ) async {
    final repo = FakeBackpackV2Repository()
      ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: [_ownedItem('own-1')],
        equippedItems: const [],
      );
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(
        BackpackV2Screen(isArabic: false, controller: controller),
        textScale: 2.0,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // Scenario: controller disposal — an internally-created controller (no
  // `controller:` override) is disposed with the screen. Removing the
  // screen mid-load and then letting the pending load resolve must not
  // throw, proving BackpackV2Controller._setState's post-dispose guard is
  // actually exercised through the screen's own dispose() call.
  testWidgets(
    'disposes an internally-created controller without throwing when a '
    'pending load resolves after removal',
    (tester) async {
      await tester.pumpWidget(wrap(const BackpackV2Screen(isArabic: false)));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
    skip:
        // This test environment never calls Supabase.initialize(), so the
        // internally-created controller's real SupabaseBackpackV2Repository
        // fails via supabase_flutter's own '_instance._isInitialized' assert
        // the moment the first frame pumps. That failure originates from the
        // un-awaited _controller.load() call in initState() (fire-and-forget
        // by design) and reaches the test as an uncaught Zone error via
        // FakeAsync.flushMicrotasks -> TestWidgetsFlutterBinding._runTest's
        // own handleUncaughtError — a path with no supported per-test
        // override (overriding FlutterError.onError here trips the
        // binding's own '_pendingExceptionDetails != null' assertion
        // instead, confirmed by running this test in isolation). Tried and
        // ruled out: wrapping pumpWidget()/pump() in try/catch (does not
        // intercept — the error is a sibling async chain, not part of the
        // awaited call stack) and overriding FlutterError.onError (wrong
        // channel; this is a Zone-level uncaught error, not a
        // FlutterError.reportError call). The disposal guard this scenario
        // targets, BackpackV2Controller._setState's post-dispose check, is
        // verified directly — with a fully controllable fake repository —
        // in backpack_v2_controller_test.dart's 'BackpackV2Controller.dispose'
        // group ("disposing prevents further state updates without
        // throwing"). Combined with the passing
        // 'does not dispose an injected controller' test below (proving the
        // screen never disposes a caller-owned controller), the ownership
        // contract this test exists to prove is already covered end to end;
        // only this specific widget-level exercise of the internally-owned
        // path is blocked by the test-environment gap described above.
        true,
  );

  // Scenario: an injected controller is left for the caller to manage — the
  // screen must not dispose it, so it stays usable after the screen is gone.
  testWidgets('does not dispose an injected controller', (tester) async {
    final repo = FakeBackpackV2Repository();
    final controller = BackpackV2Controller(repository: repo);

    await tester.pumpWidget(
      wrap(BackpackV2Screen(isArabic: false, controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    await controller.refresh();
    // FakeBackpackV2Repository's default nextSnapshot is empty, so a
    // successful refresh lands on `empty`, not `loaded`.
    expect(controller.state.status, BackpackV2Status.empty);
  });
}
