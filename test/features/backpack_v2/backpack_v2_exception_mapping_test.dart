import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/backpack_v2/exceptions/backpack_v2_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException pgError({required String code, required String message}) =>
    PostgrestException(message: message, code: code);

void main() {
  group('mapBackpackV2Error', () {
    test('28000 maps to authentication', () {
      final mapped = mapBackpackV2Error(
        pgError(code: '28000', message: 'not_authenticated'),
      );
      expect(mapped.category, BackpackV2ErrorCategory.authentication);
    });

    test('42501 maps to permission', () {
      final mapped = mapBackpackV2Error(
        pgError(code: '42501', message: 'permission denied'),
      );
      expect(mapped.category, BackpackV2ErrorCategory.permission);
    });

    test('P0002 maps to missingOwnership (not-found and cross-user both)', () {
      final mapped = mapBackpackV2Error(
        pgError(code: 'P0002', message: 'backpack_item_not_found'),
      );
      expect(mapped.category, BackpackV2ErrorCategory.missingOwnership);
    });

    test('22023 item_expired maps to expiredOwnership', () {
      final mapped = mapBackpackV2Error(
        pgError(code: '22023', message: 'item_expired'),
      );
      expect(mapped.category, BackpackV2ErrorCategory.expiredOwnership);
    });

    test('22023 item_revoked maps to missingOwnership', () {
      final mapped = mapBackpackV2Error(
        pgError(code: '22023', message: 'item_revoked'),
      );
      expect(mapped.category, BackpackV2ErrorCategory.missingOwnership);
    });

    test('22023 item_not_active/item_not_equippable/item_equip_disabled/'
        'vip_level_required map to equipEligibility', () {
      for (final msg in [
        'item_not_active',
        'item_not_equippable',
        'item_equip_disabled',
        'vip_level_required',
        'item_not_consumable',
      ]) {
        final mapped = mapBackpackV2Error(pgError(code: '22023', message: msg));
        expect(
          mapped.category,
          BackpackV2ErrorCategory.equipEligibility,
          reason: 'message=$msg',
        );
      }
    });

    test('22023 invalid_slot_type maps to unsupportedItemType', () {
      final mapped = mapBackpackV2Error(
        pgError(code: '22023', message: 'invalid_slot_type'),
      );
      expect(mapped.category, BackpackV2ErrorCategory.unsupportedItemType);
    });

    test('unmapped 22023 message falls back to databaseConstraint', () {
      final mapped = mapBackpackV2Error(
        pgError(code: '22023', message: 'some_new_business_rule'),
      );
      expect(mapped.category, BackpackV2ErrorCategory.databaseConstraint);
    });

    test('23505/23503/23514/23502 map to databaseConstraint', () {
      for (final code in ['23505', '23503', '23514', '23502']) {
        final mapped = mapBackpackV2Error(
          pgError(code: code, message: 'constraint violated'),
        );
        expect(
          mapped.category,
          BackpackV2ErrorCategory.databaseConstraint,
          reason: 'code=$code',
        );
      }
    });

    test('unrecognized Postgres code falls back to invalidResponse', () {
      final mapped = mapBackpackV2Error(
        pgError(code: '99999', message: 'weird'),
      );
      expect(mapped.category, BackpackV2ErrorCategory.invalidResponse);
    });

    // Scenario: malformed RPC response
    test('FormatException maps to invalidResponse', () {
      final mapped = mapBackpackV2Error(
        const FormatException('backpack_v2_owned_item_missing_ownership_id'),
      );
      expect(mapped.category, BackpackV2ErrorCategory.invalidResponse);
      expect(mapped.code, 'backpack_v2_owned_item_missing_ownership_id');
    });

    test('network-shaped error message maps to network', () {
      final mapped = mapBackpackV2Error(
        Exception('SocketException: Connection timed out'),
      );
      expect(mapped.category, BackpackV2ErrorCategory.network);
    });

    test('already-mapped BackpackV2Exception passes through unchanged', () {
      const original = BackpackV2Exception(
        BackpackV2ErrorCategory.permission,
        'already_mapped',
      );
      expect(mapBackpackV2Error(original), same(original));
    });

    test('unrecognized error type falls back to unknown', () {
      final mapped = mapBackpackV2Error(StateError('totally unexpected'));
      expect(mapped.category, BackpackV2ErrorCategory.unknown);
    });
  });
}
