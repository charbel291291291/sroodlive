import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// A single named event sound.
class GameSound {
  const GameSound(this.path);
  final String path;
}

/// Reusable two-player sound engine shared by game screens.
///
/// Two pooled [AudioPlayer]s:
///   * `tick`  — a short, rapidly-repeated sound (countdowns, spins). Debounced
///     so seek+play spam can't flood the underlying ExoPlayer pipeline.
///   * `event` — one-shot named sounds (bet/win/lose/…), lazy-loaded on first
///     play and cached so the same sound doesn't reload.
///
/// Safe by design — every entry point is a no-op if:
///   * audio failed to initialize,
///   * the requested asset is missing,
///   * the service has been disposed.
/// Nothing here ever throws to the caller, so a game keeps working with no sound.
class GameSoundService {
  GameSoundService({
    this.tag = 'GameSound',
    this.tickAsset,
    this.preloadEvent,
    this.events = const {},
    this.tickDebounce = const Duration(milliseconds: 120),
  });

  /// Short label used only for debug logging.
  final String tag;

  /// Asset for the tick player, or null to disable ticks.
  final String? tickAsset;

  /// Event name to pre-load into the event player at init (optional).
  final String? preloadEvent;

  /// Named events → dedicated asset.
  final Map<String, GameSound> events;

  /// Minimum spacing between tick plays.
  final Duration tickDebounce;

  AudioPlayer? _tick;
  AudioPlayer? _event;
  bool _disposed = false;

  /// When true, all playback is suppressed (respects a game/app mute setting).
  bool muted = false;

  String? _loadedEventPath;
  DateTime? _lastTickAt;

  /// Creates the players and preloads assets. If audio init fails, the service
  /// degrades to a silent no-op rather than throwing.
  Future<void> init() async {
    if (_disposed) return;
    try {
      _tick = AudioPlayer();
      _event = AudioPlayer();
    } catch (e) {
      debugPrint('[$tag] audio init failed — running silent: $e');
      _tick = null;
      _event = null;
      return;
    }
    if (tickAsset != null) {
      await _tryLoad(_tick!, tickAsset!);
    }
    final pre = preloadEvent;
    if (pre != null && events.containsKey(pre)) {
      final s = events[pre]!;
      await _tryLoad(_event!, s.path);
      _loadedEventPath = s.path;
    }
  }

  Future<void> _tryLoad(AudioPlayer p, String path) async {
    try {
      await p.setAsset(path);
    } catch (_) {}
  }

  /// Plays the debounced tick sound. Safe to call rapidly.
  void playTick() {
    if (_disposed || muted) return;
    final p = _tick;
    if (p == null) return;
    final now = DateTime.now();
    if (_lastTickAt != null && now.difference(_lastTickAt!) < tickDebounce) {
      return;
    }
    _lastTickAt = now;
    final st = p.processingState;
    if (st == ProcessingState.loading || st == ProcessingState.buffering) {
      return;
    }
    try {
      unawaited(p.seek(Duration.zero).then((_) {
        if (!_disposed) p.play();
      }));
    } catch (_) {}
  }

  /// Plays a named event sound. Unknown names are ignored.
  void playEvent(String name) {
    if (_disposed || muted) return;
    final s = events[name];
    if (s == null) return;
    unawaited(_doPlayEvent(s));
  }

  Future<void> _doPlayEvent(GameSound s) async {
    final p = _event;
    if (p == null || _disposed) return;
    try {
      if (_loadedEventPath != s.path) {
        await _tryLoad(p, s.path);
        _loadedEventPath = s.path;
      } else {
        await p.seek(Duration.zero);
      }
      if (_disposed) return;
      await p.play();
    } catch (e) {
      debugPrint('[$tag] event play error: $e');
    }
  }

  /// Stops any in-flight playback without disposing.
  Future<void> stopAll() async {
    try {
      await _tick?.stop();
    } catch (_) {}
    try {
      await _event?.stop();
    } catch (_) {}
  }

  /// Releases both players. After this, all play methods are no-ops.
  void dispose() {
    _disposed = true;
    _tick?.dispose();
    _event?.dispose();
    _tick = null;
    _event = null;
  }
}
