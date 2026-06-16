import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/room_music.dart';

class RoomMusicService extends ChangeNotifier {
  RoomMusicService() {
    _player = AudioPlayer();
    _subs = [
      _player.playerStateStream.listen(_onPlayerState),
      _player.positionStream.listen(_onPosition),
      _player.durationStream.listen(_onDuration),
    ];
    // Playlist starts with the full catalog; users can also add custom songs.
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

  // ── Stream callbacks ──────────────────────────────────────────────────────

  void _onPlayerState(PlayerState s) {
    _isPlaying = s.playing;
    _isLoading = s.processingState == ProcessingState.loading ||
        s.processingState == ProcessingState.buffering;
    if (s.processingState == ProcessingState.completed) _advanceToNext();
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
    if (index < 0 || index >= _playlist.length) return;
    _currentIndex = index;
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      await _player.stop();
      final song = _playlist[index];
      if (song.sourceType == RoomSongSourceType.localFile &&
          song.localPath != null) {
        await _player
            .setAudioSource(AudioSource.uri(Uri.file(song.localPath!)));
      } else {
        await _player.setUrl(song.url);
      }
      await _player.play();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load a song and seek to [seekTo] without starting playback.
  /// Used by the sync service to restore paused state for late joiners.
  Future<void> loadSongPaused(int index, {Duration seekTo = Duration.zero}) async {
    if (index < 0 || index >= _playlist.length) return;
    _currentIndex = index;
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      await _player.stop();
      final song = _playlist[index];
      if (song.sourceType == RoomSongSourceType.localFile &&
          song.localPath != null) {
        await _player.setAudioSource(AudioSource.uri(Uri.file(song.localPath!)));
      } else {
        await _player.setUrl(song.url);
      }
      if (seekTo > Duration.zero) await _player.seek(seekTo);
      // Do NOT call play() — this is load-only.
      _isLoading = false;
      notifyListeners();
    } catch (e) {
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
    if (_playlist.isEmpty) return;
    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    final prev = _currentIndex > 0 ? _currentIndex - 1 : _playlist.length - 1;
    await playSong(prev);
  }

  Future<void> _advanceToNext() async {
    if (_playlist.isEmpty) return;
    if (_loop) return; // LoopMode.one handles it
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
    if (_playlist.any((s) => s.id == song.id)) return;
    _playlist.add(song);
    notifyListeners();
  }

  void removeFromPlaylist(String songId) {
    final idx = _playlist.indexWhere((s) => s.id == songId);
    if (idx < 0) return;
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
    if (_localSongs.any((s) => s.id == song.id)) return;
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
