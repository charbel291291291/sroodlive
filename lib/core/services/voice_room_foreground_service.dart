import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the Android foreground-service method channel.
/// On non-Android platforms (or when the channel is unavailable) all calls
/// are silently ignored so the rest of the app never needs to guard on platform.
class VoiceRoomForegroundService {
  VoiceRoomForegroundService._();

  static const _channel = MethodChannel('com.example.srood_live/voice_room');

  /// Start the foreground service (shows the persistent notification and keeps
  /// the process alive while the screen is off).
  static Future<void> start() async {
    if (!defaultTargetPlatform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start');
      debugPrint('[VoiceRoomFG] foreground service started');
    } catch (e) {
      debugPrint('[VoiceRoomFG] start failed: $e');
    }
  }

  /// Stop the foreground service when the user leaves or closes the room.
  static Future<void> stop() async {
    if (!defaultTargetPlatform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
      debugPrint('[VoiceRoomFG] foreground service stopped');
    } catch (e) {
      debugPrint('[VoiceRoomFG] stop failed: $e');
    }
  }
}

extension on TargetPlatform {
  bool get isAndroid => this == TargetPlatform.android;
}
