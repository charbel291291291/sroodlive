import '../../../core/supabase/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class RocketCrashGameConfig {
  const RocketCrashGameConfig({
    required this.isEnabled,
    required this.testMode,
    required this.maxBet,
    required this.maxPayout,
    this.forcedCrashMultiplier,
    this.forcedExpiresAt,
    this.forcedBy,
  });

  final bool isEnabled;
  final bool testMode;
  final int maxBet;
  final int maxPayout;
  final double? forcedCrashMultiplier;
  final DateTime? forcedExpiresAt;
  final String? forcedBy;

  factory RocketCrashGameConfig.fromJson(Map<String, dynamic> j) =>
      RocketCrashGameConfig(
        isEnabled: j['is_enabled'] as bool? ?? true,
        testMode: j['test_mode'] as bool? ?? false,
        maxBet: j['max_bet'] as int? ?? 100000,
        maxPayout: j['max_payout'] as int? ?? 1000000,
        forcedCrashMultiplier:
            (j['forced_crash_multiplier'] as num?)?.toDouble(),
        forcedExpiresAt: j['forced_crash_multiplier_expires_at'] == null
            ? null
            : DateTime.parse(
                j['forced_crash_multiplier_expires_at'] as String),
        forcedBy: j['forced_crash_multiplier_by'] as String?,
      );
}

class RocketCrashForcedPreview {
  const RocketCrashForcedPreview({
    required this.testMode,
    this.forcedMultiplier,
    this.expiresAt,
    this.note,
  });

  final bool testMode;
  final double? forcedMultiplier;
  final DateTime? expiresAt;
  final String? note;

  bool get hasForced => forcedMultiplier != null;

  factory RocketCrashForcedPreview.fromJson(Map<String, dynamic> j) =>
      RocketCrashForcedPreview(
        testMode: j['test_mode'] as bool? ?? false,
        forcedMultiplier: (j['forced_multiplier'] as num?)?.toDouble(),
        expiresAt: j['expires_at'] == null
            ? null
            : DateTime.parse(j['expires_at'] as String),
        note: j['note'] as String?,
      );
}

class RocketCrashAuditEntry {
  const RocketCrashAuditEntry({
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

  factory RocketCrashAuditEntry.fromJson(Map<String, dynamic> j) =>
      RocketCrashAuditEntry(
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

class RocketCrashAdminService {
  const RocketCrashAdminService();

  // ── Config ────────────────────────────────────────────────────────────────

  Future<RocketCrashGameConfig> fetchConfig() async {
    final data = await SupabaseService.requiredClient
        .rpc('admin_get_rocket_crash_game_config') as Map<String, dynamic>;
    return RocketCrashGameConfig.fromJson(data);
  }

  // ── Test mode ─────────────────────────────────────────────────────────────

  Future<void> setTestMode(bool enabled) async {
    await SupabaseService.requiredClient.rpc(
      'admin_set_rocket_crash_test_mode',
      params: {'p_enabled': enabled},
    );
  }

  // ── Forced multiplier ─────────────────────────────────────────────────────

  Future<RocketCrashForcedPreview> previewForcedResult() async {
    final data = await SupabaseService.requiredClient
        .rpc('admin_preview_rocket_crash_result') as Map<String, dynamic>;
    return RocketCrashForcedPreview.fromJson(data);
  }

  Future<Map<String, dynamic>> setForcedNextMultiplier(
      double multiplier) async {
    final data = await SupabaseService.requiredClient.rpc(
      'set_rocket_crash_forced_next_multiplier',
      params: {'p_multiplier': multiplier},
    ) as Map<String, dynamic>;
    return data;
  }

  Future<void> clearForcedMultiplier() async {
    await SupabaseService.requiredClient
        .rpc('admin_clear_rocket_crash_forced_multiplier');
  }

  // ── Void round ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> voidRound(String roundId) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_void_rocket_crash_round',
      params: {'p_round_id': roundId},
    ) as Map<String, dynamic>;
    return data;
  }

  // ── Audit log ─────────────────────────────────────────────────────────────

  Future<List<RocketCrashAuditEntry>> fetchAuditLog({int limit = 20}) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_get_rocket_crash_audit_log',
      params: {'p_limit': limit},
    );
    return (data as List)
        .map((e) =>
            RocketCrashAuditEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
