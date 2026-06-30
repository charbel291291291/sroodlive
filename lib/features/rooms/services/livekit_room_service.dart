import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'livekit_token_service.dart';

class LiveKitRoomService {
  LiveKitRoomService({LiveKitTokenService? tokenService})
    : _tokenService = tokenService ?? const LiveKitTokenService();

  final LiveKitTokenService _tokenService;

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  StreamSubscription<dynamic>? _audioDevicesSub;

  // Last room-id we connected to -- used for reconnect after backgrounding.
  String? _lastRoomId;
  bool _lastMicEnabled = false;

  // True while the room library is in its internal reconnect cycle.
  // Outgoing sends are blocked until the cycle completes.
  bool _isReconnecting = false;

  // Mic state that was requested while the socket was not connected.
  // Applied exactly once when the socket reaches ConnectionState.connected.
  bool? _pendingMicEnabled;

  void Function(Set<String> speakingIdentities)? onSpeakersChanged;

  /// Called once the socket reaches ConnectionState.connected — either on the
  /// initial join or after a successful reconnect.  The room screen uses this
  /// to trigger a single controlled resync of mic/music/seat state.
  void Function()? onConnected;

  Room? get room => _room;

  bool get isConnected =>
      _room != null && _room!.connectionState == ConnectionState.connected;

  bool get isReconnecting => _isReconnecting;

  // ── Safe send helper ──────────────────────────────────────────────────────

  /// Runs [action] only when the LiveKit socket is fully connected.
  /// Logs and silently skips the call if the socket is not ready.
  Future<void> runWhenConnected(
    Future<void> Function() action, {
    String label = 'LiveKit action',
  }) async {
    if (!isConnected) {
      _log(
        '[$label] skipped — socket not connected '
        '(state=${_room?.connectionState})',
      );
      return;
    }
    try {
      await action();
    } catch (e, st) {
      _log('[$label] failed: $e');
      if (kDebugMode) debugPrintStack(stackTrace: st, label: label);
    }
  }

