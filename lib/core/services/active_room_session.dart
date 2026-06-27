import 'package:flutter/foundation.dart';
import '../../features/rooms/models/room.dart';
import '../../features/rooms/services/livekit_room_service.dart';
import '../../features/rooms/services/room_music_service.dart';
import '../../features/rooms/services/room_synced_music_service.dart';

/// Holds the currently minimized room session so the user can return to it
/// from anywhere in the app without disconnecting from LiveKit or music.
///
/// Lifecycle:
///   minimize(room, lk, music, synced) — screen transfers ownership before popping.
///   clear()                           — screen takes ownership on restore; no disconnect.
///   leave()                           — floating bar exit; disconnects + disposes all.
class ActiveRoomSession extends ChangeNotifier {
  ActiveRoomSession._();
  static final instance = ActiveRoomSession._();

  Room? _room;
  LiveKitRoomService? _liveKitService;
  RoomMusicService? _musicService;
  RoomSyncedMusicService? _syncedMusicService;
  bool _micEnabled = false;

  Room? get room => _room;
  LiveKitRoomService? get liveKitService => _liveKitService;
  RoomMusicService? get musicService => _musicService;
  RoomSyncedMusicService? get syncedMusicService => _syncedMusicService;
  bool get isActive => _room != null;

  /// Mic state at the moment of minimize — used to restore indicator in
  /// the floating bar.
  bool get savedMicEnabled => _micEnabled;

  /// Called by [RoomDetailsScreen] just before it pops (minimize action).
  /// Ownership of all services transfers here so audio and music continue.
  void minimize(
    Room room,
    LiveKitRoomService lkService, {
    bool micEnabled = false,
    RoomMusicService? musicService,
    RoomSyncedMusicService? syncedMusicService,
  }) {
    debugPrint('[RoomMinimize] session.minimize roomId=${room.id} mic=$micEnabled '
        'hasMusic=${musicService != null}');
    _room = room;
    _liveKitService = lkService;
    _musicService = musicService;
    _syncedMusicService = syncedMusicService;
    _micEnabled = micEnabled;
    notifyListeners();
  }

  /// Called when the restored [RoomDetailsScreen] takes ownership of the
  /// services back. Does NOT disconnect or dispose anything.
  void clear() {
    debugPrint('[RoomMinimize] session.clear (screen taking ownership)');
    _room = null;
    _liveKitService = null;
    _musicService = null;
    _syncedMusicService = null;
    _micEnabled = false;
    notifyListeners();
  }

  /// Called from the floating bar X button (leave without returning to room).
  /// Disconnects LiveKit, disposes music, then clears.
  Future<void> leave() async {
    debugPrint('[RoomMinimize] session.leave — disconnecting LiveKit + stopping music');
    final lk = _liveKitService;
    final music = _musicService;
    final synced = _syncedMusicService;
    _room = null;
    _liveKitService = null;
    _musicService = null;
    _syncedMusicService = null;
    _micEnabled = false;
    notifyListeners();
    if (lk != null) await lk.disconnect();
    if (synced != null) await synced.dispose();
    if (music != null) music.dispose();
    debugPrint('[RoomMusic] music service disposed on leave');
  }
}
