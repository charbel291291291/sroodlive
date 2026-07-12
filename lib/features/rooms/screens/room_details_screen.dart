import 'dart:async';
import 'package:srood_live/shared/utils/error_utils.dart';
import 'package:just_audio/just_audio.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/vip_username.dart';
import '../../profile/widgets/room_user_profile_sheet.dart';
import '../models/room.dart';
import '../models/room_gift.dart';
import '../models/room_member.dart';
import '../services/gifts_service.dart';
import '../../wallet/screens/wallet_screen.dart';
import '../../wallet/services/wallet_service.dart';
import '../services/livekit_room_service.dart';
import '../services/rooms_service.dart';
import '../services/room_management_service.dart';
import '../services/room_messages_service.dart';
import '../services/room_read_service.dart';
import '../services/room_chat_image_upload_service.dart';
import '../models/pk_session.dart';
import '../services/team_pk_service.dart';
import '../utils/vip_room_features.dart';
import '../../vip/services/vip_privilege_service.dart';
import '../widgets/room_tools_sheet.dart';
import '../widgets/music_panel.dart';
import '../widgets/room_mini_player.dart';
import '../services/room_music_service.dart';
import '../services/room_music_upload_service.dart';
import '../services/room_synced_music_service.dart';
import '../../messages/screens/messages_screen.dart';
import '../../messages/services/private_message_service.dart';
import '../../moderation/services/moderation_service.dart';
import '../../moderation/widgets/report_reason_sheet.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import '../models/room_reaction.dart';
import '../widgets/reaction_picker_sheet.dart';
import '../../../core/services/active_room_session.dart';
import '../../../core/services/voice_room_foreground_service.dart';
import '../widgets/vault_pin_sheet.dart';
import 'room_owner_management_screen.dart';

// ── Room UI v2 presentation layer ────────────────────────────────────────────
import '../presentation/room_screen/models/srood_gift_events.dart';
import '../presentation/room_screen/models/srood_seat_actions.dart';
import '../presentation/room_screen/widgets/common/srood_room_avatar.dart';
import '../presentation/room_screen/srood_room_shell.dart';
import '../presentation/room_screen/widgets/background/srood_room_background.dart';
import '../presentation/room_screen/widgets/bottom_actions/srood_room_bottom_actions.dart';
import '../presentation/room_screen/widgets/chat/srood_room_chat_feed.dart';
import '../presentation/room_screen/widgets/header/srood_room_header.dart';
import '../presentation/room_screen/widgets/overlays/srood_gift_event_overlay.dart';
import '../presentation/room_screen/widgets/overlays/srood_lucky_bag_overlays.dart';
import '../presentation/room_screen/widgets/overlays/srood_luxury_gift_video_overlay.dart';
import '../presentation/room_screen/widgets/overlays/srood_red_envelope_banner.dart';
import '../presentation/room_screen/widgets/overlays/srood_room_banners.dart';
import '../presentation/room_screen/widgets/overlays/srood_room_closing_overlay.dart';
import '../presentation/room_screen/widgets/overlays/srood_room_level_up_overlay.dart';
import '../presentation/room_screen/widgets/sheets/srood_gift_sheet.dart';
import '../presentation/room_screen/widgets/sheets/srood_room_exit_sheet.dart';
import '../presentation/room_screen/widgets/sheets/srood_room_level_sheet.dart';
import '../presentation/room_screen/widgets/sheets/srood_room_participants_sheet.dart';
import '../presentation/room_screen/widgets/stage/srood_room_stage.dart';
import '../presentation/theme/srood_room_theme.dart';

class RoomDetailsScreen extends StatefulWidget {
  const RoomDetailsScreen({
    required this.room,
    required this.isArabic,
    super.key,
  });

