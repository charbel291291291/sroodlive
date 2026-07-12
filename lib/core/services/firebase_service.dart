import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../supabase/supabase_service.dart';

/// Production foundation for Firebase: Crashlytics (crash reporting),
/// Analytics, and FCM push notifications.
///
/// Everything here is defensive: if the native Firebase config
/// (google-services.json / GoogleService-Info.plist) is missing, or the app
/// runs in an environment where Firebase can't initialize (tests, web dev),
/// initialization silently no-ops instead of crashing the app. This lets the
/// codebase ship the wiring now and light up once the native config lands.
class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  bool _initialized = false;
  FirebaseAnalytics? _analytics;
  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _tokenRefreshSubscription;

  FirebaseAnalytics? get analytics => _analytics;

  /// Initializes Firebase and its sub-services. Safe to call unconditionally
  /// from main(); returns silently if Firebase is unavailable.
  Future<void> init() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // No native config / unsupported platform — skip Firebase entirely.
      debugPrint('[Firebase] init skipped: $e');
      return;
    }
    _initialized = true;

    await _initCrashlytics();
    _initAnalytics();
    // FCM permission + token registration are deferred to onSignedIn(), so we
    // only ask for notification permission once the user has an account to
    // attach the token to.
  }

  Future<void> _initCrashlytics() async {
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      // Don't collect in debug — only real/release sessions.
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
      // Route Flutter framework errors and uncaught async errors to Crashlytics.
      FlutterError.onError = crashlytics.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('[Firebase] crashlytics init skipped: $e');
    }
  }

  void _initAnalytics() {
    try {
      _analytics = FirebaseAnalytics.instance;
    } catch (e) {
      debugPrint('[Firebase] analytics init skipped: $e');
    }
  }

  /// Logs a lightweight analytics event. No-ops if analytics is unavailable.
  Future<void> logEvent(String name, [Map<String, Object>? params]) async {
    try {
      await _analytics?.logEvent(name: name, parameters: params);
    } catch (_) {
      // analytics is best-effort; never surface to the user.
    }
  }

  /// Call after a user signs in: requests notification permission and
  /// registers the device's FCM token with the backend so the account can
  /// receive pushes. Safe to call when Firebase is unavailable.
  Future<void> onSignedIn() async {
    if (!_initialized) return;
    try {
      _messaging ??= FirebaseMessaging.instance;
      final messaging = _messaging!;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
      // Keep the backend in sync if the token rotates.
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
        _registerToken,
      );
    } catch (e) {
      debugPrint('[Firebase] FCM setup skipped: $e');
    }
  }

  /// Deactivates this device token while the Supabase session still exists.
  /// Best-effort: logout must continue even when Firebase is unavailable.
  Future<void> onSignedOut() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    if (!_initialized) return;

    try {
      _messaging ??= FirebaseMessaging.instance;
      final token = await _messaging!.getToken();
      final client = SupabaseService.client;
      if (token == null || client?.auth.currentUser == null) return;
      await client!.rpc(
        'deactivate_my_push_token',
        params: {'p_token': token},
      );
    } catch (e) {
      debugPrint('[Firebase] token deactivation skipped: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      final client = SupabaseService.client;
      if (client == null || client.auth.currentUser == null) return;
      await client.rpc('upsert_push_token', params: {
        'p_token': token,
        'p_platform': _platformName(),
      });
    } catch (e) {
      debugPrint('[Firebase] token register skipped: $e');
    }
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'android';
    }
  }
}
