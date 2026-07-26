/// Frame System v2 — admin service.
///
/// Thin wrappers over the v2 SECURITY DEFINER RPCs
/// (20261112000000_frame_system_v2.sql). Authorization is enforced
/// server-side by `has_admin_access()`; this class adds no second
/// permission model.
library;

import '../../../core/frames/srood_frame.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../shared/utils/error_utils.dart';
import '../exceptions/frame_admin_exception.dart';

/// Injection seam for the v2 admin RPCs, matching the closure pattern in
/// `features/backpack_v2/repositories/supabase_backpack_v2_repository.dart`.
/// The repo has no mocking library, so tests supply a closure instead.
typedef FrameAdminRpcCaller =
    Future<dynamic> Function(String fn, {Map<String, dynamic>? params});

/// Injection seam for the one plain table read this service performs.
typedef FrameCatalogReader = Future<List<Map<String, dynamic>>> Function();

/// The exact 20-key payload both `admin_create_frame_v2` and
/// `admin_upsert_frame_v2` take, in the order the SQL declares them.
///
/// Shared between create and update on purpose: the create RPC was written
/// with the same signature so one builder serves both. Every nullable column
/// is sent explicitly — the admin editor previously omitted `p_thumbnail_url`,
/// `p_animation_url`, `p_unlock_value` and `p_required_level`, which made the
/// upsert null them out on every edit.
Map<String, dynamic> frameRpcParams(SroodFrame frame) => {
  'p_code': frame.code,
  'p_name': frame.name,
  'p_category': frame.category.wire,
  'p_vip_level': frame.vipLevel,
  'p_rarity': frame.rarity.wire,
  'p_asset_type': frame.assetType.wire,
  'p_asset_url': frame.assetUrl,
  'p_thumbnail_url': frame.thumbnailUrl,
  'p_animation_url': frame.animationUrl,
  'p_is_animated': frame.isAnimated,
  'p_is_active': frame.isActive,
  'p_sort_order': frame.sortOrder,
  'p_unlock_type': frame.unlockType.wire,
  'p_unlock_value': frame.unlockValue,
  'p_required_role': frame.requiredRole,
  'p_required_level': frame.requiredLevel,
  'p_required_vip_level': frame.requiredVipLevel,
  'p_starts_at': frame.startsAt?.toUtc().toIso8601String(),
  'p_expires_at': frame.expiresAt?.toUtc().toIso8601String(),
  'p_localized_names': frame.localizedNames,
};

class FrameOwnershipAuditEntry {
  const FrameOwnershipAuditEntry({
    required this.action,
    required this.createdAt,
    this.userId,
    this.frameCode,
    this.actorId,
    this.details = const {},
  });

  final String action;
  final DateTime? createdAt;
  final String? userId;
  final String? frameCode;
  final String? actorId;
  final Map<String, dynamic> details;

  factory FrameOwnershipAuditEntry.fromJson(Map<String, dynamic> json) {
    return FrameOwnershipAuditEntry(
      action: json['action']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      userId: json['user_id']?.toString(),
      frameCode: json['frame_code']?.toString(),
      actorId: json['actor_id']?.toString(),
      details: json['details'] is Map
          ? Map<String, dynamic>.from(json['details'] as Map)
          : const {},
    );
  }
}

class FrameAdminService {
  FrameAdminService({
    FrameAdminRpcCaller? rpcCaller,
    FrameCatalogReader? reader,
  }) : _rpc = rpcCaller ?? _defaultRpcCaller,
       _readCatalog = reader ?? _defaultCatalogReader;

  final FrameAdminRpcCaller _rpc;
  final FrameCatalogReader _readCatalog;

  static Future<dynamic> _defaultRpcCaller(
    String fn, {
    Map<String, dynamic>? params,
  }) => SupabaseService.requiredClient.rpc(fn, params: params);

