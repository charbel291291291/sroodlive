class SupabaseConfig {
  // The anon/publishable key is intentionally public — Supabase security
  // relies on Row Level Security, not key secrecy.  These defaults let the
  // app run without --dart-define flags.  Override via dart-define in CI/CD:
  //   flutter build ... --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xwcldazsjauaeywklukb.supabase.co',
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_sVE1mM17eltYmn6y9nRdGg_WNXEC3qx',
  );

  static bool get isConfigured {
    return url.isNotEmpty && anonKey.isNotEmpty;
  }

  /// Returns the full public storage URL for a given bucket and path.
  /// Example: https://your-project.supabase.co/storage/v1/object/public/bucket/path
  static String getPublicStorageUrl(String bucket, String path) {
    return '$url/storage/v1/object/public/$bucket/$path';
  }
}
