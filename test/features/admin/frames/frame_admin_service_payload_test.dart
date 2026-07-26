/// Frame Management v2 — admin RPC payloads.
///
/// The regression these tests exist for: the old editor built its `SroodFrame`
/// without `thumbnailUrl`, `animationUrl`, `unlockValue` or `requiredLevel`, so
/// `admin_upsert_frame_v2` received null for all four and every edit wiped those
/// columns on live rows.
///
/// They also pin the RPC names apart — create must never reach the upsert RPC,
/// whose SQL ends in `on conflict (code) do update`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/core/frames/srood_frame.dart';
import 'package:srood_live/features/admin/exceptions/frame_admin_exception.dart';
import 'package:srood_live/features/admin/services/frame_admin_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Every nullable column populated, so a dropped key shows up as a null.
final SroodFrame fullFrame = SroodFrame(
  id: 'b6f0c2d4-0000-4000-8000-000000000001',
  code: 'vip4_celestial_crown',
  name: 'Celestial Crown',
  localizedNames: const {'ar': 'تاج سماوي'},
  category: SroodFrameCategory.vip,
  vipLevel: 4,
  rarity: SroodFrameRarity.legendary,
  assetType: SroodFrameAssetType.network,
  assetUrl: 'https://cdn.test/vip/vip4_celestial_crown/v1.webp',
  thumbnailUrl: 'https://cdn.test/vip/vip4_celestial_crown/thumb.webp',
  animationUrl: 'https://cdn.test/vip/vip4_celestial_crown/v1.webp',
  isAnimated: true,
  isActive: true,
  sortOrder: 250,
  unlockType: SroodFrameUnlock.vipLevel,
  unlockValue: 'sku_celestial',
  requiredRole: null,
  requiredLevel: 42,
  requiredVipLevel: 4,
  startsAt: DateTime.utc(2026, 7, 1, 12),
  expiresAt: DateTime.utc(2026, 12, 31, 23, 59),
);

/// The 20 parameters `admin_create_frame_v2` and `admin_upsert_frame_v2`
/// declare, in SQL order.
const List<String> expectedKeys = <String>[
  'p_code',
  'p_name',
  'p_category',
  'p_vip_level',
  'p_rarity',
  'p_asset_type',
  'p_asset_url',
  'p_thumbnail_url',
  'p_animation_url',
  'p_is_animated',
  'p_is_active',
  'p_sort_order',
  'p_unlock_type',
  'p_unlock_value',
  'p_required_role',
  'p_required_level',
  'p_required_vip_level',
  'p_starts_at',
  'p_expires_at',
  'p_localized_names',
];

class _Recorder {
  final List<String> functions = <String>[];
  final List<Map<String, dynamic>?> payloads = <Map<String, dynamic>?>[];

  Future<dynamic> call(String fn, {Map<String, dynamic>? params}) async {
    functions.add(fn);
    payloads.add(params);
    return null;
  }

  Map<String, dynamic> get lastPayload => payloads.last!;
}

