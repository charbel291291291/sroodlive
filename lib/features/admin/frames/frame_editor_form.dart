/// Frame Management v2 — editor form logic.
///
/// Every rule the frame editor enforces lives here rather than in a widget, so
/// it is unit-testable without a Flutter binding: code generation, sort-order
/// allocation, VIP synchronization, validation, and the `SroodFrame` payload
/// the admin RPCs receive.
///
/// The one invariant worth stating up front: there is a **single** `vipTier`
/// field. Both `frame_catalog.vip_level` and `frame_catalog.required_vip_level`
/// are derived from it, so the two dropdowns the old screen had — which could
/// drift apart into contradictory rows — cannot exist by construction.
library;

import '../../../core/frames/srood_frame.dart';

/// Roles a frame may require. These are the only four values either role table
/// accepts today: `20260615230000_admin_role_system_rebuild.sql` narrowed both
/// `app_user_roles_role_check` and `admin_users_role_check` to
/// `('o_super_admin','p_super_admin','super_admin','admin')`, superseding the
/// ten-value list originally introduced by
/// `20260605111935_step_12_full_admin_panel_roles.sql`.
///
/// Offering anything else would produce a frame nobody can ever unlock, because
/// no row in either table can hold the value. The same goes for
/// `agency_owner` / `recharge_owner` / `room_owner` / `host`, which are frame
/// *categories* rather than roles.
///
/// Ordered widest authority first, matching the hierarchy encoded in
/// `public.has_app_role(text)` and in
/// `public.frames_v2_user_has_admin_role(uuid, text)`
/// (`20261202000000_frames_v2_admin_role_compatibility.sql`).
const List<String> kFrameRequiredRoles = <String>[
  'o_super_admin',
  'p_super_admin',
  'super_admin',
  'admin',
];

/// `frame_catalog.vip_level` is constrained to `between 1 and 9`.
const int kFrameMinVipLevel = 1;
const int kFrameMaxVipLevel = 9;

/// Gap left between generated sort orders so an admin can hand-place a frame
/// between two existing ones without renumbering the catalog.
const int kFrameSortOrderStep = 10;

/// `frame_catalog.code` CHECK: `code ~ '^[a-z0-9_]+$'`.
final RegExp kFrameCodePattern = RegExp(r'^[a-z0-9_]+$');

/// Which control an issue belongs to, so the dialog can put the message next to
/// the offending field instead of in a generic banner.
enum FrameEditorField {
  name,
  code,
  category,
  unlockType,
  vipLevel,
  requiredRole,
  artwork,
  sortOrder,
  schedule,
}

class FrameEditorIssue {
  const FrameEditorIssue(this.field, this.message);

  final FrameEditorField field;

  /// Admin-facing English, safe to render verbatim.
  final String message;

  @override
  String toString() => '${field.name}: $message';

  @override
  bool operator ==(Object other) =>
      other is FrameEditorIssue &&
      other.field == field &&
      other.message == message;

  @override
  int get hashCode => Object.hash(field, message);
}

/// Slugifies a display name into the `^[a-z0-9_]+$` shape the DB requires.
///
/// Non-Latin names (Arabic, emoji) reduce to nothing, so callers get an empty
/// string back and [generateFrameCode] substitutes a stable fallback.
String slugifyFrameName(String name) {
  final buffer = StringBuffer();
  var lastWasUnderscore = true; // suppresses a leading underscore
  for (final rune in name.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final isWordChar =
        (rune >= 0x61 && rune <= 0x7A) || (rune >= 0x30 && rune <= 0x39);
    if (isWordChar) {
      buffer.write(char);
      lastWasUnderscore = false;
    } else if (!lastWasUnderscore) {
      buffer.write('_');
      lastWasUnderscore = true;
    }
  }
  var slug = buffer.toString();
  while (slug.endsWith('_')) {
    slug = slug.substring(0, slug.length - 1);
  }
  return slug;
}

/// Derives a unique frame code from the display name.
///
/// VIP frames are prefixed with their tier, which is the convention the 29
/// existing rows already follow: `Celestial Crown` at VIP 4 → `vip4_celestial_crown`.
/// Collisions with [existingCodes] are resolved with a `_2`, `_3`, … suffix
/// rather than by overwriting.
String generateFrameCode({
  required String name,
  SroodFrameCategory category = SroodFrameCategory.custom,
  int? vipLevel,
  Iterable<String> existingCodes = const <String>[],
}) {
  var base = slugifyFrameName(name);
  if (base.isEmpty) base = 'frame';

  final isVip = category == SroodFrameCategory.vip && vipLevel != null;
  if (isVip && !base.startsWith('vip')) {
    base = 'vip${vipLevel}_$base';
  }

  final taken = existingCodes.toSet();
  if (!taken.contains(base)) return base;

  var suffix = 2;
  while (taken.contains('${base}_$suffix')) {
    suffix++;
  }
  return '${base}_$suffix';
}

