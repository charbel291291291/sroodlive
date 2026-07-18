import '../exceptions/backpack_v2_exception.dart';
import '../models/backpack_v2_inventory_snapshot.dart';

enum BackpackV2Status {
  idle,
  loading,
  loaded,
  empty,
  refreshing,
  equipping,
  unequipping,
  error,
  authError,
  permissionError,
}

/// Immutable state for [BackpackV2Controller]. `snapshot` is preserved across
/// [BackpackV2Status.refreshing]/[BackpackV2Status.equipping]/
/// [BackpackV2Status.unequipping]/error transitions — callers should keep
/// showing the last-known-good inventory rather than a blank/loading screen
/// during those transitions.
class BackpackV2State {
  const BackpackV2State({
    this.status = BackpackV2Status.idle,
    this.snapshot,
    this.pendingOwnershipIds = const {},
    this.pendingSlots = const {},
    this.errorCategory,
    this.errorMessage,
  });

  final BackpackV2Status status;
  final BackpackV2InventorySnapshot? snapshot;

  /// `user_backpack_items.id` values with an equip request in flight —
  /// guards against duplicate concurrent equip requests for the same item.
  final Set<String> pendingOwnershipIds;

  /// Slots with an unequip request in flight.
  final Set<String> pendingSlots;

  final BackpackV2ErrorCategory? errorCategory;
  final String? errorMessage;

  bool get isLoading =>
      status == BackpackV2Status.loading || status == BackpackV2Status.idle;

  bool get hasError =>
      status == BackpackV2Status.error ||
      status == BackpackV2Status.authError ||
      status == BackpackV2Status.permissionError;

  BackpackV2State copyWith({
    BackpackV2Status? status,
    BackpackV2InventorySnapshot? snapshot,
    Set<String>? pendingOwnershipIds,
    Set<String>? pendingSlots,
    BackpackV2ErrorCategory? errorCategory,
    String? errorMessage,
    bool clearError = false,
  }) {
    return BackpackV2State(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      pendingOwnershipIds: pendingOwnershipIds ?? this.pendingOwnershipIds,
      pendingSlots: pendingSlots ?? this.pendingSlots,
      errorCategory: clearError ? null : (errorCategory ?? this.errorCategory),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
