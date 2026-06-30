import 'dart:async';

import 'package:srood_live/shared/utils/error_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/user_vip.dart';
import '../models/vip_level.dart';

/// One-stop service for all VIP data in the app.
///
/// - Singleton accessed via `VipService()`.
/// - In-memory cache prevents repeated Supabase round-trips from every widget.
/// - Cache is invalidated on logout, auth state changes, or explicit flush.
/// - All public methods are safe to call from any widget; they return cached
///   data synchronously if available, fetching lazily otherwise.
///
/// Usage:
/// ```dart
/// final vip = await VipService().getMyVip();
/// final otherVip = await VipService().getUserVip(someUserId);
/// final batchVips = await VipService().getUsersVip(memberIds);
/// ```
class VipService {
  VipService._internal();
  static final VipService _instance = VipService._internal();
  factory VipService() => _instance;

  // ── Cache ──────────────────────────────────────────────────────────────────

  final Map<String, UserVip> _cache = {};
  List<VipLevelMeta>? _levelsCache;
  // ── Realtime ───────────────────────────────────────────────────────────────

  RealtimeChannel? _myVipChannel;
  final StreamController<UserVip?> _myVipController =
      StreamController<UserVip?>.broadcast();

  // ── Auth tracking ──────────────────────────────────────────────────────────

  StreamSubscription<AuthState>? _authSub;

  /// Call once at app startup (e.g. in main.dart or AppState).
  void init() {
    _authSub?.cancel();
    _authSub = SupabaseService.requiredClient.auth.onAuthStateChange.listen(
      (event) {
        if (event.event == AuthChangeEvent.signedOut) {
          clearCache();
          _stopMyVipChannel();
        } else if (event.event == AuthChangeEvent.signedIn ||
            event.event == AuthChangeEvent.tokenRefreshed) {
          unawaited(_refreshMyVipFromServer());
        }
      },
    );
  }

