import 'package:flutter/foundation.dart' show listEquals, mapEquals;

import 'backpack_v2_equipped_item.dart';
import 'backpack_v2_owned_item.dart';
import 'backpack_v2_slot_type.dart';

/// Combined view of a user's owned items and their per-slot equipped state.
class BackpackV2InventorySnapshot {
  const BackpackV2InventorySnapshot({
    this.ownedItems = const [],
    this.equippedBySlot = const {},
  });

  final List<BackpackV2OwnedItem> ownedItems;
  final Map<BackpackV2SlotType, BackpackV2EquippedItem> equippedBySlot;

  bool get isEmpty => ownedItems.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Resolves the item currently equipped in [slot], if any. Pure lookup on
  /// already-loaded data — no network call, since equipped items are always
  /// loaded together with owned items (see backpack_v2_repository.dart).
  BackpackV2EquippedItem? equippedItemFor(BackpackV2SlotType slot) =>
      equippedBySlot[slot];

  factory BackpackV2InventorySnapshot.fromParts({
    required List<BackpackV2OwnedItem> ownedItems,
    required List<BackpackV2EquippedItem> equippedItems,
  }) => BackpackV2InventorySnapshot(
    ownedItems: List.unmodifiable(ownedItems),
    equippedBySlot: Map.unmodifiable({
      for (final equipped in equippedItems) equipped.slotType: equipped,
    }),
  );

  @override
  bool operator ==(Object other) =>
      other is BackpackV2InventorySnapshot &&
      listEquals(other.ownedItems, ownedItems) &&
      mapEquals(other.equippedBySlot, equippedBySlot);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ownedItems),
    Object.hashAllUnordered(
      equippedBySlot.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
