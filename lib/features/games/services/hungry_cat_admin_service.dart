import '../../../core/supabase/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class HungryCatGameConfig {
  const HungryCatGameConfig({
    required this.isEnabled,
    required this.testMode,
    required this.maxBet,
    required this.maxPayout,
    required this.dailyPayoutCap,
    required this.riskMode,
    required this.eventMode,
    required this.eventMultiplierBoost,
    this.forcedNextResult,
    this.forcedExpiresAt,
    this.forcedBy,
  });

  final bool isEnabled;
  final bool testMode;
  final int maxBet;
  final int maxPayout;
  final int dailyPayoutCap;
  final String riskMode;
  final bool eventMode;
  final double eventMultiplierBoost;
  final String? forcedNextResult;
  final DateTime? forcedExpiresAt;
  final String? forcedBy;

  factory HungryCatGameConfig.fromJson(Map<String, dynamic> j) =>
      HungryCatGameConfig(
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
        forcedExpiresAt: j['forced_expires_at'] == null
            ? null
            : DateTime.parse(j['forced_expires_at'] as String),
        forcedBy: j['forced_by'] as String?,
      );
}

class HungryCatForcedPreview {
  const HungryCatForcedPreview({
    required this.testMode,
    this.forcedResult,
    this.foodName,
    this.foodIcon,
    this.multiplier,
    this.expiresAt,
  });

  final bool testMode;
  final String? forcedResult;
  final String? foodName;
  final String? foodIcon;
  final double? multiplier;
  final DateTime? expiresAt;

  bool get hasForced => forcedResult != null;

  factory HungryCatForcedPreview.fromJson(Map<String, dynamic> j) =>
      HungryCatForcedPreview(
        testMode: j['test_mode'] as bool? ?? false,
        forcedResult: j['forced_result'] as String?,
        foodName: j['food_name'] as String?,
        foodIcon: j['food_icon'] as String?,
        multiplier: (j['multiplier'] as num?)?.toDouble(),
        expiresAt: j['expires_at'] == null
            ? null
            : DateTime.parse(j['expires_at'] as String),
      );
}

class HungryCatAuditEntry {
  const HungryCatAuditEntry({
    required this.id,
    required this.action,
    required this.metadata,
    required this.createdAt,
    this.adminId,
  });

  final String id;
  final String action;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final String? adminId;

  factory HungryCatAuditEntry.fromJson(Map<String, dynamic> j) =>
      HungryCatAuditEntry(
        id: j['id'] as String,
        action: j['action'] as String,
        metadata: (j['metadata'] as Map<String, dynamic>?) ?? const {},
        createdAt: DateTime.parse(j['created_at'] as String),
        adminId: j['admin_id'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class HungryCatAdminService {
  const HungryCatAdminService();

  // ── Config ────────────────────────────────────────────────────────────────

  Future<HungryCatGameConfig> fetchConfig() async {
    final data = await SupabaseService.requiredClient
        .rpc('admin_get_hungry_cat_game_config') as Map<String, dynamic>;
    return HungryCatGameConfig.fromJson(data);
  }

  Future<void> updateConfig({
    bool? isEnabled,
    int? maxBet,
    int? maxPayout,
    int? dailyPayoutCap,
    String? riskMode,
    bool? eventMode,
    double? eventBoost,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_update_hungry_cat_config',
      params: {
        'p_is_enabled': isEnabled,
        'p_max_bet': maxBet,
        'p_max_payout': maxPayout,
        'p_daily_payout_cap': dailyPayoutCap,
        'p_risk_mode': riskMode,
        'p_event_mode': eventMode,
        'p_event_boost': eventBoost,
      },
    );
  }

  // ── Odds ──────────────────────────────────────────────────────────────────

  Future<void> updateFoodOdds({
    required String foodId,
    double? weight,
    bool? isActive,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_update_hungry_cat_odds',
      params: {
        'p_food_id': foodId,
        'p_weight': weight,
        'p_is_active': isActive,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchAllFoods() async {
    final data = await SupabaseService.requiredClient
        .from('hungry_cat_config')
        .select()
        .order('sort_order', ascending: true);
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ── Test mode ─────────────────────────────────────────────────────────────

  Future<void> setTestMode(bool enabled) async {
    await SupabaseService.requiredClient.rpc(
      'admin_set_hungry_cat_test_mode',
      params: {'p_enabled': enabled},
    );
  }

  // ── Forced result ─────────────────────────────────────────────────────────

  Future<HungryCatForcedPreview> previewForcedResult() async {
    final data = await SupabaseService.requiredClient
        .rpc('admin_preview_hungry_cat_result') as Map<String, dynamic>;
    return HungryCatForcedPreview.fromJson(data);
  }

  Future<Map<String, dynamic>> setForcedNextResult(String outcomeKey) async {
    final data = await SupabaseService.requiredClient.rpc(
      'set_hungry_cat_forced_next_result',
      params: {'p_outcome_key': outcomeKey},
    ) as Map<String, dynamic>;
    return data;
  }

  Future<void> clearForcedResult() async {
    await SupabaseService.requiredClient
        .rpc('admin_clear_hungry_cat_forced_result');
  }

  // ── Void round ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> voidRound(String roundId) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_void_hungry_cat_round',
      params: {'p_round_id': roundId},
    ) as Map<String, dynamic>;
    return data;
  }

  // ── Audit log ─────────────────────────────────────────────────────────────

  Future<List<HungryCatAuditEntry>> fetchAuditLog({int limit = 20}) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_get_hungry_cat_audit_log',
      params: {'p_limit': limit},
    );
    return (data as List)
        .map((e) => HungryCatAuditEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