void main() {
  group('frameRpcParams', () {
    test('sends exactly the 20 declared parameters, in SQL order', () {
      expect(frameRpcParams(fullFrame).keys.toList(), expectedKeys);
    });

    test('serialises enums to their wire values', () {
      final params = frameRpcParams(fullFrame);
      expect(params['p_category'], 'vip');
      expect(params['p_rarity'], 'legendary');
      expect(params['p_asset_type'], 'network');
      expect(params['p_unlock_type'], 'vip_level');
    });

    test('serialises timestamps as UTC ISO-8601 strings', () {
      final params = frameRpcParams(fullFrame);
      expect(params['p_starts_at'], '2026-07-01T12:00:00.000Z');
      expect(params['p_expires_at'], '2026-12-31T23:59:00.000Z');
    });

    test('sends null (not a missing key) for unset columns', () {
      final sparse = SroodFrame(
        id: 'x',
        code: 'plain_ring',
        name: 'Plain Ring',
      );
      final params = frameRpcParams(sparse);

      expect(params.keys.toList(), expectedKeys);
      expect(params['p_asset_url'], isNull);
      expect(params['p_thumbnail_url'], isNull);
      expect(params['p_animation_url'], isNull);
      expect(params['p_unlock_value'], isNull);
      expect(params['p_required_role'], isNull);
      expect(params['p_required_level'], isNull);
      expect(params['p_required_vip_level'], isNull);
      expect(params['p_vip_level'], isNull);
      expect(params['p_starts_at'], isNull);
      expect(params['p_expires_at'], isNull);
    });

    test('has no p_legacy_frame_key — no RPC accepts one', () {
      expect(
        frameRpcParams(fullFrame).containsKey('p_legacy_frame_key'),
        isFalse,
      );
    });
  });

  group('createFrame', () {
    test('calls admin_create_frame_v2 with the full payload', () async {
      final recorder = _Recorder();
      await FrameAdminService(rpcCaller: recorder.call).createFrame(fullFrame);

      expect(recorder.functions, ['admin_create_frame_v2']);
      expect(recorder.lastPayload.keys.toList(), expectedKeys);
      expect(recorder.lastPayload['p_code'], 'vip4_celestial_crown');
      expect(recorder.lastPayload['p_localized_names'], {'ar': 'تاج سماوي'});
    });

    test('never routes through the upsert RPC', () async {
      final recorder = _Recorder();
      await FrameAdminService(rpcCaller: recorder.call).createFrame(fullFrame);
      expect(recorder.functions, isNot(contains('admin_upsert_frame_v2')));
    });
  });

  group('upsertFrame', () {
    test('calls admin_upsert_frame_v2 with the full payload', () async {
      final recorder = _Recorder();
      await FrameAdminService(rpcCaller: recorder.call).upsertFrame(fullFrame);

      expect(recorder.functions, ['admin_upsert_frame_v2']);
      expect(recorder.lastPayload.keys.toList(), expectedKeys);
    });

    test(
      'sends the four columns the old editor nulled out on every edit',
      () async {
        final recorder = _Recorder();
        await FrameAdminService(
          rpcCaller: recorder.call,
        ).upsertFrame(fullFrame);

        final payload = recorder.lastPayload;
        expect(
          payload['p_thumbnail_url'],
          'https://cdn.test/vip/vip4_celestial_crown/thumb.webp',
        );
        expect(
          payload['p_animation_url'],
          'https://cdn.test/vip/vip4_celestial_crown/v1.webp',
        );
        expect(payload['p_unlock_value'], 'sku_celestial');
        expect(payload['p_required_level'], 42);
      },
    );

    test('keeps both VIP columns in agreement', () async {
      final recorder = _Recorder();
      await FrameAdminService(rpcCaller: recorder.call).upsertFrame(fullFrame);

      expect(recorder.lastPayload['p_vip_level'], 4);
      expect(recorder.lastPayload['p_required_vip_level'], 4);
    });
  });

  group('error mapping', () {
    Future<void> expectMapped(
      Object thrown,
      FrameAdminErrorCategory category, {
      Matcher? message,
    }) async {
      final service = FrameAdminService(
        rpcCaller: (fn, {params}) async => throw thrown,
      );
      await expectLater(
        service.createFrame(fullFrame),
        throwsA(
          isA<FrameAdminException>()
              .having((e) => e.category, 'category', category)
              .having((e) => e.message, 'message', message ?? isNotEmpty),
        ),
      );
    }

    test('frame_code_exists becomes duplicateCode, not a raw exception', () {
      return expectMapped(
        const PostgrestException(message: 'frame_code_exists'),
        FrameAdminErrorCategory.duplicateCode,
        message: allOf(
          contains('already used by another frame'),
          isNot(contains('PostgrestException')),
        ),
      );
    });

    test('a unique violation SQLSTATE also becomes duplicateCode', () {
      return expectMapped(
        const PostgrestException(message: 'duplicate key value', code: '23505'),
        FrameAdminErrorCategory.duplicateCode,
      );
    });

    test('not_authorized becomes notAuthorized', () {
      return expectMapped(
        const PostgrestException(message: 'not_authorized'),
        FrameAdminErrorCategory.notAuthorized,
        message: contains('admin or super_admin app role'),
      );
    });

    test('invalid_vip_config becomes invalidVipConfig', () {
      return expectMapped(
        const PostgrestException(message: 'invalid_vip_config'),
        FrameAdminErrorCategory.invalidVipConfig,
      );
    });

    test('invalid_role_config becomes invalidRoleConfig', () {
      return expectMapped(
        const PostgrestException(message: 'invalid_role_config'),
        FrameAdminErrorCategory.invalidRoleConfig,
      );
    });

    test('a check-constraint violation becomes invalidVipConfig', () {
      return expectMapped(
        const PostgrestException(message: 'violates check', code: '23514'),
        FrameAdminErrorCategory.invalidVipConfig,
      );
    });

    test('a missing RPC tells the admin to apply the migrations', () {
      return expectMapped(
        const PostgrestException(
          message: 'Could not find the function',
          code: 'PGRST202',
        ),
        FrameAdminErrorCategory.constraintViolation,
        message: contains('Apply'),
      );
    });

    test('a connectivity failure becomes network', () {
      return expectMapped(
        Exception('SocketException: host unreachable'),
        FrameAdminErrorCategory.network,
        message: contains('Could not reach the server'),
      );
    });
  });

  group('catalog reads', () {
    test('listFrames parses rows through SroodFrame.fromJson', () async {
      final service = FrameAdminService(
        rpcCaller: (fn, {params}) async => null,
        reader: () async => <Map<String, dynamic>>[
          {
            'id': 'row-1',
            'code': 'vip4_celestial_crown',
            'name': 'Celestial Crown',
            'category': 'vip',
            'vip_level': 4,
            'required_vip_level': 4,
            'unlock_type': 'vip_level',
            'legacy_frame_key': 'vip_platinum_diamond',
            'is_active': false,
            'sort_order': 250,
          },
        ],
      );

      final frames = await service.listFrames();
      expect(frames, hasLength(1));
      expect(frames.single.code, 'vip4_celestial_crown');
      expect(frames.single.category, SroodFrameCategory.vip);
      expect(frames.single.requiredVipLevel, 4);
      expect(frames.single.legacyFrameKey, 'vip_platinum_diamond');
      // Admins read inactive rows too — the list must not hide them.
      expect(frames.single.isActive, isFalse);
    });

    test('frameCodeExists answers from the catalog', () async {
      final service = FrameAdminService(
        rpcCaller: (fn, {params}) async => null,
        reader: () async => <Map<String, dynamic>>[
          {'code': 'vip4_celestial_crown', 'name': 'Celestial Crown'},
        ],
      );

      expect(await service.frameCodeExists('vip4_celestial_crown'), isTrue);
      expect(
        await service.frameCodeExists('vip4_celestial_crown_copy'),
        isFalse,
      );
    });

    test('a failing catalog read surfaces a readable message', () async {
      final service = FrameAdminService(
        rpcCaller: (fn, {params}) async => null,
        reader: () async => throw const PostgrestException(
          message: 'permission denied',
          code: '42501',
        ),
      );

      await expectLater(
        service.listFrames(),
        throwsA(
          isA<FrameAdminException>().having(
            (e) => e.category,
            'category',
            FrameAdminErrorCategory.notAuthorized,
          ),
        ),
      );
    });
  });

  group('grant surface', () {
    test('assignFrame and revokeFrame use the v2 grant RPCs', () async {
      final recorder = _Recorder();
      final service = FrameAdminService(rpcCaller: recorder.call);

      await service.assignFrame(
        userId: 'user-1',
        code: 'vip4_celestial_crown',
        expiresAt: DateTime.utc(2026, 8, 1),
      );
      await service.revokeFrame(
        userId: 'user-1',
        code: 'vip4_celestial_crown',
        reason: 'chargeback',
      );

      expect(recorder.functions, [
        'admin_assign_frame_v2',
        'admin_revoke_frame_v2',
      ]);
      expect(recorder.payloads.first, {
        'p_user_id': 'user-1',
        'p_code': 'vip4_celestial_crown',
        'p_source': 'admin_grant',
        'p_expires_at': '2026-08-01T00:00:00.000Z',
      });
      expect(recorder.payloads.last, {
        'p_user_id': 'user-1',
        'p_code': 'vip4_celestial_crown',
        'p_reason': 'chargeback',
      });
    });
  });
}
