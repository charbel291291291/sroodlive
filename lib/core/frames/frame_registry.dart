/// Frame System v2 — central registry and legacy compatibility layer.
///
/// One place that answers: "given the raw frame key stored on a profile,
/// what frame is it, and how should it render?". Built-in defaults cover
/// every code that exists in production today, so the registry works fully
/// offline; `hydrate` merges live `frame_catalog` rows over the defaults.
///
/// Display-only. Entitlement enforcement lives server-side
/// (`select_my_frame_v2` and friends); the checks here only mirror the
/// server so a client never *renders* a frame the server would reject.
library;

import '../../shared/widgets/avatar_with_frame.dart' show avatarFrameAssetPaths;
import '../vip/vip_spec.dart' show vipFrameAssetPath;
import 'srood_frame.dart';

/// How a resolved frame should be drawn by [SroodAvatarFrame].
enum FrameRenderMode {
  /// No frame (none selected, unknown code, or entitlement stripped).
  none,

  /// Delegate to the legacy `AvatarWithFrame` pipeline — pixel-identical to
  /// today's rendering for every pre-v2 code.
  legacyDelegate,

  /// Bundled asset overlay (path in [FrameRenderSpec.assetPath]).
  bundledAsset,

  /// Network image overlay (URL in [FrameRenderSpec.assetUrl]).
  networkAsset,

  /// v2 placeholder painter for the VIP tier in [FrameRenderSpec.vipTier].
  tierPainter,
}

class FrameRenderSpec {
  const FrameRenderSpec({
    required this.mode,
    this.frame,
    this.legacyKey,
    this.assetPath,
    this.assetUrl,
    this.vipTier = 0,
    this.animated = false,
  });

  static const none = FrameRenderSpec(mode: FrameRenderMode.none);

  final FrameRenderMode mode;
  final SroodFrame? frame;

  /// Canonical key passed to the legacy pipeline for [FrameRenderMode.legacyDelegate].
  final String? legacyKey;
  final String? assetPath;
  final String? assetUrl;
  final int vipTier;

  /// Whether this frame carries an animated treatment (subject to the
  /// widget's reduced-motion / opt-in gates).
  final bool animated;
}

class FrameRegistry {
  FrameRegistry._() {
    _byCode = {for (final f in _builtIns) f.code: f};
  }

  static final FrameRegistry instance = FrameRegistry._();

  late Map<String, SroodFrame> _byCode;

  /// Legacy key → canonical v2 code. Every alias here must also exist in
  /// `frame_legacy_map` server-side (see 20261112000000_frame_system_v2.sql).
  static const Map<String, String> legacyAliases = {
    // Pre-v2 named VIP frames (client tier gates in VipFeatures.canUseVipFrame).
    'vip_bronze_star': 'vip_1',
    'vip_silver_flame': 'vip_2',
    'vip_gold_crown': 'vip_3',
    'vip_platinum_diamond': 'vip_4',
    'vip_royal_king': 'vip_5',
    'vip_elite': 'vip_6',
    'vip_mythic': 'vip_7',
    'vip_emperor': 'vip_8',
    'vip_celestial': 'vip_9',
    // Painter aliases that appeared in old data.
    'ruby_royal': 'luxury_ruby_royal',
    'ruby_royal_dark': 'luxury_ruby_royal_dark',
  };

  /// Canonical code for [raw] (resolves aliases; unknown codes pass through).
  String canonicalCode(String raw) => legacyAliases[raw.trim()] ?? raw.trim();

  /// Catalog entry for [rawCode], or null when unknown.
  SroodFrame? resolve(String? rawCode) {
    if (rawCode == null || rawCode.trim().isEmpty) return null;
    return _byCode[canonicalCode(rawCode)];
  }

  /// The implicit VIP tier frame for [level] (1–9), or null.
  SroodFrame? vipTierFrame(int level) {
    if (level < 1) return null;
    return _byCode['vip_${level.clamp(1, 9)}'];
  }

