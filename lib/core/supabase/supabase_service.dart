import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class SupabaseService {
  static bool get isConfigured {
    return SupabaseConfig.isConfigured;
  }

  static SupabaseClient? get client {
    if (!isConfigured) return null;
    return Supabase.instance.client;
  }

  static SupabaseClient get requiredClient {
    final supabaseClient = client;

    if (supabaseClient == null) {
      throw StateError('Supabase is not configured');
    }

    return supabaseClient;
  }
}
