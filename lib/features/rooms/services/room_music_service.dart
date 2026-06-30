import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/room_music.dart';

class RoomMusicService extends ChangeNotifier {
  RoomMusicService() {
    _player = AudioPlayer(handleInterruptions: false);
    _subs = [
      _player.playerStateStream.listen(_onPlayerState),
      _player.positionStream.listen(_onPosition),
      _player.durationStream.listen(_onDuration),
    ];
    _playlist = List<RoomSong>.from(kRoomMusicCatalog);
  }

  late final AudioPlayer _player;
  late final List<StreamSubscription<dynamic>> _subs;

  List<RoomSong> _playlist = [];
  final List<RoomSong> _favorites = [];
  final List<RoomSong> _localSongs = [];
  int _currentIndex = -1;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _loop = false;
  bool _shuffle = false;
  String? _error;
  double _volume = 1.0;

  void Function()? onSongCompleted;

  // ── Getters ───────────────────────────────────────────────────────────────

  List<RoomSong> get playlist => List.unmodifiable(_playlist);
  List<RoomSong> get favorites => List.unmodifiable(_favorites);
  List<RoomSong> get localSongs => List.unmodifiable(_localSongs);
  int get currentIndex => _currentIndex;
  RoomSong? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _playlist.length
      ? _playlist[_currentIndex]
      : null;
  Duration get position => _position;
  Duration? get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get isActive => currentSong != null;
  bool get loop => _loop;
  bool get shuffle => _shuffle;
  String? get error => _error;
  double get volume => _volume;

  bool isFavorite(String id) => _favorites.any((s) => s.id == id);

  // ── Validation ────────────────────────────────────────────────────────────

  static const _allowedExtensions = {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'};

  /// Returns an error description, or null if the source looks playable.
  String? _validateSource(RoomSong song) {
    if (song.sourceType == RoomSongSourceType.localFile) {
      final path = song.localPath;
      if (path == null || path.trim().isEmpty) {
        return 'Local path is empty for song "${song.title}"';
      }
      if (!File(path).existsSync()) {
        return 'Local file not found: $path  (song: "${song.title}")';
      }
      final ext = path.split('.').last.toLowerCase();
      if (!_allowedExtensions.contains(ext)) {
        return 'Unsupported local file type .$ext  (song: "${song.title}")';
      }
      return null;
    }

    // Remote URL
    final url = song.url.trim();
    if (url.isEmpty) {
      return 'URL is empty for song "${song.title}" (id: ${song.id})';
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Malformed URL "$url"  (song: "${song.title}")';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Unsupported URL scheme "${uri.scheme}" in "$url"';
    }

    // Warn if the URL looks like a Supabase Storage URL for a private bucket
    // (i.e., it has no "public" segment and no "token" query param for signed URLs)
    if (url.contains('supabase') &&
        url.contains('/storage/v1/object/') &&
        !url.contains('/public/') &&
        !url.contains('token=')) {
      // Log the warning but don't block — it may still work with a public bucket
      _log(
        'WARN',
        song,
        'URL appears to be a private Supabase Storage URL — '
            'ensure the "room_music" bucket is public or use signed URLs.',
      );
    }

    // Extension check (only if the path has a clear extension)
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      final last = segments.last;
      final dotIdx = last.lastIndexOf('.');
      if (dotIdx != -1) {
        final ext = last.substring(dotIdx + 1).toLowerCase().split('?').first;
        if (ext.isNotEmpty &&
            ext.length <= 5 &&
            !_allowedExtensions.contains(ext)) {
          return 'Unsupported audio format ".$ext" in "$url"';
        }
      }
    }

    return null;
  }

