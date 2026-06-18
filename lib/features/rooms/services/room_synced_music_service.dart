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
//   HOST:    MusicPanel → _musicService (local, immediate UI)
//            → _onLocalMusicChanged fires (only on song/play-state change)
//            → pushCurrentState() → set_room_music_state RPC
//            → Realtime event fires on all clients, including host
//            → _applyState() is a no-op on host (applyingServerState guard or
//              state already matches)
//
//   MEMBER:  Realtime fires → _applyState() → _musicService.playSong() / seek /
//            pause / stop
//
//   LATE JOIN: initialize() → get_room_music_state RPC → _applyState()
//              If playing  → load + seek + play
//              If paused   → loadSongPaused() so mini-player shows track info
//              If stopped  → nothing
//
// Not affected: LiveKit audio, mic seats, PK, games, gifts, wallet.
// Volume and mute are local-only; never pushed to Supabase.
// ─────────────────────────────────────────────────────────────────────────────

class RoomSyncedMusicService {
  RoomSyncedMusicService({
    required this.roomId,
    required this.musicService,
  });

  final String roomId;
  final RoomMusicService musicService;

  RealtimeChannel? _rtChannel;
  RoomMusicState? _lastState;

  /// True while we are applying a server update to [musicService].
  /// The room screen listener checks this to avoid writing back to Supabase.
  bool applyingServerState = false;

  // Tracks the last values we pushed so we only write on meaningful changes.
  String? _pushedSongId;
  bool? _pushedIsPlaying;
  bool _pushedIsActive = false;

  RoomMusicState? get lastState => _lastState;

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
      debugPrint('[RoomMusicSync] syncNow get_room_music_state');
      final result = await _client.rpc(
        'get_room_music_state',
        params: {'p_room_id': roomId},
      );
      if (result == null) return;
      final state = RoomMusicState.fromJson(result as Map<String, dynamic>);
      await _applyState(state, fromRealtime: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[RoomSyncedMusic] syncNow error: $e');
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
          debugPrint('[RT-MUSIC] received state=playing:${state.isPlaying} stopped:${state.isStopped} track=${state.trackId} title=${state.trackTitle} room=$roomId');
          await _applyState(state, fromRealtime: true);
        } catch (e) {
          debugPrint('[RT-MUSIC] realtime error: $e');
        }
      },
    );

    _rtChannel!.subscribe((status, [error]) {
      debugPrint('[RT-MUSIC] status=$status error=$error room=$roomId');
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
      // Paused, same track — nothing to do.
      return;
    }

    applyingServerState = true;
    try {
      // ── STOPPED ──────────────────────────────────────────────────────────
      if (newState.isStopped) {
        if (musicService.isActive) await musicService.stop();
        return;
      }

      debugPrint('[RoomMusicSync] apply state trackId=${newState.trackId} playing=${newState.isPlaying} url=${newState.trackUrl}');
      final trackUrl = newState.trackUrl;
      if (trackUrl == null) return;

      // Find or inject the song into the local playlist.
      final idx = _ensureSongInPlaylist(newState);
      if (idx == null) return;

      // ── PAUSED (with a track) ─────────────────────────────────────────────
      // Load the song so mini-player shows track info, but do NOT start playback.
      if (!newState.isPlaying) {
        debugPrint('[MUSIC-LISTENER] autoPause track=${newState.trackId} title=${newState.trackTitle}');
        final trackChanged = prev?.trackId != newState.trackId;
        if (trackChanged || !musicService.isActive) {
          await musicService.loadSongPaused(
            idx,
            seekTo: Duration(seconds: newState.positionSeconds),
          );
        } else if (musicService.isPlaying) {
          // Same track but server says pause — pause locally and seek.
          await musicService.seek(Duration(seconds: newState.positionSeconds));
          await musicService.playPause(); // playing → paused
        }
        return;
      }

      // ── PLAYING ───────────────────────────────────────────────────────────
      final trackChanged = prev?.trackId != newState.trackId;
      final wasPlaying = prev?.isPlaying ?? false;

      if (trackChanged || !musicService.isActive) {
        // New track: load and play, then seek to live position.
        debugPrint('[MUSIC-LISTENER] autoPlay track=${newState.trackId} title=${newState.trackTitle} url=${newState.trackUrl}');
        await musicService.playSong(idx);
        final seekTo = Duration(seconds: newState.livePositionSeconds);
        if (seekTo.inSeconds > 1) await musicService.seek(seekTo);
      } else if (!wasPlaying && newState.isPlaying) {
        // Resume same track: seek to live position then play.
        debugPrint('[MUSIC-LISTENER] autoPlay resume track=${newState.trackId}');
        final seekTo = Duration(seconds: newState.livePositionSeconds);
        if (seekTo.inSeconds > 1) await musicService.seek(seekTo);
        if (!musicService.isPlaying) await musicService.playPause();
      }
      // If same track, was already playing — nothing to do (position drifts
      // naturally; a full seek would cause an audible stutter).

    } finally {
      // Delay clearing the flag so the listener has time to observe it
      // before the next notifyListeners() fires.
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        applyingServerState = false;
      });
    }
  }

  /// Returns the playlist index for the song described by [state].
  /// Adds a temporary entry if the song is not in the local catalog.
  int? _ensureSongInPlaylist(RoomMusicState state) {
    final songs = musicService.playlist;

    // Try matching by ID first, then URL.
    int idx = state.trackId != null
        ? songs.indexWhere((s) => s.id == state.trackId)
        : -1;
    if (idx == -1 && state.trackUrl != null) {
      idx = songs.indexWhere((s) => s.url == state.trackUrl);
    }

    if (idx != -1) return idx;

    // Song not in local catalog — inject it so playSong(idx) works.
    final tempSong = RoomSong(
      id: state.trackId ?? 'sync_${state.trackUrl.hashCode}',
      title: state.trackTitle ?? 'Unknown',
      artist: state.trackArtist ?? '',
      url: state.trackUrl!,
    );
    musicService.addToPlaylist(tempSong);

    // Re-search after insertion.
    final updated = musicService.playlist;
    final newIdx = updated.indexWhere((s) => s.id == tempSong.id);
    return newIdx >= 0 ? newIdx : null;
  }

  // ── Host: push current local state to Supabase ────────────────────────────

  /// Called by the room screen when the host changes song or play state.
  /// Filters out position-only changes (e.g. seek bar drags, tick updates)
  /// so we only write to Supabase when something meaningful changes.
  Future<void> pushCurrentStateIfChanged() async {
    final song = musicService.currentSong;
    final isActive = musicService.isActive;
    final isPlaying = musicService.isPlaying;

    // Skip if nothing meaningful changed since the last push.
    if (_pushedSongId == song?.id &&
        _pushedIsPlaying == isPlaying &&
        _pushedIsActive == isActive) {
      return;
    }

    _pushedSongId = song?.id;
    _pushedIsPlaying = isPlaying;
    _pushedIsActive = isActive;

    try {
      if (song == null || !isActive) {
        await _client.rpc(
          'stop_room_music',
          params: {'p_room_id': roomId},
        );
        return;
      }

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
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[RoomSyncedMusic] push error: $e');
    }
  }

  /// Explicitly stop music for all room members (host-only).
  Future<void> stopForRoom() async {
    try {
      await _client.rpc(
        'stop_room_music',
        params: {'p_room_id': roomId},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[RoomSyncedMusic] stopForRoom error: $e');
    }
  }
}