  static Future<List<Map<String, dynamic>>> _defaultCatalogReader() async {
    final data = await SupabaseService.requiredClient
        .from('frame_catalog')
        .select()
        .order('sort_order', ascending: true);
    return (data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// Full catalog including inactive frames (RLS lets admins read all rows).
  Future<List<SroodFrame>> listFrames() async {
    try {
      final rows = await _readCatalog();
      return rows.map(SroodFrame.fromJson).toList();
    } catch (error, stack) {
      debugError('FrameAdminService.listFrames', error, stack);
      throw mapFrameAdminError(error);
    }
  }

  /// Whether [code] is already taken. Used for a fast, readable duplicate
  /// error before the round trip; `admin_create_frame_v2` is the race-safe
  /// backstop that actually refuses to overwrite.
  Future<bool> frameCodeExists(String code) async {
    final rows = await _readCatalog();
    return rows.any((row) => row['code']?.toString() == code);
  }

  /// Creates a new frame. Fails with [FrameAdminErrorCategory.duplicateCode]
  /// rather than overwriting an existing row — unlike [upsertFrame], whose
  /// underlying RPC ends in `on conflict (code) do update`.
  Future<void> createFrame(SroodFrame frame) =>
      _writeFrame('admin_create_frame_v2', frame);

  /// Updates an existing frame through the original v2 upsert RPC.
  Future<void> upsertFrame(SroodFrame frame) =>
      _writeFrame('admin_upsert_frame_v2', frame);

  Future<void> _writeFrame(String fn, SroodFrame frame) async {
    try {
      await _rpc(fn, params: frameRpcParams(frame));
    } catch (error, stack) {
      debugError('FrameAdminService.$fn', error, stack);
      throw mapFrameAdminError(error);
    }
  }

  Future<void> assignFrame({
    required String userId,
    required String code,
    String source = 'admin_grant',
    DateTime? expiresAt,
  }) async {
    try {
      await _rpc(
        'admin_assign_frame_v2',
        params: {
          'p_user_id': userId,
          'p_code': code,
          'p_source': source,
          'p_expires_at': expiresAt?.toUtc().toIso8601String(),
        },
      );
    } catch (error, stack) {
      debugError('FrameAdminService.assignFrame', error, stack);
      throw mapFrameAdminError(error);
    }
  }

  Future<void> revokeFrame({
    required String userId,
    required String code,
    String? reason,
  }) async {
    try {
      await _rpc(
        'admin_revoke_frame_v2',
        params: {'p_user_id': userId, 'p_code': code, 'p_reason': reason},
      );
    } catch (error, stack) {
      debugError('FrameAdminService.revokeFrame', error, stack);
      throw mapFrameAdminError(error);
    }
  }

  Future<List<FrameOwnershipAuditEntry>> ownershipHistory({
    String? userId,
    int limit = 200,
  }) async {
    try {
      final data = await _rpc(
        'admin_frame_ownership_history_v2',
        params: {'p_user_id': userId, 'p_limit': limit},
      );
      return (data as List<dynamic>)
          .map(
            (row) =>
                FrameOwnershipAuditEntry.fromJson(row as Map<String, dynamic>),
          )
          .toList();
    } catch (error, stack) {
      debugError('FrameAdminService.ownershipHistory', error, stack);
      throw mapFrameAdminError(error);
    }
  }

  Future<Map<String, dynamic>> migrationReport() async {
    try {
      final data = await _rpc('frames_v2_migration_report');
      return data is Map ? Map<String, dynamic>.from(data) : const {};
    } catch (error, stack) {
      debugError('FrameAdminService.migrationReport', error, stack);
      throw mapFrameAdminError(error);
    }
  }

  Future<void> setEnforcement(bool enforce) async {
    try {
      await _rpc(
        'admin_set_frame_enforcement_v2',
        params: {'p_enforce': enforce},
      );
    } catch (error, stack) {
      debugError('FrameAdminService.setEnforcement', error, stack);
      throw mapFrameAdminError(error);
    }
  }
}
