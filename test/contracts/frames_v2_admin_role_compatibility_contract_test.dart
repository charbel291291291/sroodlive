// Frames v2 — admin role compatibility migration contract.
//
// House-style contract test (see frame_system_v2_contract_test.dart). The fix
// in 20261202000000 has two properties that are easy to lose in a later edit
// and expensive to lose: the admin_users mapping must stay a *closed* set of
// explicit role names (no loose string comparison, no wildcard, no
// exact-match fallback), and it must stay purely additive on top of the
// original app_user_roles lookup rather than replacing it.
//
// The behavioural proof runs against real Postgres in
// supabase/tests/frame_artwork_storage_and_admin_create_contract.sql; this
// test guards the file itself.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;
  const originalName = '20261112000000_frame_system_v2.sql';
  const fixName = '20261202000000_frames_v2_admin_role_compatibility.sql';

  final fix = File('${root.path}/supabase/migrations/$fixName');
  final original = File('${root.path}/supabase/migrations/$originalName');
  final sql = fix.readAsStringSync();
  final lower = sql.toLowerCase();
  final statements = lower
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  test('the fix ships as its own migration, not an edit of the original', () {
    expect(fix.existsSync(), isTrue);
    expect(original.existsSync(), isTrue);
    // The original still owns the first definition of frames_v2_user_can_use.
    expect(
      original.readAsStringSync().toLowerCase(),
      contains('function public.frames_v2_user_can_use'),
    );
  });

  test('the helper is security definer with a pinned empty search_path', () {
    expect(
      statements,
      contains(
        'create or replace function public.frames_v2_user_has_admin_role',
      ),
    );
    expect(statements, contains('security definer'));
    expect(statements, contains("set search_path = ''"));
    expect(statements, contains('stable'));
  });

  test('the admin_users mapping is a closed set of explicit role names', () {
    // Every branch is a literal role name from admin_users_role_check.
    for (final role in const <String>[
      "when 'o_super_admin' then",
      "when 'p_super_admin' then",
      "when 'super_admin'",
      "when 'admin'",
    ]) {
      expect(statements, contains(role), reason: 'missing branch: $role');
    }
    // …and anything unrecognised fails closed.
    expect(statements, contains('else false'));
    // No exact-match fallback of the has_app_role kind, which would let any
    // string sitting in admin_users.role satisfy an arbitrary required_role.
    expect(statements, isNot(contains('au.role = lower(p_role)')));
    expect(statements, isNot(contains('au.role = p_role')));
    expect(statements, isNot(contains('like')));
    expect(statements, isNot(contains('ilike')));
  });

  test('only active admin memberships count', () {
    expect(statements, contains('au.is_active = true'));
  });

  test('the legacy app_user_roles lookup is preserved, not replaced', () {
    expect(statements, contains('from public.app_user_roles r'));
    expect(statements, contains('r.role = v_frame.required_role'));
    // The admin_users source is an additional OR-branch on the same condition.
    expect(
      statements,
      contains('and not public.frames_v2_user_has_admin_role'),
    );
  });

  test('the migration is additive: no ddl on tables, policies or data', () {
    for (final banned in const <String>[
      'drop table',
      'drop function public.frames_v2_user_can_use',
      'alter table',
      'drop policy',
      'create policy',
      'truncate',
      'delete from',
      'update public.',
      'insert into public.',
    ]) {
      expect(
        statements,
        isNot(contains(banned)),
        reason: '$fixName must stay additive: found "$banned"',
      );
    }
  });

  test('neither function is exposed directly to clients', () {
    expect(
      statements,
      contains(
        'revoke all on function public.frames_v2_user_has_admin_role(uuid, text) '
        'from public',
      ),
    );
    expect(
      statements,
      contains(
        'revoke all on function public.frames_v2_user_can_use(uuid, text) '
        'from public',
      ),
    );
    expect(statements, isNot(contains('grant execute')));
  });

  test('the header records how to roll the change back', () {
    expect(lower, contains('rollback'));
    expect(lower, contains(originalName));
  });
}
