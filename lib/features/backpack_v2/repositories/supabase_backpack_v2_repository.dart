import '../../../core/supabase/supabase_service.dart';
import '../exceptions/backpack_v2_exception.dart';
import '../models/backpack_v2_equip_result.dart';
import '../models/backpack_v2_equipped_item.dart';
import '../models/backpack_v2_inventory_snapshot.dart';
import '../models/backpack_v2_owned_item.dart';
import '../models/backpack_v2_slot_type.dart';
import 'backpack_v2_repository.dart';

/// Signature matching `SupabaseClient.rpc` closely enough to be a drop-in
/// seam for tests — lets [SupabaseBackpackV2Repository] be constructed with
/// a fake RPC caller instead of a real `SupabaseClient`, mirroring this
/// repo's existing `CrashV3Controller({this._service = const CrashV3Service()})`
/// constructor-injection idiom one layer lower (there is no mocking library
/// in this project).
typedef BackpackV2RpcCaller =
    Future<dynamic> Function(String fn, {Map<String, dynamic>? params});

Future<dynamic> _defaultRpcCaller(String fn, {Map<String, dynamic>? params}) {
  return SupabaseService.requiredClient.rpc(fn, params: params);
}

class SupabaseBackpackV2Repository implements BackpackV2Repository {
  const SupabaseBackpackV2Repository({
    BackpackV2RpcCaller rpcCaller = _defaultRpcCaller,
  }) : _rpc = rpcCaller;

  final BackpackV2RpcCaller _rpc;

  @override
  Future<List<BackpackV2OwnedItem>> loadOwnedItems() async {
    try {
      final data = await _rpc('get_my_backpack_v2');
      if (data == null) return const [];
      if (data is! List) {
        throw const FormatException('backpack_v2_owned_items_invalid_response');
      }
      return data
          .map((e) => BackpackV2OwnedItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (error) {
      throw mapBackpackV2Error(error);
    }
  }

  @override
  Future<List<BackpackV2EquippedItem>> loadEquippedItems() async {
    try {
      final data = await _rpc('get_my_equipped_items_v2');
      if (data == null) return const [];
      if (data is! List) {
        throw const FormatException(
          'backpack_v2_equipped_items_invalid_response',
        );
      }
      return data
          .map(
            (e) => BackpackV2EquippedItem.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } catch (error) {
      throw mapBackpackV2Error(error);
    }
  }

  @override
  Future<BackpackV2InventorySnapshot> loadInventory() async {
    final ownedFuture = loadOwnedItems();
    final equippedFuture = loadEquippedItems();
    final ownedItems = await ownedFuture;
    final equippedItems = await equippedFuture;
    return BackpackV2InventorySnapshot.fromParts(
      ownedItems: ownedItems,
      equippedItems: equippedItems,
    );
  }

  @override
  Future<BackpackV2InventorySnapshot> refreshInventory() => loadInventory();

  @override
  Future<BackpackV2EquipResult> equipItem(String ownershipId) async {
    try {
      final result = await _rpc(
        'equip_backpack_item_v2',
        params: {'p_user_backpack_item_id': ownershipId},
      );
      if (result is! Map<String, dynamic>) {
        throw const FormatException('backpack_v2_equip_invalid_response');
      }
      return BackpackV2EquipResult.fromJson(result);
    } catch (error) {
      throw mapBackpackV2Error(error);
    }
  }

  @override
  Future<bool> unequipSlot(BackpackV2SlotType slot) async {
    try {
      final result = await _rpc(
        'unequip_backpack_slot_v2',
        params: {'p_slot_type': slot.value},
      );
      return result == true;
    } catch (error) {
      throw mapBackpackV2Error(error);
    }
  }
}
