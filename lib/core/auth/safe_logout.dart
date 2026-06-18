import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_service.dart';

class SafeLogout {
  const SafeLogout._();

  static Future<void> run() async {
    final client = SupabaseService.requiredClient;

    try {
      await client.auth.signOut(scope: SignOutScope.local);
      return;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Logout] local signOut failed: $e');
        debugPrintStack(stackTrace: st);
      }
    }

    try {
      await client.auth.signOut();
      return;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Logout] global signOut failed: $e');
        debugPrintStack(stackTrace: st);
      }
    }

    // Last-resort fallback: do not crash the UI.
    // On web this can still leave browser storage until refresh/profile clear,
    // but the app will continue and can navigate to the auth screen.
  }
}
