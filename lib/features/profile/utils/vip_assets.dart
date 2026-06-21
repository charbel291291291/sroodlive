class VipAssets {
  static int normalizeLevel(int? level) {
    if (level == null || level <= 0) return 0;
    if (level > 9) return 9;
    return level;
  }

  static bool hasVip(int? level) => normalizeLevel(level) > 0;

  static String hero(int? level) {
    final safeLevel = normalizeLevel(level);
    return 'assets/vip/vip$safeLevel/hero.webp';
  }

  static String badge(int? level) {
    final safeLevel = normalizeLevel(level);
    return 'assets/vip/vip$safeLevel/badge.webp';
  }

  static String frame(int? level) {
    final safeLevel = normalizeLevel(level);
    return 'assets/vip/vip$safeLevel/frame.webp';
  }
}
