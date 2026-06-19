import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppConfig — central branding & environment contract.
//
// Usage (default — already wired in main.dart):
//   AppConfig.instance  →  SroodLiveConfig (set automatically)
//
// To create a new white-label client:
//   1. Add a new config class that extends AppConfig (see TODO below).
//   2. Call AppConfig.configure(MyClientConfig()) before runApp().
//   3. Replace assets in assets/branding/ with client assets.
//   4. Provide client Supabase creds via --dart-define flags.
//
// TODO(white-label): Create configs/my_client_config.dart with custom values
//   and override the fields below.  No screen files should need editing.
// ─────────────────────────────────────────────────────────────────────────────

abstract class AppConfig {
  static AppConfig _instance = const SroodLiveConfig();

  /// The active branding config.  Read anywhere via AppConfig.instance.
  static AppConfig get instance => _instance;

  /// Call once before runApp() to activate a non-default config.
  // ignore: use_setters_to_change_properties
  static void configure(AppConfig config) => _instance = config;

  // ── Identity ───────────────────────────────────────────────────────────────
  /// Internal slug (no spaces).  Used in logs; not shown to users.
  String get appName;

  /// Display name shown in UI strings, dialogs, and the OS task switcher.
  String get appDisplayName;

  /// Short tagline shown on the splash fallback and onboarding screens.
  String get appTaglineEn;
  String get appTaglineAr;

  // ── Brand colors ───────────────────────────────────────────────────────────
  /// Main accent — buttons, highlights, active borders.
  Color get primaryColor;

  /// Lighter accent — text links, secondary highlights.
  Color get secondaryColor;

  /// Deep scaffold / page background.
  Color get backgroundColor;

  /// Elevated card / surface background.
  Color get surfaceColor;

  // ── Assets ─────────────────────────────────────────────────────────────────
  /// Horizontal logo (used in headers and onboarding).
  String get logoWidePath;

  /// Square logo (used in compact contexts and the splash fallback).
  String get logoSquarePath;

  /// Full-screen video played once on launch.
  /// Leave empty ('') to skip the video and use the static fallback.
  String get splashVideoPath;

  // ── Support / legal links ──────────────────────────────────────────────────
  /// Support contact address shown in the customer-service screen.
  String get supportEmail;

  /// Privacy policy URL.  Empty string → use the embedded policy_screen.dart.
  String get privacyUrl;

  /// Terms of service URL.  Empty string → use the embedded policy_screen.dart.
  String get termsUrl;

  /// Fallback APK download URL used when app_update_service returns no URL.
  String get updateUrl;

  // ── Coins ──────────────────────────────────────────────────────────────────
  /// Human-readable name for the in-app currency (shown in wallet UI).
  String get coinsLabel;
}

// ─────────────────────────────────────────────────────────────────────────────
// SroodLiveConfig — default production values.
// These match the current Srood Live app exactly; nothing changes at runtime.
// ─────────────────────────────────────────────────────────────────────────────

class SroodLiveConfig implements AppConfig {
  const SroodLiveConfig();

  // Identity
  @override String get appName        => 'srood_live';
  @override String get appDisplayName => 'SrOOd Live';
  @override String get appTaglineEn   => 'Voice rooms. Gifts. Prestige.';
  @override String get appTaglineAr   => 'غرف صوتية. هدايا. مكانة.';

  // Brand colors — kept in sync with SroodColors constants.
  @override Color get primaryColor    => const Color(0xFFD6A84F); // SroodColors.gold
  @override Color get secondaryColor  => const Color(0xFFF2D07A); // SroodColors.goldLight
  @override Color get backgroundColor => const Color(0xFF05030A); // SroodColors.abyss
  @override Color get surfaceColor    => const Color(0xFF171125); // SroodColors.card

  // Assets
  @override String get logoWidePath   => 'assets/branding/srood_live_logo_wide.png';
  @override String get logoSquarePath => 'assets/branding/srood_live_logo_square.png';
  @override String get splashVideoPath => 'assets/videos/srood_splash.mp4';

  // Support / legal
  @override String get supportEmail   => 'support@sroodlive.com';
  @override String get privacyUrl     => ''; // embedded in policy_screen.dart
  @override String get termsUrl       => ''; // embedded in policy_screen.dart
  @override String get updateUrl      =>
      'https://example.com/srood-live-latest.apk';

  // Coins
  @override String get coinsLabel     => 'Srood Coins';
}