  final Room room;
  final bool isArabic;

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen>
    with WidgetsBindingObserver {
  final RoomsService _roomsService = const RoomsService();
  final GiftsService _giftsService = const GiftsService();
  late final LiveKitRoomService _liveKitRoomService;
  bool _minimizing = false;
  bool _isRestoring = false;

  late final RoomMusicService _musicService;
  late final RoomSyncedMusicService _syncedMusic;
  final RoomMusicUploadService _uploadService = const RoomMusicUploadService();

  // Shared one-shot SFX player for lucky-bag appear sound.
  // A single persistent player avoids creating a new ExoPlayer pipeline on
  // every appearance event, which was pushing the pipeline count above 6.
  AudioPlayer? _sfxPlayer;

  Set<String> _speakingUserIds = {};

  bool _leaving = false;
  bool _isClosingRoom = false;
  // Consecutive load cycles where the current user was absent from active
  // members.  Requires 2 misses before triggering auto-leave so a single
  // slow heartbeat on a weak network doesn't kick the user spuriously.
  int _missedHeartbeatCount = 0;
  bool _connectingAudio = false;
  bool _connectedAudio = false;
  bool _syncingMicConnection = false;
  // Notifier keeps audio state for the bottom bar without full-screen setState.
  late final ValueNotifier<({bool connecting, bool connected})>
  _audioStateNotifier;
  bool _wasCurrentUserOnMic = false;
  bool _micEnabled = true;
  bool _micToggleBusy = false;
  // Cached so we don't call permission_handler on every mic-seat change.
  bool? _micPermissionGranted;
  int _moderatorCount = 0;
  bool _isCurrentUserModerator = false;
  Set<String> _moderatorUserIds = {};
  String? _roleBusyUserId;
  String? _activeAnnouncementText;

  List<RoomMember> _members = const [];
  RealtimeChannel? _roomChannel;
  RealtimeChannel? _membersChannel;
  RealtimeChannel? _giftTransactionsChannel;
  RealtimeChannel? _walletChannel;
  Timer? _heartbeatTimer;
  Timer? _membersRefreshTimer;
  Timer? _membersDebounceTimer;
  // Debounce timer for post-reconnect resync â€” prevents duplicate
  // _syncMicConnectionWithSeat calls when RoomConnectedEvent and
  // RoomReconnectedEvent fire in quick succession.
  Timer? _reconnectDebounce;
  Timer? _giftBannerTimer;
  Timer? _giftFeedCleanupTimer;
  Timer? _vipEntryBannerTimer;
  Timer? _entryBannerTimer;
  final List<SroodRoomGiftEvent> _giftEvents = [];
  final List<Timer> _giftEventTimers = [];
  final Map<String, int> _giftSupportByUserId = {};
  List<RoomGiftTransaction> _roomGifts = const [];
  // Notifiers so banner changes rebuild only the banner widget, not the screen.
  final ValueNotifier<RoomGiftTransaction?> _giftBannerNotifier = ValueNotifier(
    null,
  );
  final ValueNotifier<RoomMember?> _vipBannerNotifier = ValueNotifier(null);
  final ValueNotifier<RoomMember?> _entryBannerNotifier = ValueNotifier(null);
  SroodActiveLuxuryGiftVideo? _activeLuxuryGiftVideo;
  Timer? _luxuryGiftVideoTimer;
  bool _soundEnabled = true;
  bool _visualEnabled = true;
  Map<String, dynamic>? _activeRedEnvelope;
  bool _claimingEnvelope = false;
  bool _isSeatMovePending = false;
  bool _showLuckyBagEntrance = false;
  int? _luckyBagWinCoins;
  final Set<String> _openedLuckyBagIds = {};
  Timer? _bannerAutoHideTimer;

  // Session-level sets â€” static so they survive screen re-entry within the app session.
  static final Set<String> _sessionDismissedEnvelopeIds = {};
  static final Set<String> _sessionClaimedEnvelopeIds = {};
  // _loadingGifts removed - gift loading state is not displayed in the overlay
  bool _isSendingGift = false;
  bool _rechargeRedirecting = false;
  RoomMember? _selectedMicMoveMember;
  int _giftEventSeed = 0;

  // -- Room chat / comments --------------------------------------------------
  final _msgService = const RoomMessagesService();
  final List<RoomMessage> _chatMessages = [];
  RealtimeChannel? _messagesChannel;
  bool _isSendingMessage = false;

  int _inboxUnreadCount = 0;
  bool _uploadingChatImage = false;

  // -- Emoji reactions (keyed by seat number 1-based) --
  final Map<int, RoomReaction> _seatReactions = {};
  final Map<int, Timer> _reactionTimers = {};
  RealtimeChannel? _reactionsChannel;
  RealtimeChannel? _redEnvelopesChannel;

  // -- Closed/locked mic seats --
  Set<int> _closedSeats = {};

  static const Duration _giftVisibleDuration = Duration(minutes: 1);

  String? get _currentUserId =>
      SupabaseService.requiredClient.auth.currentUser?.id;

  RoomMember? get _myMember {
    final currentUserId = _currentUserId;

    if (currentUserId == null) {
      return null;
    }

    for (final member in _members) {
      if (member.userId == currentUserId) {
        return member;
      }
    }

    return null;
  }

  bool _memberIsOnMic(RoomMember? member) {
    if (member == null) return false;
    // Host is always on mic regardless of seat_number â€” the DB may not have
    // assigned a seat yet when the member record first loads.
    if (member.role == 'host') return true;
    return member.role == 'speaker' && member.seatNumber != null;
  }

  bool get _isCurrentUserOnMic => _memberIsOnMic(_myMember);

  int get _activeSpeakerCount {
    return _members
        .where((member) => member.role == 'host' || member.role == 'speaker')
        .length;
  }

  List<RoomMember> get _participantsForDisplay {
    final members = [..._members];

    members.sort((a, b) {
      final vipCompare = VipFeatures.visualPriorityScore(
        b.effectiveVipLevel,
      ).compareTo(VipFeatures.visualPriorityScore(a.effectiveVipLevel));
      if (vipCompare != 0) {
        return vipCompare;
      }

      final roleCompare = _rolePriority(
        b.role,
      ).compareTo(_rolePriority(a.role));
      if (roleCompare != 0) {
        return roleCompare;
      }

      return a.joinedAt.compareTo(b.joinedAt);
    });

    return members;
  }

  int _rolePriority(String role) {
    return switch (role) {
      'host' => 3,
      'speaker' => 2,
      _ => 1,
    };
  }

  late int _currentMaxSeats;
  String? _roomBackgroundUrl;
  String? _roomAvatarUrl;
  String? _roomCoverUrl;
  // Mutable room metadata â€” kept in sync via _subscribeToRoom() realtime.
  String _roomName = '';
  String? _roomDescription;
  String? _roomLanguage;
  int _roomLevel = 1;
  int _lastShownLevel = 1;
  bool _roomIsLocked = false;
  bool _roomIsClosed = false;
  bool _roomIsMuted = false;
  bool _roomAllowImages = true;
  // Used for image-cache busting when background changes server-side.
  DateTime? _roomUpdatedAt;
  // XP progression
  int _roomXp = 0;
  int _xpToday = 0;
  int _xpWeek = 0;
  int _dailyStreak = 0;
  double _streakMultiplier = 1.0;

  int _walletCoins = 0;

  // Team PK
  final _pkService = const TeamPkService();
  PkSession? _activePk;
  bool _showPkResult = false;
  StreamSubscription<PkSession?>? _pkSub;

  bool get _speakerSeatsFull => _activeSpeakerCount >= _currentMaxSeats;

  bool get _iAmHost {
    final currentUserId = _currentUserId;

    if (currentUserId == null) {
      return false;
    }

    return _members.any(
      (member) => member.userId == currentUserId && member.role == 'host',
    );
  }

  bool get _iAmRoomOwner => _currentUserId == widget.room.ownerId;

  bool get _iAmSuperAdmin => false;

  // â”€â”€ Audio state helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Updates the audio bool fields AND pushes to the notifier â€” no setState.
  /// Callers that previously did setState just for audio now call this instead.
  void _setAudioState({bool? connecting, bool? connected}) {
    if (connecting != null) _connectingAudio = connecting;
    if (connected != null) _connectedAudio = connected;
    _audioStateNotifier.value = (
      connecting: _connectingAudio,
      connected: _connectedAudio,
    );
  }

  // â”€â”€ Member debounce â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Buffers rapid member change events and fires a single reload after 500 ms.
  /// Also refreshes moderator state so badge changes appear immediately.
  void _debouncedLoadMembers() {
    _membersDebounceTimer?.cancel();
    _membersDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      await _loadMembers(showLoading: false, detectVipEntry: true);
      if (mounted) unawaited(_loadModeratorCount());
    });
  }

  @override
  void initState() {
    super.initState();
    _audioStateNotifier = ValueNotifier((connecting: false, connected: false));
    WidgetsBinding.instance.addObserver(this);

    // â”€â”€ Reuse existing LiveKit session when returning from minimize â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final session = ActiveRoomSession.instance;
    final existingService = session.liveKitService;
    final sameRoom = session.room?.id == widget.room.id;
    if (existingService != null && sameRoom && existingService.isConnected) {
      _liveKitRoomService = existingService;
      _isRestoring = true;
      _roomLog(
        '[RoomMinimize] restore â€” reusing existing LiveKit session roomId=${widget.room.id}',
      );
      _roomLog('[RoomMinimize] savedMic=${session.savedMicEnabled}');
    } else {
      _liveKitRoomService = LiveKitRoomService();
      _isRestoring = false;
      if (existingService != null) {
        _roomLog(
          '[RoomMinimize] restore â€” existing service found but not reusable (sameRoom=$sameRoom connected=${existingService.isConnected})',
        );
      }
    }
    // Screen takes ownership; clear session reference (prevents double-use).
    session.clear();
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    _roomLog(
      '[PerfRoom] open id=${widget.room.id} ts=${DateTime.now().millisecondsSinceEpoch}',
    );
    _roomLog(
      '[Room] ${_roomTs()} room screen opened id=${widget.room.id} restoring=$_isRestoring',
    );
    unawaited(RoomReadService.instance.setActiveRoom(widget.room.id));

    // â”€â”€ Reuse music services when returning from minimize (same room) â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final savedMusic = session.musicService;
    final savedSynced = session.syncedMusicService;
    final reusingMusic =
        _isRestoring && savedMusic != null && savedSynced != null;
    if (reusingMusic) {
      _musicService = savedMusic;
      _syncedMusic = savedSynced;
      unawaited(_syncedMusic.recoverIfNeeded());
      _roomLog(
        '[RoomMusic] restore â€” reused music service roomId=${widget.room.id}',
      );
    } else {
      _musicService = RoomMusicService();
      _syncedMusic = RoomSyncedMusicService(
        roomId: widget.room.id,
        musicService: _musicService,
        currentUserId: _currentUserId ?? '',
      );
      unawaited(_syncedMusic.initialize());
      _roomLog('[RoomMusic] music service created roomId=${widget.room.id}');
    }
    _musicService.addListener(_onLocalMusicChanged);
    // When a song ends, snapshot autoReplay first (before any async work) to
    // avoid a race where the value is read after handleSongCompleted mutates it.
    // Only the controller's device triggers the replay push; listeners do nothing.
    _musicService.onSongCompleted = () {
      final replay = _syncedMusic.lastState?.autoReplay ?? false;
      if (replay) {
        unawaited(_syncedMusic.handleSongCompleted());
      } else if (_syncedMusic.isController) {
        unawaited(_syncedMusic.nextForRoom());
      }
    };
    _currentMaxSeats = widget.room.maxSeats <= 0 ? 12 : widget.room.maxSeats;
    _closedSeats = widget.room.closedSeats.toSet();
    _roomBackgroundUrl = widget.room.backgroundUrl;
    _roomAvatarUrl = widget.room.avatarUrl;
    _roomCoverUrl = widget.room.coverUrl;
    _roomName = widget.room.name;
    _roomDescription = widget.room.description;
    _roomLanguage = widget.room.language;
    _roomLevel = widget.room.roomLevel;
    _lastShownLevel = widget.room.roomLevel;
    _roomIsLocked = widget.room.isLocked;
    _roomIsClosed = widget.room.isClosed;
    _roomIsMuted = widget.room.isRoomMuted;
    _roomAllowImages = widget.room.allowImages;
    _roomXp = widget.room.roomXp;
    _xpToday = widget.room.xpToday;
    _xpWeek = widget.room.xpWeek;
    _dailyStreak = widget.room.dailyStreak;
    _streakMultiplier = widget.room.streakMultiplier;

    // Wire the onConnected callback once.  Both RoomConnectedEvent and
    // RoomReconnectedEvent fire this, so we debounce 150 ms to collapse any
    // rapid double-fire into a single controlled resync.
    _liveKitRoomService.onConnected = () {
      if (!mounted) return;
      _roomLog('[VoiceLifecycle] onConnected fired');
      _connectedAudio = true;
      _setAudioState(connecting: false, connected: true);
      _reconnectDebounce?.cancel();
      _reconnectDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted || !_liveKitRoomService.isConnected) {
          _roomLog(
            '[LiveKitGuard] reconnect resync skipped, already applied or unmounted',
          );
          return;
        }
        _roomLog('[LiveKitGuard] reconnect resync applied');
        unawaited(_syncMicConnectionWithSeat());
      });
    };

    if (_isRestoring) {
      // Already in a live session â€” foreground service already running.
      // Only mark audio as connected when the socket is actually in the
      // connected state.  If it is mid-reconnect, leave _connectedAudio false
      // so _syncMicConnectionWithSeat does not fire against a broken socket;
      // onConnected will flip the flag and trigger resync once the socket is ready.
      _liveKitRoomService.onSpeakersChanged = (ids) {
        if (mounted) setState(() => _speakingUserIds = ids);
      };
      final restoredConnected = _liveKitRoomService.isConnected;
      _connectedAudio = restoredConnected;
      _setAudioState(
        connecting: !restoredConnected,
        connected: restoredConnected,
      );
      if (restoredConnected) {
        _roomLog('[RoomMinimize] restore â€” socket confirmed connected');
      } else {
        _roomLog(
          '[RoomMinimize] restore â€” socket reconnecting, '
          'waiting for onConnected before mic sync',
        );
      }
    } else {
      // Fresh entry â€” start foreground service and connect LiveKit.
      unawaited(VoiceRoomForegroundService.start());
      unawaited(_connectAudioEarly());
    }

    // Keep the process alive (idempotent if already started).
    if (!_isRestoring) {
      // Already handled above for non-restore path.
    }

    unawaited(_loadInboxUnread());

    // Critical: member list is needed for the seat grid on first paint.
    _loadMembers();
    // Realtime subscriptions open immediately so no events are missed.
    _subscribeToRoom();
    _subscribeToMembers();
    _subscribeToGiftTransactions();
    _subscribeToMessages();
    _subscribeToPk();
    _subscribeToReactions();
    _subscribeToRedEnvelopes();
    // Timers start immediately.
    _startHeartbeat();
    _startMembersRefresh();
    _startGiftFeedCleanupTimer();

    // Non-critical queries deferred until after first frame so the room
    // scaffold renders without waiting for extra round-trips.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadRoomGifts();
      _loadModeratorCount();
      _loadAnnouncement();
      _loadWalletBalance();
      _subscribeWalletBalance();
      // Always fetch authoritative XP/level from server â€” widget.room may carry
      // a stale snapshot from the rooms list (minimize/restore or cached nav).
      unawaited(_refreshRoomXpStats());
      _loadMessages();
      unawaited(_loadActivePk());
      unawaited(_loadActiveRedEnvelope());
    });
  }

  // When a user changes music locally (via MusicPanel / mini-player), push the
  // new state to Supabase so all room members sync.
  // Skipped during server-driven updates to avoid feedback loops.
  // Skipped for position-only changes (tick updates) via pushCurrentStateIfChanged().
  // Only the current music controller (the user who started the track) may push
  // control changes. Starting a new track is always allowed for managers.
  void _onLocalMusicChanged() {
    if (_syncedMusic.applyingServerState) return;

    final uid = _currentUserId;
    if (uid == null) {
      _roomLog('[RoomMusic] denied â€” no user id');
      return;
    }

    // Managers can always start a new track (no existing controller) or take
    // over after a stop. For pause/resume the caller must be the controller.
    final isManager = _iAmRoomOwner || _iAmHost || _isCurrentUserModerator;
    final controllerId = _syncedMusic.lastState?.controllerUserId;
    final hasController = controllerId != null && controllerId.isNotEmpty;
    final isController = controllerId == uid;

    if (hasController && !isController) {
      _roomLog(
        '[RoomMusic] denied â€” not controller uid=$uid controller=$controllerId',
      );
      return;
    }

    if (!isManager && !isController) {
      _roomLog('[RoomMusic] denied â€” not manager uid=$uid');
      return;
    }

    _roomLog(
      '[RoomMusic] push allowed uid=$uid song=${_musicService.currentSong?.id}',
    );
    unawaited(_syncedMusic.pushCurrentStateIfChanged());
  }

  bool _musicActionBusy = false;

  /// Guard wrapper for music control actions. Blocks non-controllers with a
  /// snackbar and prevents rapid double-taps with a busy flag.
  Future<void> _musicAction(Future<void> Function() action) async {
    if (_musicActionBusy) return;

    final uid = _currentUserId;
    final controllerId = _syncedMusic.lastState?.controllerUserId;
    final hasController = controllerId != null && controllerId.isNotEmpty;

    if (hasController && controllerId != uid) {
      _roomLog(
        '[RoomMusic] action blocked â€” not controller uid=$uid controller=$controllerId',
      );
      if (!mounted) return;
      SroodToast.show(
        context,
        context.isArabic
            ? 'Ø§Ù„Ø´Ø®Øµ Ø§Ù„Ø°ÙŠ Ø´ØºÙ‘Ù„ Ø§Ù„Ù…ÙˆØ³ÙŠÙ‚Ù‰ ÙÙ‚Ø· ÙŠÙ…ÙƒÙ†Ù‡ Ø§Ù„ØªØ­ÙƒÙ… Ø¨Ù‡Ø§.'
            : 'Only the person who started the music can control it.',
        type: SroodToastType.info,
      );
      return;
    }

    setState(() => _musicActionBusy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _musicActionBusy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // App lifecycle ? keep audio alive on background, reconnect on resume.
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Screen off / home pressed -- do NOT disconnect or mute. The Android
        // foreground service (microphone + mediaPlayback types) keeps the mic
        // active so other participants continue hearing the user.
        _roomLog('[VoiceLifecycle] state=$state keepAudio=true');
        _roomLog('[VoiceLifecycle] background audio preserved');
        break;
      case AppLifecycleState.resumed:
        _roomLog('[VoiceLifecycle] state=resumed');
        unawaited(RoomReadService.instance.setActiveRoom(widget.room.id));
        if (!_connectedAudio || !_liveKitRoomService.isConnected) {
          _roomLog(
            '[VoiceLifecycle] audio dropped while backgrounded -- reconnecting',
          );
          unawaited(_reconnectAudio());
        }
        unawaited(_syncedMusic.recoverIfNeeded());
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _reconnectAudio() async {
    if (_syncingMicConnection) return;
    if (mounted) _setAudioState(connecting: true);
    try {
      await _liveKitRoomService.reconnectIfNeeded();
      final nowConnected = _liveKitRoomService.isConnected;
      if (mounted) _setAudioState(connected: nowConnected);
      if (nowConnected) {
        // Only push mic/seat state once the socket is confirmed ready.
        await _syncMicConnectionWithSeat();
      } else {
        _roomLog(
          '[Room] reconnect completed but socket not yet connected â€” '
          'skipping mic sync (onConnected will fire when ready)',
        );
      }
      // Re-sync XP/level after reconnect â€” Realtime may have missed events.
      unawaited(_refreshRoomXpStats());
    } catch (e) {
      _roomLog('[Room] reconnect failed: $e');
    } finally {
      if (mounted) _setAudioState(connecting: false);
    }
  }

  // ---------------------------------------------------------------------------
  // Early audio ? connects for listening immediately on room entry.
  // ---------------------------------------------------------------------------

  /// Connects LiveKit in listen-only mode in parallel with [_loadMembers].
  /// [_syncMicConnectionWithSeat] skips the connect step when it runs later
  /// because [_connectedAudio] will already be true.
  Future<void> _connectAudioEarly() async {
    // Skip if already connected (e.g. returning from minimize with reused session).
    if (_liveKitRoomService.isConnected) {
      _roomLog(
        '[RoomMinimize] _connectAudioEarly skipped â€” already connected',
      );
      _connectedAudio = true;
      _setAudioState(connecting: false, connected: true);
      _liveKitRoomService.onSpeakersChanged = (ids) {
        if (mounted) setState(() => _speakingUserIds = ids);
      };
      return;
    }
    if (_connectedAudio || _connectingAudio || _syncingMicConnection) return;
    if (mounted) _setAudioState(connecting: true);

    _liveKitRoomService.onSpeakersChanged = (ids) {
      if (mounted) setState(() => _speakingUserIds = ids);
    };

    _roomLog('[Room] ${_roomTs()} LiveKit connect started (early)');
    try {
      await _liveKitRoomService.connect(
        roomId: widget.room.id,
        microphoneEnabled: false,
      );
      _roomLog('[Room] ${_roomTs()} LiveKit connected');
      _roomLog(
        '[PerfRoom] livekit connected ts=${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) _setAudioState(connecting: false, connected: true);

      // Pre-warm: if mic permission is already cached, publish track in muted
      // state now so the first real unmute is a fast local operation (~50ms)
      // instead of a full WebRTC track publish (~500ms).
      if (_micPermissionGranted == true) {
        unawaited(_liveKitRoomService.prewarmAudioTrack());
      }
    } catch (e) {
      _roomLog('[Room] ${_roomTs()} early audio connect failed: $e');
      if (mounted) _setAudioState(connecting: false);
    }
  }

  static String _roomTs() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  void dispose() {
    RoomReadService.instance.clearActiveRoom(widget.room.id);
    _musicService.removeListener(_onLocalMusicChanged);
    // On minimize: music services are handed to ActiveRoomSession â€” do NOT dispose.
    // On true leave: dispose everything.
    if (!_minimizing) {
      unawaited(_syncedMusic.dispose());
      _musicService.dispose();
      _roomLog('[RoomMusic] music service disposed on leave');
    } else {
      _roomLog('[RoomMusic] music service preserved on minimize');
    }
    _heartbeatTimer?.cancel();
    _membersRefreshTimer?.cancel();
    _membersDebounceTimer?.cancel();
    _reconnectDebounce?.cancel();
    _audioStateNotifier.dispose();
    _giftBannerNotifier.dispose();
    _vipBannerNotifier.dispose();
    _entryBannerNotifier.dispose();
    _giftBannerTimer?.cancel();
    _giftFeedCleanupTimer?.cancel();
    _vipEntryBannerTimer?.cancel();
    _entryBannerTimer?.cancel();
    _bannerAutoHideTimer?.cancel();
    for (final timer in _giftEventTimers) {
      timer.cancel();
    }

    final roomChannel = _roomChannel;
    if (roomChannel != null) {
      unawaited(SupabaseService.requiredClient.removeChannel(roomChannel));
    }

    final membersChannel = _membersChannel;
    final giftTransactionsChannel = _giftTransactionsChannel;

    if (membersChannel != null) {
      unawaited(SupabaseService.requiredClient.removeChannel(membersChannel));
    }

    if (giftTransactionsChannel != null) {
      unawaited(
        SupabaseService.requiredClient.removeChannel(giftTransactionsChannel),
      );
    }

    final messagesChannel = _messagesChannel;
    if (messagesChannel != null) {
      unawaited(SupabaseService.requiredClient.removeChannel(messagesChannel));
    }

    _pkSub?.cancel();
    // If the user minimized, ownership of the LiveKit service was transferred
    // to ActiveRoomSession â€” do NOT disconnect or stop the foreground service.
    if (_minimizing) {
      _roomLog(
        '[RoomMinimize] dispose skipping disconnect â€” session is minimized',
      );
    } else {
      _roomLog('[RoomMinimize] dispose disconnecting â€” true leave/close');
      _liveKitRoomService.disconnect();
      unawaited(VoiceRoomForegroundService.stop());
    }
    for (final t in _reactionTimers.values) {
      t.cancel();
    }
    _reactionTimers.clear();
    final rc = _reactionsChannel;
    if (rc != null) unawaited(SupabaseService.requiredClient.removeChannel(rc));
    final rec = _redEnvelopesChannel;
    if (rec != null) {
      unawaited(SupabaseService.requiredClient.removeChannel(rec));
    }
    final wc = _walletChannel;
    if (wc != null) unawaited(SupabaseService.requiredClient.removeChannel(wc));
    _sfxPlayer?.dispose();
    debugPrint('[RoomDetails] sfxPlayer disposed');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadActivePk() async {
    try {
      final session = await _pkService.getActivePk(widget.room.id);
      if (!mounted) return;

      setState(() {
        final wasActive = _activePk?.isActive ?? false;
        _activePk = session;

        if (wasActive && session != null && session.isFinished) {
          _showPkResult = true;
        }

        if (session == null || session.status == 'cancelled') {
          _showPkResult = false;
        }
      });
    } catch (error) {
      if (kDebugMode) {
        _roomLog('[PK] load active failed: $error');
      }
    }
  }

  Future<void> _playLuckyBagAppearSound() async {
    try {
      _sfxPlayer ??= AudioPlayer(handleInterruptions: false);
      debugPrint('[RoomDetails] sfxPlayer: setAsset lucky_bag_open');
      await _sfxPlayer!.setAsset('assets/sounds/lucky_bag_open.mp3');
      debugPrint('[RoomDetails] sfxPlayer: play');
      unawaited(_sfxPlayer!.play());
    } catch (e, st) {
      debugError('_RoomDetailsScreenState._playLuckyBagAppearSound', e, st);
    }
  }

  // -- Emoji reaction channel (Supabase Broadcast) --
  Future<void> _loadActiveRedEnvelope() async {
    try {
      final rows = await SupabaseService.requiredClient
          .from('red_envelopes')
          .select()
          .eq('room_id', widget.room.id)
          .eq('is_expired', false)
          .order('created_at', ascending: false)
          .limit(1);

      if (!mounted) return;
      final list = rows as List<dynamic>;
      if (list.isEmpty) return;
      final row = list.first as Map<String, dynamic>;
      final id = row['id'] as String? ?? '';
      final claimed = (row['claimed_count'] as int? ?? 0);
      final total = (row['envelope_count'] as int? ?? 1);
      final left = total - claimed;

      _roomLog('[LuckyBag] active loaded id=$id left=$left');

      if (left <= 0) {
        _roomLog('[LuckyBag] hidden reason=empty');
        return;
      }
      if (_sessionDismissedEnvelopeIds.contains(id)) {
        _roomLog('[LuckyBag] hidden reason=dismissed_session');
        return;
      }
      if (_sessionClaimedEnvelopeIds.contains(id) ||
          _openedLuckyBagIds.contains(id)) {
        _roomLog('[LuckyBag] hidden reason=claimed');
        return;
      }
      _showRedEnvelopeBanner(row);
    } catch (e) {
      _roomLog('[LuckyBag] loadActiveRedEnvelope error: $e');
    }
  }

  /// Shows the Lucky Bag banner and auto-hides when it expires.
  void _showRedEnvelopeBanner(Map<String, dynamic> envelope) {
    final id = envelope['id'] as String? ?? '';
    _bannerAutoHideTimer?.cancel();
    _roomLog('[LuckyBag] shown id=$id');
    setState(() => _activeRedEnvelope = envelope);
    if (_soundEnabled && !_musicService.isActive) {
      unawaited(_playLuckyBagAppearSound());
    }

    // Auto-hide when expires_at elapses (fallback 120s if not set).
    final expiresAtStr = envelope['expires_at'] as String?;
    Duration hideAfter = const Duration(seconds: 120);
    if (expiresAtStr != null) {
      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt != null) {
        final remaining = expiresAt.difference(DateTime.now().toUtc());
        hideAfter = remaining > Duration.zero ? remaining : Duration.zero;
      }
    }

    _bannerAutoHideTimer = Timer(hideAfter, () {
      if (!mounted) return;
      _roomLog('[LuckyBag] auto hidden id=$id');
      _sessionDismissedEnvelopeIds.add(id);
      setState(() => _activeRedEnvelope = null);
    });
  }

  /// Manually dismisses the Lucky Bag banner for the rest of this app session.
  void _dismissRedEnvelope() {
    final id = _activeRedEnvelope?['id'] as String? ?? '';
    _bannerAutoHideTimer?.cancel();
    if (id.isNotEmpty) {
      _roomLog('[LuckyBag] dismissed id=$id');
      _sessionDismissedEnvelopeIds.add(id);
    }
    setState(() => _activeRedEnvelope = null);
  }

  void _subscribeToRedEnvelopes() {
    _redEnvelopesChannel = SupabaseService.requiredClient
        .channel('red_envelopes_${widget.room.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'red_envelopes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.room.id,
          ),
          callback: (payload) {
            if (!mounted) return;
            final row = payload.newRecord;
            if (row.isEmpty) return;
            if (row['is_expired'] == true) return;
            final envelopeId = row['id'] as String? ?? '';
            final senderId = row['sender_id'] as String? ?? '';
            final iAmSender = senderId == _currentUserId;
            _roomLog(
              '[LuckyBag] realtime insert id=$envelopeId iAmSender=$iAmSender',
            );
            // New envelope: remove any prior session-dismissed state for this id
            // (shouldn't happen in practice but guards against edge cases).
            _sessionDismissedEnvelopeIds.remove(envelopeId);
            if (!iAmSender) setState(() => _showLuckyBagEntrance = true);
            _showRedEnvelopeBanner(row);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'red_envelopes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.room.id,
          ),
          callback: (payload) {
            if (!mounted) return;
            final row = payload.newRecord;
            if (row['id'] != _activeRedEnvelope?['id']) return;
            final isExpired = row['is_expired'] == true;
            final claimed = (row['claimed_count'] as int? ?? 0);
            final total = (row['envelope_count'] as int? ?? 1);
            if (isExpired || claimed >= total) {
              setState(() => _activeRedEnvelope = null);
            } else {
              setState(() => _activeRedEnvelope = row);
            }
          },
        )
        .subscribe((status, [error]) {
          _roomLog(
            '[RT-RED] status=$status error=$error room=${widget.room.id}',
          );
        });
  }

  Future<void> _claimRedEnvelope() async {
    final envelope = _activeRedEnvelope;
    if (envelope == null || _claimingEnvelope) return;
    final envelopeId = envelope['id'] as String?;
    if (envelopeId == null) return;
    // Sender is allowed to claim their own Lucky Bag (same as everyone else).
    setState(() => _claimingEnvelope = true);
    try {
      final coins =
          await SupabaseService.requiredClient.rpc(
                'claim_red_envelope',
                params: {'p_envelope_id': envelopeId},
              )
              as int;
      if (!mounted) return;
      setState(() {
        _luckyBagWinCoins = coins;
        // Optimistic credit so toolbar balance updates instantly.
        _walletCoins += coins;
        _openedLuckyBagIds.add(envelopeId);
        _sessionClaimedEnvelopeIds.add(envelopeId);
        _bannerAutoHideTimer?.cancel();
        _activeRedEnvelope = null;
      });
      unawaited(_loadWalletBalance());
      SroodToast.show(
        context,
        context.isArabic
            ? 'Ø­ØµÙ„Øª Ø¹Ù„Ù‰ $coins Ø¹Ù…Ù„Ø©!'
            : 'You got $coins coins!',
        type: SroodToastType.success,
      );
    } catch (e, st) {
      _roomLog('[RoomImage] failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      final msg = e.toString();
      String friendly;
      if (msg.contains('already_claimed')) {
        friendly = context.isArabic
            ? 'ØªÙ… Ø§Ù„ÙØªØ­ Ù…Ø³Ø¨Ù‚Ø§Ù‹'
            : 'Already opened';
        _bannerAutoHideTimer?.cancel();
        setState(() {
          _openedLuckyBagIds.add(envelopeId);
          _sessionClaimedEnvelopeIds.add(envelopeId);
          _activeRedEnvelope = null;
        });
      } else if (msg.contains('envelope_full')) {
        friendly = context.isArabic
            ? 'ØªÙ… Ø§Ø³ØªÙ„Ø§Ù… Ø¬Ù…ÙŠØ¹ Ø§Ù„Ø£ÙƒÙŠØ§Ø³'
            : 'All bags claimed';
        setState(() => _activeRedEnvelope = null);
      } else if (msg.contains('envelope_expired')) {
        friendly = context.isArabic
            ? 'Ø§Ù†ØªÙ‡Øª ØµÙ„Ø§Ø­ÙŠØ© Ø§Ù„ÙƒÙŠØ³'
            : 'Lucky Bag expired';
        setState(() => _activeRedEnvelope = null);
      } else {
        friendly = context.isArabic ? 'Ø­Ø¯Ø« Ø®Ø·Ø£' : 'An error occurred';
      }
      SroodToast.show(context, friendly, type: SroodToastType.error);
    } finally {
      if (mounted) setState(() => _claimingEnvelope = false);
    }
  }

  void _subscribeToReactions() {
    _reactionsChannel = SupabaseService.requiredClient
        .channel('room_reactions_${widget.room.id}')
        .onBroadcast(
          event: 'reaction',
          callback: (payload) {
            if (!mounted) return;
            final seatNum = payload['seat'] as int?;
            final emoji = payload['emoji'] as String?;
            if (seatNum == null || emoji == null) return;
            _applyReaction(seatNum, emoji);
          },
        )
        .subscribe();
  }

  void _applyReaction(int seatNumber, String emoji) {
    _reactionTimers[seatNumber]?.cancel();
    setState(() {
      _seatReactions[seatNumber] = RoomReaction(
        emoji: emoji,
        expiresAt: DateTime.now().add(const Duration(seconds: 3)),
      );
    });
    _reactionTimers[seatNumber] = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _seatReactions.remove(seatNumber));
    });
  }

  void _sendReaction(String emoji) {
    // Find the current user's seat number
    final myMember = _myMember;
    final seat = myMember?.seatNumber ?? 1;
    // Broadcast to channel (fire and forget)
    _reactionsChannel?.sendBroadcastMessage(
      event: 'reaction',
      payload: {'seat': seat, 'emoji': emoji},
    );
    // Apply locally immediately
    _applyReaction(seat, emoji);
  }

  void _subscribeToPk() {
    _pkSub = _pkService.watchPk(widget.room.id).listen((session) {
      if (!mounted) return;
      setState(() {
        final wasActive = _activePk?.isActive ?? false;
        _activePk = session;
        // When PK transitions from active to finished, show result banner.
        if (wasActive && session != null && session.isFinished) {
          _showPkResult = true;
        }
        // When PK is cancelled or null, clear result.
        if (session == null || session.status == 'cancelled') {
          _showPkResult = false;
        }
      });
    });
  }

  Future<void> _handlePkAutoFinish() async {
    final pk = _activePk;
    if (pk == null || !pk.isActive) return;
    try {
      await _pkService.finishPk(pk.id);
    } catch (e, st) {
      debugError('_RoomDetailsScreenState._handlePkAutoFinish', e, st);
    }
  }

  Future<void> _handlePkCancelRequested() async {
    final pk = _activePk;
    if (pk == null) return;
    try {
      await _pkService.cancelPk(pk.id);
    } catch (e, st) {
      debugError('_RoomDetailsScreenState._handlePkCancelRequested', e, st);
    }
  }

  void _startHeartbeat() {
    unawaited(_roomsService.heartbeatRoomMember(widget.room.id));

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_roomsService.heartbeatRoomMember(widget.room.id)),
    );
  }

  void _startMembersRefresh() {
    _membersRefreshTimer?.cancel();

    _membersRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      unawaited(_loadMembers(showLoading: false));
    });
  }

  void _startGiftFeedCleanupTimer() {
    _giftFeedCleanupTimer?.cancel();
    _giftFeedCleanupTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      _cleanupExpiredRoomGifts();
    });
  }

  List<RoomGiftTransaction> _activeRoomGifts(List<RoomGiftTransaction> gifts) {
    final now = DateTime.now();

    return gifts
        .where(
          (gift) =>
              now.difference(gift.createdAt.toLocal()) <= _giftVisibleDuration,
        )
        .take(10)
        .toList();
  }

  void _cleanupExpiredRoomGifts() {
    final activeGifts = _activeRoomGifts(_roomGifts);

    if (activeGifts.length == _roomGifts.length) {
      return;
    }

    setState(() {
      _roomGifts = activeGifts;
    });
  }

  void _subscribeToRoom() {
    _roomChannel = SupabaseService.requiredClient
        .channel('room_config_${widget.room.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.room.id,
          ),
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            _roomLog('[RT-ROOM] UPDATE received roomId=${widget.room.id}');

            setState(() {
              // --- seat counts / closed seats ---
              final newMaxSeats = rec['max_seats'] as int?;
              if (newMaxSeats != null && newMaxSeats != _currentMaxSeats) {
                _roomLog('[RT-ROOM] maxSeats $newMaxSeats');
                _currentMaxSeats = newMaxSeats;
              }

              final rawClosed = rec['closed_seats'];
              if (rawClosed is List) {
                final updated = rawClosed
                    .map((e) => (e as num).toInt())
                    .toSet();
                if (!setEquals(updated, _closedSeats)) {
                  _closedSeats = updated;
                }
              }

              // --- room metadata ---
              final newName = rec['name'] as String?;
              if (newName != null &&
                  newName.isNotEmpty &&
                  newName != _roomName) {
                _roomLog('[RT-ROOM] name â†’ $newName');
                _roomName = newName;
              }

              final newDesc = rec['description'] as String?;
              if (rec.containsKey('description') &&
                  newDesc != _roomDescription) {
                _roomDescription = newDesc;
              }

              final newLang = rec['language'] as String?;
              if (newLang != null && newLang != _roomLanguage) {
                _roomLanguage = newLang;
              }

              final newLevel = (rec['room_level'] as num?)?.toInt();
              if (newLevel != null && newLevel != _roomLevel) {
                _roomLog('[RT-ROOM] room_level $newLevel');
                _roomLevel = newLevel;
                if (newLevel > _lastShownLevel && mounted) {
                  _lastShownLevel = newLevel;
                  _showRoomLevelUpOverlay(newLevel);
                }
              }

              final newXp = (rec['room_xp'] as num?)?.toInt();
              if (newXp != null && newXp != _roomXp) _roomXp = newXp;

              final newXpTodayGift =
                  (rec['xp_today_gift'] as num?)?.toInt() ?? 0;
              final newXpTodayPassive =
                  (rec['xp_today_passive'] as num?)?.toInt() ?? 0;
              if (rec.containsKey('xp_today_gift') ||
                  rec.containsKey('xp_today_passive')) {
                _xpToday = newXpTodayGift + newXpTodayPassive;
              }

              final newXpWeek = (rec['xp_week'] as num?)?.toInt();
              if (newXpWeek != null) _xpWeek = newXpWeek;

              final newStreak = (rec['daily_streak'] as num?)?.toInt();
              if (newStreak != null) _dailyStreak = newStreak;

              final newMult = (rec['streak_multiplier'] as num?)?.toDouble();
              if (newMult != null) _streakMultiplier = newMult;

              final newIsLocked = rec['is_locked'] as bool?;
              if (newIsLocked != null && newIsLocked != _roomIsLocked) {
                _roomIsLocked = newIsLocked;
              }

              final newIsClosed = rec['is_closed'] as bool?;
              if (newIsClosed != null && newIsClosed != _roomIsClosed) {
                _roomIsClosed = newIsClosed;
              }

              final newAllowImages = rec['allow_images'] as bool?;
              if (newAllowImages != null &&
                  newAllowImages != _roomAllowImages) {
                _roomAllowImages = newAllowImages;
              }

              final newRoomMuted = rec['is_room_muted'] as bool?;
              if (newRoomMuted != null && newRoomMuted != _roomIsMuted) {
                _roomLog('[RT-ROOM] is_room_muted=$newRoomMuted');
                _roomIsMuted = newRoomMuted;
              }

              // --- images (evict stale cache before assigning new URL) ---
              final updatedAt = rec['updated_at'] as String?;
              final ts = updatedAt != null
                  ? DateTime.tryParse(updatedAt)
                  : null;
              if (ts != null) _roomUpdatedAt = ts;

              final newBg = rec['background_url'] as String?;
              if (rec.containsKey('background_url') &&
                  newBg != _roomBackgroundUrl) {
                _roomLog(
                  '[RT-ROOM] background_url $_roomBackgroundUrl â†’ $newBg',
                );
                if (_roomBackgroundUrl != null) {
                  imageCache.evict(NetworkImage(_roomBackgroundUrl!));
                }
                _roomBackgroundUrl = newBg;
              }

              final newCover = rec['cover_url'] as String?;
              if (rec.containsKey('cover_url') && newCover != _roomCoverUrl) {
                _roomLog('[RT-ROOM] cover_url â†’ $newCover');
                if (_roomCoverUrl != null) {
                  imageCache.evict(NetworkImage(_roomCoverUrl!));
                }
                _roomCoverUrl = newCover;
              }

              final newAvatar = rec['room_avatar_url'] as String?;
              if (rec.containsKey('room_avatar_url') &&
                  newAvatar != _roomAvatarUrl) {
                _roomLog('[RT-ROOM] room_avatar_url â†’ $newAvatar');
                if (_roomAvatarUrl != null) {
                  imageCache.evict(NetworkImage(_roomAvatarUrl!));
                }
                _roomAvatarUrl = newAvatar;
              }
            });
          },
        )
        .subscribe((status, [error]) {
          _roomLog(
            '[RT-ROOM] status=$status error=$error room=${widget.room.id}',
          );
        });
  }

  void _subscribeToMembers() {
    _membersChannel = SupabaseService.requiredClient
        .channel('room_members_${widget.room.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.room.id,
          ),
          callback: (payload) {
            if (!mounted) return;
            _roomLog(
              '[RT-MEMBERS] event=${payload.eventType} id=${payload.newRecord["id"]} muted=${payload.newRecord["is_muted"]}',
            );
            _debouncedLoadMembers();
          },
        )
        .subscribe((status, [error]) {
          _roomLog(
            '[RT-MEMBERS] status=$status error=$error room=${widget.room.id}',
          );
        });
  }

  void _subscribeToGiftTransactions() {
    _giftTransactionsChannel = SupabaseService.requiredClient
        .channel('room_gifts_${widget.room.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'gift_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.room.id,
          ),
          callback: (payload) {
            if (!mounted) return;

            // Use the insert payload directly so luxury video shows without
            // waiting for the DB read - avoids the read-before-write race on
            // the receiver's phone.
            _roomLog(
              '[RT-RED] event room=${widget.room.id} new=${payload.newRecord} old=${payload.oldRecord}',
            );
            final record = payload.newRecord;
            if (kDebugMode) {
              _roomLog(
                '[Gift] event received room=${widget.room.id} '
                'id=${record['id']} code=${record['gift_code']} '
                'sender=${record['sender_id']} receiver=${record['receiver_id']}',
              );
            }
            if (record.isNotEmpty) {
              final giftCode = record['gift_code'] as String? ?? '';
              final giftName = record['gift_name'] as String? ?? '';
              final receiverId = record['receiver_id'] as String? ?? '';

              final config = SroodLuxuryGiftVideoConfig.fromCode(giftCode);
              if (config != null &&
                  _activeLuxuryGiftVideo == null &&
                  _visualEnabled) {
                String receiverLabel = '';
                for (final m in _members) {
                  if (m.userId == receiverId) {
                    receiverLabel = m.fallbackName(context.isArabic);
                    break;
                  }
                }
                _playLuxuryGiftVideo(
                  giftName: giftName,
                  receiverName: receiverLabel,
                  config: config,
                );
              }
            }

            // Refresh the gift feed list with a short delay so the DB read
            // catches up after the WAL-based realtime push.
            Future.delayed(const Duration(milliseconds: 400), () {
              if (!mounted) return;
              unawaited(
                _loadRoomGifts(showLoading: false, showNewestBanner: true),
              );
              // When PK is active, refresh team scores after every gift.
              if (_activePk?.isActive == true) unawaited(_loadActivePk());
            });
          },
        )
        .subscribe((status, [error]) {
          if (kDebugMode) {
            _roomLog('[Gift] realtime channel status=$status error=$error');
          }
          // Surface a clean message instead of silently failing if the room
          // gift realtime channel can't be established.
          if (!mounted) return;
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            SroodToast.show(
              context,
              context.isArabic
                  ? 'ÙØ´Ù„ Ø§ØªØµØ§Ù„ Ø§Ù„Ù‡Ø¯Ø§ÙŠØ§ Ø§Ù„Ù…Ø¨Ø§Ø´Ø±Ø©. Ù‚Ø¯ Ù„Ø§ ØªØ¸Ù‡Ø± Ø§Ù„Ù‡Ø¯Ø§ÙŠØ§ ÙÙˆØ±Ø§Ù‹.'
                  : 'Live gift connection failed. Gifts may not appear instantly.',
              type: SroodToastType.warning,
            );
          }
        });
  }

  Future<void> _loadRoomGifts({
    bool showLoading = true,
    bool showNewestBanner = false,
  }) async {
    final previousLatestId = _roomGifts.isNotEmpty ? _roomGifts.first.id : null;

    try {
      final gifts = _activeRoomGifts(
        await _giftsService.getRoomGiftTransactions(widget.room.id),
      );

      if (!mounted) return;

      setState(() {
        _roomGifts = gifts;
      });

      if (showNewestBanner &&
          gifts.isNotEmpty &&
          gifts.first.id != previousLatestId) {
        _showRoomGiftBanner(gifts.first);
        _showLuxuryGiftFromTransaction(gifts.first);
      }
      _cleanupExpiredRoomGifts();
    } catch (error) {
      if (!mounted || !showLoading) return;

      SroodToast.show(context, error.toString(), type: SroodToastType.error);
    }
  }

  void _showRoomGiftBanner(RoomGiftTransaction gift) {
    _giftBannerTimer?.cancel();
    _giftBannerNotifier.value = gift;
    _giftBannerTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_giftBannerNotifier.value?.id == gift.id) {
        _giftBannerNotifier.value = null;
      }
    });
  }

  Future<void> _loadMembers({
    bool showLoading = true,
    bool detectVipEntry = false,
  }) async {
    final previousMemberIds = detectVipEntry
        ? _members.map((member) => member.userId).toSet()
        : <String>{};

    try {
      final t0 = DateTime.now().millisecondsSinceEpoch;
      final members = await _roomsService.getActiveRoomMembers(widget.room.id);
      _roomLog(
        '[PerfRoom] members loaded in ${DateTime.now().millisecondsSinceEpoch - t0}ms count=${members.length}',
      );

      if (!mounted) return;

      // Detect if the current user was removed / kicked by someone else.
      // Guard: only check after the initial load (_members is non-empty or we
      // already had at least one successful load), and never during self-exit.
      // Two consecutive misses are required before auto-leaving so a single
      // slow heartbeat on a weak network doesn't eject the user spuriously.
      final currentUserId = _currentUserId;
      if (!_leaving &&
          currentUserId != null &&
          _members.isNotEmpty &&
          !members.any((m) => m.userId == currentUserId)) {
        _missedHeartbeatCount++;
        _roomLog(
          '[MODERATION] kicked detection: user=$currentUserId not in active members (miss #$_missedHeartbeatCount)',
        );
        if (_missedHeartbeatCount >= 2) {
          if (mounted) {
            SroodToast.show(
              context,
              context.isArabic
                  ? 'ØªÙ…Øª Ø¥Ø²Ø§Ù„ØªÙƒ Ù…Ù† Ø§Ù„ØºØ±ÙØ©'
                  : 'You were removed from the room',
              type: SroodToastType.info,
            );
            await _leaveRoom();
          }
          return;
        }
        // First miss only â€” wait for the next load cycle before deciding.
        return;
      }
      // User confirmed present â€” reset the miss counter.
      _missedHeartbeatCount = 0;

      setState(() {
        _members = members;
      });

      if (detectVipEntry) {
        _showEntryForNewMembers(members, previousMemberIds);
      }

      await _syncMicConnectionWithSeat();
    } catch (error) {
      if (!mounted) return;

      if (showLoading) {
        SroodToast.show(context, error.toString(), type: SroodToastType.error);
      }
    }
  }

  void _showEntryForNewMembers(
    List<RoomMember> members,
    Set<String> previousMemberIds,
  ) {
    final currentUserId = _currentUserId;

    for (final member in members) {
      if (previousMemberIds.contains(member.userId) ||
          member.userId == currentUserId) {
        continue;
      }

      final level = member.effectiveVipLevel;
      if (VipFeatures.hasEntryBanner(level)) {
        _entryBannerTimer?.cancel();
        _entryBannerNotifier.value = null;
        _vipEntryBannerTimer?.cancel();
        _vipBannerNotifier.value = member;
        _vipEntryBannerTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          if (_vipBannerNotifier.value?.userId == member.userId) {
            _vipBannerNotifier.value = null;
          }
        });
      } else {
        _vipEntryBannerTimer?.cancel();
        _entryBannerTimer?.cancel();
        _entryBannerNotifier.value = member;
        _entryBannerTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          if (_entryBannerNotifier.value?.userId == member.userId) {
            _entryBannerNotifier.value = null;
          }
        });
      }
      break;
    }
  }

  Future<void> _loadModeratorCount() async {
    try {
      final mods = await const RoomManagementService().getModerators(
        widget.room.id,
      );
      if (mounted) {
        setState(() {
          _moderatorCount = mods.length;
          _isCurrentUserModerator = mods.any((m) => m.userId == _currentUserId);
          _moderatorUserIds = mods.map((m) => m.userId).toSet();
        });
      }
    } catch (e, st) {
      debugError('_RoomDetailsScreenState._loadModerators', e, st);
    }
  }

  Future<void> _loadAnnouncement() async {
    try {
      final ann = await const RoomManagementService().getActiveAnnouncement(
        widget.room.id,
      );
      if (mounted) setState(() => _activeAnnouncementText = ann?.message);
    } catch (e, st) {
      debugError('_RoomDetailsScreenState._loadAnnouncement', e, st);
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final wallet = await const WalletService().fetchWallet();
      if (mounted) setState(() => _walletCoins = wallet.coinsBalance);
    } catch (e, st) {
      debugError('_RoomDetailsScreenState._loadWalletBalance', e, st);
    }
  }

  /// Fetches authoritative XP/level state from the server.
  /// Called on init and after every reconnect so widget.room staleness never
  /// causes the displayed level to lag behind the server truth.
  Future<void> _refreshRoomXpStats() async {
    try {
      final result = await SupabaseService.requiredClient.rpc(
        'get_room_xp_stats',
        params: {'p_room_id': widget.room.id},
      );
      if (!mounted || result == null) return;
      final data = result as Map<String, dynamic>;
      final newLevel = (data['room_level'] as num?)?.toInt() ?? _roomLevel;
      setState(() {
        if (newLevel > _lastShownLevel) {
          _lastShownLevel = newLevel;
          _showRoomLevelUpOverlay(newLevel);
        }
        _roomLevel = newLevel;
        _roomXp = (data['room_xp'] as num?)?.toInt() ?? _roomXp;
        _xpToday = (data['xp_today'] as num?)?.toInt() ?? _xpToday;
        _xpWeek = (data['xp_week'] as num?)?.toInt() ?? _xpWeek;
        _dailyStreak = (data['daily_streak'] as num?)?.toInt() ?? _dailyStreak;
        _streakMultiplier =
            (data['streak_multiplier'] as num?)?.toDouble() ??
            _streakMultiplier;
      });
      _roomLog(
        '[Room] refreshRoomXpStats level=$newLevel xp=${data['room_xp']}',
      );
    } catch (e) {
      _roomLog('[Room] refreshRoomXpStats failed: $e');
    }
  }

  void _subscribeWalletBalance() {
    final uid = _currentUserId;
    if (uid == null) return;
    _walletChannel = SupabaseService.requiredClient
        .channel('wallet_balance_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            final newBalance = payload.newRecord['coins_balance'];
            if (newBalance is int && mounted) {
              setState(() => _walletCoins = newBalance);
            }
          },
        )
        .subscribe();
  }

  void _redirectToWallet() {
    if (_rechargeRedirecting || !mounted) return;
    _rechargeRedirecting = true;
    _roomLog('[GiftRecharge] redirect start â†’ WalletScreen');

    final isArabic = context.isArabic;

    Future.delayed(const Duration(milliseconds: 300), () async {
      if (!mounted) {
        _rechargeRedirecting = false;
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WalletScreen(isArabic: isArabic),
        ),
      );
      if (mounted) unawaited(_loadWalletBalance());
      _rechargeRedirecting = false;
      _roomLog('[GiftRecharge] redirect done â€” balance refreshed');
    });
  }

  // -- Room messages ----------------------------------------------------------

  Future<void> _loadMessages() async {
    final msgs = await _msgService.fetchRecent(widget.room.id);
    if (!mounted) return;
    setState(() {
      _chatMessages
        ..clear()
        ..addAll(msgs);
    });
  }

  void _subscribeToMessages() {
    _messagesChannel = SupabaseService.requiredClient
        .channel('room_messages_${widget.room.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'room_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.room.id,
          ),
          callback: (payload) {
            if (!mounted) return;
            try {
              final row = payload.newRecord;
              final senderId = row['sender_id'] as String?;

              // Apply an enriched message row to the chat feed.
              void applyProfile(Map<String, dynamic>? profile) {
                if (!mounted) return;
                final enriched = <String, dynamic>{
                  ...row,
                  'profiles': ?profile,
                };
                final msg = RoomMessage.fromJson(
                  enriched.map((k, v) => MapEntry(k, v)),
                );
                if (_chatMessages.any((m) => m.id == msg.id)) return;
                setState(() {
                  _chatMessages.removeWhere(
                    (m) =>
                        m.id.startsWith('optimistic_') &&
                        m.senderId == msg.senderId,
                  );
                  _chatMessages.add(msg);
                  if (_chatMessages.length > 100) {
                    _chatMessages.removeRange(0, _chatMessages.length - 100);
                  }
                });
              }

              // Use local member cache first â€” avoids a DB round-trip per
              // message, which on active chats was causing N serial queries.
              final cached = senderId != null
                  ? _members.where((m) => m.userId == senderId).firstOrNull
                  : null;

              if (cached != null) {
                applyProfile({
                  'display_name': cached.displayName,
                  'username': cached.username,
                  'avatar_url': cached.avatarUrl,
                  'vip_level': cached.vipLevel,
                  'is_official_agent': cached.isOfficialAgent,
                  'agency_name': cached.agencyName,
                  'agency_country': cached.agencyCountry,
                });
              } else if (senderId != null) {
                // Cache miss (sender not yet in _members): fall back to DB.
                SupabaseService.requiredClient
                    .from('profiles')
                    .select('display_name, username, avatar_url, vip_level')
                    .eq('id', senderId)
                    .maybeSingle()
                    .then(applyProfile);
              } else {
                applyProfile(null);
              }
            } catch (e, st) {
              debugError(
                '_RoomDetailsScreenState._subscribeToMessages.insert',
                e,
                st,
              );
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'room_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.room.id,
          ),
          callback: (payload) {
            if (!mounted) return;
            try {
              final row = payload.newRecord;
              final isRemoved = row['is_removed'] as bool? ?? false;
              if (!isRemoved) return;
              final msgId = row['id'] as String?;
              if (msgId == null) return;
              final idx = _chatMessages.indexWhere((m) => m.id == msgId);
              if (idx == -1) return;
              setState(() {
                _chatMessages[idx] = _chatMessages[idx].copyWithRemoved();
              });
            } catch (e, st) {
              debugError(
                '_RoomDetailsScreenState._subscribeToMessages.update',
                e,
                st,
              );
            }
          },
        )
        .subscribe();
  }

  bool get _canRemoveMessages =>
      _iAmRoomOwner || _iAmHost || _isCurrentUserModerator;

  Future<void> _removeMessage(RoomMessage msg) async {
    final isArabic = context.isArabic;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1A0D2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isArabic ? 'Ø­Ø°Ù Ø§Ù„Ø±Ø³Ø§Ù„Ø©' : 'Remove message',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isArabic
                    ? 'Ù‡Ø°Ù‡ Ø§Ù„Ø±Ø³Ø§Ù„Ø© Ø³ØªÙØ®ÙÙ‰ Ø¹Ù† Ø¬Ù…ÙŠØ¹ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù…ÙŠÙ†.'
                    : 'This message will be hidden from all users.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(isArabic ? 'Ø¥Ù„ØºØ§Ø¡' : 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(isArabic ? 'Ø­Ø°Ù' : 'Remove'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _msgService.removeMessage(msg.id);
    } catch (e) {
      if (mounted) {
        SroodToast.show(
          context,
          context.isArabic
              ? 'ØªØ¹Ø°Ù‘Ø± Ø­Ø°Ù Ø§Ù„Ø±Ø³Ø§Ù„Ø©'
              : 'Could not remove message',
          type: SroodToastType.error,
        );
      }
    }
  }

  Future<void> _reportChatMessage(RoomMessage msg) async {
    if (msg.senderId == _currentUserId) return;
    final isArabic = context.isArabic;
    final submitted = await ReportReasonSheet.show(
      context,
      reportedUserId: msg.senderId,
      roomId: widget.room.id,
      isArabic: isArabic,
    );
    if (submitted == true && mounted) {
      SroodToast.show(
        context,
        isArabic
            ? 'ØªÙ… Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„Ø¨Ù„Ø§Øº Ø¥Ù„Ù‰ ÙØ±ÙŠÙ‚ Ø§Ù„Ø¥Ø´Ø±Ø§Ù.'
            : 'Report sent to moderation.',
        type: SroodToastType.success,
      );
    }
  }

  Future<void> _sendChatMessage(String text) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (text.trim().isEmpty) return;
    setState(() => _isSendingMessage = true);

    // â”€â”€ Client-side text moderation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final modResult = const ModerationService().checkMessage(text);
    if (!modResult.passed) {
      if (modResult.action == ModerationAction.warn) {
        // Severity 1: show warning but still allow send â€” log in background.
        SroodToast.show(
          context,
          context.isArabic
              ? 'ØªØ­Ø°ÙŠØ±: ÙŠØ±Ø¬Ù‰ Ø§Ù„ØªØ­Ø¯Ø« Ø¨Ø§Ø­ØªØ±Ø§Ù….'
              : 'Warning: please be respectful.',
          type: SroodToastType.warning,
        );
        unawaited(
          const ModerationService().logEvent(
            roomId: widget.room.id,
            source: 'chat',
            violationType: modResult.violationType,
            severity: modResult.severity,
            originalText: text.trim(),
            normalizedText: modResult.matchedRule,
            matchedRule: modResult.matchedRule,
            actionTaken: 'warned',
          ),
        );
        // fall through and send the message
      } else {
        // Severity 2+: block message.
        setState(() => _isSendingMessage = false);
        SroodToast.show(
          context,
          context.isArabic
              ? 'ØªÙ… Ø­Ø¸Ø± Ø±Ø³Ø§Ù„ØªÙƒ Ø¨Ø³Ø¨Ø¨ Ø§Ù†ØªÙ‡Ø§Ùƒ Ù‚ÙˆØ§Ø¹Ø¯ Ø§Ù„Ø³Ù„Ø§Ù…Ø©.'
              : 'Message blocked by safety rules.',
          type: SroodToastType.error,
        );
        unawaited(
          const ModerationService().logEvent(
            roomId: widget.room.id,
            source: 'chat',
            violationType: modResult.violationType,
            severity: modResult.severity,
            originalText: text.trim(),
            normalizedText: modResult.matchedRule,
            matchedRule: modResult.matchedRule,
            actionTaken: 'blocked',
          ),
        );
        return;
      }
    }

    // Optimistic insert using current user profile.
    final me = SupabaseService.requiredClient.auth.currentUser;
    final myMember = _myMember;
    if (me != null) {
      final optimistic = RoomMessage(
        id: 'optimistic_${DateTime.now().millisecondsSinceEpoch}',
        roomId: widget.room.id,
        senderId: me.id,
        senderName: myMember?.displayName ?? 'You',
        senderAvatarUrl: myMember?.avatarUrl,
        senderVipLevel: myMember?.effectiveVipLevel ?? 0,
        senderRole: myMember?.role ?? 'listener',
        message: text.trim(),
        messageType: 'text',
        createdAt: DateTime.now(),
        senderIsOfficialAgent: myMember?.isOfficialAgent ?? false,
        senderAgencyName: myMember?.agencyName,
        senderAgencyCountry: myMember?.agencyCountry,
      );
      setState(() => _chatMessages.add(optimistic));
    }

    try {
      await _msgService.sendMessage(
        roomId: widget.room.id,
        message: text,
        senderRole: _myMember?.role ?? 'listener',
      );
    } on UserMutedException catch (e) {
      if (mounted) {
        setState(
          () =>
              _chatMessages.removeWhere((m) => m.id.startsWith('optimistic_')),
        );
        SroodToast.show(context, e.displayMessage, type: SroodToastType.error);
      }
    } catch (e, st) {
      debugError('_RoomDetailsScreenState._sendChatMessage', e, st);
      // Remove optimistic on any other failure.
      if (mounted) {
        setState(
          () =>
              _chatMessages.removeWhere((m) => m.id.startsWith('optimistic_')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
    }
  }

  Future<void> _sendChatImageMessage() async {
    _roomLog('[RoomImage] _sendChatImageMessage tapped');
    // Check room-level permission first
    if (!_roomAllowImages) {
      if (!mounted) return;
      SroodToast.show(
        context,
        context.isArabic
            ? 'Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„ØµÙˆØ± Ù…Ø¹Ø·Ù‘Ù„ ÙÙŠ Ù‡Ø°Ù‡ Ø§Ù„ØºØ±ÙØ©'
            : 'Sending images is disabled in this room',
        type: SroodToastType.info,
      );
      return;
    }
    // Fast path: local cached VIP level is already enough.
    final localVipLevel = _myMember?.effectiveVipLevel ?? 0;
    bool canSend = localVipLevel >= 7;

    // Slow path: local data may be stale (e.g. VIP was just granted).
    // Call the backend gate which reads profiles directly.
    if (!canSend) {
      try {
        final uid = SupabaseService.requiredClient.auth.currentUser?.id;
        if (uid != null) {
          final result = await SupabaseService.requiredClient.rpc(
            'can_user_send_chat_image',
            params: {'p_user_id': uid},
          );
          canSend = result == true;
        }
      } catch (e) {
        _roomLog('[chat-image] backend VIP check failed, using local: $e');
      }
    }

    if (!canSend) {
      if (!mounted) return;
      SroodToast.show(
        context,
        context.isArabic
            ? 'Ø±Ø³Ø§Ø¦Ù„ Ø§Ù„ØµÙˆØ± ØªÙÙØªØ­ Ù…Ù† VIP 7'
            : 'Image messages unlock at VIP 7',
        type: SroodToastType.info,
      );
      return;
    }

    setState(() => _uploadingChatImage = true);
    try {
      final userId = _currentUserId;
      if (userId == null) return;

      final result = await const RoomChatImageUploadService().pickAndUpload(
        userId: userId,
        roomId: widget.room.id,
      );
      if (result == null) return; // user cancelled

      await _msgService.sendImageMessage(
        roomId: widget.room.id,
        imageUrl: result.url,
        imagePath: result.path,
        senderRole: _myMember?.role ?? 'listener',
      );
    } catch (e, st) {
      _roomLog('[RoomImage] failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      // Map known server error codes to clear, localized messages so a failure
      // is never a silent / generic "try again".
      final isArabic = context.isArabic;
      final raw = e.toString();
      String msg;
      if (e is ArgumentError) {
        msg = e.message.toString();
      } else if (raw.contains('user_muted')) {
        msg = isArabic
            ? 'Ø£Ù†Øª Ù…ÙƒØªÙˆÙ… ÙˆÙ„Ø§ ÙŠÙ…ÙƒÙ†Ùƒ Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„ØµÙˆØ±.'
            : 'You are muted and cannot send images.';
      } else if (raw.contains('image_messages_unlock_at_vip_7') ||
          raw.contains('vip7')) {
        msg = isArabic
            ? 'Ø±Ø³Ø§Ø¦Ù„ Ø§Ù„ØµÙˆØ± ØªÙÙØªØ­ Ù…Ù† VIP 7'
            : 'Image messages unlock at VIP 7';
      } else if (raw.contains('room_not_found')) {
        msg = isArabic
            ? 'Ø§Ù„ØºØ±ÙØ© ØºÙŠØ± Ù…ØªØ§Ø­Ø©.'
            : 'Room not available.';
      } else {
        msg = isArabic
            ? 'ØªØ¹Ø°Ù‘Ø± Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„ØµÙˆØ±Ø©. Ø­Ø§ÙˆÙ„ Ù…Ø±Ø© Ø£Ø®Ø±Ù‰.'
            : 'Failed to send image. Please try again.';
      }
      SroodToast.show(context, msg, type: SroodToastType.error);
    } finally {
      if (mounted) setState(() => _uploadingChatImage = false);
    }
  }

  void _clearChat() {
    // Clear the visible chat feed. Host-only UX action.
    setState(() {
      _roomGifts = const [];
      _chatMessages.clear();
      _chatMessages.add(
        RoomMessage.local(
          roomId: widget.room.id,
          message: context.isArabic
              ? 'Ù‚Ø§Ù… Ø§Ù„Ù…Ø¶ÙŠÙ Ø¨Ù…Ø³Ø­ Ø§Ù„Ø¯Ø±Ø¯Ø´Ø©.'
              : 'The room owner has cleaned the chat.',
        ),
      );
    });
  }

  // ignore: unused_element
  void _sendSalute() {
    if (_currentUserId == null) return;
    final senderName =
        _members
            .where((m) => m.userId == _currentUserId)
            .firstOrNull
            ?.displayName ??
        (context.isArabic ? 'User' : 'User');
    final text = '$senderName sent a salute to the room ??';
    setState(() {
      _chatMessages.add(
        RoomMessage.local(roomId: widget.room.id, message: text),
      );
    });
  }

  /// Stops music locally and propagates the stop to all room participants.
  /// Guarded by [_musicAction] â€” only the controller (or a manager after stop)
  /// can call this successfully.
  Future<void> _stopMusicForRoom() async {
    await _musicAction(() async {
      try {
        await _syncedMusic.stopForRoom();
      } catch (e, st) {
        debugError('RoomDetailsScreen._stopMusic', e, st);
        if (!mounted) return;
        SroodToast.show(
          context,
          context.isArabic
              ? 'ØªØ¹Ø°Ù‘Ø± Ø¥ÙŠÙ‚Ø§Ù Ø§Ù„Ù…ÙˆØ³ÙŠÙ‚Ù‰. Ø­Ø§ÙˆÙ„ Ù…Ø¬Ø¯Ø¯Ø§Ù‹.'
              : 'Could not stop music. Please try again.',
          type: SroodToastType.error,
        );
      }
    });
  }

  void _openMusicPanel() {
    final isManager = _iAmRoomOwner || _iAmHost || _isCurrentUserModerator;
    final controllerId = _syncedMusic.lastState?.controllerUserId;
    final isController = controllerId == _currentUserId;
    // Can manage = user is the controller of the current track,
    // OR no music is playing (any manager may start a new track).
    final canManage =
        isManager &&
        (isController || controllerId == null || controllerId.isEmpty);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MusicPanel(
        musicService: _musicService,
        isArabic: context.isArabic,
        canManage: canManage,
        controllerUserId: controllerId,
        currentUserId: _currentUserId,
        syncedMusic: _syncedMusic,
        roomId: widget.room.id,
        uploadService: canManage ? _uploadService : null,
        onTrackSelected: canManage
            ? (song) {
                _roomLog(
                  '[RoomMusic] controller selected id=${song.id} url=${song.url}',
                );
                _musicService.addToPlaylist(song);
                final idx = _musicService.playlist.indexWhere(
                  (s) => s.id == song.id,
                );
                if (idx >= 0) {
                  unawaited(_syncedMusic.playSongForRoom(idx));
                }
              }
            : null,
      ),
    );
  }

  void _openReactionPicker() {
    ReactionPickerSheet.show(context, onPick: _sendReaction);
  }

  /// Opens Room Owner Management screen (Overview / Moderators / Bans / Settings).
  /// Only accessible to the room owner or host.
  Future<void> _openRoomManagement() async {
    if (!(_iAmRoomOwner || _iAmHost)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoomOwnerManagementScreen(
          room: _currentRoom,
          isArabic: context.isArabic,
        ),
      ),
    );
    // Refresh member list / moderators in case anything changed inside.
    if (mounted) _loadMembers(showLoading: false);
  }

  Future<void> _openToolsSheet() async {
    // If the current user is not in the member list yet (heartbeat timing race),
    // refresh once before opening so permissions are accurate.
    if (_myMember == null && !_iAmRoomOwner) {
      await _loadMembers(showLoading: false);
      if (!mounted) return;
    }

    final isOwner = _iAmRoomOwner;
    final isHost = _iAmHost;
    final isModerator = _isCurrentUserModerator;
    _roomLog(
      '[RoomPerm] currentUserId=$_currentUserId ownerId=${widget.room.ownerId} '
      'memberRole=${_myMember?.role} isOwner=$isOwner isHost=$isHost '
      'isModerator=$isModerator',
    );

    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RoomToolsSheet(
        room: _currentRoom,
        isArabic: context.isArabic,
        isOwner: isOwner,
        isHost: isHost,
        isModerator: isModerator,
        moderatorCount: _moderatorCount,
        onClearChat: _clearChat,
        onMaxSeatsChanged: (seats) {
          setState(() => _currentMaxSeats = seats);
        },
        onBackgroundChanged: (url) {
          setState(() => _roomBackgroundUrl = url);
        },
        micMembers: _members
            .where((m) => m.role == 'host' || m.role == 'speaker')
            .toList(),
        activePkSessionId: _activePk?.isActive == true ? _activePk?.id : null,
        onPkStarted: () => unawaited(_loadActivePk()),
        onPkCancelRequested: _handlePkCancelRequested,
        onMusicTap: _openMusicPanel,
        onRedEnvelopeCreated: (envelope) {
          if (!mounted) return;
          final spent = (envelope['total_coins'] as num?)?.toInt() ?? 0;
          final envelopeId = envelope['id'] as String? ?? '';
          _roomLog('[LuckyBag] created by sender id=$envelopeId');
          // Allow new envelope from sender to appear even if prior bag was dismissed.
          _sessionDismissedEnvelopeIds.remove(envelopeId);
          setState(() {
            _showLuckyBagEntrance = false;
            // Optimistic decrement so toolbar balance updates instantly.
            if (spent > 0) {
              _walletCoins = (_walletCoins - spent).clamp(0, _walletCoins);
            }
          });
          _showRedEnvelopeBanner(envelope);
          // Background sync to confirm real server balance.
          unawaited(_loadWalletBalance());
        },
        onSoundChanged: (v) => setState(() => _soundEnabled = v),
        onVisualChanged: (v) => setState(() => _visualEnabled = v),
      ),
    );
  }

  Room get _currentRoom => Room(
    id: widget.room.id,
    ownerId: widget.room.ownerId,
    name: _roomName,
    description: _roomDescription,
    language: _roomLanguage ?? widget.room.language,
    livekitRoomName: widget.room.livekitRoomName,
    maxSeats: _currentMaxSeats,
    isPrivate: widget.room.isPrivate,
    isLocked: _roomIsLocked,
    isClosed: _roomIsClosed,
    createdAt: widget.room.createdAt,
    coverUrl: _roomCoverUrl,
    backgroundUrl: _roomBackgroundUrl,
    avatarUrl: _roomAvatarUrl,
    roomCode: widget.room.roomCode,
    roomLevel: _roomLevel,
    isRoomMuted: _roomIsMuted,
    allowImages: _roomAllowImages,
    closedSeats: _closedSeats.toList(),
  );

  Future<void> _pickListenerForSeat(int seatNumber) async {
    if (_myMember == null) {
      return;
    }

    final canManage = _iAmRoomOwner || _iAmHost || _isCurrentUserModerator;
    final isSeatLocked = _closedSeats.contains(seatNumber);

    // Non-managers cannot enter a locked seat.
    if (isSeatLocked && !canManage) return;

    // If it's locked and user is a manager, show close/open options only.
    if (isSeatLocked && canManage) {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: const Color(0xFF12091D),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) {
          final isArabic = sheetContext.isArabic;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    isArabic
                        ? 'Ù…ÙŠÙƒ $seatNumber Ù…ØºÙ„Ù‚'
                        : 'Mic $seatNumber is closed',
                    textAlign: isArabic ? TextAlign.right : TextAlign.left,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1E6B3C),
                      ),
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: Text(
                        isArabic ? 'ÙØªØ­ Ø§Ù„Ù…ÙŠÙƒØ±ÙˆÙÙˆÙ†' : 'Open mic',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (confirmed == true) await _toggleSeatClosed(seatNumber);
      return;
    }

    final selectedMicMoveMember = _iAmHost ? _selectedMicMoveMember : null;
    if (_iAmHost && selectedMicMoveMember != null) {
      setState(() {
        _selectedMicMoveMember = null;
      });

      if (selectedMicMoveMember.role == 'speaker') {
        await _moveMemberToSeat(
          member: selectedMicMoveMember,
          seatNumber: seatNumber,
        );
      } else {
        await _changeMemberRole(
          member: selectedMicMoveMember,
          role: 'speaker',
          seatNumber: seatNumber,
        );
      }
      return;
    }

    final availableMembers = _iAmHost
        ? _members.where((member) => member.role != 'host').toList()
        : <RoomMember>[];

    final selected = await showModalBottomSheet<SroodEmptySeatAction>(
      context: context,
      backgroundColor: const Color(0xFF12091D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: context.isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  context.isArabic
                      ? '\u0627\u0644\u0627\u0646\u062a\u0642\u0627\u0644 \u0625\u0644\u0649 \u0645\u0627\u064a\u0643 $seatNumber'
                      : 'Move to Mic $seatNumber',
                  textAlign: context.isArabic
                      ? TextAlign.right
                      : TextAlign.left,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(
                        sheetContext,
                      ).pop(const SroodEmptySeatAction.moveSelf());
                    },
                    icon: const Icon(Icons.event_seat_rounded),
                    label: Text(
                      context.isArabic
                          ? '\u0627\u0646\u0642\u0644\u0646\u064a \u0625\u0644\u0649 \u0647\u0630\u0627 \u0627\u0644\u0645\u0627\u064a\u0643'
                          : 'Move myself here',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (canManage) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6B6B),
                        side: const BorderSide(
                          color: Color(0xFFFF6B6B),
                          width: 1.2,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(sheetContext).pop(null);
                        _toggleSeatClosed(seatNumber);
                      },
                      icon: const Icon(Icons.lock_rounded, size: 18),
                      label: Text(
                        context.isArabic
                            ? '\u0625\u063a\u0644\u0627\u0642 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646'
                            : 'Close mic',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_iAmHost && availableMembers.isEmpty)
                  Text(
                    context.isArabic
                        ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0623\u0639\u0636\u0627\u0621 \u0645\u062a\u0627\u062d\u0648\u0646 \u0644\u0647\u0630\u0627 \u0627\u0644\u0645\u0627\u064a\u0643.'
                        : 'No available users for this mic.',
                    textAlign: context.isArabic
                        ? TextAlign.right
                        : TextAlign.left,
                    style: const TextStyle(
                      color: Color(0xFFD8CFEA),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (_iAmHost)
                  ...availableMembers.map(
                    (member) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SroodRoomAvatar(
                        avatarUrl: member.avatarUrl,
                        frameKey: member.selectedAvatarFrameKey,
                        vipLevel: member.effectiveVipLevel,
                        size: 42,
                        selected: false,
                        fallbackIcon: Icons.person_rounded,
                        isOfficialAgent: member.isOfficialAgent,
                      ),
                      title: VipUsername(
                        name: member.fallbackName(context.isArabic),
                        vipLevel: member.effectiveVipLevel,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        textAlign: context.isArabic
                            ? TextAlign.right
                            : TextAlign.left,
                      ),
                      subtitle: Text(
                        _roleLabel(member.role),
                        textAlign: context.isArabic
                            ? TextAlign.right
                            : TextAlign.left,
                      ),
                      onTap: () {
                        Navigator.of(
                          sheetContext,
                        ).pop(SroodEmptySeatAction.moveMember(member));
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }

    if (selected.moveSelf) {
      await _moveMyselfToSeat(seatNumber);
      return;
    }

    final selectedMember = selected.member;

    if (selectedMember == null) {
      return;
    }

    await _changeMemberRole(
      member: selectedMember,
      role: 'speaker',
      seatNumber: seatNumber,
    );
  }

  Future<void> _toggleSeatClosed(int seatNumber) async {
    if (!(_iAmRoomOwner || _iAmHost || _isCurrentUserModerator)) return;
    try {
      final updated = await _roomsService.toggleSeatClosed(
        widget.room.id,
        seatNumber,
      );
      if (mounted) setState(() => _closedSeats = updated.toSet());
    } catch (e) {
      if (!mounted) return;
      SroodToast.show(
        context,
        context.isArabic
            ? 'ÙØ´Ù„ ØªØºÙŠÙŠØ± Ø­Ø§Ù„Ø© Ø§Ù„Ù…ÙŠÙƒØ±ÙˆÙÙˆÙ†'
            : 'Failed to toggle mic seat',
        type: SroodToastType.error,
      );
    }
  }

  Future<void> _moveMemberToSeat({
    required RoomMember member,
    required int seatNumber,
  }) async {
    if (!_iAmHost || member.role == 'host') {
      return;
    }

    setState(() {
      _roleBusyUserId = member.userId;
      _selectedMicMoveMember = null;
    });

    try {
      await _roomsService.updateMemberSeatNumber(
        roomId: widget.room.id,
        userId: member.userId,
        seatNumber: seatNumber,
      );

      _replaceMemberLocally(member, seatNumber: seatNumber);

      await _loadMembers(showLoading: false);
    } catch (error) {
      if (!mounted) return;

      SroodToast.show(context, error.toString(), type: SroodToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _roleBusyUserId = null;
        });
      }
    }
  }

  Future<void> _moveMyselfToSeat(int seatNumber) async {
    if (_isSeatMovePending) return;
    setState(() => _isSeatMovePending = true);

    try {
      final myMember = _myMember;

      if (myMember?.role == 'host') {
        await _roomsService.updateMySeatNumber(
          roomId: widget.room.id,
          seatNumber: seatNumber,
        );
      } else {
        await _roomsService.moveMeToSpeakerSeat(
          roomId: widget.room.id,
          seatNumber: seatNumber,
        );
      }

      _replaceMemberLocally(
        myMember,
        role: myMember?.role == 'host' ? null : 'speaker',
        seatNumber: seatNumber,
      );

      // Start mic publishing immediately from local state â€” don't wait for
      // the member reload round-trip, which saves ~500 ms of perceived latency.
      unawaited(_syncMicConnectionWithSeat());

      await _loadMembers(showLoading: false);
    } catch (error) {
      if (!mounted) return;

      final msg = error.toString();
      final isArabic = context.isArabic;

      final String displayMsg;
      if (msg.contains('seat_taken') ||
          msg.contains('already taken') ||
          msg.contains('23505')) {
        displayMsg = isArabic
            ? '\u0647\u0630\u0627 \u0627\u0644\u0645\u0642\u0639\u062f \u0623\u0635\u0628\u062d \u0645\u062d\u062c\u0648\u0632\u0627\u064b. \u0627\u062e\u062a\u0631 \u0645\u0642\u0639\u062f\u0627\u064b \u0622\u062e\u0631.'
            : 'This seat was just taken. Please choose another seat.';
        // Refresh so the UI reflects who now holds the seat.
        _loadMembers(showLoading: false);
      } else if (msg.contains('force_muted')) {
        displayMsg = isArabic
            ? '\u0644\u0642\u062f \u062a\u0645 \u0643\u062a\u0645\u0643 \u0645\u0646 \u0642\u0628\u0644 \u0627\u0644\u0645\u0636\u064a\u0641.'
            : 'You have been muted from speaking by the host.';
      } else if (msg.contains('banned_from_room')) {
        displayMsg = isArabic
            ? '\u0623\u0646\u062a \u0645\u062d\u0638\u0648\u0631 \u0645\u0646 \u0647\u0630\u0647 \u0627\u0644\u063a\u0631\u0641\u0629.'
            : 'You are banned from this room.';
      } else if (msg.contains('not_in_room')) {
        displayMsg = isArabic
            ? '\u0623\u0646\u062a \u0644\u0633\u062a \u0639\u0636\u0648\u0627\u064b \u0646\u0634\u0637\u0627\u064b \u0641\u064a \u0647\u0630\u0647 \u0627\u0644\u063a\u0631\u0641\u0629.'
            : 'You are not an active member of this room.';
      } else {
        displayMsg = isArabic
            ? '\u062d\u062f\u062b \u062e\u0637\u0623. \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.'
            : 'Something went wrong. Please try again.';
      }

      SroodToast.show(context, displayMsg, type: SroodToastType.error);
    } finally {
      if (mounted) setState(() => _isSeatMovePending = false);
    }
  }

  Future<void> _showMemberSeatActions(RoomMember member, int seatNumber) async {
    if (!_iAmHost) {
      return;
    }

    if (member.role == 'host') {
      SroodToast.show(
        context,
        context.isArabic
            ? '\u0644\u0627 \u064a\u0645\u0643\u0646 \u0646\u0642\u0644 \u0645\u0642\u0639\u062f \u0627\u0644\u0645\u0636\u064a\u0641.'
            : 'Host seat cannot be moved.',
        type: SroodToastType.info,
      );
      return;
    }

    final emptySeats = _emptySeatNumbers(exceptUserId: member.userId);

    final action = await showModalBottomSheet<SroodOccupiedSeatAction>(
      context: context,
      backgroundColor: const Color(0xFF12091D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final textAlign = context.isArabic ? TextAlign.right : TextAlign.left;
        final crossAxisAlignment = context.isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: crossAxisAlignment,
              children: [
                Text(
                  member.fallbackName(context.isArabic),
                  textAlign: textAlign,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.isArabic
                      ? '${_roleLabel(member.role)} - \u0645\u0627\u064a\u0643 $seatNumber'
                      : '${_roleLabel(member.role)} - Mic $seatNumber',
                  textAlign: textAlign,
                  style: const TextStyle(
                    color: Color(0xFFD8CFEA),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(
                      sheetContext,
                    ).pop(const SroodOccupiedSeatAction.selectForMove()),
                    icon: const Icon(Icons.touch_app_rounded),
                    label: Text(
                      context.isArabic
                          ? '\u0627\u062e\u062a\u0631\u0647 \u062b\u0645 \u0627\u0636\u063a\u0637 \u0645\u0627\u064a\u0643 \u0641\u0627\u0631\u063a'
                          : 'Select, then tap empty mic',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (emptySeats.isNotEmpty) ...[
                  Text(
                    context.isArabic
                        ? '\u0646\u0642\u0644\u0647 \u0625\u0644\u0649 \u0645\u0627\u064a\u0643 \u0622\u062e\u0631'
                        : 'Move to another mic',
                    textAlign: textAlign,
                    style: const TextStyle(
                      color: Color(0xFFF0C15A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    textDirection: context.isArabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: emptySeats.map((number) {
                      return ActionChip(
                        avatar: const Icon(Icons.event_seat_rounded, size: 18),
                        label: Text('Mic $number'),
                        onPressed: () {
                          Navigator.of(
                            sheetContext,
                          ).pop(SroodOccupiedSeatAction.moveToSeat(number));
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(
                      sheetContext,
                    ).pop(const SroodOccupiedSeatAction.moveToListener()),
                    icon: const Icon(Icons.hearing_rounded),
                    label: Text(
                      context.isArabic
                          ? '\u0625\u0639\u0627\u062f\u062a\u0647 \u0645\u0633\u062a\u0645\u0639\u0627\u064b'
                          : 'Move to listener',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(
                      context.isArabic
                          ? '\u0625\u063a\u0644\u0627\u0642'
                          : 'Close',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null) {
      return;
    }

    if (action.selectForMove) {
      _selectMicMoveMember(member);
      return;
    }

    if (action.seatNumber != null) {
      if (member.role == 'speaker') {
        await _moveMemberToSeat(member: member, seatNumber: action.seatNumber!);
      } else {
        await _changeMemberRole(
          member: member,
          role: 'speaker',
          seatNumber: action.seatNumber,
        );
      }
      return;
    }

    await _changeMemberRole(member: member, role: 'listener');
  }

  void _handleOccupiedSeatTap(RoomMember member, int seatNumber) {
    if (!_iAmHost) return;
    // Route single-tap to the full action sheet (same as long-press) so move
    // mode never activates accidentally from a casual tap.
    _showMemberSeatActions(member, seatNumber);
  }

  void _selectMicMoveMember(RoomMember member) {
    setState(() {
      _selectedMicMoveMember = member;
    });

    SroodToast.show(
      context,
      context.isArabic
          ? '\u0627\u0636\u063a\u0637 \u0639\u0644\u0649 \u0645\u0627\u064a\u0643 \u0641\u0627\u0631\u063a \u0644\u0646\u0642\u0644 ${member.fallbackName(context.isArabic)}.'
          : 'Tap an empty mic to move ${member.fallbackName(context.isArabic)}.',
      type: SroodToastType.info,
    );
  }

  List<int> _emptySeatNumbers({String? exceptUserId}) {
    final maxSeats = _currentMaxSeats;
    final occupied = <int>{};

    for (final member in _members) {
      if (member.userId == exceptUserId) {
        continue;
      }

      if ((member.role == 'host' || member.role == 'speaker') &&
          member.seatNumber != null &&
          member.seatNumber! >= 1 &&
          member.seatNumber! <= maxSeats) {
        occupied.add(member.seatNumber!);
      }
    }

    return List<int>.generate(
      maxSeats,
      (index) => index + 1,
    ).where((number) => !occupied.contains(number)).toList();
  }

  Future<void> _changeMemberRole({
    required RoomMember member,
    required String role,
    int? seatNumber,
  }) async {
    setState(() {
      _roleBusyUserId = member.userId;
    });

    try {
      if (role == 'speaker' && member.role != 'speaker' && _speakerSeatsFull) {
        SroodToast.show(
          context,
          context.isArabic
              ? '\u0645\u0642\u0627\u0639\u062f \u0627\u0644\u0645\u062a\u062d\u062f\u062b\u064a\u0646 \u0645\u0645\u062a\u0644\u0626\u0629.'
              : 'Speaker seats are full.',
          type: SroodToastType.info,
        );
        return;
      }

      await _roomsService.updateMemberRole(
        roomId: widget.room.id,
        userId: member.userId,
        role: role,
        seatNumber: seatNumber,
      );

      _replaceMemberLocally(
        member,
        role: role,
        seatNumber: role == 'speaker' ? seatNumber : null,
      );

      await _loadMembers(showLoading: false);

      if (!mounted) return;

      SroodToast.show(
        context,
        context.isArabic
            ? '\u062a\u0645 \u062a\u062d\u062f\u064a\u062b \u0627\u0644\u062f\u0648\u0631'
            : 'Role updated',
        type: SroodToastType.success,
      );
    } catch (error) {
      if (!mounted) return;

      SroodToast.show(context, error.toString(), type: SroodToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _roleBusyUserId = null;
        });
      }
    }
  }

  Future<bool> _confirmVipKick(RoomMember member) async {
    if (!requiresKickConfirmation(member.effectiveVipLevel)) {
      return true;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171125),
          title: const Text(
            'VIP Protected User',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This user has VIP kick protection. Are you sure you want to remove them from the room?',
            style: TextStyle(color: Color(0xFFD8CFEA)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove Anyway'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _removeMemberFromRoom(RoomMember member) async {
    final targetVipLevel = member.effectiveVipLevel;
    final actorVipLevel = _myMember?.effectiveVipLevel ?? 0;

    if (VipFeatures.hasKickProtection(targetVipLevel) &&
        !_iAmRoomOwner &&
        actorVipLevel < targetVipLevel) {
      SroodToast.show(
        context,
        context.isArabic
            ? '\u0644\u0627 \u064a\u0645\u0643\u0646\u0643 \u0637\u0631\u062f \u0645\u0633\u062a\u062e\u062f\u0645 VIP \u0628\u0647\u0630\u0627 \u0627\u0644\u0645\u0633\u062a\u0648\u0649'
            : 'You cannot remove a VIP user at this level',
        type: SroodToastType.error,
      );
      return;
    }

    if (hasAntiKickProtection(targetVipLevel) &&
        !canKickVip5User(
          isRoomOwner: _iAmRoomOwner,
          isSuperAdmin: _iAmSuperAdmin,
        )) {
      SroodToast.show(
        context,
        context.isArabic
            ? '\u0644\u0627 \u064a\u0645\u0643\u0646\u0643 \u0637\u0631\u062f \u0645\u0633\u062a\u062e\u062f\u0645 VIP \u0628\u0647\u0630\u0627 \u0627\u0644\u0645\u0633\u062a\u0648\u0649'
            : 'This VIP 5+ user is protected from removal.',
        type: SroodToastType.error,
      );
      return;
    }

    // Check Anti-Kick VIP privilege setting.
    if (!_iAmRoomOwner && !_iAmSuperAdmin) {
      final kickBlocked = await const VipPrivilegeService().isKickBlocked(
        targetUserId: member.userId,
        actorIsRoomOwner: _iAmRoomOwner,
        actorIsSuperAdmin: _iAmSuperAdmin,
      );
      if (!mounted) return;
      if (kickBlocked) {
        SroodToast.show(
          context,
          context.isArabic
              ? 'This VIP user is protected from kick.'
              : 'This VIP user is protected from kick.',
          type: SroodToastType.error,
        );
        return;
      }
    }

    final confirmed = await _confirmVipKick(member);
    if (!mounted) {
      return;
    }

    if (!confirmed) {
      return;
    }

    setState(() {
      _roleBusyUserId = member.userId;
    });

    try {
      await _roomsService.removeMemberFromRoom(
        roomId: widget.room.id,
        userId: member.userId,
      );

      if (!mounted) return;

      setState(() {
        _members = _members
            .where((item) => item.userId != member.userId)
            .toList();
      });

      SroodToast.show(
        context,
        context.isArabic
            ? '\u062a\u0645 \u0625\u0632\u0627\u0644\u0629 \u0627\u0644\u0639\u0636\u0648 \u0645\u0646 \u0627\u0644\u063a\u0631\u0641\u0629.'
            : 'User removed from the room.',
        type: SroodToastType.success,
      );

      await _loadMembers(showLoading: false);
    } catch (error) {
      if (!mounted) return;

      SroodToast.show(context, error.toString(), type: SroodToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _roleBusyUserId = null;
        });
      }
    }
  }

  void _replaceMemberLocally(
    RoomMember? member, {
    String? role,
    int? seatNumber,
  }) {
    if (member == null) {
      return;
    }

    setState(() {
      _members = _members.map((item) {
        if (item.userId != member.userId) {
          return item;
        }

        return RoomMember(
          id: item.id,
          roomId: item.roomId,
          userId: item.userId,
          role: role ?? item.role,
          isMuted: item.isMuted,
          seatNumber: seatNumber,
          joinedAt: item.joinedAt,
          leftAt: item.leftAt,
          displayName: item.displayName,
          username: item.username,
          publicUserId: item.publicUserId,
          avatarUrl: item.avatarUrl,
          selectedAvatarFrameKey: item.selectedAvatarFrameKey,
          vipLevel: item.vipLevel,
          vipStartedAt: item.vipStartedAt,
          vipExpiresAt: item.vipExpiresAt,
        );
      }).toList();

      if (_selectedMicMoveMember?.userId == member.userId) {
        _selectedMicMoveMember = null;
      }
    });
  }

  Future<bool> _ensureMicrophonePermission() async {
    // Short-circuit if we already know it's granted (avoids a system IPC call
    // on every seat change).
    if (_micPermissionGranted == true) return true;

    final status = await Permission.microphone.status;

    if (status.isGranted) {
      _micPermissionGranted = true;
      return true;
    }

    final result = await Permission.microphone.request();

    if (result.isGranted) {
      _micPermissionGranted = true;
      return true;
    }

    if (!mounted) {
      return false;
    }

    final permanentlyDenied = result.isPermanentlyDenied;

    SroodToast.show(
      context,
      context.isArabic
          ? (permanentlyDenied
                ? '\u062a\u0645 \u062d\u0638\u0631 \u0625\u0630\u0646 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646. \u0627\u0641\u062a\u062d \u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a \u0648\u0627\u0633\u0645\u062d \u0628\u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646.'
                : '\u064a\u062d\u062a\u0627\u062c SrOOd Live \u0625\u0644\u0649 \u0625\u0630\u0646 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646 \u0644\u0644\u062a\u062d\u062f\u062b \u0641\u064a \u0627\u0644\u063a\u0631\u0641.')
          : (permanentlyDenied
                ? 'Microphone permission is blocked. Open app settings and allow microphone.'
                : 'Srood Live needs microphone permission so you can speak in rooms.'),
      type: SroodToastType.warning,
    );

    return false;
  }

  Future<void> _syncMicConnectionWithSeat() async {
    if (_syncingMicConnection || !mounted) return;

    final member = _myMember;
    final shouldPublishMic = _memberIsOnMic(member);
    final justTookSeat = shouldPublishMic && !_wasCurrentUserOnMic;

    _syncingMicConnection = true;
    var attemptingPublish = false;

    try {
      if (!_connectedAudio) {
        // If early connect is still in-flight, wait for it instead of bailing ?
        // bailing causes up to a 5-second delay before the next refresh retries.
        if (_connectingAudio) {
          _syncingMicConnection = false;
          while (_connectingAudio && mounted) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
          if (!mounted) return;
          _syncingMicConnection = true;
        }

        if (!_connectedAudio) {
          // Early connect failed or never started ? connect now.
          if (mounted) _setAudioState(connecting: true);

          _liveKitRoomService.onSpeakersChanged = (ids) {
            if (mounted) setState(() => _speakingUserIds = ids);
          };

          _roomLog('[Room] ${_roomTs()} LiveKit connect started (sync)');
          await _liveKitRoomService.connect(
            roomId: widget.room.id,
            microphoneEnabled: false,
          );
          _roomLog('[Room] ${_roomTs()} LiveKit connected');

          if (mounted) _setAudioState(connected: true);
        }
      }

      // Room-level mute: block non-staff from publishing when room is muted.
      if (shouldPublishMic &&
          _roomIsMuted &&
          !_iAmRoomOwner &&
          !_iAmHost &&
          !_isCurrentUserModerator) {
        _roomLog('[MUTE] seat mic denied reason=room_muted');
        await _liveKitRoomService.setMicrophoneEnabled(false);
        if (mounted) {
          setState(() {
            _micEnabled = false;
            _wasCurrentUserOnMic = false;
          });
          SroodToast.show(
            context,
            context.isArabic
                ? 'Ø§Ù„ØºØ±ÙØ© Ù…ÙƒØªÙˆÙ…Ø© Ø­Ø§Ù„ÙŠØ§Ù‹'
                : 'Room is muted right now',
            type: SroodToastType.warning,
          );
        }
        return;
      }

      if (shouldPublishMic) {
        attemptingPublish = true;
        final hasMicrophonePermission = await _ensureMicrophonePermission();

        if (!hasMicrophonePermission) {
          // Stay connected so the user still hears the room; just don't publish.
          await _liveKitRoomService.setMicrophoneEnabled(false);
          if (mounted) {
            setState(() {
              _micEnabled = false;
              _wasCurrentUserOnMic = false;
            });
          }
          return;
        }

        final desiredMicEnabled = justTookSeat
            ? true
            : !(member?.isMuted ?? false);

        await _liveKitRoomService.setMicrophoneEnabled(desiredMicEnabled);

        // Clear self-mute on seat take, but never clear a force-mute set by owner.
        if (justTookSeat &&
            member?.isMuted == true &&
            member?.forceMuted != true) {
          await _roomsService.setMyMuteStatus(
            roomId: widget.room.id,
            isMuted: false,
          );
        }
        if (justTookSeat && member?.forceMuted == true) {
          _roomLog(
            '[MUTE] forced mute applied user=${member?.userId} â€” seat taken but mute preserved',
          );
        }

        if (!mounted) return;

        setState(() {
          _micEnabled = desiredMicEnabled;
          _wasCurrentUserOnMic = true;
        });

        if (kDebugMode) {
          _roomLog('[Room] Mic published enabled=$desiredMicEnabled');
        }
        return;
      }

      // Not on a mic seat \u2192 make sure the mic is off, but stay connected so we
      // keep hearing other speakers.
      await _liveKitRoomService.setMicrophoneEnabled(false);

      if (member != null && !member.isMuted) {
        await _roomsService.setMyMuteStatus(
          roomId: widget.room.id,
          isMuted: true,
        );
      }

      if (!mounted) return;

      setState(() {
        _micEnabled = false;
        _wasCurrentUserOnMic = false;
      });
    } catch (error) {
      if (!mounted) return;

      _setAudioState(connected: _liveKitRoomService.room != null);
      setState(() {
        _micEnabled = false;
        _wasCurrentUserOnMic = false;
      });

      // Only surface the microphone error when we were actually trying to
      // publish \u2014 a listen-only connection issue shouldn't blame the mic.
      if (attemptingPublish) {
        SroodToast.show(
          context,
          context.isArabic
              ? '\u062a\u0639\u0630\u0631 \u062a\u0634\u063a\u064a\u0644 \u0627\u0644\u0645\u0627\u064a\u0643. \u062a\u0623\u0643\u062f \u0645\u0646 \u0625\u0630\u0646 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646.'
              : 'Could not start the microphone. Please check microphone permission.',
          type: SroodToastType.error,
        );
      }
    } finally {
      _syncingMicConnection = false;

      if (mounted) _setAudioState(connecting: false);
    }
  }

  Future<void> _toggleMic() async {
    if (!_isCurrentUserOnMic) return;
    // De-bounce: ignore tap while a toggle is already in flight.
    if (_micToggleBusy) {
      _roomLog('[MicUX] tap ignored â€” toggle already in flight');
      return;
    }

    if (!_connectedAudio) {
      _roomLog('[MicUX] tap â€” audio not connected, syncing seat');
      await _syncMicConnectionWithSeat();
      return;
    }

    final nextValue = !_micEnabled;
    final tapMs = DateTime.now().millisecondsSinceEpoch;
    _roomLog('[MicUX] tap received nextValue=$nextValue');

    // â”€â”€ Blocked states (check before any UI change) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (nextValue &&
        _roomIsMuted &&
        !_iAmRoomOwner &&
        !_iAmHost &&
        !_isCurrentUserModerator) {
      _roomLog('[MicUX] blocked â€” room_muted');
      if (mounted) {
        SroodToast.show(
          context,
          context.isArabic
              ? 'Ø§Ù„ØºØ±ÙØ© Ù…ÙƒØªÙˆÙ…Ø© Ø­Ø§Ù„ÙŠØ§Ù‹'
              : 'Room is muted right now',
          type: SroodToastType.warning,
        );
      }
      return;
    }

    if (nextValue && _myMember?.forceMuted == true) {
      _roomLog('[MicUX] blocked â€” forced_mute');
      if (mounted) {
        SroodToast.show(
          context,
          context.isArabic
              ? 'Ù„Ù‚Ø¯ ØªÙ… ÙƒØªÙ…Ùƒ Ù…Ù† Ù‚Ø¨Ù„ Ø§Ù„Ù…Ø¶ÙŠÙ.'
              : 'You have been muted by the room owner.',
          type: SroodToastType.warning,
        );
      }
      return;
    }

    // â”€â”€ Optimistic UI â€” react in the same frame as the tap â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Button shows busy spinner immediately; icon flips to target state.
    setState(() {
      _micEnabled = nextValue;
      _micToggleBusy = true;
    });
    _roomLog(
      '[MicUX] UI updated optimistically +${DateTime.now().millisecondsSinceEpoch - tapMs}ms',
    );

    // â”€â”€ Permission check (only for unmute; cached after first grant) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (nextValue) {
      final hasPerm = await _ensureMicrophonePermission();
      if (!hasPerm) {
        _roomLog('[MicUX] permission denied â€” reverting');
        if (mounted) {
          setState(() {
            _micEnabled = !nextValue;
            _micToggleBusy = false;
          });
        }
        return;
      }
      _roomLog(
        '[MicUX] permission ok +${DateTime.now().millisecondsSinceEpoch - tapMs}ms',
      );
    }

    // â”€â”€ LiveKit + RPC â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // RPC always runs so Supabase mute state stays authoritative.
    // LiveKit setMicrophoneEnabled is internally guarded â€” if the socket is not
    // connected it saves a pending state and applies it automatically on the
    // next RoomConnectedEvent / RoomReconnectedEvent.
    try {
      final t1 = DateTime.now().millisecondsSinceEpoch;
      // Run in parallel; both are individually safe if the other fails.
      await Future.wait([
        _liveKitRoomService.setMicrophoneEnabled(nextValue),
        _roomsService.setMyMuteStatus(
          roomId: widget.room.id,
          isMuted: !nextValue,
        ),
      ]);
      final elapsed = DateTime.now().millisecondsSinceEpoch - t1;
      _roomLog('[MicUX] LiveKit+RPC done in ${elapsed}ms');
      _roomLog(
        '[MicUX] total end-to-end ${DateTime.now().millisecondsSinceEpoch - tapMs}ms',
      );
      if (elapsed > 1500) {
        _roomLog('[MicUX] slow toggle detected: ms');
      }
    } catch (e) {
      _roomLog('[MicUX] error â€” reverting: $e');
      if (mounted) setState(() => _micEnabled = !nextValue);
    } finally {
      if (mounted) setState(() => _micToggleBusy = false);
    }
  }

  // Single entry point for all leave/close flows.
  // Shared teardown: cancels timers, removes realtime channels, disconnects audio.
  Future<void> _teardownRoom() async {
    _heartbeatTimer?.cancel();
    _membersRefreshTimer?.cancel();
    _membersDebounceTimer?.cancel();
    _giftBannerTimer?.cancel();
    _giftFeedCleanupTimer?.cancel();
    _vipEntryBannerTimer?.cancel();
    _entryBannerTimer?.cancel();
    for (final t in _giftEventTimers) {
      t.cancel();
    }
    _pkSub?.cancel();
    final mc = _membersChannel;
    final gc = _giftTransactionsChannel;
    final ms = _messagesChannel;
    if (mc != null) unawaited(SupabaseService.requiredClient.removeChannel(mc));
    if (gc != null) unawaited(SupabaseService.requiredClient.removeChannel(gc));
    if (ms != null) unawaited(SupabaseService.requiredClient.removeChannel(ms));
    _roomLog('[VoiceLifecycle] disconnect reason=user_left');
    await _liveKitRoomService.disconnect();
    unawaited(VoiceRoomForegroundService.stop());
  }

  // Exit Room: only the current user leaves. Room stays open for others.
  Future<void> _handleExitRoom() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await _roomsService.leaveRoom(widget.room.id);
      await _teardownRoom();
      if (!mounted) return;
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ActiveRoomSession.instance.clear();
      });
    } catch (e, st) {
      debugError('RoomDetailsScreen._leaveRoom', e, st);
      if (!mounted) return;
      setState(() => _leaving = false);
      SroodToast.show(
        context,
        context.isArabic
            ? '\u062a\u0639\u0630\u0631 \u0645\u063a\u0627\u062f\u0631\u0629 \u0627\u0644\u063a\u0631\u0641\u0629. \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.'
            : 'Could not leave the room. Please try again.',
        type: SroodToastType.error,
      );
    }
  }

  // Close Room: owner force-closes the room for all participants.
  Future<void> _handleCloseRoom({String? pin}) async {
    if (_isClosingRoom) return;
    setState(() {
      _isClosingRoom = true;
      _leaving = true;
    });
    try {
      await Future.wait<void>([
        _roomsService.closeRoomWithPin(widget.room.id, pin: pin),
        Future<void>.delayed(const Duration(milliseconds: 850)),
      ]);
      await _teardownRoom();
      if (!mounted) return;
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ActiveRoomSession.instance.clear();
      });
    } catch (e, st) {
      debugError('RoomDetailsScreen._closeRoom', e, st);
      if (!mounted) return;
      setState(() {
        _isClosingRoom = false;
        _leaving = false;
      });
      SroodToast.show(
        context,
        context.isArabic
            ? '\u062a\u0639\u0630\u0631 \u0625\u063a\u0644\u0627\u0642 \u0627\u0644\u063a\u0631\u0641\u0629. \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.'
            : 'Could not close the room. Please try again.',
        type: SroodToastType.error,
      );
    }
  }

  // Called from the bottom action bar exit button \u2014 exits quietly (no vault anim).
  Future<void> _leaveRoom() => _handleExitRoom();

  Future<void> _loadInboxUnread() async {
    try {
      final count = await const PrivateMessageService().fetchTotalUnreadCount();
      if (mounted) setState(() => _inboxUnreadCount = count);
    } catch (e, st) {
      debugError('RoomDetailsScreen._loadInboxUnread', e, st);
    }
  }

  Future<void> _openInbox() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessagesScreen(isArabic: context.isArabic),
      ),
    );
    // Refresh unread count when returning from inbox.
    unawaited(_loadInboxUnread());
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'host':
        return context.isArabic ? '\u0645\u0636\u064a\u0641' : 'Host';
      case 'speaker':
        return context.isArabic ? '\u0645\u062a\u062d\u062f\u062b' : 'Speaker';
      default:
        return context.isArabic ? '\u0645\u0633\u062a\u0645\u0639' : 'Listener';
    }
  }

  Future<void> _openUserProfileSheet(String userId) async {
    // Resolve the target member so the sheet has room context
    final target = _members.where((m) => m.userId == userId).firstOrNull;
    final isOnMic =
        target != null &&
        (target.role == 'speaker' || target.role == 'host') &&
        target.seatNumber != null;
    final isTargetOwner = userId == widget.room.ownerId;

    // Can the viewer moderate this user?
    final canModerate = _iAmRoomOwner || _iAmHost;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (sheetContext) {
        return RoomUserProfileSheet(
          userId: userId,
          currentUserId: _currentUserId,
          isArabic: context.isArabic,
          onSendGift: (targetUserId) {
            Future.microtask(() => _openGiftSheet(targetUserId: targetUserId));
          },
          // Room context
          roomId: widget.room.id,
          isViewerOwner: _iAmRoomOwner,
          isViewerHost: _iAmHost,
          targetRoomRole: target?.role,
          targetMicSeat: target?.seatNumber,
          targetIsMuted: target?.isMuted ?? false,
          // Moderation callbacks - only provided when caller can act
          onToggleMute: (canModerate && !isTargetOwner && target != null)
              ? (muted) async {
                  _roomLog(
                    '[MUTE] forced mute applied user=$userId isMuted=$muted',
                  );
                  await const RoomManagementService().ownerMuteMember(
                    widget.room.id,
                    userId,
                    isMuted: muted,
                  );
                  // Refresh member list so room UI reflects change
                  await _loadMembers(showLoading: false);
                }
              : null,
          onStandUp: (canModerate && !isTargetOwner && isOnMic)
              ? () async {
                  await _changeMemberRole(member: target, role: 'listener');
                }
              : null,
          onKick: (canModerate && !isTargetOwner && target != null)
              ? () async {
                  await _removeMemberFromRoom(target);
                }
              : null,
          onBan: (_iAmRoomOwner && !isTargetOwner && target != null)
              ? () async {
                  await const RoomManagementService().banUser(
                    widget.room.id,
                    userId,
                  );
                  await _removeMemberFromRoom(target);
                }
              : null,
          onSetAdmin: (_iAmRoomOwner && !isTargetOwner && target != null)
              ? () async {
                  await const RoomManagementService().addModerator(
                    widget.room.id,
                    userId,
                  );
                }
              : null,
        );
      },
    );
  }

  Future<void> _openGiftSheet({String? targetUserId}) async {
    if (_isSendingGift) return;
    setState(() => _isSendingGift = true);
    try {
      await _openGiftSheetImpl(targetUserId: targetUserId);
    } finally {
      if (mounted) setState(() => _isSendingGift = false);
    }
  }

  Future<void> _openGiftSheetImpl({String? targetUserId}) async {
    // Refresh balance in the background so it is fresh by the time the user taps Send.
    unawaited(_loadWalletBalance());

    final currentUserId = _currentUserId;
    final receivers =
        _members.where((member) => member.userId != currentUserId).toList()
          ..sort(
            (a, b) =>
                _giftReceiverRank(a.role).compareTo(_giftReceiverRank(b.role)),
          );

    var gifts = _fallbackRoomGifts;

    try {
      final remoteGifts = await _giftsService.fetchActiveGifts();
      if (remoteGifts.isNotEmpty) {
        final remoteCodes = remoteGifts.map((gift) => gift.code).toSet();
        gifts = [
          ...remoteGifts,
          ..._localLuxuryRoomGifts.where(
            (gift) => !remoteCodes.contains(gift.code),
          ),
        ];
      }
    } catch (error) {
      if (!mounted) return;

      SroodToast.show(
        context,
        context.isArabic
            ? '\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0647\u062f\u0627\u064a\u0627. \u0633\u064a\u062a\u0645 \u0627\u0633\u062a\u062e\u062f\u0627\u0645 \u0627\u0644\u0642\u0627\u0626\u0645\u0629 \u0627\u0644\u0645\u062d\u0644\u064a\u0629.'
            : 'Could not load gifts. Using local gifts.',
        type: SroodToastType.error,
      );
    }

    if (!mounted) return;

    final result = await showModalBottomSheet<SroodGiftSendResult>(
      context: context,
      backgroundColor: const Color(0xFF12091D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SroodGiftSheet(
          isArabic: context.isArabic,
          receivers: receivers,
          gifts: gifts,
          roleLabel: _roleLabel,
          initialReceiverUserId: targetUserId,
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    // \u2500\u2500 Local balance pre-check (fast fail before hitting the backend) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    final totalCost = result.gift.priceCoins * result.quantity;
    _roomLog(
      '[GiftRecharge] gift=${result.gift.code} qty=${result.quantity} '
      'unitPrice=${result.gift.priceCoins} totalCost=$totalCost '
      'balance=$_walletCoins',
    );
    if (_walletCoins < totalCost) {
      _roomLog('[GiftRecharge] insufficient local balance \u2014 redirecting');
      _redirectToWallet();
      return;
    }

    try {
      if (kDebugMode) {
        _roomLog(
          '[Gift] send tapped room=${widget.room.id} '
          'receiver=${result.receiverUserId} gift=${result.gift.code}',
        );
      }
      _roomLog(
        '[GiftQuantity] selected qty=${result.quantity} gift=${result.gift.code} unitPrice=${result.gift.priceCoins} total=$totalCost',
      );
      await _giftsService.sendGift(
        roomId: widget.room.id,
        receiverId: result.receiverUserId,
        gift: result.gift,
        quantity: result.quantity,
      );
      if (kDebugMode) {
        _roomLog('[GiftQuantity] send success qty=${result.quantity}');
      }
    } catch (error) {
      if (!mounted) return;

      final errorText = error.toString();
      if (errorText.contains('insufficient_coins')) {
        _roomLog(
          '[GiftRecharge] backend insufficient_coins \u2014 refreshing balance and redirecting',
        );
        unawaited(_loadWalletBalance());
        _redirectToWallet();
        return;
      }

      SroodToast.show(
        context,
        context.isArabic
            ? '\u062a\u0639\u0630\u0631 \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0647\u062f\u064a\u0629. \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.'
            : 'Could not send gift. Please try again.',
        type: SroodToastType.error,
      );
      return;
    }

    if (!mounted) return;

    await _loadRoomGifts(showLoading: false, showNewestBanner: true);

    if (!mounted) return;

    _showGiftEvent(result);

    SroodToast.show(
      context,
      context.isArabic
          ? '\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 ${result.gift.name} \u0625\u0644\u0649 ${result.receiverName}'
          : '${result.gift.name} sent to ${result.receiverName}',
      type: SroodToastType.success,
    );
  }

  void _showGiftEvent(SroodGiftSendResult result) {
    final event = SroodRoomGiftEvent(
      id: _giftEventSeed++,
      gift: result.gift,
      receiverName: result.receiverName,
      quantity: result.quantity,
    );

    setState(() {
      _giftSupportByUserId[result.receiverUserId] =
          (_giftSupportByUserId[result.receiverUserId] ?? 0) +
          (result.gift.priceCoins * result.quantity);
      _giftEvents.insert(0, event);
      if (_giftEvents.length > 3) {
        _giftEvents.removeLast();
      }
    });

    late final Timer timer;
    timer = Timer(const Duration(seconds: 5), () {
      _giftEventTimers.remove(timer);

      if (!mounted) return;

      setState(() {
        _giftEvents.removeWhere((item) => item.id == event.id);
      });
    });

    _giftEventTimers.add(timer);
  }

  void _showLuxuryGiftFromTransaction(RoomGiftTransaction transaction) {
    if (!_visualEnabled) return;
    final config = SroodLuxuryGiftVideoConfig.fromCode(transaction.giftCode);

    if (config == null) {
      return;
    }

    _playLuxuryGiftVideo(
      giftName: transaction.giftName,
      receiverName: transaction.receiverLabel,
      config: config,
    );
  }

  void _playLuxuryGiftVideo({
    required String giftName,
    required String receiverName,
    required SroodLuxuryGiftVideoConfig config,
  }) {
    _luxuryGiftVideoTimer?.cancel();

    setState(() {
      _activeLuxuryGiftVideo = SroodActiveLuxuryGiftVideo(
        key: UniqueKey(),
        giftName: giftName,
        receiverName: receiverName,
        assetPath: config.assetPath,
      );
    });

    _luxuryGiftVideoTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _activeLuxuryGiftVideo = null;
      });
    });
  }

  void _clearLuxuryGiftVideo() {
    _luxuryGiftVideoTimer?.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _activeLuxuryGiftVideo = null;
    });
  }

  int _giftReceiverRank(String role) {
    switch (role) {
      case 'host':
        return 0;
      case 'speaker':
        return 1;
      default:
        return 2;
    }
  }

  void _showRoomLevelUpOverlay(int newLevel) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => SroodRoomLevelUpOverlay(
        newLevel: newLevel,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  void _showRoomLevelSheet(BuildContext ctx) {
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => SroodRoomLevelSheet(
        roomId: widget.room.id,
        level: _roomLevel,
        roomXp: _roomXp,
        xpToday: _xpToday,
        xpWeek: _xpWeek,
        dailyStreak: _dailyStreak,
        streakMultiplier: _streakMultiplier,
      ),
    );
  }

  Future<void> _showParticipantsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (sheetContext) {
        var refreshing = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> refreshMembers() async {
              setSheetState(() {
                refreshing = true;
              });

              await _loadMembers(showLoading: false);

              if (!context.mounted) {
                return;
              }

              setSheetState(() {
                refreshing = false;
              });
            }

            return SroodRoomParticipantsSheet(
              members: _participantsForDisplay,
              currentUserId: _currentUserId,
              isArabic: context.isArabic,
              refreshing: refreshing,
              supportByUserId: _giftSupportByUserId,
              roleBusyUserId: _roleBusyUserId,
              roleLabel: _roleLabel,
              isHost: _iAmHost,
              onRefresh: refreshMembers,
              onProfileTap: _openUserProfileSheet,
              onPromote: (member) =>
                  _changeMemberRole(member: member, role: 'speaker'),
              onMoveToListener: (member) =>
                  _changeMemberRole(member: member, role: 'listener'),
              onRemove: _removeMemberFromRoom,
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmLeave() async {
    if (_isClosingRoom) return false;
    final isOwner = _iAmRoomOwner;
    final isArabic = context.isArabic;

    final action = await showModalBottomSheet<SroodRoomExitAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          SroodRoomExitSheet(isOwner: isOwner, isArabic: isArabic),
    );

    if (action == null || !mounted) return false;

    if (action == SroodRoomExitAction.minimize) {
      _minimizeRoom();
      return false;
    }

    if (action == SroodRoomExitAction.exit) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A0840),
          title: Text(
            isArabic ? 'Exit Room?' : 'Exit Room?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            isArabic
                ? 'You will leave this room. The room will stay open for others.'
                : 'You will leave this room. The room will stay open for others.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(isArabic ? 'Cancel' : 'Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE63946),
              ),
              child: Text(isArabic ? 'Exit Room' : 'Exit Room'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) await _handleExitRoom();
      return false;
    }

    // closeRoom ? show vault PIN sheet as dramatic confirmation
    final pin = await showVaultPinSheet(
      context,
      title: isArabic ? 'Close Room' : 'Close Room',
      subtitle: isArabic
          ? (widget.room.roomPinEnabled
                ? 'Enter the heart PIN to close the room.'
                : 'The room will close for all participants.')
          : (widget.room.roomPinEnabled
                ? 'Enter your vault PIN to close the room.'
                : 'This will end the room for all participants.'),
      requirePin: widget.room.roomPinEnabled,
    );
    if (pin == null || !mounted) return false;
    // Pass pin directly; backend validates it (or ignores it if no PIN set).
    await _handleCloseRoom(pin: widget.room.roomPinEnabled ? pin : null);
    return false; // Navigation already handled inside _handleCloseRoom
  }

  void _minimizeRoom() {
    _roomLog('[RoomMinimize] minimize tapped roomId=${widget.room.id}');
    _roomLog(
      '[RoomMinimize] lkConnected=${_liveKitRoomService.isConnected} mic=$_micEnabled members=${_members.length}',
    );
    _roomLog(
      '[RoomMusic] music service preserved on minimize '
      'isActive=${_musicService.isActive} song=${_musicService.currentSong?.id}',
    );
    _minimizing = true;
    ActiveRoomSession.instance.minimize(
      widget.room,
      _liveKitRoomService,
      micEnabled: _micEnabled,
      musicService: _musicService,
      syncedMusicService: _syncedMusic,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _isClosingRoom) return;
        final ok = await _confirmLeave();
        if (ok && mounted) await _handleCloseRoom();
      },
      child: Stack(
        children: [
          Scaffold(
            resizeToAvoidBottomInset: false,
            backgroundColor: SroodRoomColors.bgDeep,
            body: SroodRoomShell(
              // â”€â”€ Immersive background â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              background: SroodRoomBackground(
                key: ValueKey(
                  '${_roomBackgroundUrl ?? ''}_${_roomCoverUrl ?? ''}_${_roomUpdatedAt?.millisecondsSinceEpoch ?? 0}',
                ),
                room: _currentRoom,
                backgroundUrl: _roomBackgroundUrl,
              ),

              // â”€â”€ Top zone â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              header: SroodRoomHeader(
                room: _currentRoom,
                roomName: _roomName,
                roomLevel: _roomLevel,
                avatarUrl: _roomAvatarUrl,
                memberCount: _members.length,
                walletCoins: _walletCoins,
                isHost: _iAmHost,
                isOwner: _iAmRoomOwner,
                isArabic: isArabic,
                leaving: _leaving,
                onExitTap: () => _confirmLeave(),
                onLevelTap: () => _showRoomLevelSheet(context),
                onManagementTap: (_iAmRoomOwner || _iAmHost)
                    ? _openRoomManagement
                    : null,
                announcement: _activeAnnouncementText,
              ),

              // â”€â”€ Event banners (gift > VIP entry > user entry) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              banners: [
                ValueListenableBuilder<RoomGiftTransaction?>(
                  valueListenable: _giftBannerNotifier,
                  builder: (ctx, giftBanner, child) => AnimatedSwitcher(
                    duration: SroodRoomMotion.normal,
                    child: giftBanner == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(giftBanner.id),
                            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                            child: SroodGiftRoomBanner(
                              gift: giftBanner,
                              isArabic: isArabic,
                              onProfileTap: _openUserProfileSheet,
                            ),
                          ),
                  ),
                ),
                ValueListenableBuilder<RoomMember?>(
                  valueListenable: _vipBannerNotifier,
                  builder: (ctx, vipMember, child) =>
                      ValueListenableBuilder<RoomGiftTransaction?>(
                        valueListenable: _giftBannerNotifier,
                        builder: (ctx2, giftBanner, child2) => AnimatedSwitcher(
                          duration: SroodRoomMotion.normal,
                          child: giftBanner != null || vipMember == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  key: ValueKey(vipMember.userId),
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    6,
                                    14,
                                    0,
                                  ),
                                  child: SroodVipEntryRoomBanner(
                                    member: vipMember,
                                    isArabic: isArabic,
                                  ),
                                ),
                        ),
                      ),
                ),
                ValueListenableBuilder<RoomMember?>(
                  valueListenable: _entryBannerNotifier,
                  builder: (ctx, entryMember, child) =>
                      ValueListenableBuilder<RoomGiftTransaction?>(
                        valueListenable: _giftBannerNotifier,
                        builder: (ctx2, giftBanner, child2) =>
                            ValueListenableBuilder<RoomMember?>(
                              valueListenable: _vipBannerNotifier,
                              builder: (ctx3, vipMember, child3) =>
                                  AnimatedSwitcher(
                                    duration: SroodRoomMotion.normal,
                                    child:
                                        giftBanner != null ||
                                            vipMember != null ||
                                            entryMember == null
                                        ? const SizedBox.shrink()
                                        : Padding(
                                            key: ValueKey(entryMember.userId),
                                            padding: const EdgeInsets.fromLTRB(
                                              14,
                                              6,
                                              14,
                                              0,
                                            ),
                                            child: SroodUserEntryRoomBanner(
                                              member: entryMember,
                                              isArabic: isArabic,
                                            ),
                                          ),
                                  ),
                            ),
                      ),
                ),
              ],

              // â”€â”€ Main stage: mic grid + PK â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              stage: SroodRoomStage(
                members: _members,
                maxSeats: _currentMaxSeats,
                isArabic: isArabic,
                activeSpeakerCount: _activeSpeakerCount,
                isHost: _iAmHost,
                onEmptySeatTap: _pickListenerForSeat,
                onOccupiedSeatTap: _handleOccupiedSeatTap,
                onOccupiedSeatLongPress: _showMemberSeatActions,
                onProfileTap: _openUserProfileSheet,
                memberCount: _members.length,
                onParticipantsTap: _showParticipantsSheet,
                supportByUserId: _giftSupportByUserId,
                selectedMoveUserId: _selectedMicMoveMember?.userId,
                speakingUserIds: _speakingUserIds,
                moderatorUserIds: _moderatorUserIds,
                closedSeats: _closedSeats,
                roomLevel: _roomLevel,
                activePk: _activePk?.isActive == true ? _activePk : null,
                showPkResult: _showPkResult,
                pkResult: _showPkResult && _activePk?.isFinished == true
                    ? _activePk
                    : null,
                onPkFinish: _handlePkAutoFinish,
                onPkResultClose: () => setState(() => _showPkResult = false),
                seatReactions: _seatReactions,
              ),

              // â”€â”€ Chat zone â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              chatFeed: SroodRoomChatFeed(
                chatMessages: _chatMessages,
                isArabic: isArabic,
                onProfileTap: _openUserProfileSheet,
                bottomPad: 0,
                currentUserId: _currentUserId ?? '',
                onRemoveTap: _canRemoveMessages ? _removeMessage : null,
                onReportTap: _reportChatMessage,
              ),

              // â”€â”€ Floating now-playing chip â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              musicChip: ListenableBuilder(
                listenable: _musicService,
                builder: (_, _) {
                  final controllerId = _syncedMusic.lastState?.controllerUserId;
                  final isController = controllerId == _currentUserId;
                  final isManager =
                      _iAmRoomOwner || _iAmHost || _isCurrentUserModerator;
                  return RoomMiniPlayer(
                    musicService: _musicService,
                    isArabic: isArabic,
                    isManager: isManager,
                    canManage: isManager && isController,
                    onTap: _openMusicPanel,
                    controllerUserId: controllerId,
                    currentUserId: _currentUserId,
                    onStop: (isManager && isController)
                        ? () => unawaited(_stopMusicForRoom())
                        : null,
                    onNonControllerAction: () => _musicAction(() async {}),
                    keyboardOpen: MediaQuery.of(context).viewInsets.bottom > 0,
                  );
                },
              ),

              // â”€â”€ Bottom control zone â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              bottomBar:
                  ValueListenableBuilder<({bool connecting, bool connected})>(
                    valueListenable: _audioStateNotifier,
                    builder: (context2, audioState, child2) =>
                        SroodRoomBottomActions(
                          isArabic: isArabic,
                          connectingAudio:
                              audioState.connecting || _micToggleBusy,
                          micEnabled: _micEnabled,
                          isOnMic: _isCurrentUserOnMic,
                          leaving: _leaving,
                          isSendingMessage: _isSendingMessage,
                          myVipLevel: _myMember?.effectiveVipLevel ?? 0,
                          isUploadingImage: _uploadingChatImage,
                          onToggleMic: _toggleMic,
                          onGiftTap: _openGiftSheet,
                          onMoreTap: _openToolsSheet,
                          onReactionTap: _openReactionPicker,
                          onInboxTap: _openInbox,
                          inboxUnreadCount: _inboxUnreadCount,
                          onSendMessage: _sendChatMessage,
                          onSendImage: _sendChatImageMessage,
                          members: _members,
                          bottomPad: bottomPad,
                        ),
                  ),

              // â”€â”€ Full-screen overlays â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              overlays: [
                SroodGiftEventOverlay(events: _giftEvents, isArabic: isArabic),

                if (_activeLuxuryGiftVideo != null)
                  SroodLuxuryGiftVideoOverlay(
                    playback: _activeLuxuryGiftVideo!,
                    onDone: _clearLuxuryGiftVideo,
                    // Mute gift video audio while room music is playing so
                    // the music player is never interrupted.
                    soundEnabled: _soundEnabled && !_musicService.isActive,
                  ),

                if (_activeRedEnvelope != null &&
                    !_openedLuckyBagIds.contains(
                      _activeRedEnvelope!['id'] as String?,
                    ) &&
                    !_sessionClaimedEnvelopeIds.contains(
                      _activeRedEnvelope!['id'] as String?,
                    ) &&
                    !_sessionDismissedEnvelopeIds.contains(
                      _activeRedEnvelope!['id'] as String?,
                    ))
                  Builder(
                    builder: (context) {
                      final envelope = _activeRedEnvelope!;
                      final envelopeId = envelope['id'] as String? ?? '';
                      final isSender =
                          (envelope['sender_id'] as String?) == _currentUserId;
                      _roomLog(
                        '[LuckyBag] shown id=$envelopeId isSender=$isSender',
                      );
                      return Positioned(
                        top: 80 + MediaQuery.of(context).padding.top,
                        left: 16,
                        right: 16,
                        child: SroodRedEnvelopeBanner(
                          envelope: envelope,
                          isArabic: isArabic,
                          loading: _claimingEnvelope,
                          isSender: isSender,
                          onClaim: _claimRedEnvelope,
                          onDismiss: _dismissRedEnvelope,
                        ),
                      );
                    },
                  ),

                if (_showLuckyBagEntrance)
                  Positioned.fill(
                    child: SroodLuckyBagEntranceOverlay(
                      key: const ValueKey('lucky-bag-entrance-overlay'),
                      soundEnabled: _soundEnabled,
                      onDone: () {
                        if (mounted) {
                          setState(() => _showLuckyBagEntrance = false);
                        }
                      },
                    ),
                  ),

                if (_luckyBagWinCoins != null)
                  Positioned.fill(
                    child: SroodLuckyBagWinOverlay(
                      key: ValueKey('lucky-bag-win-overlay-$_luckyBagWinCoins'),
                      coins: _luckyBagWinCoins!,
                      soundEnabled: _soundEnabled,
                      onDone: () {
                        if (mounted) setState(() => _luckyBagWinCoins = null);
                      },
                    ),
                  ),
              ],
            ),
          ), // Scaffold
          // Vault closing overlay â€” rendered above everything.
          if (_isClosingRoom)
            SroodRoomClosingOverlay(
              key: ValueKey('room-closing-overlay-${widget.room.id}'),
              isOwnerClosing: _iAmRoomOwner,
              isArabic: isArabic,
            ),
        ],
      ),
    ); // PopScope
  }
}

