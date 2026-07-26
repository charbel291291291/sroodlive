/// Typed client for the `frames_v2_rendering_enabled` database feature flag.
///
/// Backed by `public.frames_v2_rendering_flag()` (see
/// 20261114000000_frames_v2_rendering_enabled_flag.sql) — a SECURITY DEFINER
/// RPC readable by anon/authenticated that always returns a boolean and
/// defaults to `false` server-side. This service adds an in-memory cache and
/// a client-side false fallback on top, following the same
/// fetch-in-try/catch-return-safe-default shape as [AppUpdateService].
///
/// Contract: [value] is always safe to read synchronously (e.g. as a widget
/// default) and is `false` until a fetch has succeeded at least once, or
/// whenever the underlying data is missing or a fetch fails — the exact
/// current legacy rendering path is what every caller gets in those cases.
library;

import 'package:flutter/foundation.dart';

import '../supabase/supabase_service.dart';

/// How the flag was last resolved. Exposed for tests/diagnostics only — app
/// code should just read [FramesV2RenderingFlagService.value].
enum FramesV2FlagStatus {
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

class FramesV2RenderingFlagService {
  FramesV2RenderingFlagService({
    Future<dynamic> Function()? rpcCall,
    this.cacheTtl = const Duration(minutes: 5),
  }) : _rpcCall = rpcCall ?? _defaultRpcCall;

  static final FramesV2RenderingFlagService instance =
      FramesV2RenderingFlagService();

  static const _rpcName = 'frames_v2_rendering_flag';

  static Future<dynamic> _defaultRpcCall() async {
    final client = SupabaseService.client;
    if (client == null) return null;
    return client.rpc(_rpcName);
  }

  final Future<dynamic> Function() _rpcCall;
  final Duration cacheTtl;

  bool _cached = false;
  DateTime? _cachedAt;
  FramesV2FlagStatus _status = FramesV2FlagStatus.unloaded;
  Future<bool>? _inFlight;

  /// Cached flag value, safe to read synchronously (e.g. as a widget
  /// default). `false` — the legacy rendering path — until proven otherwise
  /// by a successful [load].
  bool get value => _cached;

  /// Diagnostic status of the last resolution attempt.
  FramesV2FlagStatus get status => _status;

  bool get _isStale =>
      _cachedAt == null || DateTime.now().difference(_cachedAt!) > cacheTtl;

  /// Loads (or returns the cached) flag value. Never throws: any failure —
  /// missing client, RPC error, malformed response — safely resolves to
  /// `false` without disturbing a prior successful cache entry beyond
  /// recording [status].
  Future<bool> load({bool forceRefresh = false}) {
    if (!forceRefresh && _status != FramesV2FlagStatus.unloaded && !_isStale) {
      return Future.value(_cached);
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<bool> _fetch() async {
    try {
      final result = await _rpcCall();
      if (result is! bool) {
        _status = FramesV2FlagStatus.missing;
        _cached = false;
        _cachedAt = DateTime.now();
        return false;
      }
      _status = result
          ? FramesV2FlagStatus.enabled
          : FramesV2FlagStatus.disabled;
      _cached = result;
      _cachedAt = DateTime.now();
      return result;
    } catch (e) {
      debugPrint('[FRAMES_V2] rendering flag load failed: $e');
      _status = FramesV2FlagStatus.loadingError;
      _cached = false;
      _cachedAt = DateTime.now();
      return false;
    }
  }

  @visibleForTesting
  void resetForTest() {
    _cached = false;
    _cachedAt = null;
    _status = FramesV2FlagStatus.unloaded;
    _inFlight = null;
  }

  /// Seeds the cache directly (bypassing [_rpcCall]), for widgets/tests that
  /// need a specific resolved value without a fetch round-trip.
  @visibleForTesting
  void seedForTest(bool value, {FramesV2FlagStatus? status}) {
    _cached = value;
    _cachedAt = DateTime.now();
    _status =
        status ??
        (value ? FramesV2FlagStatus.enabled : FramesV2FlagStatus.disabled);
  }
}
