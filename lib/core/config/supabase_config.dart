class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured {
    return url.isNotEmpty && anonKey.isNotEmpty;
  }

  /// Returns the full public storage URL for a given bucket and path.
  /// Example: https://your-project.supabase.co/storage/v1/object/public/bucket/path
  static String getPublicStorageUrl(String bucket, String path) {
    return '$url/storage/v1/object/public/$bucket/$path';
  }
}
