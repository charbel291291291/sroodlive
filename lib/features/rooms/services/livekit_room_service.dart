import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'livekit_token_service.dart';

class LiveKitRoomService {
  LiveKitRoomService({LiveKitTokenService? tokenService})
    : _tokenService = tokenService ?? const LiveKitTokenService();

  final LiveKitTokenService _tokenService;

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  // Last room-id we connected to — used for reconnect after backgrounding.
  String? _lastRoomId;
  bool _lastMicEnabled = false;

  void Function(Set<String> speakingIdentities)? onSpeakersChanged;

  Room? get room => _room;

  bool get isConnected =>
      _room != null &&
      _room!.connectionState == ConnectionState.connected;

  Future<Room> connect({
    required String roomId,
    bool microphoneEnabled = true,
  }) async {
    // Clean up any previous connection first.
    await disconnect(invalidateToken: false);

    _lastRoomId = roomId;
    _lastMicEnabled = microphoneEnabled;

    _log(
      '[LiveKit] ${_ts()} token requested roomId=$roomId',
    );
    final tokenResponse = await _tokenService.getToken(roomId: roomId);
    _log('[LiveKit] ${_ts()} token received — connecting…');

    _log('[VoiceQuality] echoCancellation enabled');
    _log('[VoiceQuality] noiseSuppression enabled');
    _log('[VoiceQuality] autoGainControl enabled');
    _log('[VoiceQuality] highPassFilter enabled');
    _log('[VoiceQuality] typingNoiseDetection enabled');

    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        // Explicit audio processing flags — applied to every mic track published.
        defaultAudioCaptureOptions: AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          highPassFilter: true,
          typingNoiseDetection: true,
        ),
        defaultAudioOutputOptions: AudioOutputOptions(speakerOn: true),
      ),
    );

    _setupEventListeners(room);

    await room.connect(tokenResponse.url, tokenResponse.token);
    _log(
      '[LiveKit] ${_ts()} connected '
      'local=${room.localParticipant?.identity} '
      'remote=${room.remoteParticipants.length}',
    );

    // Force loudspeaker so remote participants are audible without earpiece.
    try {
      await room.setSpeakerOn(true);
    } catch (e) {
      _log('[LiveKit] setSpeakerOn failed: $e');
    }

    // Publish mic track only for speakers/hosts; listeners connect mic-off.
    await room.localParticipant?.setMicrophoneEnabled(microphoneEnabled);
    _log('[LiveKit] ${_ts()} mic enabled=$microphoneEnabled');

    _room = room;
    return room;
  }

  /// Reconnects using the same roomId + mic state from the last [connect] call.
  /// Safe to call on app resume — no-ops if already connected.
  Future<void> reconnectIfNeeded() async {
    if (isConnected) return;
    final roomId = _lastRoomId;
    if (roomId == null) return;
    _log('[LiveKit] ${_ts()} reconnecting to $roomId…');
    try {
      await connect(roomId: roomId, microphoneEnabled: _lastMicEnabled);
    } catch (e) {
      _log('[LiveKit] reconnect failed: $e');
    }
  }

  void _setupEventListeners(Room room) {
    final listener = room.createListener();
    _listener = listener;

    listener
      ..on<RoomConnectedEvent>((_) {
        _log('[LiveKit] ${_ts()} RoomConnectedEvent');
      })
      ..on<RoomDisconnectedEvent>((e) {
        _log('[LiveKit] ${_ts()} RoomDisconnectedEvent reason=${e.reason}');
      })
      ..on<ParticipantConnectedEvent>((e) {
        _log('[LiveKit] ParticipantConnected id=${e.participant.identity}');
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        _log(
          '[LiveKit] ParticipantDisconnected id=${e.participant.identity}',
        );
      })
      ..on<TrackPublishedEvent>((e) {
        _log(
          '[LiveKit] TrackPublished kind=${e.publication.kind} '
          'by=${e.participant.identity}',
        );
      })
      ..on<TrackUnpublishedEvent>((e) {
        _log(
          '[LiveKit] TrackUnpublished kind=${e.publication.kind} '
          'by=${e.participant.identity}',
        );
      })
      ..on<TrackSubscribedEvent>((e) {
        _log(
          '[LiveKit] TrackSubscribed kind=${e.track.kind} '
          'from=${e.participant.identity} muted=${e.track.muted}',
        );
      })
      ..on<TrackUnsubscribedEvent>((e) {
        _log(
          '[LiveKit] TrackUnsubscribed kind=${e.track.kind} '
          'from=${e.participant.identity}',
        );
      })
      ..on<TrackMutedEvent>((e) {
        _log(
          '[LiveKit] TrackMuted kind=${e.publication.kind} '
          'by=${e.participant.identity}',
        );
      })
      ..on<TrackUnmutedEvent>((e) {
        _log(
          '[LiveKit] TrackUnmuted kind=${e.publication.kind} '
          'by=${e.participant.identity}',
        );
      })
      ..on<ActiveSpeakersChangedEvent>((e) {
        final ids = e.speakers.map((p) => p.identity).toSet();
        onSpeakersChanged?.call(ids);
      });
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    _lastMicEnabled = enabled;
    _log('[LiveKit] ${_ts()} setMicrophoneEnabled($enabled)');
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
  }

  Future<void> disconnect({bool invalidateToken = true}) async {
    _listener?.dispose();
    _listener = null;
    if (_room != null) {
      _log('[LiveKit] ${_ts()} disconnecting…');
      await _room?.disconnect();
      _room = null;
      _log('[LiveKit] disconnected');
    }
    if (invalidateToken && _lastRoomId != null) {
      LiveKitTokenService.invalidate(_lastRoomId!);
    }
  }

  // Gated logging — interpolation and printing are skipped entirely in release
  // builds, so the high-frequency audio event listeners add no overhead in
  // production.
  static void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  static String _ts() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }
}