/// Next sort order for a new frame in [category]: the highest sort order among
/// same-category frames plus [kFrameSortOrderStep]. An empty category starts at
/// the step so 0 stays available for manual placement.
int nextSortOrder(Iterable<SroodFrame> frames, SroodFrameCategory category) {
  var highest = 0;
  var found = false;
  for (final frame in frames) {
    if (frame.category != category) continue;
    if (!found || frame.sortOrder > highest) highest = frame.sortOrder;
    found = true;
  }
  return highest + kFrameSortOrderStep;
}

/// Infers the asset type from an artwork URL, so an admin never picks it.
SroodFrameAssetType assetTypeForUrl(String? url) {
  final value = url?.trim() ?? '';
  if (value.isEmpty) return SroodFrameAssetType.painter;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return SroodFrameAssetType.network;
  }
  if (value.startsWith('assets/')) return SroodFrameAssetType.bundled;
  return SroodFrameAssetType.network;
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Mutable editor state. The dialog mutates fields inside `setState`; every
/// derived rule is a getter so nothing can be left stale.
class FrameEditorState {
  FrameEditorState({
    required this.isNew,
    this.original,
    this.code = '',
    this.name = '',
    this.arabicName = '',
    this.category = SroodFrameCategory.luxury,
    this.rarity = SroodFrameRarity.common,
    this.unlockType = SroodFrameUnlock.free,
    this.vipTier,
    this.requiredRole,
    this.unlockValue,
    this.requiredLevel,
    this.assetUrl,
    this.thumbnailUrl,
    this.animationUrl,
    this.assetType = SroodFrameAssetType.painter,
    this.isAnimated = false,
    this.isActive = true,
    this.sortOrder = 0,
    this.startsAt,
    this.expiresAt,
    this.legacyFrameKey,
    this.codeIsManual = false,
    Set<String>? existingCodes,
  }) : existingCodes = existingCodes ?? <String>{};

  /// A blank editor for a brand new frame, pre-seeded with the next sort order
  /// for [category] and every code already in the catalog.
  factory FrameEditorState.blank({
    required Iterable<SroodFrame> catalog,
    SroodFrameCategory category = SroodFrameCategory.luxury,
  }) {
    return FrameEditorState(
      isNew: true,
      category: category,
      sortOrder: nextSortOrder(catalog, category),
      existingCodes: catalog.map((frame) => frame.code).toSet(),
    );
  }

  /// Editing an existing catalog row. [original] is retained so [toFrame] can
  /// carry through columns the editor does not surface.
  factory FrameEditorState.fromFrame(
    SroodFrame frame, {
    Iterable<SroodFrame> catalog = const <SroodFrame>[],
  }) {
    return FrameEditorState(
      isNew: false,
      original: frame,
      code: frame.code,
      name: frame.name,
      arabicName: frame.localizedNames['ar'] ?? '',
      category: frame.category,
      rarity: frame.rarity,
      unlockType: frame.unlockType,
      vipTier: frame.requiredVipLevel ?? frame.vipLevel,
      requiredRole: frame.requiredRole,
      unlockValue: frame.unlockValue,
      requiredLevel: frame.requiredLevel,
      assetUrl: frame.assetUrl,
      thumbnailUrl: frame.thumbnailUrl,
      animationUrl: frame.animationUrl,
      assetType: frame.assetType,
      isAnimated: frame.isAnimated,
      isActive: frame.isActive,
      sortOrder: frame.sortOrder,
      startsAt: frame.startsAt,
      expiresAt: frame.expiresAt,
      legacyFrameKey: frame.legacyFrameKey,
      codeIsManual: true,
      existingCodes: catalog
          .map((entry) => entry.code)
          .where((entry) => entry != frame.code)
          .toSet(),
    );
  }

  /// Whether saving creates a row (`admin_create_frame_v2`) or updates one
  /// (`admin_upsert_frame_v2`).
  final bool isNew;

  /// The row being edited, or null for a new frame. Never mutated.
  final SroodFrame? original;

  /// Codes already taken by *other* frames, for duplicate detection.
  final Set<String> existingCodes;

  String code;
  String name;
  String arabicName;
  SroodFrameCategory category;
  SroodFrameRarity rarity;
  SroodFrameUnlock unlockType;

