import 'package:flutter/services.dart';

class CrashV3AudioService {
  bool enabled = true;
  Future<void> cue() async {
    if (enabled) await SystemSound.play(SystemSoundType.click);
  }

  void toggle() => enabled = !enabled;
  Future<void> dispose() async {}
}
