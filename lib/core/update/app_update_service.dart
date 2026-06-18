import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../supabase/supabase_service.dart';

class AppVersionInfo {
  const AppVersionInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.releaseNotes,
    required this.forceUpdate,
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String releaseNotes;
  final bool forceUpdate;
}

class AppUpdateService {
  const AppUpdateService();

  static const _rowId = 'android_latest';

  /// Returns [AppVersionInfo] if a newer version is available, otherwise null.
  /// Only runs on Android; always returns null on other platforms.
  Future<AppVersionInfo?> checkForUpdate() async {
    if (!defaultTargetPlatform.isAndroid) return null;

    try {
      final client = SupabaseService.client;
      if (client == null) return null;

      final row = await client
          .from('app_versions')
          .select()
          .eq('id', _rowId)
          .eq('is_active', true)
          .maybeSingle();

      if (row == null) return null;

      final remoteCode = (row['version_code'] as num?)?.toInt() ?? 0;
      final info = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(info.buildNumber) ?? 0;

      if (remoteCode <= localCode) return null;

      return AppVersionInfo(
        versionCode: remoteCode,
        versionName: row['version_name'] as String? ?? '',
        apkUrl: row['apk_url'] as String? ?? '',
        releaseNotes: row['release_notes'] as String? ?? '',
        forceUpdate: row['force_update'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('[UPDATE] check failed: $e');
      return null;
    }
  }
}

extension on TargetPlatform {
  bool get isAndroid => this == TargetPlatform.android;
}
