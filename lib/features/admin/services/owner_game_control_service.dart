import '../../../core/supabase/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class OwnerGameAuditEntry {
  const OwnerGameAuditEntry({
    required this.id,
    required this.action,
    required this.gameType,
    required this.createdAt,
    this.oldValue,
    this.newValue,
  });

  final String id;
  final String action;
  final String gameType;
  final DateTime createdAt;
  final Map<String, dynamic>? oldValue;
  final Map<String, dynamic>? newValue;

  factory OwnerGameAuditEntry.fromJson(Map<String, dynamic> j) =>
      OwnerGameAuditEntry(
        id: j['id'] as String,
        action: j['action'] as String,
        gameType: j['game_type'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        oldValue: j['old_value'] as Map<String, dynamic>?,
        newValue: j['new_value'] as Map<String, dynamic>?,
      );
}

class HungryCatFood {
  const HungryCatFood({
    required this.foodId,
    required this.name,
    required this.icon,
    required this.multiplier,
    required this.weight,
    required this.rarity,
    required this.isActive,
    required this.sortOrder,
  });

  final String foodId;
  final String name;
  final String icon;
  final double multiplier;
  final double weight;
  final String rarity;
  final bool isActive;
  final int sortOrder;

  factory HungryCatFood.fromJson(Map<String, dynamic> j) => HungryCatFood(
    foodId: j['food_id'] as String,
    name: j['name'] as String,
    icon: j['icon'] as String? ?? '🍽️',
    multiplier: (j['multiplier'] as num).toDouble(),
    weight: (j['weight'] as num).toDouble(),
    rarity: j['rarity'] as String? ?? 'common',
    isActive: j['is_active'] as bool? ?? true,
    sortOrder: j['sort_order'] as int? ?? 0,
  );
}

class GameSettings {
  const GameSettings({
    required this.gameKey,
    required this.isEnabled,
    required this.testMode,
    required this.maxBet,
    required this.maxPayout,
    required this.dailyPayoutCap,
    required this.riskMode,
    required this.eventMode,
    required this.eventMultiplierBoost,
    this.forcedNextResult,
    this.forcedNextResultExpiresAt,
  });

  final String gameKey;
  final bool isEnabled;
  final bool testMode;
  final int maxBet;
  final int maxPayout;
  final int dailyPayoutCap;
  final String riskMode;
  final bool eventMode;
  final double eventMultiplierBoost;
  final String? forcedNextResult;
  final DateTime? forcedNextResultExpiresAt;

  factory GameSettings.fromJson(Map<String, dynamic> j) => GameSettings(
    gameKey: j['game_key'] as String,
    isEnabled: j['is_enabled'] as bool? ?? true,
    testMode: j['test_mode'] as bool? ?? false,
    maxBet: j['max_bet'] as int? ?? 100000,
    maxPayout: j['max_payout'] as int? ?? 1000000,
    dailyPayoutCap: j['daily_payout_cap'] as int? ?? 10000000,
    riskMode: j['risk_mode'] as String? ?? 'normal',
    eventMode: j['event_mode'] as bool? ?? false,
    eventMultiplierBoost:
        (j['event_multiplier_boost'] as num?)?.toDouble() ?? 1.0,
    forcedNextResult: j['forced_next_result'] as String?,
    forcedNextResultExpiresAt: j['forced_next_result_expires_at'] == null
        ? null
        : DateTime.parse(j['forced_next_result_expires_at'] as String),
  );
}

class GameRiskSnapshot {
  const GameRiskSnapshot({required this.hungryCat, required this.snapshotAt});

  final Map<String, dynamic> hungryCat;
  final DateTime snapshotAt;

