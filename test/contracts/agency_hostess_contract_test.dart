import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;
  final migration = File(
    '${root.path}/supabase/migrations/'
    '20261105000000_agency_hostess_production_contract.sql',
  );

  test('production migration defines the Agency and Hostess RPC contract', () {
    final sql = migration.readAsStringSync().toLowerCase();

    for (final rpc in const {
      'get_my_agency_membership',
      'get_my_host_status',
      'get_my_host_availability',
      'save_my_host_availability',
      'apply_to_create_agency',
      'admin_review_agency_application',
      'agency_owner_review_application',
    }) {
      expect(
        RegExp(
          'create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.$rpc\\s*\\(',
        ).hasMatch(sql),
        isTrue,
        reason: '$rpc must be source controlled',
      );
    }

    expect(sql, contains('create table if not exists public.approved_hosts'));
    expect(
      sql,
      contains('create table if not exists public.host_availability'),
    );
    expect(sql, contains('perform public._activate_approved_host'));
    expect(sql, contains("'agency_created'"));
    expect(sql, contains('grant execute on function'));
    expect(sql, contains('revoke all on public.host_availability'));
  });

  test('Me uses one secure Agency and Hosting entry point', () {
    final profile = File(
      '${root.path}/lib/features/profile/profile_screen.dart',
    ).readAsStringSync();
    final service = File(
      '${root.path}/lib/features/profile_hub/services/agency_service.dart',
    ).readAsStringSync();

    expect(profile, isNot(contains('HostRegistrationScreen(')));
    expect(service, contains("'get_my_agency_membership'"));
    expect(service, contains("'get_my_host_status'"));
    expect(service, isNot(contains(".from('agency_members')")));
  });

  test('host availability uses guarded RPCs instead of direct writes', () {
    final screen = File(
      '${root.path}/lib/features/host/screens/availability_screen.dart',
    ).readAsStringSync();

    expect(screen, contains("'get_my_host_availability'"));
    expect(screen, contains("'save_my_host_availability'"));
    expect(screen, isNot(contains(".from('host_availability')")));
  });
}
