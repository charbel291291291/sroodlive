/// Frame Management v2 — editor form logic.
///
/// Covers the rules an admin can break in under a minute: code generation and
/// uniqueness, sort-order allocation, VIP synchronization (the old screen's two
/// dropdowns could drift into contradictory rows), role visibility, duplication
/// safety, and the payload regression that silently nulled four columns.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/core/frames/srood_frame.dart';
import 'package:srood_live/features/admin/frames/frame_editor_form.dart';

SroodFrame _frame({
  required String code,
  String name = 'Frame',
  SroodFrameCategory category = SroodFrameCategory.luxury,
  int sortOrder = 0,
  int? vipLevel,
  int? requiredVipLevel,
  SroodFrameUnlock unlockType = SroodFrameUnlock.free,
  String? requiredRole,
  String? assetUrl,
  String? thumbnailUrl,
  String? animationUrl,
  String? unlockValue,
  int? requiredLevel,
  String? legacyFrameKey,
  SroodFrameAssetType assetType = SroodFrameAssetType.painter,
  Map<String, String> localizedNames = const {},
}) {
  return SroodFrame(
    id: 'id-$code',
    code: code,
    name: name,
    category: category,
    sortOrder: sortOrder,
    vipLevel: vipLevel,
    requiredVipLevel: requiredVipLevel,
    unlockType: unlockType,
    requiredRole: requiredRole,
    assetType: assetType,
    assetUrl: assetUrl,
    thumbnailUrl: thumbnailUrl,
    animationUrl: animationUrl,
    unlockValue: unlockValue,
    requiredLevel: requiredLevel,
    legacyFrameKey: legacyFrameKey,
    localizedNames: localizedNames,
  );
}