const List<RoomGift> _localLuxuryRoomGifts = [
  RoomGift(
    id: 'local-golden-lion',
    code: 'golden_lion',
    name: 'Golden Lion',
    arabicName:
        '\u0627\u0644\u0623\u0633\u062f \u0627\u0644\u0630\u0647\u0628\u064a',
    priceCoins: 999,
    icon: '',
    sortOrder: 90,
  ),
  RoomGift(
    id: 'local-baalbek-temple',
    code: 'baalbek_temple',
    name: 'Baalbek Temple',
    arabicName: '\u0642\u0644\u0639\u0629 \u0628\u0639\u0644\u0628\u0643',
    priceCoins: 777,
    icon: '',
    sortOrder: 91,
  ),
];

const List<RoomGift> _fallbackRoomGifts = [
  RoomGift(
    id: 'local-rose',
    code: 'rose',
    name: 'Rose',
    arabicName: '\u0648\u0631\u062f\u0629',
    priceCoins: 10,
    icon: '\uD83C\uDF39',
    sortOrder: 1,
  ),
  RoomGift(
    id: 'local-star',
    code: 'star',
    name: 'Star',
    arabicName: '\u0646\u062c\u0645\u0629',
    priceCoins: 50,
    icon: '\u2B50',
    sortOrder: 2,
  ),
  RoomGift(
    id: 'local-crown',
    code: 'crown',
    name: 'Crown',
    arabicName: '\u062a\u0627\u062c',
    priceCoins: 250,
    icon: '\uD83D\uDC51',
    sortOrder: 3,
  ),
  RoomGift(
    id: 'local-rocket',
    code: 'rocket',
    name: 'Rocket',
    arabicName: '\u0635\u0627\u0631\u0648\u062e',
    priceCoins: 1000,
    icon: '\uD83D\uDE80',
    sortOrder: 4,
  ),
];

// Gated room logging â€” interpolation and printing are skipped entirely in
// release builds so per-timer (member refresh, music tick) and per-event logs
// add no overhead in production.
void _roomLog(String message) {
  if (kDebugMode) debugPrint(message);
}
