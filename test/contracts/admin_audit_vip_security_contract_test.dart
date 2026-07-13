import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;
  final migration = File(
    '${root.path}/supabase/migrations/'
    '20260711021359_harden_admin_audit_and_vip_privacy.sql',
  );

  test('audit table writes are revoked and both writers authorize callers', () {
    final sql = migration.readAsStringSync().toLowerCase();

    expect(
      sql,
      contains(
        'revoke insert, update, delete on table public.admin_audit_logs '
        'from authenticated',
      ),
    );
    expect(
      RegExp(
        r'v_actor is null or not public\.has_admin_access\(\)',
      ).allMatches(sql).length,
      2,
    );
    expect(sql, isNot(contains('with check (true)')));
  });

  test('legacy private VIP RPCs are revoked from API roles', () {
    final sql = migration.readAsStringSync().toLowerCase();

    expect(
      RegExp(
        r'revoke all on function public\.get_user_vip\(uuid\)\s+'
        r'from public, anon, authenticated',
      ).hasMatch(sql),
      isTrue,
    );
    expect(
      RegExp(
        r'revoke all on function public\.get_users_with_vip\(uuid\[\]\)\s+'
        r'from public, anon, authenticated',
      ).hasMatch(sql),
      isTrue,
    );
  });

  test(
    'Flutter uses only the minimal public VIP contracts for other users',
    () {
      final service = File(
        '${root.path}/lib/features/vip/services/vip_service.dart',
      ).readAsStringSync();

      expect(service, contains("'get_public_user_vip'"));
      expect(service, contains("'get_public_users_vip'"));
      expect(service, isNot(contains(".rpc('get_user_vip'")));
      expect(service, isNot(contains(".rpc('get_users_with_vip'")));
    },
  );
}
