/// Loads live `frame_catalog` rows into [FrameRegistry].
///
/// Without this the registry only ever serves its hardcoded built-ins:
/// `hydrate` had no callers in `lib/`, so a frame an admin created was stored,
/// entitled, and equippable — and then rendered as nothing, because the
/// renderer could not find a row for its code.
///
/// This does **not** change what users see on its own. `SroodAvatarFrame`
/// still consults `frames_v2_rendering_enabled` (default `false`) before it
/// will prefer v2 art, so hydrating the registry only makes the catalog
/// *available* to the renderer.
///
/// Shape copied from [FramesV2RenderingFlagService]: a static [instance], an
/// injectable RPC closure, a TTL, single-flight de-duplication, and a `load`
/// that never throws — a failed catalog fetch must degrade to the built-ins,
/// never break avatar rendering.
library;

import 'package:flutter/foundation.dart';

import '../supabase/supabase_service.dart';
import 'frame_registry.dart';
import 'srood_frame.dart';

enum FrameCatalogSyncStatus {
  /// No successful fetch has completed yet.
  unloaded,

  /// Rows were fetched and hydrated.
  loaded,

  /// The fetch succeeded but returned nothing usable (Supabase not configured,
  /// malformed payload) — the built-ins stand.
  missing,

  /// The fetch threw — the built-ins stand.
  loadingError,
}

class FrameCatalogSyncService {
  FrameCatalogSyncService({
    Future<dynamic> Function()? rpcCall,
    FrameRegistry? registry,
    this.cacheTtl = const Duration(minutes: 10),
  }) : _rpcCall = rpcCall ?? _defaultRpcCall,
       _registry = registry ?? FrameRegistry.instance;

  static final FrameCatalogSyncService instance = FrameCatalogSyncService();

  /// `get_frame_catalog_v2()` — a stable SECURITY DEFINER RPC granted to
  /// `authenticated` that already filters to active, in-window rows.
  static const _rpcName = 'get_frame_catalog_v2';

  static Future<dynamic> _defaultRpcCall() async {
    final client = SupabaseService.client;
    if (client == null) return null;
    return client.rpc(_rpcName);
  }

  final Future<dynamic> Function() _rpcCall;
  final FrameRegistry _registry;
  final Duration cacheTtl;

  DateTime? _loadedAt;
  FrameCatalogSyncStatus _status = FrameCatalogSyncStatus.unloaded;
  int _rowCount = 0;
  Future<int>? _inFlight;

  FrameCatalogSyncStatus get status => _status;

  /// How many catalog rows the last successful load hydrated.
  int get rowCount => _rowCount;

  bool get _isStale =>
      _loadedAt == null || DateTime.now().difference(_loadedAt!) > cacheTtl;

  /// Fetches the catalog and hydrates the registry. Returns the number of rows
  /// hydrated (0 on any failure). Never throws.
  ///
  /// Admin writes pass `forceRefresh: true` so the admin sees the frame they
  /// just saved rather than a stale list.
  Future<int> load({bool forceRefresh = false}) {
    if (!forceRefresh &&
        _status != FrameCatalogSyncStatus.unloaded &&
        !_isStale) {
      return Future.value(_rowCount);
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<int> _fetch() async {
    try {
      final result = await _rpcCall();
      if (result is! List) {
        _status = FrameCatalogSyncStatus.missing;
        _loadedAt = DateTime.now();
        return 0;
      }

      final rows = <SroodFrame>[];
      for (final entry in result) {
        if (entry is! Map) continue;
        try {
          rows.add(SroodFrame.fromJson(Map<String, dynamic>.from(entry)));
        } catch (e) {
          // One malformed row must not cost the whole catalog.
          debugPrint('[FRAMES_V2] skipped unparseable catalog row: $e');
        }
      }

      // Reset first: `hydrate` merges, so a frame that was deactivated (and is
      // therefore absent from this payload) would otherwise linger.
      _registry.resetToBuiltIns();
      _registry.hydrate(rows);

      _status = FrameCatalogSyncStatus.loaded;
      _rowCount = rows.length;
      _loadedAt = DateTime.now();
      return rows.length;
    } catch (e) {
      debugPrint('[FRAMES_V2] catalog sync failed: $e');
      _status = FrameCatalogSyncStatus.loadingError;
      _loadedAt = DateTime.now();
      return 0;
    }
  }

  @visibleForTesting
  void resetForTest() {
    _loadedAt = null;
    _status = FrameCatalogSyncStatus.unloaded;
    _rowCount = 0;
    _inFlight = null;
  }
}
