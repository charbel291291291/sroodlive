import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/startup_promo.dart';

class StartupPromoService {
  const StartupPromoService();

  static const _prefKeyLastShownDate = 'startup_promo_last_date_';
  static const _prefKeyShownOnce     = 'startup_promo_shown_once_';

  // In-memory flag for once_per_session so it survives hot-restart checks.
  static final Set<String> _sessionShown = {};

  // ── User-facing: fetch active promo ────────────────────────────────────────

  Future<StartupPromo?> fetchActivePromo() async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[PerfStartupPromo] check started');
    try {
      final data = await SupabaseService.requiredClient
          .rpc('get_active_startup_promo');
      final rows = data as List<dynamic>;
      if (rows.isEmpty) {
        debugPrint('[PerfStartupPromo] no active promo');
        return null;
      }
      final promo = StartupPromo.fromJson(rows.first as Map<String, dynamic>);
      debugPrint('[PerfStartupPromo] promo fetched in ${DateTime.now().millisecondsSinceEpoch - t0}ms id=${promo.id}');
      return promo;
    } catch (e) {
      debugPrint('[PerfStartupPromo] fetch error: $e');
      return null;
    }
  }

  // ── Frequency / display-rule check ─────────────────────────────────────────

  Future<bool> shouldDisplay(StartupPromo promo) async {
    if (promo.imageUrl.isEmpty) return false;

    switch (promo.frequency) {
      case 'every_open':
        return true;

      case 'once_per_session':
        if (_sessionShown.contains(promo.id)) return false;
        return true;

      case 'once_only':
        final prefs = await SharedPreferences.getInstance();
        return !(prefs.getBool('$_prefKeyShownOnce${promo.id}') ?? false);

      case 'once_per_day':
      default:
        final prefs = await SharedPreferences.getInstance();
        final lastDate = prefs.getString('$_prefKeyLastShownDate${promo.id}');
        if (lastDate == null) return true;
        final today = _todayKey();
        return lastDate != today;
    }
  }

  Future<void> recordDisplayed(StartupPromo promo) async {
    _sessionShown.add(promo.id);
    final prefs = await SharedPreferences.getInstance();
    switch (promo.frequency) {
      case 'once_only':
        await prefs.setBool('$_prefKeyShownOnce${promo.id}', true);
      case 'once_per_day':
      default:
        await prefs.setString('$_prefKeyLastShownDate${promo.id}', _todayKey());
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // ── Admin: list / save / delete ────────────────────────────────────────────

  Future<List<AdminStartupPromo>> adminListPromos() async {
    final data = await SupabaseService.requiredClient
        .rpc('admin_list_startup_promos');
    return (data as List<dynamic>)
        .map((r) => AdminStartupPromo.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<String> adminSavePromo({
    String? id,
    required String title,
    required String imageUrl,
    String? storagePath,
    required bool isActive,
    DateTime? startsAt,
    DateTime? endsAt,
    required int durationSeconds,
    required String frequency,
    required int priority,
  }) async {
    final data = await SupabaseService.requiredClient
        .rpc('admin_save_startup_promo', params: {
      'p_id':               id,
      'p_title':            title,
      'p_image_url':        imageUrl,
      'p_storage_path':     storagePath,
      'p_is_active':        isActive,
      'p_starts_at':        startsAt?.toIso8601String(),
      'p_ends_at':          endsAt?.toIso8601String(),
      'p_duration_seconds': durationSeconds,
      'p_frequency':        frequency,
      'p_priority':         priority,
    });
    return data.toString();
  }

  Future<void> adminDeletePromo(String id) async {
    await SupabaseService.requiredClient
        .rpc('admin_delete_startup_promo', params: {'p_id': id});
  }

  // ── Upload promo image to dedicated bucket ─────────────────────────────────

  Future<String> uploadPromoImage({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    final client = SupabaseService.requiredClient;
    final userId = client.auth.currentUser?.id ?? 'anon';
    final now = DateTime.now();
    final ts = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}'
        '_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}${now.second.toString().padLeft(2,'0')}';
    final ext = filename.split('.').last.toLowerCase();
    final path = '${ts}_$userId.$ext';

    await client.storage
        .from('startup-promos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return client.storage.from('startup-promos').getPublicUrl(path);
  }
}
