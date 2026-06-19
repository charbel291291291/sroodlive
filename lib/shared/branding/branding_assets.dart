import '../../core/config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BrandingAssets — delegates to AppConfig.instance so all asset paths come
// from the active branding config.
//
// Existing callers (BrandingAssets.logoWide, etc.) continue to work unchanged.
// TODO(white-label): No changes needed here — just swap AppConfig.instance.
// ─────────────────────────────────────────────────────────────────────────────

class BrandingAssets {
  const BrandingAssets._();

  static String get logoWide   => AppConfig.instance.logoWidePath;
  static String get logoSquare => AppConfig.instance.logoSquarePath;
  static String get splashVideo => AppConfig.instance.splashVideoPath;

  // The owl mark and app icon are Srood-specific assets that don't yet have
  // a generic AppConfig slot.
  // TODO(white-label): Add owlMarkPath / appIconPath to AppConfig if needed.
  static const owlMark = 'assets/branding/srood_live_owl_mark.png';
  static const appIcon = 'assets/branding/srood_live_app_icon.png';
}
