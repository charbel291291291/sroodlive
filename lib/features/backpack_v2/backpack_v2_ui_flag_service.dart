/// Typed client for the `backpack_v2_ui_enabled` database feature flag.
///
/// Backed by `public.backpack_v2_ui_enabled()` (see
/// 20261123000000_backpack_v2_ui_flag.sql) — a SECURITY DEFINER RPC readable
/// by authenticated callers that always returns a boolean and defaults to
/// `false` server-side. This service mirrors
/// `FramesV2RenderingFlagService` (lib/core/frames/frames_v2_rendering_flag_service.dart)
/// exactly in shape (in-memory cache, coalesced concurrent loads, safe-false
/// fallback) but is a distinct flag instance scoped to this module — Backpack
/// V2 UI reachability is a different concern from Frame V2 rendering and
/// must be switchable independently. No new feature-flag framework is
/// introduced.
///
/// Contract: [value] is always safe to read synchronously (e.g. as a widget
/// default) and is `false` until a fetch has succeeded and returned `true`
/// at least once, or whenever the underlying data is missing or a fetch
/// fails — the Backpack V2 screen stays unreachable in every one of those
/// cases.
library;

import 'package:flutter/foundation.dart';

import '../../core/supabase/supabase_service.dart';

/// How the flag was last resolved. Exposed for tests/diagnostics only — app
/// code should just read [BackpackV2UiFlagService.value].
enum BackpackV2UiFlagStatus {
  /// No successful fetch has completed yet.
  unloaded,

  /// Last fetch succeeded and returned `true`.
  enabled,

  /// Last fetch succeeded and returned `false`.
  disabled,

  /// Last fetch succeeded but returned no usable value (null/malformed
  /// response, or Supabase not configured) — treated as disabled.
  missing,

  /// Last fetch threw (network/RPC error) — treated as disabled.
  loadingError,
}

class BackpackV2UiFlagService {
  BackpackV2UiFlagService({
    Future<dynamic> Function()? rpcCall,
    this.cacheTtl = const Duration(minutes: 5),
  }) : _rpcCall = rpcCall ?? _defaultRpcCall;

  static final BackpackV2UiFlagService instance = BackpackV2UiFlagService();

  static const _rpcName = 'backpack_v2_ui_enabled';

  static Future<dynamic> _defaultRpcCall() async {
    final client = SupabaseService.client;
    if (client == null) return null;
    return client.rpc(_rpcName);
  }

  final Future<dynamic> Function() _rpcCall;
  final Duration cacheTtl;

  bool _cached = false;
  DateTime? _cachedAt;
  BackpackV2UiFlagStatus _status = BackpackV2UiFlagStatus.unloaded;
  Future<bool>? _inFlight;

  /// Cached flag value, safe to read synchronously (e.g. as a widget
  /// default). `false` — screen unreachable — until proven otherwise by a
  /// successful [load].
  bool get value => _cached;

  /// Diagnostic status of the last resolution attempt.
  BackpackV2UiFlagStatus get status => _status;

  bool get _isStale =>
      _cachedAt == null || DateTime.now().difference(_cachedAt!) > cacheTtl;

  /// Loads (or returns the cached) flag value. Never throws: any failure —
  /// missing client, RPC error, malformed response — safely resolves to
  /// `false` without disturbing a prior successful cache entry beyond
  /// recording [status]. Concurrent callers coalesce onto the same in-flight
  /// fetch.
  Future<bool> load({bool forceRefresh = false}) {
    if (!forceRefresh &&
        _status != BackpackV2UiFlagStatus.unloaded &&
        !_isStale) {
      return Future.value(_cached);
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<bool> _fetch() async {
    try {
      final result = await _rpcCall();
      if (result is! bool) {
        _status = BackpackV2UiFlagStatus.missing;
        _cached = false;
        _cachedAt = DateTime.now();
        return false;
      }
      _status = result
          ? BackpackV2UiFlagStatus.enabled
          : BackpackV2UiFlagStatus.disabled;
      _cached = result;
      _cachedAt = DateTime.now();
      return result;
    } catch (e) {
      debugPrint('[BACKPACK_V2] ui flag load failed: $e');
      _status = BackpackV2UiFlagStatus.loadingError;
      _cached = false;
      _cachedAt = DateTime.now();
      return false;
    }
  }

  @visibleForTesting
  void resetForTest() {
    _cached = false;
    _cachedAt = null;
    _status = BackpackV2UiFlagStatus.unloaded;
    _inFlight = null;
  }

  /// Seeds the cache directly (bypassing [_rpcCall]), for widgets/tests that
  /// need a specific resolved value without a fetch round-trip.
  @visibleForTesting
  void seedForTest(bool value, {BackpackV2UiFlagStatus? status}) {
    _cached = value;
    _cachedAt = DateTime.now();
    _status =
        status ??
        (value
            ? BackpackV2UiFlagStatus.enabled
            : BackpackV2UiFlagStatus.disabled);
  }
}
