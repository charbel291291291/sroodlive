import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/room_music.dart';
import '../models/room_music_state.dart';
import 'room_music_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RoomSyncedMusicService
//
// Bridge between Supabase Realtime and the local RoomMusicService.
//
// Data flow:
//   CONTROLLER: MusicPanel → _musicService (local, immediate UI)
//               → _onLocalMusicChanged fires (only on song/play-state change)
//               → pushCurrentState() → set_room_music_state RPC
//               → Realtime event fires on all clients, including controller
//               → _applyState() is a no-op on controller (applyingServerState
//                 guard or state already matches)
//
//   LISTENER:   Realtime fires → _applyState() → _musicService.playSong() /
//               seek / pause / stop
//
//   LATE JOIN:  initialize() → get_room_music_state RPC → _applyState()
//               If playing  → load + seek + play
//               If paused   → loadSongPaused() so mini-player shows track info
//               If stopped  → nothing
//
//   AUTO REPLAY: when song ends, only the controller's device calls
//               _handleSongCompleted() → seeks to 0 + plays → push.
//               Listeners receive the replay push via Realtime.
//               This prevents every client from restarting simultaneously.
//
// Not affected: LiveKit audio, mic seats, PK, games, gifts, wallet.
// Volume and mute are local-only; never pushed to Supabase.
// ─────────────────────────────────────────────────────────────────────────────

class RoomSyncedMusicService {
  RoomSyncedMusicService({
    required this.roomId,
    required this.musicService,
    required this.currentUserId,
  });

  final String roomId;
  final RoomMusicService musicService;

  /// The Supabase user ID of the person running this instance.
  final String currentUserId;

  RealtimeChannel? _rtChannel;
  RoomMusicState? _lastState;

  /// True while we are applying a server update to [musicService].
  /// The room screen listener checks this to avoid writing back to Supabase.
  bool applyingServerState = false;

  // Tracks the last values we pushed so we only write on meaningful changes.
  String? _pushedSongId;
  bool? _pushedIsPlaying;
  bool _pushedIsActive = false;
  bool _pushedAutoReplay = false;

  RoomMusicState? get lastState => _lastState;

  /// Whether the current device owns the music controls.
  bool get isController =>
      _lastState?.controllerUserId != null &&
      _lastState!.controllerUserId == currentUserId;

