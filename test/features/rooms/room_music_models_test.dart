import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/rooms/models/room_music.dart';
import 'package:srood_live/features/rooms/models/room_music_state.dart';

void main() {
  test('RoomSong formats known and unknown durations safely', () {
    const unknown = RoomSong(
      id: 'unknown',
      title: 'Unknown',
      artist: '',
      url: 'https://example.com/unknown.mp3',
    );
    const known = RoomSong(
      id: 'known',
      title: 'Known',
      artist: '',
      url: 'https://example.com/known.mp3',
      durationSeconds: 125,
    );

    expect(unknown.formattedDuration, '--:--');
    expect(known.formattedDuration, '2:05');
  });

  test('RoomMusicState parses controller and server clock fields', () {
    final state = RoomMusicState.fromJson(const {
      'room_id': 'room-1',
      'track_id': 'track-1',
      'track_url': 'https://example.com/track.mp3',
      'is_playing': true,
      'started_at': '2026-07-06T10:00:00Z',
      'position_seconds': 12,
      'updated_at': '2026-07-06T10:00:00Z',
      'server_now': '2026-07-06T10:00:05Z',
      'controller_user_id': 'user-1',
      'auto_replay': true,
    });

    expect(state.hasTrack, isTrue);
    expect(state.controllerUserId, 'user-1');
    expect(state.autoReplay, isTrue);
    expect(state.serverNow, DateTime.parse('2026-07-06T10:00:05Z'));
    expect(state.livePositionSeconds, greaterThanOrEqualTo(17));
  });

  test('stopped state is recognized without a track', () {
    final state = RoomMusicState.fromJson(const {
      'room_id': 'room-1',
      'is_playing': false,
      'position_seconds': 0,
      'updated_at': '2026-07-06T10:00:00Z',
    });

    expect(state.isStopped, isTrue);
    expect(state.livePositionSeconds, 0);
  });
}
