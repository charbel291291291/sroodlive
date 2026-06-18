import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_service.dart';

class SafeLogout {
  const SafeLogout._();

  /// Signs the current user out, clearing the local session.
  ///
  /// Step 1: `signOut(scope: SignOutScope.local)` — clears local storage
  ///   without a network call. Should always succeed.
  /// Step 2: Verify `currentUser` is null. If not, try a global signOut.
  /// Step 3: If `currentUser` is still non-null, throw so the caller can
  ///   surface an error. In practice Step 1 always succeeds.
  static Future<void> run() async {
    final client = SupabaseService.requiredClient;

    debugPrint('[SafeLogout] ① begin — currentUser=${client.auth.currentUser?.id}');

    // ── Step 1: local sign-out (clears hive/shared_prefs, no network) ─────
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (e, st) {
      debugPrint('[SafeLogout] local signOut threw: $e');
      if (kDebugMode) debugPrintStack(stackTrace: st);
    }

    debugPrint('[SafeLogout] ② after local signOut — currentUser=${client.auth.currentUser?.id}');

    if (client.auth.currentUser == null) {
      debugPrint('[SafeLogout] ✓ session cleared');
      return;
    }

    // ── Step 2: global sign-out fallback ──────────────────────────────────
    debugPrint('[SafeLogout] ③ currentUser still set — trying global signOut');
    try {
      await client.auth.signOut();
    } catch (e, st) {
      debugPrint('[SafeLogout] global signOut threw: $e');
      if (kDebugMode) debugPrintStack(stackTrace: st);
    }

    debugPrint('[SafeLogout] ④ after global signOut — currentUser=${client.auth.currentUser?.id}');

    if (client.auth.currentUser == null) {
      debugPrint('[SafeLogout] ✓ session cleared via global signOut');
      return;
    }

    // ── Step 3: both failed ───────────────────────────────────────────────
    debugPrint('[SafeLogout] ✗ currentUser still non-null after both signOut calls');
    throw Exception('[SafeLogout] Could not clear session — user still authenticated');
  }
}
