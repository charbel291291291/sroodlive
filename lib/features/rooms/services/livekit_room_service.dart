import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'livekit_token_service.dart';

class LiveKitRoomService {
  LiveKitRoomService({LiveKitTokenService? tokenService})
    : _tokenService = tokenService ?? const LiveKitTokenService();

  final LiveKitTokenService _tokenService;

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  void Function(Set<String> speakingIdentities)? onSpeakersChanged;

  Room? get room => _room;

  Future<Room> connect({
    required String roomId,
    bool microphoneEnabled = true,
  }) async {
    // Clean up any previous connection
    await disconnect();

    final tokenResponse = await _tokenService.getToken(roomId: roomId);

    final room = Room(
      // speakerOn:true routes remote audio to the loudspeaker on mobile so a
      // listener actually hears the room (the default earpiece route is easy to
      // miss in a social audio room).
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioOutputOptions: AudioOutputOptions(speakerOn: true),
      ),
    );

    _setupEventListeners(room);

    debugPrint('[LiveKit] Connecting to ${tokenResponse.url} …');
    await room.connect(tokenResponse.url, tokenResponse.token);

    debugPrint(
      '[LiveKit] Connected. '
      'localParticipant=${room.localParticipant?.identity} '
      'remoteParticipants=${room.remoteParticipants.length}',
    );

    // Force loudspeaker output so remote participants are audible.
    try {
      await room.setSpeakerOn(true);
    } catch (e) {
      debugPrint('[LiveKit] setSpeakerOn failed: $e');
    }

    // Enable microphone AFTER connection so the track is published. Listeners
    // connect with microphoneEnabled=false — they still subscribe and hear.
    await room.localParticipant?.setMicrophoneEnabled(microphoneEnabled);
    debugPrint('[LiveKit] Microphone enabled=$microphoneEnabled');

    _room = room;
    return room;
  }

  void _setupEventListeners(Room room) {
    final listener = room.createListener();
    _listener = listener;

    listener
      ..on<RoomConnectedEvent>((_) {
        debugPrint('[LiveKit] RoomConnectedEvent');
      })
      ..on<RoomDisconnectedEvent>((e) {
        debugPrint('[LiveKit] RoomDisconnectedEvent reason=${e.reason}');
      })
      ..on<ParticipantConnectedEvent>((e) {
        debugPrint(
          '[LiveKit] ParticipantConnectedEvent identity=${e.participant.identity}',
        );
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        debugPrint(
          '[LiveKit] ParticipantDisconnectedEvent identity=${e.participant.identity}',
        );
      })
      ..on<TrackPublishedEvent>((e) {
        debugPrint(
          '[LiveKit] TrackPublishedEvent kind=${e.publication.kind} '
          'by=${e.participant.identity} sid=${e.publication.sid}',
        );
      })
      ..on<TrackUnpublishedEvent>((e) {
        debugPrint(
          '[LiveKit] TrackUnpublishedEvent kind=${e.publication.kind} '
          'by=${e.participant.identity}',
        );
      })
      ..on<TrackSubscribedEvent>((e) {
        debugPrint(
          '[LiveKit] TrackSubscribedEvent kind=${e.track.kind} '
          'from=${e.participant.identity} muted=${e.track.muted}',
        );
      })
      ..on<TrackUnsubscribedEvent>((e) {
        debugPrint(
          '[LiveKit] TrackUnsubscribedEvent kind=${e.track.kind} '
          'from=${e.participant.identity}',
        );
      })
      ..on<TrackMutedEvent>((e) {
        debugPrint(
          '[LiveKit] TrackMutedEvent kind=${e.publication.kind} '
          'by=${e.participant.identity}',
        );
      })
      ..on<TrackUnmutedEvent>((e) {
        debugPrint(
          '[LiveKit] TrackUnmutedEvent kind=${e.publication.kind} '
          'by=${e.participant.identity}',
        );
      })
      ..on<ActiveSpeakersChangedEvent>((e) {
        debugPrint(
          '[LiveKit] ActiveSpeakersChangedEvent count=${e.speakers.length}',
        );
        final ids = e.speakers.map((p) => p.identity).toSet();
        onSpeakersChanged?.call(ids);
      });
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    debugPrint('[LiveKit] setMicrophoneEnabled($enabled)');
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
  }

  Future<void> disconnect() async {
    _listener?.dispose();
    _listener = null;
    if (_room != null) {
      debugPrint('[LiveKit] Disconnecting …');
      await _room?.disconnect();
      _room = null;
      debugPrint('[LiveKit] Disconnected');
    }
  }
}
