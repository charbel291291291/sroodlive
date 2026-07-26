// Frame Management v2 — artwork storage + create RPC contract.
//
// House-style contract test (see frame_system_v2_contract_test.dart): the
// admin editor's upload path and its overwrite guard live entirely in this
// migration, so a later edit must not be able to quietly widen the bucket,
// drop a policy, or turn the guarded insert back into an upsert.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/admin/services/frame_artwork_upload_service.dart';

void main() {
  final root = Directory.current;
  final path =
      '${root.path}/supabase/migrations/'
      '20261133000000_frame_artwork_storage_and_create_rpc.sql';
  final file = File(path);
  final sql = file.readAsStringSync();
  final lower = sql.toLowerCase();
  // The header comment names the tables this migration deliberately leaves
  // alone, so the "does not touch" assertions must read executable SQL only.
  final statements = lower
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  test('the migration exists at its own version slot', () {
    // It must be a new file: editing an already-applied migration is banned.
    expect(file.existsSync(), isTrue);
    expect(
      File(
        '${root.path}/supabase/migrations/20261112000000_frame_system_v2.sql',
      ).readAsStringSync(),
      isNot(contains('avatar-frames')),
      reason: 'the applied v2 migration must stay untouched',
    );
  });

  group('storage bucket', () {
    test('is created as avatar-frames, the name the client uploads to', () {
      expect(lower, contains('insert into storage.buckets'));
      expect(sql, contains("'avatar-frames'"));
      // The Dart constant and the SQL bucket id are the same string, so a
      // rename on either side fails here rather than at runtime.
      expect(kFrameArtworkBucket, 'avatar-frames');
      expect(sql, contains("'$kFrameArtworkBucket'"));
    });

    test('is public-read and capped at the animated-WebP ceiling', () {
      expect(lower, contains('true'));
      expect(sql, contains('2097152'));
      expect(kFrameArtworkAnimatedMaxBytes, 2097152);
    });

    test('allows only the two formats the renderer can draw', () {
      expect(sql, contains("array['image/webp', 'image/png']"));
      expect(lower, isNot(contains('image/gif')));
      expect(lower, isNot(contains('application/json')), reason: 'no Lottie');
      expect(kFrameArtworkExtensions, ['webp', 'png']);
    });

    test('is idempotent so a re-run cannot fail the deploy', () {
      expect(lower, contains('on conflict (id) do update set'));
    });
  });

  group('storage policies', () {
    for (final name in const [
      'avatar_frames_select',
      'avatar_frames_insert',
      'avatar_frames_update',
      'avatar_frames_delete',
    ]) {
      test('$name is declared and re-runnable', () {
        expect(sql, contains('create policy "$name"'));
        expect(sql, contains('drop policy if exists "$name"'));
      });
    }

    test('every write policy is gated on has_admin_access()', () {
      // Reads are open (public bucket); writes must match the exact gate on the
      // catalog RPCs, so an account can never upload artwork it cannot register.
      final writeBlocks = <String>[];
      for (final name in const [
        'avatar_frames_insert',
        'avatar_frames_update',
        'avatar_frames_delete',
      ]) {
        final start = sql.indexOf('create policy "$name"');
        expect(start, greaterThan(-1));
        final end = sql.indexOf(';', start);
        writeBlocks.add(sql.substring(start, end));
      }
      for (final block in writeBlocks) {
        expect(block, contains('public.has_admin_access()'));
        expect(block, contains("bucket_id = 'avatar-frames'"));
        expect(block, contains('to authenticated'));
        expect(block, isNot(contains('to anon')));
      }
    });

    test('the read policy is scoped to this bucket only', () {
      final start = sql.indexOf('create policy "avatar_frames_select"');
      final block = sql.substring(start, sql.indexOf(';', start));
      expect(block, contains("using (bucket_id = 'avatar-frames')"));
      expect(block, contains('to anon, authenticated'));
    });
  });

  group('admin_create_frame_v2', () {
    test('is defined with the same 20 parameters as the upsert', () {
      expect(
        sql,
        contains('create or replace function public.admin_create_frame_v2'),
      );
      for (final param in const [
        'p_code text',
        'p_name text',
        'p_category text',
        'p_vip_level int',
        'p_rarity text',
        'p_asset_type text',
        'p_asset_url text',
        'p_thumbnail_url text',
        'p_animation_url text',
        'p_is_animated boolean',
        'p_is_active boolean',
        'p_sort_order int',
        'p_unlock_type text',
        'p_unlock_value text',
        'p_required_role text',
        'p_required_level int',
        'p_required_vip_level int',
        'p_starts_at timestamptz',
        'p_expires_at timestamptz',
        'p_localized_names jsonb',
      ]) {
        expect(sql, contains(param), reason: '$param missing');
      }
    });

    test('never overwrites an existing frame_catalog row', () {
      // The whole reason this RPC exists: admin_upsert_frame_v2 ends in
      // `on conflict (code) do update`, which silently replaces another
      // admin's frame when codes collide.
      final start = sql.indexOf(
        'create or replace function public.admin_create_frame_v2',
      );
      final body = sql.substring(start, sql.indexOf(r'end $$;', start));
      final catalogInsert = body.substring(
        body.indexOf('insert into public.frame_catalog'),
        body.indexOf('insert into public.avatar_frames'),
      );
      expect(catalogInsert.toLowerCase(), isNot(contains('on conflict')));
      expect(body, contains("raise exception 'frame_code_exists'"));
      expect(body, contains('when unique_violation then'));
    });

    test('refuses callers without admin access', () {
      expect(sql, contains('if not public.has_admin_access() then'));
      expect(sql, contains("raise exception 'not_authorized'"));
    });

    test('validates the VIP and role combinations the editor blocks', () {
      expect(sql, contains("raise exception 'invalid_vip_config'"));
      expect(sql, contains("raise exception 'invalid_role_config'"));
      // Contradictory VIP columns must not be persistable by a stale client.
      expect(sql, contains('p_vip_level <> p_required_vip_level'));
    });

    test('runs security definer with a pinned search_path', () {
      expect(lower, contains('security definer'));
      expect(sql, contains("set search_path = ''"));
    });

    test('is executable by authenticated only, not public', () {
      expect(
        statements,
        contains('revoke all on function public.admin_create_frame_v2'),
      );
      expect(
        statements,
        contains('grant execute on function public.admin_create_frame_v2'),
      );
      // The revoke comes first, and the only grantee is `authenticated`.
      final revoke = statements.indexOf('revoke all on function');
      final grant = statements.indexOf('grant execute on function');
      expect(revoke, lessThan(grant));
      expect(statements.substring(grant), contains(') to authenticated;'));
      expect(statements.substring(grant), isNot(contains('to public')));
      expect(statements.substring(grant), isNot(contains('to anon')));
    });

    test('mirrors the legacy avatar_frames row the profiles FK needs', () {
      expect(sql, contains('insert into public.avatar_frames'));
      expect(sql, contains('on conflict (frame_key) do update set'));
    });

    test('writes an audit log entry', () {
      expect(sql, contains('insert into public.admin_audit_logs'));
      expect(sql, contains("'create_frame_v2'"));
    });
  });

  group('destructive statements', () {
    test('the migration alters nothing that already exists', () {
      for (final banned in const [
        'drop table',
        'drop function public.admin_upsert_frame_v2',
        'truncate',
        'delete from public.frame_catalog',
        'update public.frame_catalog',
        'alter table public.frame_catalog',
        'drop policy if exists "avatar_frames_select" on public.frame_catalog',
      ]) {
        expect(
          statements,
          isNot(contains(banned)),
          reason: '$banned is banned',
        );
      }
    });

    test('it does not touch the tables the task ring-fenced', () {
      expect(
        statements,
        isNot(contains('drop table if exists public.avatar_frames')),
      );
      expect(statements, isNot(contains('user_avatar_frames')));
      expect(statements, isNot(contains('frames_v2_user_can_use')));
      expect(statements, isNot(contains('alter table public.avatar_frames')));
    });
  });
}