void main() {
  group('generateFrameCode', () {
    test('the documented case: Celestial Crown at VIP 4', () {
      expect(
        generateFrameCode(
          name: 'Celestial Crown',
          category: SroodFrameCategory.vip,
          vipLevel: 4,
        ),
        'vip4_celestial_crown',
      );
    });

    test('no VIP prefix outside the vip category', () {
      expect(
        generateFrameCode(
          name: 'Celestial Crown',
          category: SroodFrameCategory.luxury,
          vipLevel: 4,
        ),
        'celestial_crown',
      );
    });

    test('does not double-prefix a name that already starts with vip', () {
      expect(
        generateFrameCode(
          name: 'VIP Emperor',
          category: SroodFrameCategory.vip,
          vipLevel: 8,
        ),
        'vip_emperor',
      );
    });

    test(
      'punctuation and repeated separators collapse to single underscores',
      () {
        expect(
          generateFrameCode(name: "  Dragon's   Fire!! (2024) "),
          'dragon_s_fire_2024',
        );
      },
    );

    test('a fully non-Latin name falls back to a stable code', () {
      expect(generateFrameCode(name: 'إطار ملكي'), 'frame');
      expect(generateFrameCode(name: '👑✨'), 'frame');
      expect(generateFrameCode(name: ''), 'frame');
    });

    test('a mixed Arabic/Latin name keeps the Latin part', () {
      expect(generateFrameCode(name: 'إطار Royal'), 'royal');
    });

    test('every generated code satisfies the frame_catalog CHECK', () {
      const names = <String>[
        'Celestial Crown',
        "Dragon's Fire!!",
        'إطار ملكي',
        '👑✨',
        '',
        'VIP 9 — Ultra',
      ];
      for (final name in names) {
        final code = generateFrameCode(
          name: name,
          category: SroodFrameCategory.vip,
          vipLevel: 9,
        );
        expect(
          kFrameCodePattern.hasMatch(code),
          isTrue,
          reason: '"$name" generated "$code", which violates ^[a-z0-9_]+\$',
        );
      }
    });

    test('collisions de-duplicate with _2 then _3 instead of overwriting', () {
      expect(
        generateFrameCode(
          name: 'Celestial Crown',
          existingCodes: const ['celestial_crown'],
        ),
        'celestial_crown_2',
      );
      expect(
        generateFrameCode(
          name: 'Celestial Crown',
          existingCodes: const ['celestial_crown', 'celestial_crown_2'],
        ),
        'celestial_crown_3',
      );
    });

    test('an unused code is returned untouched', () {
      expect(
        generateFrameCode(
          name: 'Celestial Crown',
          existingCodes: const ['something_else'],
        ),
        'celestial_crown',
      );
    });
  });

  group('nextSortOrder', () {
    final catalog = <SroodFrame>[
      _frame(code: 'a', category: SroodFrameCategory.luxury, sortOrder: 10),
      _frame(code: 'b', category: SroodFrameCategory.luxury, sortOrder: 240),
      _frame(code: 'c', category: SroodFrameCategory.luxury, sortOrder: 30),
      _frame(code: 'd', category: SroodFrameCategory.vip, sortOrder: 900),
    ];

    test('is the highest same-category order plus the step', () {
      expect(nextSortOrder(catalog, SroodFrameCategory.luxury), 250);
      expect(nextSortOrder(catalog, SroodFrameCategory.vip), 910);
    });

    test('an empty category starts at the step, leaving 0 free', () {
      expect(nextSortOrder(catalog, SroodFrameCategory.event), 10);
      expect(nextSortOrder(const <SroodFrame>[], SroodFrameCategory.vip), 10);
      expect(kFrameSortOrderStep, 10);
    });

    test('blank() seeds the next order for its category', () {
      final state = FrameEditorState.blank(
        catalog: catalog,
        category: SroodFrameCategory.luxury,
      );
      expect(state.sortOrder, 250);
    });
  });

  group('duplicate code rejection', () {
    test('validate() rejects a code another frame already uses', () {
      final state = FrameEditorState.blank(
        catalog: [_frame(code: 'celestial_crown')],
      );
      state.name = 'Something Else';
      state.code = 'celestial_crown';
      state.codeIsManual = true;

      expect(
        state.validate(),
        contains(
          const FrameEditorIssue(
            FrameEditorField.code,
            'That frame code is already used by another frame.',
          ),
        ),
      );
      expect(state.isValid, isFalse);
    });

    test('editing a frame does not flag its own code as a duplicate', () {
      final existing = _frame(code: 'celestial_crown', name: 'Celestial Crown');
      final state = FrameEditorState.fromFrame(existing, catalog: [existing]);

      expect(state.existingCodes, isNot(contains('celestial_crown')));
      expect(state.validate(), isEmpty);
    });

    test('a code outside the DB CHECK alphabet is rejected', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Celestial Crown';
      state.code = 'Celestial-Crown';
      state.codeIsManual = true;

      expect(
        state.validate().map((issue) => issue.field),
        contains(FrameEditorField.code),
      );
    });

    test('renaming stops regenerating the code once it is manual', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Celestial Crown';
      expect(state.syncCodeFromName(), 'celestial_crown');

      state.codeIsManual = true;
      state.name = 'Renamed Frame';
      expect(state.syncCodeFromName(), 'celestial_crown');
      // ...unless the admin presses Regenerate.
      expect(state.syncCodeFromName(force: true), 'renamed_frame');
    });
  });

  group('VIP synchronization', () {
    FrameEditorState vipState(int? tier, {SroodFrameUnlock? unlock}) {
      final state = FrameEditorState.blank(
        catalog: const <SroodFrame>[],
        category: SroodFrameCategory.vip,
      );
      state.name = 'Celestial Crown';
      state.unlockType = unlock ?? SroodFrameUnlock.vipLevel;
      state.vipTier = tier;
      state.syncCodeFromName();
      return state;
    }

    test('VIP 4 writes 4 to both vip_level and required_vip_level', () {
      final frame = vipState(4).toFrame();
      expect(frame.vipLevel, 4);
      expect(frame.requiredVipLevel, 4);
    });

    test('VIP 7 writes 7 to both columns', () {
      final frame = vipState(7).toFrame();
      expect(frame.vipLevel, 7);
      expect(frame.requiredVipLevel, 7);
    });

    test('the two columns are always equal — one field feeds both', () {
      for (var tier = kFrameMinVipLevel; tier <= kFrameMaxVipLevel; tier++) {
        final frame = vipState(tier).toFrame();
        expect(frame.vipLevel, frame.requiredVipLevel);
        expect(frame.vipLevel, tier);
      }
    });

    test('forbidden: VIP category with no level', () {
      final state = vipState(null, unlock: SroodFrameUnlock.adminGrant);
      expect(state.usesVipLevel, isTrue, reason: 'category vip implies VIP');
      expect(
        state.validate(),
        contains(
          const FrameEditorIssue(
            FrameEditorField.vipLevel,
            'A VIP frame needs a VIP level.',
          ),
        ),
      );
    });

    test('forbidden: vip_level unlock with no level', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Gilded Ring';
      state.syncCodeFromName();
      state.unlockType = SroodFrameUnlock.vipLevel;
      state.vipTier = null;

      expect(
        state.validate(),
        contains(
          const FrameEditorIssue(
            FrameEditorField.vipLevel,
            'A VIP-unlocked frame needs a VIP level.',
          ),
        ),
      );
    });

    test('forbidden: a VIP tier left behind on a non-VIP configuration', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Gilded Ring';
      state.syncCodeFromName();
      state.unlockType = SroodFrameUnlock.free;
      state.vipTier = 4;

      expect(state.usesVipLevel, isFalse);
      expect(
        state.validate(),
        contains(
          const FrameEditorIssue(
            FrameEditorField.vipLevel,
            'This unlock method does not use a VIP level. Clear it first.',
          ),
        ),
      );
    });

    test('forbidden: a VIP level outside the 1–9 CHECK range', () {
      for (final tier in <int>[0, 10, 99]) {
        expect(
          vipState(tier).validate(),
          contains(
            const FrameEditorIssue(
              FrameEditorField.vipLevel,
              'VIP level must be between 1 and 9.',
            ),
          ),
          reason: 'VIP $tier should be rejected',
        );
      }
    });

    test('a cleared tier is never persisted on a non-VIP frame', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Gilded Ring';
      state.syncCodeFromName();
      state.unlockType = SroodFrameUnlock.vipLevel;
      state.vipTier = 4;
      expect(state.hasMeaningfulVipValue, isTrue);

      // What the dialog does after the admin confirms the clear.
      state.unlockType = SroodFrameUnlock.free;
      state.vipTier = null;

      final frame = state.toFrame();
      expect(frame.vipLevel, isNull);
      expect(frame.requiredVipLevel, isNull);
      expect(state.validate(), isEmpty);
    });

    test('effectiveVipLevel is null while VIP does not apply', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.vipTier = 5;
      state.unlockType = SroodFrameUnlock.purchase;
      expect(state.effectiveVipLevel, isNull);

      state.unlockType = SroodFrameUnlock.vipLevel;
      expect(state.effectiveVipLevel, 5);
    });

    test('the VIP code prefix follows the tier', () {
      final state = vipState(4);
      expect(state.code, 'vip4_celestial_crown');
      state.vipTier = 7;
      expect(state.syncCodeFromName(force: true), 'vip7_celestial_crown');
    });
  });

  group('role frames', () {
    test('the role field shows only for a role unlock', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      for (final unlock in SroodFrameUnlock.values) {
        state.unlockType = unlock;
        expect(
          state.usesRequiredRole,
          unlock == SroodFrameUnlock.role,
          reason: 'unlock ${unlock.wire}',
        );
      }
    });

    test('VIP and role controls are mutually exclusive', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.unlockType = SroodFrameUnlock.role;
      expect(state.usesRequiredRole, isTrue);
      expect(state.usesVipLevel, isFalse);

      state.unlockType = SroodFrameUnlock.vipLevel;
      expect(state.usesRequiredRole, isFalse);
      expect(state.usesVipLevel, isTrue);
    });

    test('a role unlock with no role is rejected', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Moderator Halo';
      state.syncCodeFromName();
      state.unlockType = SroodFrameUnlock.role;
      state.requiredRole = '   ';

      expect(
        state.validate(),
        contains(
          const FrameEditorIssue(
            FrameEditorField.requiredRole,
            'A role-unlocked frame needs a required role.',
          ),
        ),
      );
    });

    test('a role outside app_user_roles_role_check is rejected', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Agency Crown';
      state.syncCodeFromName();
      state.unlockType = SroodFrameUnlock.role;
      // A frame *category*, never a role — using it yields an unlockable frame.
      state.requiredRole = 'agency_owner';

      expect(
        state.validate().map((issue) => issue.message),
        contains(
          '"agency_owner" is not a role this app grants. '
          'Pick one from the list.',
        ),
      );
    });

    test(
      'the offered roles are exactly the four values either table holds',
      () {
        // 20260615230000_admin_role_system_rebuild.sql narrowed both
        // app_user_roles_role_check and admin_users_role_check to these four.
        expect(kFrameRequiredRoles, const <String>[
          'o_super_admin',
          'p_super_admin',
          'super_admin',
          'admin',
        ]);
        expect(kFrameRequiredRoles, isNot(contains('agency_owner')));
        expect(kFrameRequiredRoles, isNot(contains('host')));
        expect(kFrameRequiredRoles, isNot(contains('room_owner')));
        expect(kFrameRequiredRoles, isNot(contains('recharge_owner')));
      },
    );

    test('roles dropped by the 2026-06-15 rebuild are rejected', () {
      // These were offered by the old ten-value list but no row in
      // app_user_roles or admin_users can hold them any more, so a frame
      // requiring one could never be worn.
      for (final stale in const <String>[
        'finance_admin',
        'bd_admin',
        'content_admin',
        'room_admin',
        'support_admin',
        'support',
        'moderator',
        'viewer',
      ]) {
        final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
        state.name = 'Stale Role Halo';
        state.syncCodeFromName();
        state.unlockType = SroodFrameUnlock.role;
        state.requiredRole = stale;

        expect(
          state.validate().map((issue) => issue.message),
          contains(
            '"$stale" is not a role this app grants. '
            'Pick one from the list.',
          ),
          reason: '$stale must not be selectable',
        );
      }
    });

    test('a valid role round-trips and is dropped when the unlock changes', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Super Admin Halo';
      state.syncCodeFromName();
      state.unlockType = SroodFrameUnlock.role;
      state.requiredRole = 'super_admin';
      expect(state.validate(), isEmpty);
      expect(state.toFrame().requiredRole, 'super_admin');

      state.unlockType = SroodFrameUnlock.free;
      expect(state.toFrame().requiredRole, isNull);
    });
  });

  group('artwork and asset type', () {
    test('assetTypeForUrl derives the type the renderer branches on', () {
      expect(assetTypeForUrl(null), SroodFrameAssetType.painter);
      expect(assetTypeForUrl('  '), SroodFrameAssetType.painter);
      expect(
        assetTypeForUrl('https://x.supabase.co/a.webp'),
        SroodFrameAssetType.network,
      );
      expect(
        assetTypeForUrl('assets/images/frames/vip_4.webp'),
        SroodFrameAssetType.bundled,
      );
    });

    test('applyArtwork wires url, type, animated flag and animation url', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.applyArtwork(url: 'https://cdn/a.webp', animated: true);

      expect(state.assetUrl, 'https://cdn/a.webp');
      expect(state.assetType, SroodFrameAssetType.network);
      expect(state.isAnimated, isTrue);
      expect(state.animationUrl, 'https://cdn/a.webp');

      state.applyArtwork(url: 'https://cdn/b.png', animated: false);
      expect(state.isAnimated, isFalse);
      expect(state.animationUrl, isNull);
    });

    test('a network asset type with no URL is rejected', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Gilded Ring';
      state.syncCodeFromName();
      state.assetType = SroodFrameAssetType.network;
      state.assetUrl = null;

      expect(
        state.validate(),
        contains(
          const FrameEditorIssue(
            FrameEditorField.artwork,
            'Upload artwork, or leave the asset type as the painter '
            'placeholder.',
          ),
        ),
      );

      state.clearArtwork();
      expect(state.assetType, SroodFrameAssetType.painter);
      expect(state.validate(), isEmpty);
    });
  });

  group('validate()', () {
    test('a blank editor asks for a name and a code', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      expect(
        state.validate().map((issue) => issue.field),
        containsAll(<FrameEditorField>[
          FrameEditorField.name,
          FrameEditorField.code,
        ]),
      );
    });

    test('expiry must be after the start date', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Event Ring';
      state.syncCodeFromName();
      state.startsAt = DateTime(2026, 7, 10);
      state.expiresAt = DateTime(2026, 7, 1);

      expect(
        state.validate(),
        contains(
          const FrameEditorIssue(
            FrameEditorField.schedule,
            'The expiry date must be after the start date.',
          ),
        ),
      );

      state.expiresAt = DateTime(2026, 7, 20);
      expect(state.validate(), isEmpty);
    });

    test('a negative sort order is rejected', () {
      final state = FrameEditorState.blank(catalog: const <SroodFrame>[]);
      state.name = 'Event Ring';
      state.syncCodeFromName();
      state.sortOrder = -1;
      expect(
        state.validate().map((issue) => issue.field),
        contains(FrameEditorField.sortOrder),
      );
    });
  });

  group('toFrame() preserves columns the editor does not own', () {
    final original = _frame(
      code: 'vip4_celestial_crown',
      name: 'Celestial Crown',
      category: SroodFrameCategory.vip,
      vipLevel: 4,
      requiredVipLevel: 4,
      unlockType: SroodFrameUnlock.vipLevel,
      assetType: SroodFrameAssetType.network,
      assetUrl: 'https://cdn/v1.webp',
      thumbnailUrl: 'https://cdn/v1_thumb.webp',
      animationUrl: 'https://cdn/v1_anim.webp',
      unlockValue: 'sku_celestial',
      requiredLevel: 42,
      legacyFrameKey: 'vip_platinum_diamond',
      localizedNames: const {'ar': 'تاج سماوي', 'fr': 'Couronne'},
    );

    test('the four columns the old screen nulled on every edit survive', () {
      final state = FrameEditorState.fromFrame(original);
      state.name = 'Celestial Crown II';

      final saved = state.toFrame();
      expect(saved.thumbnailUrl, 'https://cdn/v1_thumb.webp');
      expect(saved.animationUrl, 'https://cdn/v1_anim.webp');
      expect(saved.unlockValue, 'sku_celestial');
      expect(saved.requiredLevel, 42);
      expect(saved.name, 'Celestial Crown II');
    });

    test('id, legacy key and other locales survive an edit', () {
      final state = FrameEditorState.fromFrame(original);
      state.isActive = false;

      final saved = state.toFrame();
      expect(saved.id, 'id-vip4_celestial_crown');
      expect(saved.legacyFrameKey, 'vip_platinum_diamond');
      expect(saved.localizedNames['fr'], 'Couronne');
      expect(saved.localizedNames['ar'], 'تاج سماوي');
      expect(saved.isActive, isFalse);
    });

    test('clearing the Arabic name removes only that locale', () {
      final state = FrameEditorState.fromFrame(original);
      state.arabicName = '';

      final saved = state.toFrame();
      expect(saved.localizedNames.containsKey('ar'), isFalse);
      expect(saved.localizedNames['fr'], 'Couronne');
    });

    test('fromFrame() reads the tier from required_vip_level first', () {
      final state = FrameEditorState.fromFrame(original);
      expect(state.vipTier, 4);
      expect(state.isNew, isFalse);
      expect(state.codeIsManual, isTrue);
      expect(state.legacyFrameKey, 'vip_platinum_diamond');
    });
  });

  group('duplicateFrom', () {
    final source = _frame(
      code: 'vip4_celestial_crown',
      name: 'Celestial Crown',
      category: SroodFrameCategory.vip,
      sortOrder: 40,
      vipLevel: 4,
      requiredVipLevel: 4,
      unlockType: SroodFrameUnlock.vipLevel,
      assetType: SroodFrameAssetType.network,
      assetUrl: 'https://cdn/v1.webp',
      thumbnailUrl: 'https://cdn/v1_thumb.webp',
      animationUrl: 'https://cdn/v1_anim.webp',
      unlockValue: 'sku_celestial',
      requiredLevel: 42,
      localizedNames: const {'ar': 'تاج سماوي'},
    );

    test('copies configuration under a new code with "Copy" in the name', () {
      final state = duplicateFrom(source, catalog: [source]);

      expect(state.isNew, isTrue);
      expect(state.name, 'Celestial Crown Copy');
      expect(state.code, isNot(source.code));
      expect(state.code, 'vip4_celestial_crown_copy');
      expect(kFrameCodePattern.hasMatch(state.code), isTrue);
      expect(state.category, source.category);
      expect(state.unlockType, source.unlockType);
      expect(state.vipTier, 4);
      expect(state.unlockValue, 'sku_celestial');
      expect(state.requiredLevel, 42);
      expect(state.sortOrder, 50);
      expect(state.original, isNull);
    });

    test('artwork is cleared by default so two rows never share an object', () {
      final state = duplicateFrom(source, catalog: [source]);

      expect(state.assetUrl, isNull);
      expect(state.thumbnailUrl, isNull);
      expect(state.animationUrl, isNull);
      expect(state.assetType, SroodFrameAssetType.painter);
      expect(state.isAnimated, isFalse);
    });

    test('artwork is kept only when explicitly asked for', () {
      final state = duplicateFrom(source, catalog: [source], keepArtwork: true);

      expect(state.assetUrl, 'https://cdn/v1.webp');
      expect(state.thumbnailUrl, 'https://cdn/v1_thumb.webp');
      expect(state.assetType, SroodFrameAssetType.network);
    });

    test('the source frame is not modified', () {
      final before = <String, Object?>{
        'code': source.code,
        'name': source.name,
        'assetUrl': source.assetUrl,
        'sortOrder': source.sortOrder,
        'vipLevel': source.vipLevel,
      };

      final state = duplicateFrom(source, catalog: [source]);
      state.name = 'Renamed Copy';
      state.vipTier = 9;
      state.applyArtwork(url: 'https://cdn/other.webp', animated: true);
      state.toFrame();

      expect(source.code, before['code']);
      expect(source.name, before['name']);
      expect(source.assetUrl, before['assetUrl']);
      expect(source.sortOrder, before['sortOrder']);
      expect(source.vipLevel, before['vipLevel']);
    });

    test('a second duplicate does not collide with the first', () {
      final first = duplicateFrom(source, catalog: [source]);
      final firstFrame = first.toFrame();
      final second = duplicateFrom(source, catalog: [source, firstFrame]);

      expect(second.code, isNot(first.code));
      expect(second.code, 'vip4_celestial_crown_copy_2');
    });

    test('the copy validates without further edits', () {
      expect(duplicateFrom(source, catalog: [source]).validate(), isEmpty);
    });
  });
}
