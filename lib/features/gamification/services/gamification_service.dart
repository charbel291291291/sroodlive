import '../../../core/supabase/supabase_service.dart';
import '../models/backpack_item.dart';
import '../models/checkin_status.dart';
import '../models/store_item.dart';
import '../models/task_item.dart';

class GamificationService {
  const GamificationService();

  // ---------------------------------------------------------------------------
  // Store
  // ---------------------------------------------------------------------------

  Future<List<StoreItem>> getStoreItems() async {
    final data = await SupabaseService.requiredClient
        .rpc('get_store_items') as List<dynamic>;
    return data
        .map((e) => StoreItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns the server response map. Throws on RPC error.
  Future<Map<String, dynamic>> purchaseStoreItem(String itemId) async {
    final result = await SupabaseService.requiredClient.rpc(
      'purchase_store_item',
      params: {'p_item_id': itemId},
    );
    return (result as Map<String, dynamic>?) ?? {};
  }

  // ---------------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------------

  Future<List<TaskItem>> getMyTasks() async {
    final data = await SupabaseService.requiredClient
        .rpc('get_my_tasks') as List<dynamic>;
    return data
        .map((e) => TaskItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> claimTaskReward(String taskId) async {
    final result = await SupabaseService.requiredClient.rpc(
      'claim_task_reward',
      params: {'p_task_id': taskId},
    );
    return (result as Map<String, dynamic>?) ?? {};
  }

  // ---------------------------------------------------------------------------
  // Daily check-in
  // ---------------------------------------------------------------------------

  Future<CheckinStatus> getCheckinStatus() async {
    final result = await SupabaseService.requiredClient
        .rpc('get_my_checkin_status');
    return CheckinStatus.fromJson(result as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> claimDailyCheckin() async {
    final result = await SupabaseService.requiredClient
        .rpc('claim_daily_checkin');
    return (result as Map<String, dynamic>?) ?? {};
  }

  // ---------------------------------------------------------------------------
  // Backpack
  // ---------------------------------------------------------------------------

  Future<List<BackpackItem>> getMyBackpack() async {
    final data = await SupabaseService.requiredClient
        .rpc('get_my_backpack') as List<dynamic>;
    return data
        .map((e) => BackpackItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> equipBackpackItem(String backpackItemId) async {
    final result = await SupabaseService.requiredClient.rpc(
      'equip_backpack_item',
      params: {'p_backpack_item_id': backpackItemId},
    );
    return (result as Map<String, dynamic>?) ?? {};
  }

  // ---------------------------------------------------------------------------
  // VIP plans (read-only, no purchase — VIP is admin-granted)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getVipPlans() async {
    final data = await SupabaseService.requiredClient
        .from('vip_plans')
        .select()
        .eq('is_active', true)
        .order('level');
    return (data as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }
}
