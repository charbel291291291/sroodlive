// Frame System v2 — migration + safety contract.
//
// House-style contract test (see agency_hostess_contract_test.dart): verifies
// the v2 migration file keeps its non-destructive guarantees and required
// security objects, so a later edit can't silently drop them.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;
  final sql = File(
    '${root.path}/supabase/migrations/20261112000000_frame_system_v2.sql',
  ).readAsStringSync();
  final lower = sql.toLowerCase();

  test('v2 schema objects exist', () {
    expect(sql, contains('create table if not exists public.frame_catalog'));
    expect(sql, contains('create table if not exists public.user_frames'));
    expect(sql, contains('create table if not exists public.frame_legacy_map'));
    expect(
      sql,
      contains('create table if not exists public.frame_ownership_audit'),
    );
    expect(
      sql,
      contains('create table if not exists public.frame_settings_v2'),
    );
    expect(sql, contains('frames_v2_user_can_use'));
    expect(sql, contains('select_my_frame_v2'));
    expect(sql, contains('admin_upsert_frame_v2'));
    expect(sql, contains('admin_assign_frame_v2'));
    expect(sql, contains('admin_revoke_frame_v2'));
    expect(sql, contains('frames_v2_migration_report'));
  });

  test('RLS is enabled on every new table', () {
    for (final table in const [
      'frame_catalog',
      'frame_legacy_map',
      'user_frames',
      'frame_ownership_audit',
      'frame_settings_v2',
    ]) {
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
        reason: '$table must have RLS',
      );
    }
  });

  test('admin RPCs reuse the existing authorization model', () {
    expect(sql, contains('public.has_admin_access()'));
    expect(
      lower,
      isNot(contains('create table if not exists public.admin')),
      reason: 'must not create a second admin permission model',
    );
  });

  test('enforcement ships log-only by default', () {
    expect(sql, contains('enforce_selection boolean not null default false'));
  });

  test('migration is strictly additive to legacy objects', () {
    expect(lower, isNot(contains('drop table public.avatar_frames')));
    expect(lower, isNot(contains('drop table public.user_avatar_frames')));
    expect(lower, isNot(contains('delete from public.avatar_frames')));
    expect(lower, isNot(contains('delete from public.user_avatar_frames')));
    expect(lower, isNot(contains('delete from public.profiles')));
    expect(lower, isNot(contains('alter table public.profiles drop')));
    expect(lower, isNot(contains('update public.user_avatar_frames')));
  });

  test('legacy FK compatibility rows and alias map are seeded', () {
    // vip_1..vip_9 must be inserted into the LEGACY catalog for the
    // profiles.selected_avatar_frame_key FK.
    expect(sql, contains('insert into public.avatar_frames'));
    expect(sql, contains("('vip_bronze_star', 'vip_1')"));
    expect(sql, contains("('vip_celestial', 'vip_9')"));
    // Ownership backfill preserves legacy rows (insert-only).
    expect(sql, contains("'legacy_migration'"));
  });

  test('writes are RPC-only (no table write grants to authenticated)', () {
    expect(lower, isNot(contains('grant insert on public.user_frames')));
    expect(lower, isNot(contains('grant update on public.user_frames')));
    expect(lower, isNot(contains('grant insert on public.frame_catalog')));
  });
}