  SupabaseClient get _client => SupabaseService.requiredClient;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    _subscribeRealtime();
    await syncNow();
  }

  Future<void> dispose() async {
    await _rtChannel?.unsubscribe();
    _rtChannel = null;
  }

  // ── Late-join sync ────────────────────────────────────────────────────────

  Future<void> syncNow() async {
    try {
      debugPrint('[RoomMusic] syncNow get_room_music_state roomId=$roomId');
      final result = await _client.rpc(
        'get_room_music_state',
        params: {'p_room_id': roomId},
      );
      if (result == null) return;
      final state = RoomMusicState.fromJson(result as Map<String, dynamic>);
      await _applyState(state, fromRealtime: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[RoomMusic] syncNow error: $e');
    }
  }

  // ── Realtime subscription ─────────────────────────────────────────────────

  void _subscribeRealtime() {
    _rtChannel?.unsubscribe();
    _rtChannel = _client.channel('room_music_sync_$roomId');

    _rtChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'room_music_state',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: roomId,
      ),
      callback: (payload) async {
        try {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          final state = RoomMusicState.fromJson(row);
          debugPrint('[RoomMusic] RT received playing=${state.isPlaying} stopped=${state.isStopped} '
              'track=${state.trackId} controller=${state.controllerUserId} '
              'autoReplay=${state.autoReplay}');
          await _applyState(state, fromRealtime: true);
        } catch (e) {
          debugPrint('[RoomMusic] RT error: $e');
        }
      },
    );

    _rtChannel!.subscribe((status, [error]) {
      debugPrint('[RoomMusic] RT status=$status error=$error');
    });
  }

  // ── Apply server state → local RoomMusicService ───────────────────────────

  Future<void> _applyState(RoomMusicState newState, {required bool fromRealtime}) async {
    final prev = _lastState;
    _lastState = newState;

    // Skip if the important fields haven't changed (de-dupe Realtime events).
    if (fromRealtime &&
        prev != null &&
        prev.trackId == newState.trackId &&
        prev.isPlaying == newState.isPlaying &&
        !newState.isPlaying) {
      return;
    }

    applyingServerState = true;
    try {
      // ── STOPPED ──────────────────────────────────────────────────────────
      if (newState.isStopped) {
        if (musicService.isActive) await musicService.stop();
        return;
      }

      debugPrint('[RoomMusic] apply trackId=${newState.trackId} playing=${newState.isPlaying} '
          'controller=${newState.controllerUserId} autoReplay=${newState.autoReplay}');
      final trackUrl = newState.trackUrl;
      if (trackUrl == null) return;

      final idx = _ensureSongInPlaylist(newState);
      if (idx == null) return;

      // ── PAUSED (with a track) ─────────────────────────────────────────────
      if (!newState.isPlaying) {
        debugPrint('[RoomMusic] autoPause track=${newState.trackId}');
        final trackChanged = prev?.trackId != newState.trackId;
        if (trackChanged || !musicService.isActive) {
          await musicService.loadSongPaused(
            idx,
            seekTo: Duration(seconds: newState.positionSeconds),
          );
        } else if (musicService.isPlaying) {
          await musicService.seek(Duration(seconds: newState.positionSeconds));
          await musicService.playPause();
        }
        return;
      }

      // ── PLAYING ───────────────────────────────────────────────────────────
      final trackChanged = prev?.trackId != newState.trackId;
      final wasPlaying = prev?.isPlaying ?? false;

      if (trackChanged || !musicService.isActive) {
        debugPrint('[RoomMusic] autoPlay new track=${newState.trackId}');
        await musicService.playSong(idx);
        final seekTo = Duration(seconds: newState.livePositionSeconds);
        if (seekTo.inSeconds > 1) await musicService.seek(seekTo);
      } else if (!wasPlaying && newState.isPlaying) {
        debugPrint('[RoomMusic] autoPlay resume track=${newState.trackId}');
        final seekTo = Duration(seconds: newState.livePositionSeconds);
        if (seekTo.inSeconds > 1) await musicService.seek(seekTo);
        if (!musicService.isPlaying) await musicService.playPause();
      }
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        applyingServerState = false;
      });
    }
  }

  /// Called by the room screen when the local player reaches
  /// [ProcessingState.completed] — only the controller handles replay.
  Future<void> handleSongCompleted() async {
    final state = _lastState;
    if (state == null) return;
    if (!state.autoReplay) return;
    if (state.controllerUserId != currentUserId) {
      debugPrint('[RoomMusic] song ended — not controller, skipping replay');
      return;
    }
    debugPrint('[RoomMusic] song ended — controller triggers autoReplay');
    // Seek to start and play locally; pushCurrentStateIfChanged will broadcast.
    await musicService.seek(Duration.zero);
    if (!musicService.isPlaying) await musicService.playPause();
    // Force push since position reset isn't a "meaningful change" by itself.
    await _forcePushCurrentState();
  }

  /// Returns the playlist index for the song described by [state].
  /// Adds a temporary entry if the song is not in the local catalog.
  int? _ensureSongInPlaylist(RoomMusicState state) {
    final songs = musicService.playlist;

    int idx = state.trackId != null
        ? songs.indexWhere((s) => s.id == state.trackId)
        : -1;
    if (idx == -1 && state.trackUrl != null) {
      idx = songs.indexWhere((s) => s.url == state.trackUrl);
    }

    if (idx != -1) return idx;

    final tempSong = RoomSong(
      id: state.trackId ?? 'sync_${state.trackUrl.hashCode}',
      title: state.trackTitle ?? 'Unknown',
      artist: state.trackArtist ?? '',
      url: state.trackUrl!,
    );
    musicService.addToPlaylist(tempSong);

    final updated = musicService.playlist;
    final newIdx = updated.indexWhere((s) => s.id == tempSong.id);
    return newIdx >= 0 ? newIdx : null;
  }

  // ── Push local state → Supabase ───────────────────────────────────────────

  /// Called by the room screen when the controller changes song or play state.
  /// Filters out position-only changes so we only write on meaningful changes.
  Future<void> pushCurrentStateIfChanged({bool? autoReplay}) async {
    final song = musicService.currentSong;
    final isActive = musicService.isActive;
    final isPlaying = musicService.isPlaying;
    final ar = autoReplay ?? _lastState?.autoReplay ?? false;

    if (_pushedSongId == song?.id &&
        _pushedIsPlaying == isPlaying &&
        _pushedIsActive == isActive &&
        _pushedAutoReplay == ar) {
      return;
    }

    _pushedSongId = song?.id;
    _pushedIsPlaying = isPlaying;
    _pushedIsActive = isActive;
    _pushedAutoReplay = ar;

    try {
      if (song == null || !isActive) {
        debugPrint('[RoomMusic] push stop roomId=$roomId');
        await _client.rpc(
          'stop_room_music',
          params: {'p_room_id': roomId},
        );
        return;
      }

      debugPrint('[RoomMusic] push playing=$isPlaying track=${song.id} autoReplay=$ar');
      await _client.rpc(
        'set_room_music_state',
        params: {
          'p_room_id': roomId,
          'p_track_id': song.id,
          'p_track_title': song.title,
          'p_track_artist': song.artist,
          'p_track_url': song.url,
          'p_is_playing': isPlaying,
          'p_position_seconds': musicService.position.inSeconds,
          'p_auto_replay': ar,
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[RoomMusic] push error: $e');
    }
  }

  /// Force push — bypasses the "nothing changed" guard. Used for auto replay.
  Future<void> _forcePushCurrentState() async {
    _pushedSongId = null; // invalidate cache
    await pushCurrentStateIfChanged();
  }

  /// Toggle auto replay and push. Only the controller should call this.
  Future<void> setAutoReplay({required bool value}) async {
    debugPrint('[RoomMusic] setAutoReplay=$value controller=$currentUserId');
    // Update local state so UI reflects immediately.
    if (_lastState != null) {
      _lastState = _lastState!.copyWith(autoReplay: value);
    }
    _pushedAutoReplay = !value; // force push
    await pushCurrentStateIfChanged(autoReplay: value);
  }

  /// Explicitly stop music for all room members. Any room manager may call.
  Future<void> stopForRoom() async {
    debugPrint('[RoomMusic] stopForRoom roomId=$roomId');
    try {
      await _client.rpc(
        'stop_room_music',
        params: {'p_room_id': roomId},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[RoomMusic] stopForRoom error: $e');
    }
  }
}
