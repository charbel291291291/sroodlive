import 'package:livekit_client/livekit_client.dart';

import 'livekit_token_service.dart';

class LiveKitRoomService {
  LiveKitRoomService({
    LiveKitTokenService? tokenService,
  }) : _tokenService = tokenService ?? const LiveKitTokenService();

  final LiveKitTokenService _tokenService;

  Room? _room;

  Room? get room => _room;

  Future<Room> connect({
    required String roomId,
    bool microphoneEnabled = true,
  }) async {
    final tokenResponse = await _tokenService.getToken(roomId: roomId);

    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      ),
    );

    await room.connect(
      tokenResponse.url,
      tokenResponse.token,
    );

    await room.localParticipant?.setMicrophoneEnabled(microphoneEnabled);

    _room = room;

    return room;
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
  }

  Future<void> disconnect() async {
    await _room?.disconnect();
    _room = null;
  }
}

