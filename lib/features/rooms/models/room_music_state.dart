/// Server-synced music playback state for a live room.
///
/// One row per room in `public.room_music_state`.
/// All clients subscribe via Realtime and drive their local [just_audio]
/// player from this state.
class RoomMusicState {
  const RoomMusicState({
    required this.roomId,
    this.trackId,
    this.trackTitle,
    this.trackArtist,
    this.trackUrl,
    required this.isPlaying,
    this.startedAt,
    this.pausedAt,
    required this.positionSeconds,
    required this.updatedAt,
    this.controllerUserId,
    this.autoReplay = false,
  });

  final String roomId;
  final String? trackId;
  final String? trackTitle;
  final String? trackArtist;
  final String? trackUrl;
  final bool isPlaying;

  /// UTC timestamp when playback began at [positionSeconds].
  /// Used by clients to compute the live playback position:
  ///   currentSec = positionSeconds + secondsSince(startedAt)
  final DateTime? startedAt;
  final DateTime? pausedAt;

  /// Playback position (seconds) recorded when [startedAt] / [pausedAt] was set.
  final int positionSeconds;
  final DateTime updatedAt;

  /// The user who started the current track.
  /// Only this user may pause, resume, stop, replay, or change tracks.
  final String? controllerUserId;

  /// When true, the controller's device restarts the same track when it ends.
  final bool autoReplay;

  bool get hasTrack => trackUrl != null && trackUrl!.isNotEmpty;

  bool get isStopped => !isPlaying && trackUrl == null;

  /// Best estimate of the current server-side playback position.
  /// Returns 0 when stopped or paused.
  int get livePositionSeconds {
    if (!isPlaying || startedAt == null) return positionSeconds;
    final elapsed = DateTime.now().toUtc().difference(startedAt!.toUtc());
    return (positionSeconds + elapsed.inSeconds).clamp(0, 86400);
  }

  factory RoomMusicState.fromJson(Map<String, dynamic> j) => RoomMusicState(
        roomId: j['room_id'].toString(),
        trackId: j['track_id'] as String?,
        trackTitle: j['track_title'] as String?,
        trackArtist: j['track_artist'] as String?,
        trackUrl: j['track_url'] as String?,
        isPlaying: (j['is_playing'] as bool?) ?? false,
        startedAt: _dt(j['started_at']),
        pausedAt: _dt(j['paused_at']),
        positionSeconds: (j['position_seconds'] as num?)?.toInt() ?? 0,
        updatedAt: _dt(j['updated_at']) ?? DateTime.now(),
        controllerUserId: j['controller_user_id'] as String?,
        autoReplay: (j['auto_replay'] as bool?) ?? false,
      );

  RoomMusicState copyWith({
    String? trackId,
    String? trackTitle,
    String? trackArtist,
    String? trackUrl,
    bool? isPlaying,
    DateTime? startedAt,
    DateTime? pausedAt,
    int? positionSeconds,
    DateTime? updatedAt,
    String? controllerUserId,
    bool? autoReplay,
  }) =>
      RoomMusicState(
        roomId: roomId,
        trackId: trackId ?? this.trackId,
        trackTitle: trackTitle ?? this.trackTitle,
        trackArtist: trackArtist ?? this.trackArtist,
        trackUrl: trackUrl ?? this.trackUrl,
        isPlaying: isPlaying ?? this.isPlaying,
        startedAt: startedAt ?? this.startedAt,
        pausedAt: pausedAt ?? this.pausedAt,
        positionSeconds: positionSeconds ?? this.positionSeconds,
        updatedAt: updatedAt ?? this.updatedAt,
        controllerUserId: controllerUserId ?? this.controllerUserId,
        autoReplay: autoReplay ?? this.autoReplay,
      );

  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