  /// Release resources. Usually called only on full app shutdown.
  void dispose() {
    _authSub?.cancel();
    _stopMyVipChannel();
    _myVipController.close();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Current authenticated user's VIP summary (cached).
  /// Returns null when not logged in.
  Future<UserVip?> getMyVip() async {
    final uid = SupabaseService.requiredClient.auth.currentUser?.id;
    if (uid == null) return null;
    if (_cache.containsKey(uid)) return _cache[uid];
    return _refreshMyVipFromServer();
  }

  /// Any user's VIP summary (cached).
  Future<UserVip?> getUserVip(String userId) async {
    if (_cache.containsKey(userId)) return _cache[userId];
    return refreshUserVip(userId);
  }

  /// Batch-load VIP for many users at once (one Supabase round-trip).
  /// Already-cached users are returned from cache; only missing ones fetched.
  Future<Map<String, UserVip>> getUsersVip(List<String> userIds) async {
    if (userIds.isEmpty) return {};

    final result = <String, UserVip>{};
    final missing = <String>[];

    for (final id in userIds) {
      final cached = _cache[id];
      if (cached != null) {
        result[id] = cached;
      } else {
        missing.add(id);
      }
    }

    if (missing.isEmpty) return result;

    try {
      final raw = await SupabaseService.requiredClient.rpc(
        'get_users_with_vip',
        params: {'p_user_ids': missing},
      );

      if (raw is Map) {
        for (final entry in raw.entries) {
          final uid = entry.key as String;
          final row = entry.value as Map<String, dynamic>?;
          final vip =
              row != null ? UserVip.fromJson(row) : UserVip.none(uid);
          _cache[uid] = vip;
          result[uid] = vip;
        }
      }
    } catch (e, st) {
      debugError('VipService.getUsersVip', e, st);
      for (final id in missing) {
        result[id] = UserVip.none(id);
      }
    }

    return result;
  }

  /// Live stream of the current user's VIP status.
  /// Emits whenever the profile row for the current user changes (realtime).
  Stream<UserVip?> watchMyVip() {
    _ensureMyVipChannel();
    return _myVipController.stream;
  }

  /// Sync check from in-memory cache only (no network). Returns false if
  /// data is not cached yet.
  bool isVipActiveSync(String userId) {
    return _cache[userId]?.isVipActive ?? false;
  }

  /// Check whether the current user's cached VIP grants a named feature.
  /// Feature keys match [VipLevelMeta.roomPrivileges] keys.
  bool canUseFeature(String featureKey) {
    final uid = SupabaseService.requiredClient.auth.currentUser?.id;
    if (uid == null) return false;
    final vip = _cache[uid];
    if (vip == null || !vip.isVipActive) return false;
    return vip.visuals != null; // valid VIP
  }

  /// Evict everything from cache.  Next access will re-fetch from Supabase.
  void clearCache() {
    _cache.clear();
    _levelsCache = null;
  }

  /// Force-refresh a single user's VIP from Supabase.
  Future<UserVip?> refreshUserVip(String userId) async {
    try {
      final raw = await SupabaseService.requiredClient
          .rpc('get_user_vip', params: {'p_user_id': userId});
      if (raw == null) {
        final vip = UserVip.none(userId);
        _cache[userId] = vip;
        return vip;
      }
      final vip =
          UserVip.fromJson(Map<String, dynamic>.from(raw as Map));
      _cache[userId] = vip;
      return vip;
    } catch (e, st) {
      debugError('VipService.refreshUserVip', e, st);
      return _cache[userId]; // return stale cache on error
    }
  }

  /// Load all active VIP levels metadata (cached until clearCache).
  Future<List<VipLevelMeta>> getVipLevels() async {
    if (_levelsCache != null) return _levelsCache!;
    try {
      final rows = await SupabaseService.requiredClient
          .from('vip_levels')
          .select()
          .eq('is_active', true)
          .order('level');
      _levelsCache = (rows as List)
          .map((r) => VipLevelMeta.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      return _levelsCache!;
    } catch (e, st) {
      debugError('VipService.getVipLevels', e, st);
      return [];
    }
  }

  // ── Admin operations ───────────────────────────────────────────────────────

  /// Admin: grant VIP to a user.  Returns the result JSON or throws.
  Future<Map<String, dynamic>> grantVip({
    required String userId,
    required int vipLevel,
    int durationDays = 30,
  }) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'grant_vip',
      params: {
        'p_user_id': userId,
        'p_vip_level': vipLevel,
        'p_duration_days': durationDays,
      },
    );
    // Invalidate cache for this user so next read is fresh.
    _cache.remove(userId);
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Admin: revoke VIP from a user (grant level 0).
  Future<void> revokeVip(String userId) async {
    await grantVip(userId: userId, vipLevel: 0, durationDays: 0);
  }

  /// Admin: set or clear the Golden ID badge on a user's profile.
  ///
  /// [enabled] = true  → activates Golden ID.
  ///   [durationDays] null = permanent; a positive number = expires after N days.
  /// [enabled] = false → clears Golden ID and its expiry.
  ///
  /// Returns the updated profile fields or throws on permission denial.
  Future<Map<String, dynamic>> setGoldenId({
    required String userId,
    required bool enabled,
    int? durationDays,
  }) async {
    final params = <String, dynamic>{
      'p_user_id': userId,
      'p_enabled': enabled,
    };
    if (durationDays != null) params['p_duration_days'] = durationDays;

    final raw = await SupabaseService.requiredClient.rpc(
      'set_golden_id',
      params: params,
    );
    _cache.remove(userId);
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Admin-only: set a custom Golden ID with full style and frame options.
  ///
  /// Calls [set_custom_golden_id] which validates uniqueness, format, style
  /// and frame, then updates the profile atomically.
  Future<Map<String, dynamic>> setCustomGoldenId({
    required String userId,
    required String publicUserId,
    required bool enabled,
    int? durationDays,
    String style = 'gold',
    String frame = 'classic',
  }) async {
    final params = <String, dynamic>{
      'p_user_id':        userId,
      'p_public_user_id': publicUserId,
      'p_enabled':        enabled,
      'p_style':          style,
      'p_frame':          frame,
    };
    if (durationDays != null) params['p_duration_days'] = durationDays;

    final raw = await SupabaseService.requiredClient.rpc(
      'set_custom_golden_id',
      params: params,
    );
    _cache.remove(userId);
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Trigger expiry sweep on the server.
  Future<int> expireOldVips() async {
    final count = await SupabaseService.requiredClient.rpc('expire_old_vips');
    return (count as int?) ?? 0;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<UserVip?> _refreshMyVipFromServer() async {
    final uid = SupabaseService.requiredClient.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final raw = await SupabaseService.requiredClient.rpc('get_my_vip');
      if (raw == null) {
        final vip = UserVip.none(uid);
        _cache[uid] = vip;
        _myVipController.add(vip);
        return vip;
      }
      final vip = UserVip.fromJson(Map<String, dynamic>.from(raw as Map));
      _cache[uid] = vip;
      _myVipController.add(vip);
      return vip;
    } catch (e, st) {
      debugError('VipService._refreshMyVipFromServer', e, st);
      return _cache[uid];
    }
  }

  void _ensureMyVipChannel() {
    if (_myVipChannel != null) return;
    final uid = SupabaseService.requiredClient.auth.currentUser?.id;
    if (uid == null) return;

    _myVipChannel = SupabaseService.requiredClient
        .channel('vip_watch_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            final vip = UserVip.fromProfileRow(row, uid);
            _cache[uid] = vip;
            _myVipController.add(vip);
          },
        )
        .subscribe();
  }

  void _stopMyVipChannel() {
    final ch = _myVipChannel;
    if (ch != null) {
      unawaited(
        SupabaseService.requiredClient.removeChannel(ch),
      );
      _myVipChannel = null;
    }
  }
}