  /// The single source of truth for VIP. Feeds both `vip_level` and
  /// `required_vip_level`, which is why they can never disagree.
  int? vipTier;

  String? requiredRole;
  String? unlockValue;
  int? requiredLevel;
  String? assetUrl;
  String? thumbnailUrl;
  String? animationUrl;
  SroodFrameAssetType assetType;
  bool isAnimated;
  bool isActive;
  int sortOrder;
  DateTime? startsAt;
  DateTime? expiresAt;

  /// Read-only: `admin_upsert_frame_v2` has no `p_legacy_frame_key`.
  final String? legacyFrameKey;

  /// Set once the admin edits the code by hand, after which renaming the frame
  /// stops regenerating it.
  bool codeIsManual;

  /// Whether a VIP level is part of this frame's configuration at all.
  bool get usesVipLevel =>
      unlockType == SroodFrameUnlock.vipLevel ||
      category == SroodFrameCategory.vip;

  bool get usesRequiredRole => unlockType == SroodFrameUnlock.role;

  /// The VIP level actually written to the database — null unless VIP applies,
  /// which is what stops a leftover tier from being persisted.
  int? get effectiveVipLevel => usesVipLevel ? vipTier : null;

  String? get effectiveRequiredRole =>
      usesRequiredRole ? _trimToNull(requiredRole) : null;

  /// Whether clearing VIP would discard something the admin chose, in which
  /// case the dialog confirms before switching away.
  bool get hasMeaningfulVipValue => vipTier != null;

  bool get hasMeaningfulRoleValue => _trimToNull(requiredRole) != null;

  /// Regenerates [code] from the current name unless the admin took it over.
  /// Returns the code in effect afterwards.
  String syncCodeFromName({bool force = false}) {
    if (codeIsManual && !force) return code;
    code = generateFrameCode(
      name: name,
      category: category,
      vipLevel: effectiveVipLevel,
      existingCodes: existingCodes,
    );
    return code;
  }

  /// Applies the artwork produced by an upload: URL, asset type, animation
  /// flag, and the animated variant column all follow from the file itself.
  void applyArtwork({required String url, required bool animated}) {
    assetUrl = url;
    assetType = assetTypeForUrl(url);
    isAnimated = animated;
    animationUrl = animated ? url : null;
  }

  void clearArtwork() {
    assetUrl = null;
    animationUrl = null;
    thumbnailUrl = null;
    assetType = SroodFrameAssetType.painter;
    isAnimated = false;
  }

  List<FrameEditorIssue> validate() {
    final issues = <FrameEditorIssue>[];

    if (_trimToNull(name) == null) {
      issues.add(
        const FrameEditorIssue(FrameEditorField.name, 'Enter a frame name.'),
      );
    }

    final trimmedCode = code.trim();
    if (trimmedCode.isEmpty) {
      issues.add(
        const FrameEditorIssue(
          FrameEditorField.code,
          'A frame code is required. Open Advanced to set one.',
        ),
      );
    } else if (!kFrameCodePattern.hasMatch(trimmedCode)) {
      issues.add(
        const FrameEditorIssue(
          FrameEditorField.code,
          'Frame codes may use lowercase letters, numbers and underscores only.',
        ),
      );
    } else if (existingCodes.contains(trimmedCode)) {
      issues.add(
        const FrameEditorIssue(
          FrameEditorField.code,
          'That frame code is already used by another frame.',
        ),
      );
    }

    if (usesVipLevel && effectiveVipLevel == null) {
      issues.add(
        FrameEditorIssue(
          FrameEditorField.vipLevel,
          category == SroodFrameCategory.vip
              ? 'A VIP frame needs a VIP level.'
              : 'A VIP-unlocked frame needs a VIP level.',
        ),
      );
    }
    if (vipTier != null &&
        (vipTier! < kFrameMinVipLevel || vipTier! > kFrameMaxVipLevel)) {
      issues.add(
        const FrameEditorIssue(
          FrameEditorField.vipLevel,
          'VIP level must be between 1 and 9.',
        ),
      );
    }
    if (!usesVipLevel && vipTier != null) {
      issues.add(
        const FrameEditorIssue(
          FrameEditorField.vipLevel,
          'This unlock method does not use a VIP level. Clear it first.',
        ),
      );
    }

    if (usesRequiredRole && effectiveRequiredRole == null) {
      issues.add(
        const FrameEditorIssue(
          FrameEditorField.requiredRole,
          'A role-unlocked frame needs a required role.',
        ),
      );
    }
    final role = _trimToNull(requiredRole);
    if (usesRequiredRole &&
        role != null &&
        !kFrameRequiredRoles.contains(role)) {
      issues.add(
        FrameEditorIssue(
          FrameEditorField.requiredRole,
          '"$role" is not a role this app grants. Pick one from the list.',
        ),
      );
    }

    if (assetType != SroodFrameAssetType.painter &&
        _trimToNull(assetUrl) == null) {
      issues.add(
        const FrameEditorIssue(
          FrameEditorField.artwork,
          'Upload artwork, or leave the asset type as the painter placeholder.',
        ),
      );
    }

    if (sortOrder < 0) {
      issues.add(
        const FrameEditorIssue(
          FrameEditorField.sortOrder,
          'Sort order cannot be negative.',
        ),
      );
    }

    if (startsAt != null &&
        expiresAt != null &&
        !expiresAt!.isAfter(startsAt!)) {
      issues.add(
        const FrameEditorIssue(
          FrameEditorField.schedule,
          'The expiry date must be after the start date.',
        ),
      );
    }

    return issues;
  }

