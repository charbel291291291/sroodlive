import 'package:flutter/foundation.dart';

import '../exceptions/backpack_v2_exception.dart';
import '../models/backpack_v2_equipped_item.dart';
import '../models/backpack_v2_slot_type.dart';
import '../repositories/backpack_v2_repository.dart';
import '../repositories/supabase_backpack_v2_repository.dart';
import 'backpack_v2_state.dart';

/// State-holder for a single user's Backpack V2 inventory. Not registered
/// globally and not wired into any existing screen/provider — this is a
/// standalone unit for M4, to be connected in M5.
class BackpackV2Controller extends ChangeNotifier {
  BackpackV2Controller({
    this._repository = const SupabaseBackpackV2Repository(),
  });

  final BackpackV2Repository _repository;

  BackpackV2State _state = const BackpackV2State();
  BackpackV2State get state => _state;

  bool _disposed = false;

  /// Coalesces concurrent refresh callers onto the same in-flight request —
  /// a user-triggered refresh and a post-equip authoritative refresh must not
  /// silently drop one another; both should resolve once the single
  /// in-flight load completes.
  Future<void>? _inFlightRefresh;

  void _setState(BackpackV2State next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  Future<void> load() => refresh();

  Future<void> refresh() {
    final existing = _inFlightRefresh;
    if (existing != null) return existing;

    final future = _runRefresh();
    _inFlightRefresh = future;
    future.whenComplete(() {
      if (identical(_inFlightRefresh, future)) {
        _inFlightRefresh = null;
      }
    });
    return future;
  }

  Future<void> _runRefresh() async {
    final hadSnapshot = _state.snapshot != null;
    _setState(
      _state.copyWith(
        status: hadSnapshot
            ? BackpackV2Status.refreshing
            : BackpackV2Status.loading,
        clearError: true,
      ),
    );

    try {
      final snapshot = await _repository.loadInventory();
      _setState(
        _state.copyWith(
          status: snapshot.isEmpty
              ? BackpackV2Status.empty
              : BackpackV2Status.loaded,
          snapshot: snapshot,
          clearError: true,
        ),
      );
    } catch (error) {
      final mapped = mapBackpackV2Error(error);
      _setState(
        _state.copyWith(
          status: _statusForError(mapped.category),
          errorCategory: mapped.category,
          errorMessage: mapped.code,
        ),
      );
    }
  }

  BackpackV2Status _statusForError(BackpackV2ErrorCategory category) {
    switch (category) {
      case BackpackV2ErrorCategory.authentication:
        return BackpackV2Status.authError;
      case BackpackV2ErrorCategory.permission:
        return BackpackV2Status.permissionError;
      default:
        return BackpackV2Status.error;
    }
  }

  /// Equips [ownershipId], then re-loads authoritative state from the
  /// server. Local state never marks the item equipped before the server
  /// confirms success — the optimistic UI signal is only [pendingOwnershipIds]
  /// (a "this is in progress" flag), never a synthesized equipped entry.
  Future<void> equip(String ownershipId) async {
    if (_state.pendingOwnershipIds.contains(ownershipId)) return;

    _setState(
      _state.copyWith(
        status: BackpackV2Status.equipping,
        pendingOwnershipIds: {..._state.pendingOwnershipIds, ownershipId},
        clearError: true,
      ),
    );

    try {
      await _repository.equipItem(ownershipId);
      await refresh();
    } catch (error) {
      final mapped = mapBackpackV2Error(error);
      _setState(
        _state.copyWith(
          status: _statusForError(mapped.category),
          errorCategory: mapped.category,
          errorMessage: mapped.code,
        ),
      );
    } finally {
      final remaining = {..._state.pendingOwnershipIds}..remove(ownershipId);
      _setState(_state.copyWith(pendingOwnershipIds: remaining));
    }
  }

  /// Unequips [slot], then re-loads authoritative state from the server.
  Future<void> unequip(BackpackV2SlotType slot) async {
    final slotKey = slot.value;
    if (_state.pendingSlots.contains(slotKey)) return;

    _setState(
      _state.copyWith(
        status: BackpackV2Status.unequipping,
        pendingSlots: {..._state.pendingSlots, slotKey},
        clearError: true,
      ),
    );

    try {
      await _repository.unequipSlot(slot);
      await refresh();
    } catch (error) {
      final mapped = mapBackpackV2Error(error);
      _setState(
        _state.copyWith(
          status: _statusForError(mapped.category),
          errorCategory: mapped.category,
          errorMessage: mapped.code,
        ),
      );
    } finally {
      final remaining = {..._state.pendingSlots}..remove(slotKey);
      _setState(_state.copyWith(pendingSlots: remaining));
    }
  }

  BackpackV2EquippedItem? equippedItemForSlot(BackpackV2SlotType slot) =>
      _state.snapshot?.equippedItemFor(slot);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