  factory GameRiskSnapshot.fromJson(Map<String, dynamic> j) => GameRiskSnapshot(
    hungryCat: (j['hungry_cat'] as Map<String, dynamic>?) ?? const {},
    snapshotAt: DateTime.parse(j['snapshot_at'] as String),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class OwnerGameControlService {
  const OwnerGameControlService();

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<bool> isOwner() async {
    final result =
        await SupabaseService.requiredClient.rpc('is_owner_control_user')
            as bool;
    return result;
  }

  Future<Map<String, dynamic>> fetchCrashV3Settings() async =>
      Map<String, dynamic>.from(
        await SupabaseService.requiredClient.rpc('crash_v3_admin_get_settings')
            as Map,
      );

  Future<Map<String, dynamic>> fetchCrashV3Risk() async =>
      Map<String, dynamic>.from(
        await SupabaseService.requiredClient.rpc('crash_v3_admin_get_live_risk')
            as Map,
      );

  Future<void> updateCrashV3Settings(Map<String, dynamic> patch) async {
    await SupabaseService.requiredClient.rpc(
      'crash_v3_admin_update_settings',
      params: {'p_patch': patch},
    );
  }

  Future<void> crashV3EmergencyStop() async {
    await SupabaseService.requiredClient.rpc('crash_v3_admin_emergency_stop');
  }

  Future<void> crashV3Resume() async {
    await SupabaseService.requiredClient.rpc('crash_v3_admin_resume');
  }

  Future<List<Map<String, dynamic>>> fetchCrashV3Reconciliation() async {
    final raw =
        await SupabaseService.requiredClient.rpc(
              'crash_v3_admin_get_reconciliation',
              params: {'p_limit': 30},
            )
            as List;
    return raw
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
  }

  // ── Risk snapshot ─────────────────────────────────────────────────────────

  Future<GameRiskSnapshot> fetchRiskSnapshot() async {
    final data =
        await SupabaseService.requiredClient.rpc('owner_get_game_risk_snapshot')
            as Map<String, dynamic>;
    return GameRiskSnapshot.fromJson(data);
  }

  // ── Hungry Cat ────────────────────────────────────────────────────────────

  Future<({GameSettings settings, List<HungryCatFood> foods})>
  fetchHungryCatFullConfig() async {
    final data =
        await SupabaseService.requiredClient.rpc(
              'owner_get_hungry_cat_full_config',
            )
            as Map<String, dynamic>;
    final settings = GameSettings.fromJson(
      data['settings'] as Map<String, dynamic>,
    );
    final rawFoods = data['foods'] as List<dynamic>? ?? const [];
    final foods = rawFoods
        .map((e) => HungryCatFood.fromJson(e as Map<String, dynamic>))
        .toList();
    return (settings: settings, foods: foods);
  }

  Future<void> updateHungryCatFoodOdds({
    required String foodId,
    double? weight,
    bool? isActive,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'owner_update_hungry_cat_food_odds',
      params: {
        'p_food_id': foodId,
        'p_weight': ?weight,
        'p_is_active': ?isActive,
      },
    );
  }

  Future<Map<String, dynamic>> setHungryCatForcedResult(
    String outcomeKey,
  ) async {
    final data =
        await SupabaseService.requiredClient.rpc(
              'owner_set_hungry_cat_forced_result',
              params: {'p_outcome_key': outcomeKey},
            )
            as Map<String, dynamic>;
    return data;
  }

  Future<void> clearHungryCatForcedResult() async {
    await SupabaseService.requiredClient.rpc(
      'owner_clear_hungry_cat_forced_result',
    );
  }

  Future<void> voidHungryCatRound(String roundId) async {
    await SupabaseService.requiredClient.rpc(
      'owner_void_hungry_cat_round',
      params: {'p_round_id': roundId},
    );
  }

  // ── Gold Ladder ───────────────────────────────────────────────────────────

  Future<GameSettings> fetchGoldLadderConfig() async {
    final data =
        await SupabaseService.requiredClient.rpc(
              'owner_get_gold_ladder_full_config',
            )
            as Map<String, dynamic>;
    return GameSettings.fromJson(data);
  }

  // ── Generic game config ───────────────────────────────────────────────────

  Future<void> updateGameConfig({
    required String gameKey,
    bool? isEnabled,
    bool? testMode,
    String? riskMode,
    bool? eventMode,
    double? eventMultiplierBoost,
    int? maxBet,
    int? maxPayout,
    int? dailyPayoutCap,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'owner_set_game_config',
      params: {
        'p_game_key': gameKey,
        'p_is_enabled': ?isEnabled,
        'p_test_mode': ?testMode,
        'p_risk_mode': ?riskMode,
        'p_event_mode': ?eventMode,
        'p_event_multiplier_boost': ?eventMultiplierBoost,
        'p_max_bet': ?maxBet,
        'p_max_payout': ?maxPayout,
        'p_daily_payout_cap': ?dailyPayoutCap,
      },
    );
  }

  // ── Audit log ─────────────────────────────────────────────────────────────

  Future<List<OwnerGameAuditEntry>> fetchAuditLog({
    String? gameType,
    int limit = 50,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'owner_get_audit_log',
      params: {'p_game_type': ?gameType, 'p_limit': limit},
    );
    return (data as List)
        .map((e) => OwnerGameAuditEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
