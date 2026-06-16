import 'package:flutter/foundation.dart';
import '../../features/rooms/models/room.dart';

/// Holds the currently minimized room session so the user can return to it
/// from anywhere in the app without having left the room on the backend.
///
/// Usage:
///   // Minimize: save the session (do NOT call leaveRoom first)
///   ActiveRoomSession.instance.minimize(room);
///
///   // Return to room: read the room, then clear
///   final room = ActiveRoomSession.instance.room;
///   ActiveRoomSession.instance.clear();
///
///   // Exit from the floating bar: call leaveRoom first, then clear
///   ActiveRoomSession.instance.clear();
class ActiveRoomSession extends ChangeNotifier {
  ActiveRoomSession._();
  static final instance = ActiveRoomSession._();

  Room? _room;
  Room? get room => _room;
  bool get isActive => _room != null;

  void minimize(Room room) {
    _room = room;
    notifyListeners();
  }

  void clear() {
    _room = null;
    notifyListeners();
  }
}