  /// Logs song details to the debug console before every load attempt.
  void _log(String level, RoomSong song, [String? extra]) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[RoomMusic:$level] ─────────────────────────────────');
    debugPrint('[RoomMusic:$level]  id       = ${song.id}');
    debugPrint('[RoomMusic:$level]  title    = "${song.title}"');
    debugPrint('[RoomMusic:$level]  artist   = "${song.artist}"');
    debugPrint('[RoomMusic:$level]  source   = ${song.sourceType.name}');
    debugPrint('[RoomMusic:$level]  url      = "${song.url}"');
    if (song.localPath != null) {
      debugPrint('[RoomMusic:$level]  local    = "${song.localPath}"');
    }
    if (extra != null) {
      debugPrint('[RoomMusic:$level]  note     = $extra');
    }
  }

  // ── Stream callbacks ──────────────────────────────────────────────────────

  void _onPlayerState(PlayerState s) {
    _isPlaying = s.playing;
    _isLoading =
        s.processingState == ProcessingState.loading ||
        s.processingState == ProcessingState.buffering;
    if (s.processingState == ProcessingState.completed) {
      if (onSongCompleted != null) {
        onSongCompleted!();
      } else {
        _advanceToNext();
      }
    }
    notifyListeners();
  }

  void _onPosition(Duration p) {
    _position = p;
    notifyListeners();
  }

  void _onDuration(Duration? d) {
    _duration = d;
    notifyListeners();
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  Future<void> playSong(int index) async {
    if (index < 0 || index >= _playlist.length) {
      return;
    }
    _currentIndex = index;
    _error = null;
    _isLoading = true;
    notifyListeners();

    final song = _playlist[index];
    _log('PLAY', song);

    // Validate before touching ExoPlayer
    final validationError = _validateSource(song);
    if (validationError != null) {
      debugPrint('[RoomMusic:ERROR] Validation failed: $validationError');
      _error = _friendlyError(validationError);
      _isLoading = false;
      notifyListeners();
      // Skip broken track — advance to the next one
      await _advanceToNext();
      return;
    }

    try {
      await _player.stop();

      if (song.sourceType == RoomSongSourceType.localFile &&
          song.localPath != null) {
        debugPrint('[RoomMusic:LOAD] setAudioSource(file) → ${song.localPath}');
        await _player.setAudioSource(
          AudioSource.uri(Uri.file(song.localPath!)),
        );
      } else {
        debugPrint('[RoomMusic:LOAD] setUrl → ${song.url}');
        await _player.setUrl(song.url);
      }

      await _player.play();
      debugPrint('[RoomMusic:OK] playback started for "${song.title}"');
    } on PlayerException catch (e) {
      // PlayerException carries the ExoPlayer error code and message
      debugPrint('[RoomMusic:PLAYER_ERROR] ─────────────────────────────────');
      debugPrint('[RoomMusic:PLAYER_ERROR]  code    = ${e.code}');
      debugPrint('[RoomMusic:PLAYER_ERROR]  message = ${e.message}');
      debugPrint('[RoomMusic:PLAYER_ERROR]  song id = ${song.id}');
      debugPrint('[RoomMusic:PLAYER_ERROR]  url     = "${song.url}"');
      _error = 'هذا الملف الصوتي لا يمكن تشغيله'; // friendly
      _isLoading = false;
      notifyListeners();
      // Skip to next track rather than hanging on the broken one
      await _advanceToNext();
    } catch (e, st) {
      debugPrint('[RoomMusic:ERROR] Unexpected error for "${song.title}": $e');
      if (kDebugMode) {
        debugPrintStack(stackTrace: st, label: 'RoomMusicService.playSong');
      }
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load a song and seek to [seekTo] without starting playback.
  Future<void> loadSongPaused(
    int index, {
    Duration seekTo = Duration.zero,
  }) async {
    if (index < 0 || index >= _playlist.length) {
      return;
    }
    _currentIndex = index;
    _error = null;
    _isLoading = true;
    notifyListeners();

    final song = _playlist[index];
    _log('LOAD_PAUSED', song);

    final validationError = _validateSource(song);
    if (validationError != null) {
      debugPrint(
        '[RoomMusic:ERROR] Validation failed (paused load): $validationError',
      );
      _error = _friendlyError(validationError);
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      await _player.stop();

      if (song.sourceType == RoomSongSourceType.localFile &&
          song.localPath != null) {
        debugPrint(
          '[RoomMusic:LOAD] setAudioSource(file/paused) → ${song.localPath}',
        );
        await _player.setAudioSource(
          AudioSource.uri(Uri.file(song.localPath!)),
        );
      } else {
        debugPrint('[RoomMusic:LOAD] setUrl(paused) → ${song.url}');
        await _player.setUrl(song.url);
      }

      if (seekTo > Duration.zero) {
        await _player.seek(seekTo);
      }
      _isLoading = false;
      notifyListeners();
    } on PlayerException catch (e) {
      debugPrint(
        '[RoomMusic:PLAYER_ERROR] loadSongPaused ─────────────────────',
      );
      debugPrint('[RoomMusic:PLAYER_ERROR]  code    = ${e.code}');
      debugPrint('[RoomMusic:PLAYER_ERROR]  message = ${e.message}');
      debugPrint('[RoomMusic:PLAYER_ERROR]  url     = "${song.url}"');
      _error = _friendlyError('${e.code}: ${e.message}');
      _isLoading = false;
      notifyListeners();
    } catch (e, st) {
      debugPrint('[RoomMusic:ERROR] loadSongPaused unexpected: $e');
      if (kDebugMode) {
        debugPrintStack(
          stackTrace: st,
          label: 'RoomMusicService.loadSongPaused',
        );
      }
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> playPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else if (_currentIndex >= 0) {
      await _player.play();
    } else if (_playlist.isNotEmpty) {
      await playSong(0);
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _currentIndex = -1;
    _position = Duration.zero;
    _duration = null;
    notifyListeners();
  }

  Future<void> next() => _advanceToNext();
  Future<void> previous() async {
    if (_playlist.isEmpty) {
      return;
    }
    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    final prev = _currentIndex > 0 ? _currentIndex - 1 : _playlist.length - 1;
    await playSong(prev);
  }

  Future<void> _advanceToNext() async {
    if (_playlist.isEmpty) return;
    if (_loop) return;
    final next = _shuffle
        ? (DateTime.now().millisecondsSinceEpoch % _playlist.length)
        : (_currentIndex + 1) % _playlist.length;
    await playSong(next);
  }

  Future<void> seek(Duration pos) => _player.seek(pos);

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    notifyListeners();
  }

  Future<void> toggleLoop() async {
    _loop = !_loop;
    await _player.setLoopMode(_loop ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    notifyListeners();
  }

  // ── Playlist management ───────────────────────────────────────────────────

  void addToPlaylist(RoomSong song) {
    if (_playlist.any((s) => s.id == song.id)) {
      return;
    }
    _playlist.add(song);
    notifyListeners();
  }

  void removeFromPlaylist(String songId) {
    final idx = _playlist.indexWhere((s) => s.id == songId);
    if (idx < 0) {
      return;
    }
    if (idx == _currentIndex) {
      _player.stop();
      _currentIndex = -1;
    } else if (idx < _currentIndex) {
      _currentIndex--;
    }
    _playlist.removeAt(idx);
    notifyListeners();
  }

  void addLocalSong(RoomSong song) {
    if (_localSongs.any((s) => s.id == song.id)) {
      return;
    }
    _localSongs.add(song);
    notifyListeners();
  }

  void removeLocalSong(String songId) {
    _localSongs.removeWhere((s) => s.id == songId);
    notifyListeners();
  }

  void clearLocalSongs() {
    _localSongs.clear();
    notifyListeners();
  }

  void toggleFavorite(RoomSong song) {
    final idx = _favorites.indexWhere((s) => s.id == song.id);
    if (idx >= 0) {
      _favorites.removeAt(idx);
    } else {
      _favorites.add(song);
    }
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _friendlyError(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('empty') || l.contains('null')) {
      return 'لا يوجد مسار صوتي';
    }
    if (l.contains('not found') || l.contains('404')) {
      return 'الملف الصوتي غير موجود';
    }
    if (l.contains('unsupported') ||
        l.contains('format') ||
        l.contains('1004')) {
      return 'صيغة الملف غير مدعومة';
    }
    if (l.contains('network') ||
        l.contains('timeout') ||
        l.contains('connection')) {
      return 'خطأ في الاتصال بالإنترنت';
    }
    return 'هذا الملف الصوتي لا يمكن تشغيله';
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