  /// All known frames, sorted for pickers.
  List<SroodFrame> all() {
    final list = _byCode.values.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  /// Merge live catalog rows over the built-in defaults. Unknown codes from
  /// the server are added; built-ins keep working when the fetch fails.
  void hydrate(Iterable<SroodFrame> rows) {
    for (final row in rows) {
      _byCode[row.code] = row;
    }
  }

  /// Drops everything [hydrate] added and restores the built-in catalog.
  ///
  /// [hydrate] merges, so without this a frame an admin just deactivated or
  /// renamed would linger in `_byCode` for the rest of the process. The catalog
  /// sync service calls this before each fresh load.
  void resetToBuiltIns() {
    _byCode = {for (final f in _builtIns) f.code: f};
  }

  /// Resolves what to draw for a stored [rawCode] + the viewer-independent
  /// [effectiveVipLevel] of the avatar's owner.
  ///
  /// Fallback chain (mirrors current production behavior):
  /// 1. explicit code → its frame, unless it is a VIP frame above the
  ///    owner's effective level (expired VIP ⇒ stripped, like today);
  /// 2. no/unknown code + active VIP → implicit `vip_N` tier frame;
  /// 3. otherwise → no frame.
  FrameRenderSpec resolveRender({
    String? rawCode,
    int effectiveVipLevel = 0,
    DateTime? now,
    bool preferV2TierArt = false,
  }) {
    final at = now ?? DateTime.now();
    final code = rawCode?.trim();

    SroodFrame? frame;
    if (code != null && code.isNotEmpty) {
      frame = resolve(code);
      if (frame == null) {
        // Unknown legacy id: keep legacy pipeline behavior (it renders its
        // own safe fallback ring for unknown keys) instead of guessing.
        return FrameRenderSpec(
          mode: FrameRenderMode.legacyDelegate,
          legacyKey: code,
        );
      }
      // Entitlement mirror: VIP frames require the matching tier.
      final requiredVip =
          frame.requiredVipLevel ??
          (frame.category == SroodFrameCategory.vip ? frame.vipLevel : null);
      if (requiredVip != null && effectiveVipLevel < requiredVip) {
        frame = null;
      } else if (!frame.isAvailableAt(at)) {
        frame = null;
      }
    }

    // Implicit VIP tier frame when nothing (valid) is selected.
    frame ??= effectiveVipLevel > 0 ? vipTierFrame(effectiveVipLevel) : null;
    if (frame == null) return FrameRenderSpec.none;

    return specForFrame(frame, preferV2TierArt: preferV2TierArt);
  }

  /// How [frame] draws, skipping code resolution and the entitlement mirror.
  ///
  /// Used by the admin frame editor's live preview so it takes the exact same
  /// branch a real profile takes — an admin previewing an unsaved frame has no
  /// catalog row to resolve, and must not be shown a different renderer than
  /// users will get.
  FrameRenderSpec specForFrame(
    SroodFrame frame, {
    bool preferV2TierArt = false,
  }) {
    // v2 tier placeholder art (opt-in until final tier assets land).
    if (preferV2TierArt &&
        frame.category == SroodFrameCategory.vip &&
        (frame.vipLevel ?? 0) > 0) {
      return FrameRenderSpec(
        mode: FrameRenderMode.tierPainter,
        frame: frame,
        vipTier: frame.vipLevel!,
        animated: frame.isAnimated,
      );
    }

    switch (frame.assetType) {
      case SroodFrameAssetType.network:
        if (frame.assetUrl != null && frame.assetUrl!.isNotEmpty) {
          return FrameRenderSpec(
            mode: FrameRenderMode.networkAsset,
            frame: frame,
            assetUrl: frame.assetUrl,
            animated: frame.isAnimated,
          );
        }
        return _bundledOrLegacy(frame);
      case SroodFrameAssetType.bundled:
      case SroodFrameAssetType.painter:
        return _bundledOrLegacy(frame);
    }
  }

  FrameRenderSpec _bundledOrLegacy(SroodFrame frame) {
    // Every built-in code has a proven legacy rendering path; delegating
    // keeps v2 pixel-identical for existing frames until cleanup approval.
    final canonical = frame.code;
    final bundled = _bundledAssetPath(canonical);
    if (bundled == null) {
      return FrameRenderSpec(
        mode: FrameRenderMode.legacyDelegate,
        frame: frame,
        legacyKey: canonical,
        animated: frame.isAnimated,
      );
    }
    return FrameRenderSpec(
      mode: FrameRenderMode.legacyDelegate,
      frame: frame,
      legacyKey: canonical,
      assetPath: bundled,
      animated: frame.isAnimated,
    );
  }

  static String? _bundledAssetPath(String code) {
    final custom = avatarFrameAssetPaths[code];
    if (custom != null) return custom;
    if (code.startsWith('vip_')) {
      final level = int.tryParse(code.substring(4));
      if (level != null) return vipFrameAssetPath(level);
    }
    return null;
  }

  // ── Built-in defaults ─────────────────────────────────────────────────────
  // Complete offline catalog covering every production code (audit table,
  // docs/frames_v2/PHASE1_AUDIT.md §8). DB rows hydrate over these.

  static final List<SroodFrame> _builtIns = [
    // VIP tiers 1–9 (implicit entitlement by VIP level).
    for (var level = 1; level <= 9; level++)
      SroodFrame(
        id: 'vip_$level',
        code: 'vip_$level',
        name: _vipNames[level - 1],
        localizedNames: {'ar': 'إطار VIP $level'},
        category: SroodFrameCategory.vip,
        vipLevel: level,
        rarity: level >= 8
            ? SroodFrameRarity.mythic
            : level >= 6
            ? SroodFrameRarity.legendary
            : level >= 4
            ? SroodFrameRarity.epic
            : SroodFrameRarity.rare,
        assetType: SroodFrameAssetType.bundled,
        assetUrl: vipFrameAssetPath(level),
        isAnimated: level >= 6,
        sortOrder: 200 + level * 10,
        unlockType: SroodFrameUnlock.vipLevel,
        requiredVipLevel: level,
      ),

    // Free painter frames.
    const SroodFrame(
      id: 'normal_silver_ring',
      code: 'normal_silver_ring',
      name: 'Silver Ring',
      category: SroodFrameCategory.normal,
      sortOrder: 10,
    ),
    const SroodFrame(
      id: 'normal_blue_glow',
      code: 'normal_blue_glow',
      name: 'Blue Glow',
      category: SroodFrameCategory.normal,
      sortOrder: 20,
    ),
    const SroodFrame(
      id: 'normal_soft_gold',
      code: 'normal_soft_gold',
      name: 'Soft Gold',
      category: SroodFrameCategory.normal,
      sortOrder: 30,
    ),

    // Luxury painter/PNG frames.
    const SroodFrame(
      id: 'luxury_royal_gold',
      code: 'luxury_royal_gold',
      name: 'Royal Gold',
      category: SroodFrameCategory.luxury,
      rarity: SroodFrameRarity.rare,
      sortOrder: 110,
    ),
    const SroodFrame(
      id: 'luxury_diamond_purple',
      code: 'luxury_diamond_purple',
      name: 'Diamond Purple',
      category: SroodFrameCategory.luxury,
      rarity: SroodFrameRarity.rare,
      isAnimated: true,
      sortOrder: 120,
    ),
    const SroodFrame(
      id: 'luxury_black_gold_crown',
      code: 'luxury_black_gold_crown',
      name: 'Black Gold Crown',
      category: SroodFrameCategory.luxury,
      rarity: SroodFrameRarity.epic,
      isAnimated: true,
      sortOrder: 130,
    ),
    const SroodFrame(
      id: 'luxury_ruby_royal',
      code: 'luxury_ruby_royal',
      name: 'Ruby Royal Frame',
      category: SroodFrameCategory.luxury,
      rarity: SroodFrameRarity.epic,
      assetType: SroodFrameAssetType.bundled,
      assetUrl: 'assets/avatar_frames/luxury_ruby_royal.png',
      sortOrder: 140,
    ),
    const SroodFrame(
      id: 'luxury_ruby_royal_dark',
      code: 'luxury_ruby_royal_dark',
      name: 'Ruby Royal Dark Frame',
      category: SroodFrameCategory.luxury,
      rarity: SroodFrameRarity.epic,
      assetType: SroodFrameAssetType.bundled,
      assetUrl: 'assets/avatar_frames/luxury_ruby_royal_dark.png',
      sortOrder: 150,
    ),
    const SroodFrame(
      id: 'custom_luxury_gold',
      code: 'custom_luxury_gold',
      name: 'Luxury Gold Frame',
      category: SroodFrameCategory.luxury,
      rarity: SroodFrameRarity.epic,
      assetType: SroodFrameAssetType.bundled,
      assetUrl: 'assets/avatar_frames/custom/luxury_gold_frame_transparent.png',
      isAnimated: true,
      sortOrder: 160,
    ),
    const SroodFrame(
      id: 'custom_luxury_diamond',
      code: 'custom_luxury_diamond',
      name: 'Luxury Diamond Frame',
      category: SroodFrameCategory.luxury,
      rarity: SroodFrameRarity.legendary,
      assetType: SroodFrameAssetType.bundled,
      assetUrl:
          'assets/avatar_frames/custom/luxury_diamond_frame_transparent.png',
      isAnimated: true,
      sortOrder: 170,
    ),

    // Role frames — server-enforced from v2 on (see migration).
    const SroodFrame(
      id: 'custom_srood_live',
      code: 'custom_srood_live',
      name: 'SrOOd Live Frame',
      category: SroodFrameCategory.specialEdition,
      rarity: SroodFrameRarity.legendary,
      assetType: SroodFrameAssetType.bundled,
      assetUrl: 'assets/avatar_frames/custom/srood_live_frame_final.png',
      isAnimated: true,
      sortOrder: 300,
      unlockType: SroodFrameUnlock.adminGrant,
    ),
    const SroodFrame(
      id: 'custom_admin',
      code: 'custom_admin',
      name: 'Admin Frame',
      category: SroodFrameCategory.admin,
      rarity: SroodFrameRarity.legendary,
      assetType: SroodFrameAssetType.bundled,
      assetUrl: 'assets/avatar_frames/custom/admin_frame_transparent.png',
      isAnimated: true,
      sortOrder: 310,
      unlockType: SroodFrameUnlock.role,
      requiredRole: 'admin',
    ),
    const SroodFrame(
      id: 'custom_super_admin',
      code: 'custom_super_admin',
      name: 'Super Admin Frame',
      category: SroodFrameCategory.superAdmin,
      rarity: SroodFrameRarity.mythic,
      assetType: SroodFrameAssetType.bundled,
      assetUrl: 'assets/avatar_frames/custom/super_admin_frame_transparent.png',
      isAnimated: true,
      sortOrder: 320,
      unlockType: SroodFrameUnlock.role,
      requiredRole: 'super_admin',
    ),
  ];

  static const List<String> _vipNames = [
    'Bronze Sentinel', // VIP 1 — clean bronze
    'Silver Meridian', // VIP 2 — polished silver
    'Royal Aurum', // VIP 3 — royal gold
    'Emerald Court', // VIP 4 — emerald royal
    'Ruby Sovereign', // VIP 5 — ruby prestige
    'Sapphire Regalia', // VIP 6 — sapphire, animated accents
    'Imperial Amethyst', // VIP 7 — imperial purple, particles
    'Black Diamond', // VIP 8 — black diamond energy
    'Srood Mythic', // VIP 9 — gold/violet/black Srood identity
  ];
}