  Future<Room> connect({
    required String roomId,
    bool microphoneEnabled = true,
  }) async {
    // Clean up any previous connection first.
    await disconnect(invalidateToken: false);

    _lastRoomId = roomId;
    _lastMicEnabled = microphoneEnabled;

    _log('[LiveKit] ${_ts()} token requested roomId=$roomId');
    final tokenResponse = await _tokenService.getToken(roomId: roomId);
    _log('[LiveKit] ${_ts()} token received - connecting...');

    _log('[VoiceQuality] echoCancellation enabled');
    _log('[VoiceQuality] noiseSuppression enabled');
    _log('[VoiceQuality] autoGainControl enabled');
    _log('[VoiceQuality] highPassFilter enabled');
    _log('[VoiceQuality] typingNoiseDetection enabled');

    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        // Explicit audio processing flags -- applied to every mic track published.
        defaultAudioCaptureOptions: AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          highPassFilter: true,
          typingNoiseDetection: true,
          voiceIsolation: true,
        ),
        // speakerOn is NOT set here -- we handle routing after connect
        // so we can check whether headphones are plugged in first.
        defaultAudioOutputOptions: AudioOutputOptions(),
      ),
    );

    _setupEventListeners(room);

    await room.connect(tokenResponse.url, tokenResponse.token);
    _log(
      '[LiveKit] ${_ts()} connected '
      'local=${room.localParticipant?.identity} '
      'remote=${room.remoteParticipants.length}',
    );

    // Route audio to loudspeaker only when no headset is attached.
    // Calling setSpeakerOn(true) unconditionally overrides wired/BT headset
    // routing on Android and iOS, causing users to hear nothing in earphones.
    await _applyAudioRouting(room);

    // Publish mic track only for speakers/hosts; listeners connect mic-off.
    await room.localParticipant?.setMicrophoneEnabled(microphoneEnabled);
    _log('[LiveKit] ${_ts()} mic enabled=$microphoneEnabled');

    _room = room;
    return room;
  }

  /// Reconnects using the same roomId + mic state from the last [connect] call.
  /// Safe to call on app resume -- no-ops if already connected.
  Future<void> reconnectIfNeeded() async {
    if (isConnected) return;
    final roomId = _lastRoomId;
    if (roomId == null) return;
    _log('[LiveKit] ${_ts()} reconnecting to $roomId...');
    try {
      await connect(roomId: roomId, microphoneEnabled: _lastMicEnabled);
    } catch (e) {
      _log('[LiveKit] reconnect failed: $e');
    }
  }

  /// Applies and clears the pending mic state that was saved while the socket
  /// was disconnected.  Must only be called when [isConnected] is already true.
  Future<void> _applyPendingMicState() async {
    final pending = _pendingMicEnabled;
    if (pending == null) return;
    _pendingMicEnabled = null;
    _log(
      '[LiveKitGuard] reconnect resync applied — applying pending mic=$pending',
    );
    await setMicrophoneEnabled(pending);
  }

  void _setupEventListeners(Room room) {
    final listener = room.createListener();
    _listener = listener;

    listener
      ..on<RoomConnectedEvent>((_) async {
        _isReconnecting = false;
        _log('[LiveKit] ${_ts()} RoomConnectedEvent');
        await _applyPendingMicState();
        onConnected?.call();
      })
      ..on<RoomReconnectingEvent>((_) {
        _isReconnecting = true;
        _log(
          '[LiveKit] ${_ts()} RoomReconnectingEvent — outgoing sends blocked',
        );
      })
      ..on<RoomReconnectedEvent>((_) async {
        _isReconnecting = false;
        _log('[LiveKit] ${_ts()} RoomReconnectedEvent — sends unblocked');
        await _applyPendingMicState();
        onConnected?.call();
      })
      ..on<RoomDisconnectedEvent>((e) {
        _isReconnecting = false;
        _log('[LiveKit] ${_ts()} RoomDisconnectedEvent reason=${e.reason}');
      })
      ..on<ParticipantConnectedEvent>((e) {
        _log('[LiveKit] ParticipantConnected id=${e.participant.identity}');
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        _log('[LiveKit] ParticipantDisconnected id=${e.participant.identity}');
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

  /// Returns true when any wired or Bluetooth audio output is connected.
  Future<bool> _headsetConnected() async {
    try {
      final session = await AudioSession.instance;
      final devices = await session.getDevices(includeInputs: false);
      // Avoid depending on experimental AudioDeviceType enum -- match type name strings.
      return devices.any((d) {
        final t = d.type.toString().toLowerCase();
        return t.contains('wired') ||
            t.contains('bluetooth') ||
            t.contains('headphone') ||
            t.contains('headset');
      });
    } catch (e) {
      _log('[LiveKit] headsetConnected check failed: $e');
      return false; // safe default: don't force speaker if unsure
    }
  }

  /// Routes audio to the loudspeaker only when no headset is plugged in.
  /// Also subscribes to device changes so plugging/unplugging while in the
  /// room re-applies the correct routing automatically.
  Future<void> _applyAudioRouting(Room room) async {
    final headset = await _headsetConnected();
    _log('[LiveKit] headsetConnected=$headset -> setSpeakerOn=${!headset}');
    try {
      await room.setSpeakerOn(!headset);
    } catch (e) {
      _log('[LiveKit] setSpeakerOn failed: $e');
    }

    // Re-route whenever a headset is plugged in or removed mid-session.
    try {
      final session = await AudioSession.instance;
      await _audioDevicesSub?.cancel();
      _audioDevicesSub = session.devicesChangedEventStream.listen((_) async {
        if (_room == null) return;
        final nowHasHeadset = await _headsetConnected();
        _log('[LiveKit] devices changed - headset=$nowHasHeadset');
        try {
          await _room?.setSpeakerOn(!nowHasHeadset);
        } catch (e) {
          _log('[LiveKit] setSpeakerOn on device change failed: $e');
        }
      });
    } catch (e) {
      _log('[LiveKit] devicesChangedEventStream unavailable: $e');
    }
  }

  /// Whether a local audio track is already published (even if muted).
  bool get hasPublishedAudioTrack =>
      _room?.localParticipant?.audioTrackPublications.isNotEmpty == true;

  /// The first (and normally only) local audio track publication, if any.
  LocalTrackPublication<LocalAudioTrack>? get _localAudioPub =>
      _room?.localParticipant?.audioTrackPublications.firstOrNull;

  /// Toggle mic on/off.
  ///
  /// Fast path (track already published):
  ///   Uses publication.mute/unmute with stopOnMute=false so the microphone
  ///   hardware stays alive. No restartTrack() call — toggle is <50 ms.
  ///
  /// Slow path (no track yet):
  ///   Full WebRTC publish via setMicrophoneEnabled(true). ~300–800 ms,
  ///   happens only once. After this, all toggles use the fast path.
  ///
  /// Privacy: with stopOnMute=false the mic hardware remains active while
  /// muted. No audio is transmitted — LiveKit suppresses muted tracks at
  /// the server level. This is the standard approach for instant toggling
  /// (Discord, Clubhouse, etc.).
  Future<void> setMicrophoneEnabled(bool enabled) async {
    _lastMicEnabled = enabled;
    if (!isConnected) {
      _pendingMicEnabled = enabled;
      _log(
        '[LiveKitGuard] mic skipped because socket not connected '
        '(state=${_room?.connectionState}) — pending mic state saved: $enabled',
      );
      return;
    }
    // Consume any stale pending state now that we are actually sending.
    _pendingMicEnabled = null;
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final pub = _localAudioPub;

    if (pub != null) {
      // ── Fast path: keep hardware alive, only change mute signal ──────────
      _log('[MicUX] setMicrophoneEnabled($enabled) path=fast-mute ts=${_ts()}');
      if (enabled) {
        await pub.unmute(stopOnMute: false);
      } else {
        await pub.mute(stopOnMute: false);
      }
      _log(
        '[MicUX] fast-mute done in ${DateTime.now().millisecondsSinceEpoch - t0}ms',
      );
    } else if (enabled) {
      // ── Slow path: first publish ──────────────────────────────────────────
      _log(
        '[MicUX] setMicrophoneEnabled($enabled) path=first-publish ts=${_ts()}',
      );
      await _room?.localParticipant?.setMicrophoneEnabled(true);
      _log(
        '[MicUX] first-publish done in ${DateTime.now().millisecondsSinceEpoch - t0}ms',
      );
    }
    // enabled=false with no existing pub → already silent, no-op.
  }

  /// Publish the local audio track in muted state immediately after room join
  /// so the user's first real unmute is a fast <50 ms hardware-unmute instead
  /// of a full WebRTC publish (~300–800 ms).
  ///
  /// Uses stopOnMute=false so the hardware stays alive after the initial mute,
  /// keeping every subsequent toggle on the fast path.
  Future<void> prewarmAudioTrack() async {
    if (_room == null) return;
    if (!isConnected) {
      _log('[MicUX] pre-warm skipped — not connected');
      return;
    }
    if (hasPublishedAudioTrack) {
      _log('[MicUX] pre-warm skipped — track already published');
      return;
    }
    _log('[MicUX] pre-warm start ts=${_ts()}');
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      // Publish the track (mic opens briefly — no way around this on first publish).
      await _room!.localParticipant?.setMicrophoneEnabled(true);
      // Mute without stopping hardware so future unmutes are instant.
      final pub = _localAudioPub;
      if (pub != null) {
        await pub.mute(stopOnMute: false);
        _log(
          '[MicUX] pre-warm done in ${DateTime.now().millisecondsSinceEpoch - t0}ms — hardware alive, track muted',
        );
      } else {
        // Fallback: pub not found, disable normally (slower future toggle).
        await _room!.localParticipant?.setMicrophoneEnabled(false);
        _log(
          '[MicUX] pre-warm fallback done in ${DateTime.now().millisecondsSinceEpoch - t0}ms',
        );
      }
    } catch (e) {
      _log('[MicUX] pre-warm failed: $e');
    }
  }

  Future<void> disconnect({bool invalidateToken = true}) async {
    onConnected = null;
    _isReconnecting = false;
    _pendingMicEnabled = null;
    await _audioDevicesSub?.cancel();
    _audioDevicesSub = null;
    _listener?.dispose();
    _listener = null;
    if (_room != null) {
      _log('[LiveKit] ${_ts()} disconnecting...');
      await _room?.disconnect();
      _room = null;
      _log('[LiveKit] disconnected');
    }
    if (invalidateToken && _lastRoomId != null) {
      LiveKitTokenService.invalidate(_lastRoomId!);
    }
  }

  // Gated logging -- interpolation and printing are skipped entirely in release
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
