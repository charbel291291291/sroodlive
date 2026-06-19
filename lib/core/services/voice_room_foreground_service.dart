import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper around the Android foreground-service method channel.
///
/// The foreground service keeps the mic alive while the screen is off. It is
/// strictly optional: if the OS rejects it (targetSDK 36 / Android 14+ state
/// rules, or RECORD_AUDIO not yet granted) the room still opens and the user
/// can still speak while the app is foregrounded.
///
/// On non-Android platforms all calls are no-ops.
class VoiceRoomForegroundService {
  VoiceRoomForegroundService._();

  static const _channel = MethodChannel('com.example.srood_live/voice_room');

  /// Start the foreground service. Safe to call before `await`ing mic permission
  /// — the method checks permission first and skips the native call when it has
  /// not been granted yet.
  static Future<void> start() async {
    if (!_isAndroid) return;
    try {
      final granted =
          await Permission.microphone.status == PermissionStatus.granted;
      debugPrint('[VoiceRoomFG] microphone permission granted=$granted');
      if (!granted) {
        debugPrint(
          '[VoiceRoomFG] continuing without foreground service'
          ' (microphone permission not granted)',
        );
        return;
      }
      debugPrint('[VoiceRoomFG] starting foreground service');
      await _channel.invokeMethod<void>('start');
      debugPrint('[VoiceRoomFG] service started');
    } catch (e) {
      debugPrint('[VoiceRoomFG] service unavailable reason=$e');
      debugPrint('[VoiceRoomFG] continuing without foreground service');
    }
  }

  /// Stop the foreground service when the user leaves or closes the room.
  static Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
      debugPrint('[VoiceRoomFG] service stopped');
    } catch (e) {
      debugPrint('[VoiceRoomFG] stop failed: $e');
    }
  }

  static bool get _isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;
}