  bool get isValid => validate().isEmpty;

  /// The row to send to the admin RPC.
  ///
  /// For an edit this starts from [original] and overrides only what the editor
  /// owns, so columns the form never shows survive the round trip. The old
  /// screen rebuilt `SroodFrame` from scratch and silently nulled
  /// `thumbnail_url`, `animation_url`, `unlock_value` and `required_level` on
  /// every save.
  SroodFrame toFrame() {
    final localizedNames = <String, String>{
      ...?original?.localizedNames,
      if (_trimToNull(arabicName) != null) 'ar': arabicName.trim(),
    };
    if (_trimToNull(arabicName) == null) localizedNames.remove('ar');

    final base =
        original ??
        SroodFrame(id: code.trim(), code: code.trim(), name: name.trim());

    return base.copyWith(
      id: base.id.isEmpty ? code.trim() : base.id,
      code: code.trim(),
      name: name.trim(),
      localizedNames: localizedNames,
      category: category,
      vipLevel: effectiveVipLevel,
      rarity: rarity,
      assetType: assetType,
      assetUrl: _trimToNull(assetUrl),
      thumbnailUrl: _trimToNull(thumbnailUrl),
      animationUrl: _trimToNull(animationUrl),
      isAnimated: isAnimated,
      isActive: isActive,
      sortOrder: sortOrder,
      unlockType: unlockType,
      unlockValue: _trimToNull(unlockValue),
      requiredRole: effectiveRequiredRole,
      requiredLevel: requiredLevel,
      // Both VIP columns come from the one tier field.
      requiredVipLevel: effectiveVipLevel,
      startsAt: startsAt,
      expiresAt: expiresAt,
    );
  }
}

/// Editor state for a copy of [source]. The source row is never written: the
/// copy is a fresh create that only exists once the admin presses Save.
///
/// Artwork is cleared by default — a duplicate almost always gets new art, and
/// sharing one storage object between two catalog rows would make "replace
/// artwork" on one silently change the other.
FrameEditorState duplicateFrom(
  SroodFrame source, {
  required Iterable<SroodFrame> catalog,
  bool keepArtwork = false,
}) {
  final existing = catalog.map((frame) => frame.code).toSet();
  final state = FrameEditorState(
    isNew: true,
    code: generateFrameCode(
      name: '${source.name} copy',
      category: source.category,
      vipLevel: source.category == SroodFrameCategory.vip
          ? (source.requiredVipLevel ?? source.vipLevel)
          : null,
      existingCodes: existing,
    ),
    name: '${source.name} Copy',
    arabicName: source.localizedNames['ar'] ?? '',
    category: source.category,
    rarity: source.rarity,
    unlockType: source.unlockType,
    vipTier: source.requiredVipLevel ?? source.vipLevel,
    requiredRole: source.requiredRole,
    unlockValue: source.unlockValue,
    requiredLevel: source.requiredLevel,
    assetUrl: keepArtwork ? source.assetUrl : null,
    thumbnailUrl: keepArtwork ? source.thumbnailUrl : null,
    animationUrl: keepArtwork ? source.animationUrl : null,
    assetType: keepArtwork ? source.assetType : SroodFrameAssetType.painter,
    isAnimated: keepArtwork && source.isAnimated,
    isActive: source.isActive,
    sortOrder: nextSortOrder(catalog, source.category),
    startsAt: source.startsAt,
    expiresAt: source.expiresAt,
    existingCodes: existing,
  );
  return state;
}
