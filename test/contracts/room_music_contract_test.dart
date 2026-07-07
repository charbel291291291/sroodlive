import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;

  String read(String relativePath) =>
      File('${root.path}/$relativePath').readAsStringSync();

  test(
    'room music migration releases stale controllers and hardens storage',
    () {
      final sql = read(
        'supabase/migrations/'
        '20261106000000_room_music_reliability_and_storage_hardening.sql',
      ).toLowerCase();

      expect(sql, contains('release_departed_music_controller'));
      expect(sql, contains('after update of left_at or delete'));
      expect(sql, contains('for update'));
      expect(sql, contains('not_music_controller'));
      expect(sql, contains('room music: managers can insert'));
      expect(sql, contains('public.is_room_manager'));
      expect(
        sql,
        contains(
          'drop policy if exists room_music_tracks_select_authenticated',
        ),
      );
      expect(
        sql,
        contains('revoke all on function public.set_room_music_state'),
      );
    },
  );

  test('client recovers every unhealthy realtime state and resyncs', () {
    final source = read(
      'lib/features/rooms/services/room_synced_music_service.dart',
    );

    expect(source, contains('RealtimeSubscribeStatus.channelError'));
    expect(source, contains('RealtimeSubscribeStatus.closed'));
    expect(source, contains('RealtimeSubscribeStatus.timedOut'));
    expect(source, contains('recoverIfNeeded'));
    expect(source, contains('await syncNow()'));
  });

  test('room controls use the synchronized service', () {
    final room = read('lib/features/rooms/screens/room_details_screen.dart');
    final panel = read('lib/features/rooms/widgets/music_panel.dart');

    expect(room, contains('_syncedMusic.nextForRoom()'));
    expect(room, contains('_syncedMusic.recoverIfNeeded()'));
    expect(room, isNot(contains('_musicService.next();')));
    expect(panel, contains('seekForRoom'));
    expect(panel, contains('playPauseForRoom'));
    expect(panel, contains('stopForRoom'));
  });

  test('listener playback failures do not advance local playlists', () {
    final sync = read(
      'lib/features/rooms/services/room_synced_music_service.dart',
    );

    expect(sync, contains('advanceOnFailure: false'));
  });
}
