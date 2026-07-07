import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class CrashRocketSoundService {
  final AudioPlayer _ambient = AudioPlayer();
  final AudioPlayer _flight = AudioPlayer();
  final AudioPlayer _tick = AudioPlayer();
  final AudioPlayer _event = AudioPlayer();

  bool _ready = false;
  bool _muted = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_ready || _disposed) return;
    try {
      await Future.wait([
        _ambient.setAsset('assets/sounds/rocket_ambient.wav'),
        _flight.setAsset('assets/sounds/rocket_flight.wav'),
        _tick.setAsset('assets/sounds/rocket_tick.wav'),
      ]);
      await _ambient.setLoopMode(LoopMode.one);
      await _flight.setLoopMode(LoopMode.one);
      await _ambient.setVolume(0.16);
      await _flight.setVolume(0.24);
      await _tick.setVolume(0.34);
      await _event.setVolume(0.42);
      if (_disposed) return;
      _ready = true;
      if (!_muted) unawaited(_ambient.play());
    } catch (error) {
      debugPrint('[SroodRocketSound] initialization failed: $error');
    }
  }

  Future<void> setMuted(bool muted) async {
    _muted = muted;
    if (!_ready || _disposed) return;
    await Future.wait([
      _ambient.setVolume(muted ? 0 : 0.16),
      _flight.setVolume(muted ? 0 : 0.24),
      _tick.setVolume(muted ? 0 : 0.34),
      _event.setVolume(muted ? 0 : 0.42),
    ]);
  }

  void playTick() {
    if (!_canPlay) return;
    unawaited(_restart(_tick));
  }

  void playLaunch() {
    _playEvent('assets/sounds/rocket_launch.wav');
  }

  void startFlight() {
    if (!_canPlay) return;
    unawaited(_restart(_flight));
  }

  void stopFlight() {
    if (!_ready || _disposed) return;
    unawaited(_flight.stop());
  }

  void playCashout() {
    _playEvent('assets/sounds/rocket_cashout.wav');
  }

  void playCrash() {
    stopFlight();
    _playEvent('assets/sounds/rocket_crash.wav');
  }

  void playThreshold({required bool premium}) {
    _playEvent(
      premium
          ? 'assets/sounds/rocket_jackpot.wav'
          : 'assets/sounds/rocket_threshold.wav',
    );
  }

  void playTap() {
    _playEvent('assets/sounds/rocket_tap.wav', volume: 0.24);
  }

  bool get _canPlay => _ready && !_muted && !_disposed;

  Future<void> _restart(AudioPlayer player) async {
    try {
      await player.seek(Duration.zero);
      await player.play();
    } catch (error) {
      debugPrint('[SroodRocketSound] playback failed: $error');
    }
  }

  void _playEvent(String asset, {double volume = 0.42}) {
    if (!_canPlay) return;
    unawaited(() async {
      try {
        await _event.stop();
        await _event.setAsset(asset);
        await _event.setVolume(volume);
        await _event.play();
      } catch (error) {
        debugPrint('[SroodRocketSound] event failed for $asset: $error');
      }
    }());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait([
      _ambient.dispose(),
      _flight.dispose(),
      _tick.dispose(),
      _event.dispose(),
    ]);
  }
}
