import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../vip/widgets/vip_mic_wave_ring.dart';
import '../../../core/vip/vip_spec.dart';
import '../../../shared/widgets/avatar_with_frame.dart';
import '../../../shared/widgets/vip_badge.dart';
import '../../../shared/widgets/vip_username.dart';
import '../../profile/widgets/room_user_profile_sheet.dart';
import '../models/room.dart';
import '../models/room_gift.dart';
import '../models/room_member.dart';
import '../services/gifts_service.dart';
import '../../wallet/services/wallet_service.dart';
import '../services/livekit_room_service.dart';
import '../services/rooms_service.dart';
import '../services/room_management_service.dart';
import '../services/room_messages_service.dart';
import '../services/room_chat_image_upload_service.dart';
import '../models/pk_session.dart';
import '../services/team_pk_service.dart';
import '../utils/vip_room_features.dart';
import '../../vip/services/vip_privilege_service.dart';
import '../widgets/pk_stage_overlay.dart';
import '../widgets/room_tools_sheet.dart';
import '../widgets/music_panel.dart';
import '../widgets/room_mini_player.dart';
import '../services/room_music_service.dart';
import '../services/room_music_upload_service.dart';
import '../services/room_synced_music_service.dart';
import '../../games/screens/srood_loto_screen.dart';
import 'room_owner_management_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';
import '../models/room_reaction.dart';
import '../widgets/reaction_picker_sheet.dart';
import '../widgets/seat_reaction_overlay.dart';
import '../../../core/services/active_room_session.dart';
import '../../../core/services/voice_room_foreground_service.dart';
import '../widgets/vault_pin_sheet.dart';

// Seat sizes ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â host > occupied > empty, never the reverse.
// Reduced ~17% from previous values to open more background space.
const double _hostSeatAvatarSize = 46.0;
const double _hostSeatOuterSize  = 50.0;
const double _seatAvatarSize     = 40.0;
const double _seatOuterSize      = 44.0;
const double _emptySeatSize      = 44.0;
const double _micSeatIconSize    = 13.0;
const double _micSeatBadgeHorizontalPadding = 4.0;
const double _micSeatSupportSlotHeight      = 16.0;
// Fixed height for the avatar zone inside every grid cell.
// Must be >= _hostSeatOuterSize (58) so the host avatar is never clipped.
const double _kAvatarAreaHeight = 50.0;


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
  final LiveKitRoomService _liveKitRoomService = LiveKitRoomService();

  late final RoomMusicService _musicService;
  late final RoomSyncedMusicService _syncedMusic;
  final RoomMusicUploadService _uploadService = const RoomMusicUploadService();

  Set<String> _speakingUserIds = {};

  bool _leaving = false;
  bool _isClosingRoom = false;
  bool _connectingAudio = false;
  bool _connectedAudio = false;
  bool _syncingMicConnection = false;
  // Notifier keeps audio state for the bottom bar without full-screen setState.
  late final ValueNotifier<({bool connecting, bool connected})> _audioStateNotifier;
  bool _wasCurrentUserOnMic = false;
  bool _micEnabled = true;
  // Cached so we don't call permission_handler on every mic-seat change.
  bool? _micPermissionGranted;
  int _moderatorCount = 0;
  String? _roleBusyUserId;
  String? _activeAnnouncementText;

  List<RoomMember> _members = const [];
  RealtimeChannel? _roomChannel;
  RealtimeChannel? _membersChannel;
  RealtimeChannel? _giftTransactionsChannel;
  Timer? _heartbeatTimer;
  Timer? _membersRefreshTimer;
  Timer? _membersDebounceTimer;
  Timer? _giftBannerTimer;
  Timer? _giftFeedCleanupTimer;
  Timer? _vipEntryBannerTimer;
  final List<_RoomGiftEvent> _giftEvents = [];
  final List<Timer> _giftEventTimers = [];
  final Map<String, int> _giftSupportByUserId = {};
  List<RoomGiftTransaction> _roomGifts = const [];
  // Notifiers so banner changes rebuild only the banner widget, not the screen.
  final ValueNotifier<RoomGiftTransaction?> _giftBannerNotifier = ValueNotifier(null);
  final ValueNotifier<RoomMember?>          _vipBannerNotifier  = ValueNotifier(null);
  _ActiveLuxuryGiftVideo? _activeLuxuryGiftVideo;
  Timer? _luxuryGiftVideoTimer;
  bool _soundEnabled = true;
  bool _visualEnabled = true;
  Map<String, dynamic>? _activeRedEnvelope;
  bool _claimingEnvelope = false;
  bool _showLuckyBagEntrance = false;
  int? _luckyBagWinCoins;
  final Set<String> _openedLuckyBagIds = {};
  // _loadingGifts removed ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â gift loading state is not displayed in the overlay
  bool _isSendingGift = false;
  RoomMember? _selectedMicMoveMember;
  int _giftEventSeed = 0;

  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Room chat / comments ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
  final _msgService = const RoomMessagesService();
  final List<RoomMessage> _chatMessages = [];
  RealtimeChannel? _messagesChannel;
  bool _isSendingMessage = false;
  bool _uploadingChatImage = false;

  // -- Emoji reactions (keyed by seat number 1-based) --
  final Map<int, RoomReaction> _seatReactions = {};
  final Map<int, Timer> _reactionTimers = {};
  RealtimeChannel? _reactionsChannel;
  RealtimeChannel? _redEnvelopesChannel;


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

  bool _memberCanUseMic(RoomMember? member) {
    return member?.role == 'host' || member?.role == 'speaker';
  }

  bool _memberIsOnMic(RoomMember? member) {
    return _memberCanUseMic(member) && member?.seatNumber != null;
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

  // ── Audio state helpers ────────────────────────────────────────────────────

  /// Updates the audio bool fields AND pushes to the notifier — no setState.
  /// Callers that previously did setState just for audio now call this instead.
  void _setAudioState({bool? connecting, bool? connected}) {
    if (connecting != null) _connectingAudio = connecting;
    if (connected  != null) _connectedAudio  = connected;
    _audioStateNotifier.value = (
      connecting: _connectingAudio,
      connected:  _connectedAudio,
    );
  }

  // ── Member debounce ────────────────────────────────────────────────────────

  /// Buffers rapid member change events and fires a single reload after 500 ms.
  void _debouncedLoadMembers() {
    _membersDebounceTimer?.cancel();
    _membersDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      unawaited(_loadMembers(showLoading: false, detectVipEntry: true));
    });
  }

  @override
  void initState() {
    super.initState();
    _audioStateNotifier = ValueNotifier((connecting: false, connected: false));
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[Room] ${_roomTs()} room screen opened id=${widget.room.id}');
    _musicService = RoomMusicService();
    _syncedMusic = RoomSyncedMusicService(
      roomId: widget.room.id,
      musicService: _musicService,
    );
    unawaited(_syncedMusic.initialize());
    _musicService.addListener(_onLocalMusicChanged);
    _currentMaxSeats = widget.room.maxSeats <= 0 ? 12 : widget.room.maxSeats;
    _roomBackgroundUrl = widget.room.backgroundUrl;
    _roomAvatarUrl = widget.room.avatarUrl;
    _roomCoverUrl = widget.room.coverUrl;

    // Keep the process alive while the user is in the voice room so audio
    // continues when the screen turns off.
    unawaited(VoiceRoomForegroundService.start());

    // Start LiveKit in listen-only mode immediately, in parallel with
    // member loading, so audio is ready before the member list arrives.
    unawaited(_connectAudioEarly());

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
      _loadMessages();
      unawaited(_loadActivePk());
      unawaited(_loadActiveRedEnvelope());
    });
  }

  // When the host changes music locally (via MusicPanel), push the new state
  // to Supabase so all room members sync.
  // Skipped during server-driven updates to avoid feedback loops.
  // Skipped for position-only changes (tick updates) via pushCurrentStateIfChanged().
  void _onLocalMusicChanged() {
    if (!(_iAmRoomOwner || _iAmHost)) {
      debugPrint('[MUSIC-CONTROL] denied user=$_currentUserId reason=not_manager');
      return;
    }
    if (_syncedMusic.applyingServerState) return;
    debugPrint('[MUSIC-CONTROL] allowed user=$_currentUserId song=${_musicService.currentSong?.id}');
    unawaited(_syncedMusic.pushCurrentStateIfChanged());
  }

  // ---------------------------------------------------------------------------
  // App lifecycle Ã¢â‚¬â€ keep audio alive on background, reconnect on resume.
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Screen off / home pressed Ã¢â‚¬â€ do NOT disconnect. The Android foreground
        // service and LiveKit native SDK keep the audio session alive.
        debugPrint('[Room] ${_roomTs()} app $state Ã¢â‚¬â€ keeping audio alive');
        break;
      case AppLifecycleState.resumed:
        debugPrint('[Room] ${_roomTs()} app resumed Ã¢â‚¬â€ checking audio state');
        if (!_connectedAudio || !_liveKitRoomService.isConnected) {
          debugPrint('[Room] ${_roomTs()} audio dropped Ã¢â‚¬â€ reconnecting silentlyÃ¢â‚¬Â¦');
          unawaited(_reconnectAudio());
        }
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
      if (mounted) _setAudioState(connected: _liveKitRoomService.isConnected);
      await _syncMicConnectionWithSeat();
    } catch (e) {
      debugPrint('[Room] reconnect failed: $e');
    } finally {
      if (mounted) _setAudioState(connecting: false);
    }
  }

  // ---------------------------------------------------------------------------
  // Early audio Ã¢â‚¬â€ connects for listening immediately on room entry.
  // ---------------------------------------------------------------------------

  /// Connects LiveKit in listen-only mode in parallel with [_loadMembers].
  /// [_syncMicConnectionWithSeat] skips the connect step when it runs later
  /// because [_connectedAudio] will already be true.
  Future<void> _connectAudioEarly() async {
    if (_connectedAudio || _connectingAudio || _syncingMicConnection) return;
    if (mounted) _setAudioState(connecting: true);

    _liveKitRoomService.onSpeakersChanged = (ids) {
      if (mounted) setState(() => _speakingUserIds = ids);
    };

    debugPrint('[Room] ${_roomTs()} LiveKit connect started (early)');
    try {
      await _liveKitRoomService.connect(
        roomId: widget.room.id,
        microphoneEnabled: false,
      );
      debugPrint('[Room] ${_roomTs()} LiveKit connected');
      if (mounted) _setAudioState(connecting: false, connected: true);
    } catch (e) {
      debugPrint('[Room] ${_roomTs()} early audio connect failed: $e');
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
    _musicService.removeListener(_onLocalMusicChanged);
    unawaited(_syncedMusic.dispose());
    _musicService.dispose();
    _heartbeatTimer?.cancel();
    _membersRefreshTimer?.cancel();
    _membersDebounceTimer?.cancel();
    _audioStateNotifier.dispose();
    _giftBannerNotifier.dispose();
    _vipBannerNotifier.dispose();
    _giftBannerTimer?.cancel();
    _giftFeedCleanupTimer?.cancel();
    _vipEntryBannerTimer?.cancel();
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
      unawaited(
        SupabaseService.requiredClient.removeChannel(messagesChannel),
      );
    }

    _pkSub?.cancel();
    _liveKitRoomService.disconnect();
    for (final t in _reactionTimers.values) { t.cancel(); }
    _reactionTimers.clear();
    final rc = _reactionsChannel;
    if (rc != null) unawaited(SupabaseService.requiredClient.removeChannel(rc));
    final rec = _redEnvelopesChannel;
    if (rec != null) unawaited(SupabaseService.requiredClient.removeChannel(rec));
    WidgetsBinding.instance.removeObserver(this);
    unawaited(VoiceRoomForegroundService.stop());
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
        debugPrint('[PK] load active failed: $error');
      }
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
      final claimed = (row['claimed_count'] as int? ?? 0);
      final total   = (row['envelope_count'] as int? ?? 1);
      if (claimed < total) {
        final envelopeId = row['id'] as String? ?? '';
        debugPrint('[L luckybag] active envelope loaded id=$envelopeId sender=${row['sender_id']}');
        setState(() => _activeRedEnvelope = row);
      }
    } catch (e) {
      debugPrint('[RED] loadActiveRedEnvelope error: $e');
    }
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
            debugPrint('[L luckybag] realtime insert envelope=$envelopeId sender=$senderId iAmSender=$iAmSender');
            setState(() {
              _activeRedEnvelope = row;
              // Show the entrance overlay only to receivers, not the sender
              // (sender already saw the confirmation from onRedEnvelopeCreated).
              if (!iAmSender) _showLuckyBagEntrance = true;
            });
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
          debugPrint('[RT-RED] status=$status error=$error room=${widget.room.id}');
        });
  }

  Future<void> _claimRedEnvelope() async {
    final envelope = _activeRedEnvelope;
    if (envelope == null || _claimingEnvelope) return;
    final envelopeId = envelope['id'] as String?;
    if (envelopeId == null) return;
    // Sender cannot claim their own Lucky Bag.
    if ((envelope['sender_id'] as String?) == _currentUserId) {
      debugPrint('[L luckybag] hidden reason=sender id=$envelopeId');
      return;
    }
    setState(() => _claimingEnvelope = true);
    try {
      final coins = await SupabaseService.requiredClient
          .rpc('claim_red_envelope', params: {'p_envelope_id': envelopeId}) as int;
      if (!mounted) return;
      setState(() {
        _luckyBagWinCoins = coins;
        // Optimistic credit so toolbar balance updates instantly.
        _walletCoins += coins;
        _openedLuckyBagIds.add(envelopeId);
        _activeRedEnvelope = null;
      });
      unawaited(_loadWalletBalance());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          context.isArabic ? 'Ø­ØµÙ„Øª Ø¹Ù„Ù‰ $coins Ø¹Ù…Ù„Ø©!' : 'You got $coins coins!',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFFD4380D),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        duration: const Duration(seconds: 3),
      ));
    } catch (e, st) {
      debugPrint('[RoomImage] failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      final msg = e.toString();
      String friendly;
      if (msg.contains('already_claimed')) {
        friendly = context.isArabic ? 'ÙØªØ­Øª Ù‡Ø°Ù‡ Ø§Ù„Ø­Ù‚ÙŠØ¨Ø© Ù…Ø³Ø¨Ù‚Ø§Ù‹' : 'Already opened';
        setState(() {
          _openedLuckyBagIds.add(envelopeId);
          _activeRedEnvelope = null;
        });
      } else if (msg.contains('envelope_full')) {
        friendly = context.isArabic ? 'Ù†ÙØ¯Øª Ø§Ù„Ø­Ù‚Ø§Ø¦Ø¨' : 'All bags claimed';
        setState(() => _activeRedEnvelope = null);
      } else if (msg.contains('envelope_expired')) {
        friendly = context.isArabic ? 'Ø§Ù†ØªÙ‡Øª ØµÙ„Ø§Ø­ÙŠØ© Ø§Ù„Ø­Ù‚ÙŠØ¨Ø©' : 'Lucky Bag expired';
        setState(() => _activeRedEnvelope = null);
      } else {
        friendly = context.isArabic ? 'Ø­Ø¯Ø« Ø®Ø·Ø£' : 'An error occurred';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendly, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2A0F1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ));
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
    } catch (_) {}
  }

  Future<void> _handlePkCancelRequested() async {
    final pk = _activePk;
    if (pk == null) return;
    try {
      await _pkService.cancelPk(pk.id);
    } catch (_) {}
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
            final newMaxSeats = rec['max_seats'] as int?;
            debugPrint(
              '[RT-ROOM] event=UPDATE roomId=${widget.room.id} maxSeats=$newMaxSeats',
            );
            if (newMaxSeats != null && newMaxSeats != _currentMaxSeats) {
              debugPrint('[RT-ROOM] applying maxSeats=$newMaxSeats locally');
              setState(() => _currentMaxSeats = newMaxSeats);
            }
          },
        )
        .subscribe((status, [error]) {
          debugPrint('[RT-ROOM] status=$status error=$error room=${widget.room.id}');
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
            debugPrint('[RT-MEMBERS] event=${payload.eventType} id=${payload.newRecord["id"]} muted=${payload.newRecord["is_muted"]}');
            _debouncedLoadMembers();
          },
        )
        .subscribe((status, [error]) {
          debugPrint('[RT-MEMBERS] status=$status error=$error room=${widget.room.id}');
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
            // waiting for the DB read ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â avoids the read-before-write race on
            // the receiver's phone.
            debugPrint('[RT-RED] event room=${widget.room.id} new=${payload.newRecord} old=${payload.oldRecord}');
            final record = payload.newRecord;
            if (kDebugMode) {
              debugPrint(
                '[Gift] event received room=${widget.room.id} '
                'id=${record['id']} code=${record['gift_code']} '
                'sender=${record['sender_id']} receiver=${record['receiver_id']}',
              );
            }
            if (record.isNotEmpty) {
              final giftCode = record['gift_code'] as String? ?? '';
              final giftName = record['gift_name'] as String? ?? '';
              final receiverId = record['receiver_id'] as String? ?? '';

              final config = _LuxuryGiftVideoConfig.fromCode(giftCode);
              if (config != null && _activeLuxuryGiftVideo == null && _visualEnabled) {
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
            debugPrint('[Gift] realtime channel status=$status error=$error');
          }
          // Surface a clean message instead of silently failing if the room
          // gift realtime channel can't be established.
          if (!mounted) return;
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.isArabic
                      ? 'ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â°ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â± ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂµÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â« ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â´ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±. ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¸ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â± ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¹Ã¢â‚¬Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¹.'
                      : 'Live gift connection failed. Gifts may not appear instantly.',
                ),
              ),
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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
      final members = await _roomsService.getActiveRoomMembers(widget.room.id);

      if (!mounted) return;

      // Detect if the current user was removed / kicked by someone else.
      // Guard: only check after the initial load (_members is non-empty or we
      // already had at least one successful load), and never during self-exit.
      final currentUserId = _currentUserId;
      if (!_leaving &&
          currentUserId != null &&
          _members.isNotEmpty &&
          !members.any((m) => m.userId == currentUserId)) {
        debugPrint('[MODERATION] kicked detection: user=$currentUserId not in active members');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.isArabic
                    ? 'تمت إزالتك من الغرفة'
                    : 'You were removed from the room',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
          await _leaveRoom();
        }
        return;
      }

      setState(() {
        _members = members;
      });

      if (detectVipEntry) {
        _showVipEntryForNewMembers(members, previousMemberIds);
      }

      await _syncMicConnectionWithSeat();
    } catch (error) {
      if (!mounted) return;

      if (showLoading) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _showVipEntryForNewMembers(
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
      if (!VipFeatures.hasEntryBanner(level)) {
        continue;
      }

      _vipEntryBannerTimer?.cancel();
      _vipBannerNotifier.value = member;
      _vipEntryBannerTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        if (_vipBannerNotifier.value?.userId == member.userId) {
          _vipBannerNotifier.value = null;
        }
      });
      break;
    }
  }

  Future<void> _loadModeratorCount() async {
    try {
      final mods = await const RoomManagementService().getModerators(widget.room.id);
      if (mounted) setState(() => _moderatorCount = mods.length);
    } catch (_) {}
  }

  Future<void> _loadAnnouncement() async {
    try {
      final ann = await const RoomManagementService()
          .getActiveAnnouncement(widget.room.id);
      if (mounted) setState(() => _activeAnnouncementText = ann?.message);
    } catch (_) {}
  }

  Future<void> _loadWalletBalance() async {
    try {
      final wallet = await const WalletService().fetchWallet();
      if (mounted) setState(() => _walletCoins = wallet.coinsBalance);
    } catch (_) {}
  }

  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Room messages ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬

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
              // Fetch sender profile to enrich the message.
              SupabaseService.requiredClient
                  .from('profiles')
                  .select('display_name, username, avatar_url, vip_level')
                  .eq('id', row['sender_id'] as String)
                  .maybeSingle()
                  .then((profile) {
                if (!mounted) return;
                final enriched = {
                  ...row,
                  'profiles': profile,
                };
                final msg = RoomMessage.fromJson(
                  enriched.map((k, v) => MapEntry(k, v)),
                );
                // Avoid duplicate: skip if real ID already present.
                if (_chatMessages.any((m) => m.id == msg.id)) return;
                setState(() {
                  // Remove optimistic placeholder for this sender so the
                  // confirmed server message replaces it without duplication.
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
              });
            } catch (_) {}
          },
        )
        .subscribe();
  }

  Future<void> _sendChatMessage(String text) async {
    
    FocusManager.instance.primaryFocus?.unfocus();if (text.trim().isEmpty) return;
    setState(() => _isSendingMessage = true);

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
      );
      setState(() => _chatMessages.add(optimistic));
    }

    try {
      await _msgService.sendMessage(
        roomId: widget.room.id,
        message: text,
        senderRole: _myMember?.role ?? 'listener',
      );
    } catch (_) {
      // Remove optimistic on failure.
      if (mounted) {
        setState(() => _chatMessages.removeWhere(
          (m) => m.id.startsWith('optimistic_'),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
    }
  }

  Future<void> _sendChatImageMessage() async {
    debugPrint('[RoomImage] _sendChatImageMessage tapped');
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
        debugPrint('[chat-image] backend VIP check failed, using local: $e');
      }
    }

    if (!canSend) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? 'رسائل الصور تُفتح من VIP 7'
                : 'Image messages unlock at VIP 7',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _uploadingChatImage = true);
    try {
      final userId = _currentUserId;
      if (userId == null) return;

      final result = await const RoomChatImageUploadService()
          .pickAndUpload(userId: userId);
      if (result == null) return; // user cancelled

      await _msgService.sendImageMessage(
        roomId: widget.room.id,
        imageUrl: result.url,
        imagePath: result.path,
        senderRole: _myMember?.role ?? 'listener',
      );
    } catch (e, st) {
      debugPrint('[RoomImage] failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      final msg = e is ArgumentError
          ? e.message.toString()
          : 'Failed to send image. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingChatImage = false);
    }
  }

  void _clearChat() {
    // Clear the visible chat feed. Host-only UX action.
    setState(() {
      _roomGifts = const [];
      _chatMessages.clear();
      _chatMessages.add(RoomMessage.local(
        roomId: widget.room.id,
        message: context.isArabic
            ? 'ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¶ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â´ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â©.'
            : 'The room owner has cleaned the chat.',
      ));
    });
  }

  // ignore: unused_element
  void _sendSalute() {
    if (_currentUserId == null) return;
    final senderName = _members
            .where((m) => m.userId == _currentUserId)
            .firstOrNull
            ?.displayName ??
        (context.isArabic ? 'ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦' : 'User');
    final text = context.isArabic
        ? '$senderName ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â£ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â© ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂºÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â© ÃƒÆ’Ã‚Â°Ãƒâ€¦Ã‚Â¸ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¹'
        : '$senderName sent a salute to the room ÃƒÆ’Ã‚Â°Ãƒâ€¦Ã‚Â¸ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¹';
    setState(() {
      _chatMessages.add(RoomMessage.local(
        roomId: widget.room.id,
        message: text,
      ));
    });
  }

  /// Stops music locally right away and propagates the stop to all room
  /// participants via the Supabase RPC.  Shows a snackbar on failure.
  Future<void> _stopMusicForRoom() async {
    // 1. Stop local player immediately so this device feels instant.
    await _musicService.stop();
    // 2. Push stop to Supabase Ã¢â€ â€™ Realtime will propagate to all participants.
    try {
      await _syncedMusic.stopForRoom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? 'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã™â€˜Ã˜Â± Ã˜Â¥Ã™Å Ã™â€šÃ˜Â§Ã™Â Ã˜Â§Ã™â€žÃ™â€¦Ã™Ë†Ã˜Â³Ã™Å Ã™â€šÃ™â€°. Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€ž Ã™â€¦Ã˜Â±Ã˜Â© Ã˜Â£Ã˜Â®Ã˜Â±Ã™â€°.'
                : 'Could not stop music. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _openMusicPanel() {
    final canManage = _iAmRoomOwner || _iAmHost;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MusicPanel(
        musicService: _musicService,
        isArabic: context.isArabic,
        canManage: canManage,
        roomId: widget.room.id,
        uploadService: canManage ? _uploadService : null,
        // When the host selects a track, add it to the playlist and play Ã¢â‚¬â€
        // _onLocalMusicChanged will push the state to Supabase automatically.
        onTrackSelected: canManage
            ? (song) {
                debugPrint('[RoomMusicSync] host selected id=${song.id} source=${song.sourceType} url=${song.url} localPath=${song.localPath}');
                _musicService.addToPlaylist(song);
                final idx = _musicService.playlist.indexWhere((s) => s.id == song.id);
                if (idx >= 0) unawaited(_musicService.playSong(idx));
              }
            : null,
      ),
    );
  }

  void _openReactionPicker() {
    ReactionPickerSheet.show(context, onPick: _sendReaction);
  }

  void _openToolsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RoomToolsSheet(
        room: _currentRoom,
        isArabic: context.isArabic,
        isOwner: _iAmRoomOwner,
        isHost: _iAmHost,
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
          debugPrint('[L luckybag] created sender=$_currentUserId envelope=$envelopeId');
          setState(() {
            _activeRedEnvelope = envelope;
            // Sender sees their own sent-confirmation banner, not the entrance
            // overlay (which is reserved for receivers via Realtime).
            _showLuckyBagEntrance = false;
            // Optimistic decrement so toolbar balance updates instantly.
            if (spent > 0) _walletCoins = (_walletCoins - spent).clamp(0, _walletCoins);
          });
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
        name: widget.room.name,
        description: widget.room.description,
        language: widget.room.language,
        livekitRoomName: widget.room.livekitRoomName,
        maxSeats: _currentMaxSeats,
        isPrivate: widget.room.isPrivate,
        isLocked: widget.room.isLocked,
        isClosed: widget.room.isClosed,
        createdAt: widget.room.createdAt,
        coverUrl: _roomCoverUrl,
        backgroundUrl: _roomBackgroundUrl,
        avatarUrl: _roomAvatarUrl,
      );

  Future<void> _pickListenerForSeat(int seatNumber) async {
    if (_myMember == null) {
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

    final selected = await showModalBottomSheet<_EmptySeatAction>(
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
                  textAlign: context.isArabic ? TextAlign.right : TextAlign.left,
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
                      ).pop(const _EmptySeatAction.moveSelf());
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
                      leading: _RoomAvatar(
                        avatarUrl: member.avatarUrl,
                        frameKey: member.selectedAvatarFrameKey,
                        vipLevel: member.effectiveVipLevel,
                        size: 42,
                        selected: false,
                        fallbackIcon: Icons.person_rounded,
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
                        ).pop(_EmptySeatAction.moveMember(member));
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

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u062a\u0645 \u0646\u0642\u0644\u0647 \u0625\u0644\u0649 \u0645\u0627\u064a\u0643 $seatNumber.'
                : 'Moved to Mic $seatNumber.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _roleBusyUserId = null;
        });
      }
    }
  }

  Future<void> _moveMyselfToSeat(int seatNumber) async {
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

      await _loadMembers(showLoading: false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u062a\u0645 \u0646\u0642\u0644\u0643 \u0625\u0644\u0649 \u0647\u0630\u0627 \u0627\u0644\u0645\u0627\u064a\u0643'
                : 'Moved you to this mic.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showMemberSeatActions(RoomMember member, int seatNumber) async {
    if (!_iAmHost) {
      return;
    }

    if (member.role == 'host') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u0644\u0627 \u064a\u0645\u0643\u0646 \u0646\u0642\u0644 \u0645\u0642\u0639\u062f \u0627\u0644\u0645\u0636\u064a\u0641.'
                : 'Host seat cannot be moved.',
          ),
        ),
      );
      return;
    }

    final emptySeats = _emptySeatNumbers(exceptUserId: member.userId);

    final action = await showModalBottomSheet<_OccupiedSeatAction>(
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
                    ).pop(const _OccupiedSeatAction.selectForMove()),
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
                          ).pop(_OccupiedSeatAction.moveToSeat(number));
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
                    ).pop(const _OccupiedSeatAction.moveToListener()),
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
    if (!_iAmHost) {
      return;
    }

    if (member.role == 'host') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u0644\u0627 \u064a\u0645\u0643\u0646 \u0646\u0642\u0644 \u0645\u0642\u0639\u062f \u0627\u0644\u0645\u0636\u064a\u0641.'
                : 'Host seat cannot be moved.',
          ),
        ),
      );
      return;
    }

    _selectMicMoveMember(member);
  }

  void _selectMicMoveMember(RoomMember member) {
    setState(() {
      _selectedMicMoveMember = member;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.isArabic
              ? '\u0627\u0636\u063a\u0637 \u0639\u0644\u0649 \u0645\u0627\u064a\u0643 \u0641\u0627\u0631\u063a \u0644\u0646\u0642\u0644 ${member.fallbackName(context.isArabic)}.'
              : 'Tap an empty mic to move ${member.fallbackName(context.isArabic)}.',
        ),
      ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.isArabic
                  ? '\u0645\u0642\u0627\u0639\u062f \u0627\u0644\u0645\u062a\u062d\u062f\u062b\u064a\u0646 \u0645\u0645\u062a\u0644\u0626\u0629.'
                  : 'Speaker seats are full.',
            ),
          ),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u062a\u0645 \u062a\u062d\u062f\u064a\u062b \u0627\u0644\u062f\u0648\u0631'
                : 'Role updated',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u0644\u0627 \u064a\u0645\u0643\u0646\u0643 \u0637\u0631\u062f \u0645\u0633\u062a\u062e\u062f\u0645 VIP \u0628\u0647\u0630\u0627 \u0627\u0644\u0645\u0633\u062a\u0648\u0649'
                : 'You cannot remove a VIP user at this level',
          ),
        ),
      );
      return;
    }

    if (hasAntiKickProtection(targetVipLevel) &&
        !canKickVip5User(
          isRoomOwner: _iAmRoomOwner,
          isSuperAdmin: _iAmSuperAdmin,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u0644\u0627 \u064a\u0645\u0643\u0646\u0643 \u0637\u0631\u062f \u0645\u0633\u062a\u062e\u062f\u0645 VIP \u0628\u0647\u0630\u0627 \u0627\u0644\u0645\u0633\u062a\u0648\u0649'
                : 'This VIP 5+ user is protected from removal.',
          ),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            context.isArabic
                ? 'ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â°ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚ÂªÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â®ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ VIP ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢Ãƒâ€¦Ã‚Â  ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â§ÃƒÆ’Ã¢â€žÂ¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â·ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â±ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¯'
                : 'This VIP user is protected from kick.',
          ),
        ));
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u062a\u0645 \u0625\u0632\u0627\u0644\u0629 \u0627\u0644\u0639\u0636\u0648 \u0645\u0646 \u0627\u0644\u063a\u0631\u0641\u0629.'
                : 'User removed from the room.',
          ),
        ),
      );

      await _loadMembers(showLoading: false);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.isArabic
              ? (permanentlyDenied
                    ? '\u062a\u0645 \u062d\u0638\u0631 \u0625\u0630\u0646 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646. \u0627\u0641\u062a\u062d \u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a \u0648\u0627\u0633\u0645\u062d \u0628\u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646.'
                    : '\u064a\u062d\u062a\u0627\u062c SrOOd Live \u0625\u0644\u0649 \u0625\u0630\u0646 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646 \u0644\u0644\u062a\u062d\u062f\u062b \u0641\u064a \u0627\u0644\u063a\u0631\u0641.')
              : (permanentlyDenied
                    ? 'Microphone permission is blocked. Open app settings and allow microphone.'
                    : 'Srood Live needs microphone permission so you can speak in rooms.'),
        ),
        action: permanentlyDenied
            ? SnackBarAction(
                label: context.isArabic
                    ? '\u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a'
                    : 'Settings',
                onPressed: openAppSettings,
              )
            : null,
      ),
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
        // If early connect is still in-flight, wait for it instead of bailing Ã¢â‚¬â€
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
          // Early connect failed or never started Ã¢â‚¬â€ connect now.
          if (mounted) _setAudioState(connecting: true);

          _liveKitRoomService.onSpeakersChanged = (ids) {
            if (mounted) setState(() => _speakingUserIds = ids);
          };

          debugPrint('[Room] ${_roomTs()} LiveKit connect started (sync)');
          await _liveKitRoomService.connect(
            roomId: widget.room.id,
            microphoneEnabled: false,
          );
          debugPrint('[Room] ${_roomTs()} LiveKit connected');

          if (mounted) _setAudioState(connected: true);
        }
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
        if (justTookSeat && member?.isMuted == true && member?.forceMuted != true) {
          await _roomsService.setMyMuteStatus(
            roomId: widget.room.id,
            isMuted: false,
          );
        }
        if (justTookSeat && member?.forceMuted == true) {
          debugPrint('[MUTE] forced mute applied user=${member?.userId} — seat taken but mute preserved');
        }

        if (!mounted) return;

        setState(() {
          _micEnabled = desiredMicEnabled;
          _wasCurrentUserOnMic = true;
        });

        if (kDebugMode) {
          debugPrint('[Room] Mic published enabled=$desiredMicEnabled');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.isArabic
                  ? '\u062a\u0639\u0630\u0631 \u062a\u0634\u063a\u064a\u0644 \u0627\u0644\u0645\u0627\u064a\u0643. \u062a\u0623\u0643\u062f \u0645\u0646 \u0625\u0630\u0646 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646.'
                  : 'Could not start the microphone. Please check microphone permission.',
            ),
          ),
        );
      }
    } finally {
      _syncingMicConnection = false;

      if (mounted) _setAudioState(connecting: false);
    }
  }

  Future<void> _toggleMic() async {
    if (!_isCurrentUserOnMic) {
      return;
    }

    if (!_connectedAudio) {
      await _syncMicConnectionWithSeat();
      return;
    }

    final nextValue = !_micEnabled;

    // Block self-unmute when owner has force-muted this user.
    if (nextValue && (_myMember?.forceMuted == true)) {
      debugPrint('[MUTE] self unmute denied reason=forced_mute');
      return;
    }

    if (nextValue) {
      final hasMicrophonePermission = await _ensureMicrophonePermission();

      if (!hasMicrophonePermission) {
        return;
      }
    }

    await _liveKitRoomService.setMicrophoneEnabled(nextValue);
    await _roomsService.setMyMuteStatus(
      roomId: widget.room.id,
      isMuted: !nextValue,
    );

    if (!mounted) return;

    setState(() {
      _micEnabled = nextValue;
    });

    await _loadMembers();
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _leaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u062a\u0639\u0630\u0631 \u0645\u063a\u0627\u062f\u0631\u0629 \u0627\u0644\u063a\u0631\u0641\u0629. \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.'
                : 'Could not leave the room. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isClosingRoom = false;
        _leaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u062a\u0639\u0630\u0631 \u0625\u063a\u0644\u0627\u0642 \u0627\u0644\u063a\u0631\u0641\u0629. \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.'
                : 'Could not close the room. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Called from the bottom action bar exit button \u2014 exits quietly (no vault anim).
  Future<void> _leaveRoom() => _handleExitRoom();

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
    final isOnMic = target != null &&
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
          // Moderation callbacks ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â only provided when caller can act
          onToggleMute: (canModerate && !isTargetOwner && target != null)
              ? (muted) async {
                  debugPrint('[MUTE] forced mute applied user=$userId isMuted=$muted');
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
                  await _changeMemberRole(
                    member: target,
                    role: 'listener',
                  );
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
                  await const RoomManagementService()
                      .addModerator(widget.room.id, userId);
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0647\u062f\u0627\u064a\u0627. \u0633\u064a\u062a\u0645 \u0627\u0633\u062a\u062e\u062f\u0627\u0645 \u0627\u0644\u0642\u0627\u0626\u0645\u0629 \u0627\u0644\u0645\u062d\u0644\u064a\u0629.'
                : 'Could not load gifts. Using local gifts.',
          ),
        ),
      );
    }

    if (!mounted) return;

    final result = await showModalBottomSheet<_GiftSendResult>(
      context: context,
      backgroundColor: const Color(0xFF12091D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return _GiftSheet(
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

    try {
      if (kDebugMode) {
        debugPrint(
          '[Gift] send tapped room=${widget.room.id} '
          'receiver=${result.receiverUserId} gift=${result.gift.code}',
        );
      }
      await _giftsService.sendGift(
        roomId: widget.room.id,
        receiverId: result.receiverUserId,
        gift: result.gift,
      );
      if (kDebugMode) {
        debugPrint('[Gift] send + wallet debit succeeded (RPC)');
      }
    } catch (error) {
      if (!mounted) return;

      final errorText = error.toString();
      final message = errorText.contains('insufficient_coins')
          ? (context.isArabic
                ? '\u0631\u0635\u064a\u062f\u0643 \u063a\u064a\u0631 \u0643\u0627\u0641\u064d'
                : 'Not enough coins')
          : (context.isArabic
                ? '\u062a\u0639\u0630\u0631 \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0647\u062f\u064a\u0629. \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.'
                : 'Could not send gift. Please try again.');

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    if (!mounted) return;

    await _loadRoomGifts(showLoading: false, showNewestBanner: true);

    if (!mounted) return;

    _showGiftEvent(result);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.isArabic
              ? '\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 ${result.gift.name} \u0625\u0644\u0649 ${result.receiverName}'
              : '${result.gift.name} sent to ${result.receiverName}',
        ),
      ),
    );
  }

  void _showGiftEvent(_GiftSendResult result) {
    final event = _RoomGiftEvent(
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
    timer = Timer(const Duration(seconds: 4), () {
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
    final config = _LuxuryGiftVideoConfig.fromCode(transaction.giftCode);

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
    required _LuxuryGiftVideoConfig config,
  }) {
    _luxuryGiftVideoTimer?.cancel();

    setState(() {
      _activeLuxuryGiftVideo = _ActiveLuxuryGiftVideo(
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

            return _RoomParticipantsSheet(
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

    final action = await showModalBottomSheet<_RoomExitAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RoomExitSheet(isOwner: isOwner, isArabic: isArabic),
    );

    if (action == null || !mounted) return false;

    if (action == _RoomExitAction.minimize) {
      _minimizeRoom();
      return false;
    }

    if (action == _RoomExitAction.exit) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A0840),
          title: Text(
            isArabic ? 'Ã™â€¦Ã˜ÂºÃ˜Â§Ã˜Â¯Ã˜Â±Ã˜Â© Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â©Ã˜Å¸' : 'Exit Room?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Text(
            isArabic
                ? 'Ã˜Â³Ã˜ÂªÃ˜ÂºÃ˜Â§Ã˜Â¯Ã˜Â± Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â©. Ã˜Â³Ã˜ÂªÃ˜Â¨Ã™â€šÃ™â€° Ã™â€¦Ã™ÂÃ˜ÂªÃ™Ë†Ã˜Â­Ã˜Â© Ã™â€žÃ™â€žÃ˜Â¢Ã˜Â®Ã˜Â±Ã™Å Ã™â€ .'
                : 'You will leave this room. The room will stay open for others.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(isArabic ? 'Ã˜Â¥Ã™â€žÃ˜ÂºÃ˜Â§Ã˜Â¡' : 'Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFE63946)),
              child: Text(isArabic ? 'Ã™â€¦Ã˜ÂºÃ˜Â§Ã˜Â¯Ã˜Â±Ã˜Â©' : 'Exit Room'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) await _handleExitRoom();
      return false;
    }

    // closeRoom Ã¢â‚¬â€ show vault PIN sheet as dramatic confirmation
    final pin = await showVaultPinSheet(
      context,
      title: isArabic ? 'Ã˜Â¥Ã˜ÂºÃ™â€žÃ˜Â§Ã™â€š Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â©' : 'Close Room',
      subtitle: isArabic
          ? (widget.room.roomPinEnabled
              ? 'Ã˜Â£Ã˜Â¯Ã˜Â®Ã™â€ž Ã˜Â±Ã™â€¦Ã˜Â² Ã˜Â§Ã™â€žÃ™â€šÃ˜Â¨Ã™Ë† Ã™â€žÃ˜Â¥Ã˜ÂºÃ™â€žÃ˜Â§Ã™â€š Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â©.'
              : 'Ã˜Â³Ã™Å Ã˜ÂªÃ™â€¦ Ã˜Â¥Ã™â€ Ã™â€¡Ã˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â© Ã™â€žÃ˜Â¬Ã™â€¦Ã™Å Ã˜Â¹ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜Â§Ã˜Â±Ã™Æ’Ã™Å Ã™â€ .')
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
    ActiveRoomSession.instance.minimize(widget.room);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final kbHeight = MediaQuery.of(context).viewInsets.bottom;
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
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          context.isArabic ? '\u0627\u0644\u063a\u0631\u0641\u0629' : 'Room',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
          ),
        ),
        actions: [
          if (_iAmRoomOwner)
            IconButton(
              icon: const Icon(Icons.manage_accounts_rounded),
              tooltip: context.isArabic ? '\u0625\u062f\u0627\u0631\u0629 \u0627\u0644\u063a\u0631\u0641\u0629' : 'Manage Room',
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.35),
              ),
              onPressed: () async {
                final result = await Navigator.of(context).push<Map<String, String?>>(
                  MaterialPageRoute(
                    builder: (_) => RoomOwnerManagementScreen(
                      room: _currentRoom,
                      isArabic: context.isArabic,
                    ),
                  ),
                );
                if (result != null && mounted) {
                  setState(() {
                    if (result.containsKey('cover_url')) {
                      _roomCoverUrl = result['cover_url'];
                    }
                    if (result.containsKey('avatar_url')) {
                      _roomAvatarUrl = result['avatar_url'];
                    }
                  });
                }
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // \u2500\u2500 1. Full-screen immersive background \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          _FullRoomBackground(room: widget.room, backgroundUrl: _roomBackgroundUrl),

          // \u2500\u2500 2. Scrollable content + pinned bottom bar \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 2. Fixed column: header + mic stage + scrollable chat ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Room info card (fixed ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â never scrolls)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                  child: _CompactRoomHeader(
                    room: _currentRoom,
                    activeSpeakerCount: _activeSpeakerCount,
                    memberCount: _members.length,
                    walletCoins: _walletCoins,
                    isHost: _iAmHost,
                    isArabic: context.isArabic,
                    announcement: _activeAnnouncementText,
                  ),
                ),
                // Gift / VIP entry banners — rebuilt only when banner changes.
                ValueListenableBuilder<RoomGiftTransaction?>(
                  valueListenable: _giftBannerNotifier,
                  builder: (ctx, giftBanner, child) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: giftBanner == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(giftBanner.id),
                            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                            child: _GiftRoomBanner(
                              gift: giftBanner,
                              isArabic: ctx.isArabic,
                              onProfileTap: _openUserProfileSheet,
                            ),
                          ),
                  ),
                ),
                ValueListenableBuilder<RoomMember?>(
                  valueListenable: _vipBannerNotifier,
                  builder: (ctx, vipMember, child) => ValueListenableBuilder<RoomGiftTransaction?>(
                    valueListenable: _giftBannerNotifier,
                    builder: (ctx2, giftBanner, child2) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: giftBanner != null || vipMember == null
                          ? const SizedBox.shrink()
                          : Padding(
                              key: ValueKey(vipMember.userId),
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                              child: _VipEntryRoomBanner(
                                member: vipMember,
                                isArabic: ctx2.isArabic,
                              ),
                            ),
                    ),
                  ),
                ),
                // Mic stage glass panel (FIXED -- never inside a scroll container)
                Container(
                  margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                    child: _LiveRoomStage(
                    members: _members,
                    maxSeats: _currentMaxSeats,
                    isArabic: context.isArabic,
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
                    activePk: _activePk?.isActive == true ? _activePk : null,
                    showPkResult: _showPkResult,
                    pkResult: _showPkResult && _activePk?.isFinished == true
                        ? _activePk
                        : null,
                    onPkFinish: _handlePkAutoFinish,
                    onPkResultClose: () =>
                        setState(() => _showPkResult = false),
                    seatReactions: _seatReactions,
                  ),
                ),
                ),
                // Scrollable chat feed (only this area scrolls)
                Expanded(
                  child: _RoomChatFeed(
                    chatMessages: _chatMessages,
                    isArabic: context.isArabic,
                    onProfileTap: _openUserProfileSheet,
                    bottomPad: 116 + bottomPad + kbHeight,
                  ),
                ),
              ],
            ),
          ),

          // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Pinned bottom action bar ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
          Positioned(
            bottom: kbHeight,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<({bool connecting, bool connected})>(
              valueListenable: _audioStateNotifier,
              builder: (context2, audioState, child2) => _LiveBottomActionBar(
                isArabic: context.isArabic,
                connectingAudio: audioState.connecting,
                micEnabled: _micEnabled,
                isOnMic: _isCurrentUserOnMic,
                leaving: _leaving,
                isSendingMessage: _isSendingMessage,
                myVipLevel: _myMember?.effectiveVipLevel ?? 0,
                isUploadingImage: _uploadingChatImage,
                onToggleMic: _toggleMic,
                onLeaveRoom: _leaveRoom,
                onGiftTap: _openGiftSheet,
                onMoreTap: _openToolsSheet,
                onReactionTap: _openReactionPicker,
                onSendMessage: _sendChatMessage,
                onSendImage: _sendChatImageMessage,
                bottomPad: bottomPad,
              ),
            ),
          ),

          // \u2500\u2500 3. Gift floating event overlay \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          _GiftEventOverlay(
              events: _giftEvents, isArabic: context.isArabic),

          // \u2500\u2500 4. Full-screen luxury gift video \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          if (_activeLuxuryGiftVideo != null)
            _LuxuryGiftVideoOverlay(
              playback: _activeLuxuryGiftVideo!,
              onDone: _clearLuxuryGiftVideo,
              // Mute gift video audio while room music is playing so the music
              // player is never interrupted by the video's audio track.
              soundEnabled: _soundEnabled && !_musicService.isActive,
            ),

          if (_activeRedEnvelope != null &&
              !_openedLuckyBagIds.contains(_activeRedEnvelope!['id'] as String?))
            Builder(builder: (context) {
              final envelope = _activeRedEnvelope!;
              final envelopeId = envelope['id'] as String? ?? '';
              final isSender = (envelope['sender_id'] as String?) == _currentUserId;
              if (isSender) {
                debugPrint('[L luckybag] sender confirmation only id=$envelopeId');
              } else {
                debugPrint('[L luckybag] show receiver claim ui id=$envelopeId');
              }
              return Positioned(
                top: 80 + MediaQuery.of(context).padding.top,
                left: 16,
                right: 16,
                child: _RedEnvelopeBanner(
                  envelope: envelope,
                  isArabic: context.isArabic,
                  loading: _claimingEnvelope,
                  isSender: isSender,
                  onClaim: _claimRedEnvelope,
                  onDismiss: () => setState(() => _activeRedEnvelope = null),
                ),
              );
            }),

          // -- 6. Lucky Bag entrance overlay (receivers see this on Realtime INSERT) --
          if (_showLuckyBagEntrance)
            Positioned.fill(
              child: _LuckyBagEntranceOverlay(
                key: const ValueKey('lucky-bag-entrance-overlay'),
                soundEnabled: _soundEnabled,
                onDone: () {
                  if (mounted) setState(() => _showLuckyBagEntrance = false);
                },
              ),
            ),

          // -- 7. Lucky Bag win overlay (claimer sees this) --
          if (_luckyBagWinCoins != null)
            Positioned.fill(
              child: _LuckyBagWinOverlay(
                key: ValueKey('lucky-bag-win-overlay-$_luckyBagWinCoins'),
                coins: _luckyBagWinCoins!,
                soundEnabled: _soundEnabled,
                onDone: () {
                  if (mounted) setState(() => _luckyBagWinCoins = null);
                },
              ),
            ),

          // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ 5. Music mini-player ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
          // Music mini-player sits just above the bottom toolbar + chat bar.
          // bottom = action bar height (~116) + 4px breathing gap + bottomPad
          Positioned(
            bottom: 120 + bottomPad + kbHeight,
            left: 0,
            right: 0,
            child: ListenableBuilder(
              listenable: _musicService,
              builder: (_, _) => _musicService.isActive
                  ? RoomMiniPlayer(
                      musicService: _musicService,
                      isArabic: context.isArabic,
                      onTap: _openMusicPanel,
                      canManage: _iAmRoomOwner || _iAmHost,
                      onStop: (_iAmRoomOwner || _iAmHost)
                          ? () => unawaited(_stopMusicForRoom())
                          : null,
                    )
                  : const SizedBox.shrink(),
            ),
          ),

          // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ 6. Srood Loto side shortcut (lower-right / lower-left for RTL) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
          // Positioned above the chat overlay so it never blocks messages.
          Positioned(
            right: context.isArabic ? null : 0,
            left: context.isArabic ? 0 : null,
            bottom: 280 + bottomPad + kbHeight,
            child: _LotoFloatingButton(
              isArabic: context.isArabic,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SroodLotoScreen(isArabic: context.isArabic),
                ),
              ),
            ),
          ),
        ],
      ),
          ), // Scaffold

          // Vault closing overlay ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â rendered above everything, owner-only style
          if (_isClosingRoom)
            _RoomClosingOverlay(
              key: ValueKey('room-closing-overlay-${widget.room.id}'),
              isOwnerClosing: _iAmRoomOwner,
              isArabic: context.isArabic,
            ),
        ],
      ),
    ); // PopScope
  }
}

class _CompactRoomHeader extends StatelessWidget {
  const _CompactRoomHeader({
    required this.room,
    required this.activeSpeakerCount,
    required this.memberCount,
    required this.walletCoins,
    required this.isHost,
    required this.isArabic,
    this.announcement,
  });

  final Room room;
  final int activeSpeakerCount;
  final int memberCount;
  final int walletCoins;
  final bool isHost;
  final bool isArabic;
  final String? announcement;

  @override
  Widget build(BuildContext context) {
    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final hasCover = room.coverUrl != null;

    return Directionality(
      textDirection: textDir,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // \u2500\u2500 Main identity card \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF4A3470).withValues(alpha: 0.7),
              ),
            ),
            child: Stack(
              children: [
                // Background (cover or gradient)
                if (hasCover)
                  Positioned.fill(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Layer 1: blurred fill so no gaps on tall/wide images
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Image.network(
                            room.coverUrl!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            errorBuilder: (_, e, s) => const _RoomDefaultBg(),
                          ),
                        ),
                        // Layer 2: actual image showing full width without harsh crop
                        Image.network(
                          room.coverUrl!,
                          fit: BoxFit.fitWidth,
                          alignment: Alignment.center,
                          errorBuilder: (_, e, s) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  )
                else
                  const Positioned.fill(child: _RoomDefaultBg()),

                // Dark overlay for readability
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: hasCover ? 0.30 : 0.0),
                          Colors.black.withValues(alpha: hasCover ? 0.65 : 0.0),
                        ],
                      ),
                    ),
                  ),
                ),

                // Content row
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      // Room icon / avatar
                      Container(
                        width: 48,
                        height: 48,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0C15A).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFF0C15A)
                                .withValues(alpha: 0.50),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF0C15A).withValues(alpha: 0.18),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: room.avatarUrl?.isNotEmpty == true
                            ? Image.network(
                                room.avatarUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, e, s) => const Icon(
                                  Icons.mic_rounded,
                                  color: Color(0xFFF0C15A),
                                  size: 22,
                                ),
                              )
                            : const Icon(
                                Icons.mic_rounded,
                                color: Color(0xFFF0C15A),
                                size: 22,
                              ),
                      ),
                      const SizedBox(width: 12),

                      // Name + description
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              room.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                shadows: hasCover
                                    ? [
                                        const Shadow(
                                          blurRadius: 6,
                                          color: Colors.black54,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            if (room.description?.isNotEmpty == true) ...[
                              const SizedBox(height: 2),
                              Text(
                                room.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: hasCover
                                      ? Colors.white.withValues(alpha: 0.8)
                                      : const Color(0xFFCFC6DE),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Status pills column
                      // Status pills Ã¢â‚¬â€ wrap so 4 pills fit in 2 rows (saves ~45px vs stacked column)
                      Wrap(
                        direction: Axis.horizontal,
                        alignment: WrapAlignment.end,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          // Online members count
                          _MiniRoomStatusPill(
                            icon: Icons.people_alt_rounded,
                            label: memberCount.toString(),
                            color: const Color(0xFF4ADE80),
                          ),
                          // Seats
                          _MiniRoomStatusPill(
                            icon: Icons.event_seat_rounded,
                            label: '$activeSpeakerCount/${room.maxSeats}',
                          ),
                          // Wallet coins
                          _MiniRoomStatusPill(
                            icon: Icons.monetization_on_rounded,
                            label: walletCoins > 999
                                ? '${(walletCoins / 1000).toStringAsFixed(1)}k'
                                : walletCoins.toString(),
                            color: const Color(0xFFF0C15A),
                          ),
                          if (isHost)
                            _MiniRoomStatusPill(
                              icon: Icons.admin_panel_settings_rounded,
                              label: isArabic ? 'Ã™â€¦Ã˜Â¶Ã™Å Ã™Â' : 'Host',
                              color: const Color(0xFFF0C15A),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // \u2500\u2500 Announcement strip \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          if (announcement != null && announcement!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E0E38),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.campaign_rounded,
                      color: Color(0xFFF0C15A),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        announcement!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-screen immersive background for the live room.
/// Shows cover image (if set) with a dark readability overlay,
/// or a premium decorative gradient when no cover exists.
class _FullRoomBackground extends StatelessWidget {
  const _FullRoomBackground({required this.room, this.backgroundUrl});
  final Room room;
  final String? backgroundUrl;

  @override
  Widget build(BuildContext context) {
    // Custom uploaded background takes priority over room cover
    final imageUrl = backgroundUrl ?? room.coverUrl;
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base image or gradient
          if (imageUrl != null)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) =>
                  const _RoomGradientBg(),
            )
          else
            const _RoomGradientBg(),

          // Layered cinematic overlay ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â header dark, center reveals background,
          // bottom darker for chat/controls readability.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: imageUrl != null ? 0.78 : 0.0),
                  Colors.black.withValues(alpha: imageUrl != null ? 0.52 : 0.0),
                  Colors.black.withValues(alpha: imageUrl != null ? 0.62 : 0.0),
                  Colors.black.withValues(alpha: 0.92),
                ],
                stops: const [0.0, 0.28, 0.55, 1.0],
              ),
            ),
          ),
          // Subtle purple vignette sides
          if (imageUrl != null)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF1A0633).withValues(alpha: 0.35),
                    Colors.transparent,
                    Colors.transparent,
                    const Color(0xFF1A0633).withValues(alpha: 0.35),
                  ],
                  stops: const [0.0, 0.25, 0.75, 1.0],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rich purple/gold gradient used when no cover image is set.
class _RoomGradientBg extends StatelessWidget {
  const _RoomGradientBg();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base deep purple gradient
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.3),
              radius: 1.4,
              colors: [Color(0xFF3D1260), Color(0xFF1A0633), Color(0xFF080314)],
            ),
          ),
        ),
        // Gold glow ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â top center
        Positioned(
          top: -80,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFF0C15A).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        // Purple glow ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â bottom right
        Positioned(
          bottom: 50,
          right: -40,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF8B26D9).withValues(alpha: 0.22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Blue glow ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â bottom left
        Positioned(
          bottom: 120,
          left: -30,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF1A6FFF).withValues(alpha: 0.14),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact gradient fallback inside header cover preview.
class _RoomDefaultBg extends StatelessWidget {
  const _RoomDefaultBg();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A0E50), Color(0xFF12091D)],
        ),
      ),
    );
  }
}

class _MiniRoomStatusPill extends StatelessWidget {
  const _MiniRoomStatusPill({
    required this.icon,
    required this.label,
    this.color = const Color(0xFFF0C15A),
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF241638),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Srood Loto floating button ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬

class _LotoFloatingButton extends StatelessWidget {
  const _LotoFloatingButton({
    required this.isArabic,
    required this.onTap,
  });

  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Side-tab pill: attached flush to the screen edge with a rounded inward corner.
    final radius = isArabic
        ? const BorderRadius.only(
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(14),
            bottomLeft: Radius.circular(14),
          );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A0D6E), Color(0xFF1E0842)],
          ),
          borderRadius: radius,
          border: Border.all(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.50),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B26D9).withValues(alpha: 0.40),
              blurRadius: 14,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              color: Color(0xFFF0C15A),
              size: 16,
            ),
            const SizedBox(height: 3),
            Text(
              isArabic ? 'ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â³ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â­ÃƒÆ’Ã‹Å“Ãƒâ€šÃ‚Â¨' : 'Draw',
              style: const TextStyle(
                color: Color(0xFFF0C15A),
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveRoomStage extends StatelessWidget {
  const _LiveRoomStage({
    required this.members,
    required this.maxSeats,
    required this.isArabic,
    required this.activeSpeakerCount,
    required this.isHost,
    required this.onEmptySeatTap,
    required this.onOccupiedSeatTap,
    required this.onOccupiedSeatLongPress,
    required this.onProfileTap,
    required this.memberCount,
    required this.onParticipantsTap,
    required this.supportByUserId,
    required this.selectedMoveUserId,
    required this.speakingUserIds,
    this.activePk,
    this.showPkResult = false,
    this.pkResult,
    this.onPkFinish,
    this.onPkResultClose,
    this.seatReactions = const {},
  });

  final List<RoomMember> members;
  final int maxSeats;
  final bool isArabic;
  final int activeSpeakerCount;
  final bool isHost;
  final ValueChanged<int> onEmptySeatTap;
  final void Function(RoomMember member, int seatNumber) onOccupiedSeatTap;
  final void Function(RoomMember member, int seatNumber)
  onOccupiedSeatLongPress;
  final ValueChanged<String> onProfileTap;
  final int memberCount;
  final VoidCallback onParticipantsTap;
  final Map<String, int> supportByUserId;
  final String? selectedMoveUserId;
  final Set<String> speakingUserIds;
  final PkSession? activePk;
  final bool showPkResult;
  final PkSession? pkResult;
  final VoidCallback? onPkFinish;
  final VoidCallback? onPkResultClose;
  final Map<int, RoomReaction> seatReactions;

  @override
  Widget build(BuildContext context) {
    final seats = _buildSeats();
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          // \u2500\u2500 Header: PK banner OR normal Voice Stage row \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          if (activePk != null)
            PkBanner(
              session: activePk!,
              isArabic: isArabic,
              isHost: isHost,
              onFinish: onPkFinish ?? () {},
            )
          else
          // Stage header row (compact single line)
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              // Left: title + live dot + count + participants chip on one row
              Expanded(
                child: Row(
                  textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    Text(
                      isArabic ? 'Ã™â€¦Ã™â€ Ã˜ÂµÃ˜Â© Ã˜Â§Ã™â€žÃ˜ÂµÃ™Ë†Ã˜Âª' : 'Voice Stage',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black45),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF4ADE80),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        isArabic
                            ? '$activeSpeakerCount/$maxSeats Ã™â€ Ã˜Â´Ã˜Â·'
                            : '$activeSpeakerCount/$maxSeats',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _ParticipantsChip(
                      count: memberCount,
                      isArabic: isArabic,
                      onTap: onParticipantsTap,
                    ),
                  ],
                ),
              ),
              // Right: animated EQ icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD978), Color(0xFFD99A2B)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF0C15A).withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Color(0xFF160B26),
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ PK result banner ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
          if (showPkResult && pkResult != null) ...[
            PkResultBanner(
              session: pkResult!,
              isArabic: isArabic,
              onClose: onPkResultClose ?? () {},
            ),
            const SizedBox(height: 14),
          ],
          // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Seat grid ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
          // When PK active, a subtle red-left/blue-right background split
          // signals the team sides without breaking the seat grid layout.
          Stack(
            children: [
              if (activePk != null)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  kPkRed.withValues(alpha: 0.09),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.transparent,
                                  kPkBlue.withValues(alpha: 0.09),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              _SeatGrid(
                seats: seats,
                cols: _colsForSeatCount(seats.length),
                isArabic: isArabic,
                isHost: isHost,
                onEmptySeatTap: onEmptySeatTap,
                onOccupiedSeatTap: onOccupiedSeatTap,
                onOccupiedSeatLongPress: onOccupiedSeatLongPress,
                onProfileTap: onProfileTap,
                selectedMoveUserId: selectedMoveUserId,
                speakingUserIds: speakingUserIds,
                activePk: activePk,
                seatReactions: seatReactions,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_StageSeat> _buildSeats() {
    final safeMaxSeats = maxSeats <= 0 ? 12 : maxSeats;
    final seats = List<_StageSeat>.generate(
      safeMaxSeats,
      (index) => _StageSeat.empty(index + 1),
    );

    final stageMembers = members
        .where((member) => member.role == 'host' || member.role == 'speaker')
        .toList();

    for (final member in stageMembers) {
      final preferredSeat = member.seatNumber;

      if (preferredSeat != null &&
          preferredSeat >= 1 &&
          preferredSeat <= safeMaxSeats &&
          seats[preferredSeat - 1].isEmpty) {
        seats[preferredSeat - 1] = _StageSeat.fromMember(
          number: preferredSeat,
          member: member,
          isArabic: isArabic,
          supportAmount: supportByUserId[member.userId] ?? 0,
        );
        continue;
      }

      final emptyIndex = seats.indexWhere((seat) => seat.isEmpty);
      if (emptyIndex != -1) {
        seats[emptyIndex] = _StageSeat.fromMember(
          number: emptyIndex + 1,
          member: member,
          isArabic: isArabic,
          supportAmount: supportByUserId[member.userId] ?? 0,
        );
      }
    }

    return seats;
  }

  // 6 seats ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ 3 cols (2ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â3), 9 seats ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ 3 cols (3ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â3), 12 seats ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ 4 cols (3ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â4).
  static int _colsForSeatCount(int count) => count <= 9 ? 3 : 4;
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
// Custom seat grid ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â cols determined by seat count so every mode is balanced.
// Full rows use spaceBetween so tile edges align with container edges.
// Partial rows (e.g. 9th seat) use center so lone seats don't hug the left.
// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬

class _SeatGrid extends StatelessWidget {
  const _SeatGrid({
    required this.seats,
    required this.cols,
    required this.isArabic,
    required this.isHost,
    required this.onEmptySeatTap,
    required this.onOccupiedSeatTap,
    required this.onOccupiedSeatLongPress,
    required this.onProfileTap,
    required this.selectedMoveUserId,
    required this.speakingUserIds,
    this.activePk,
    this.seatReactions = const {},
  });

  final List<_StageSeat> seats;
  final int cols;
  final bool isArabic;
  final bool isHost;
  final ValueChanged<int> onEmptySeatTap;
  final void Function(RoomMember, int) onOccupiedSeatTap;
  final void Function(RoomMember, int) onOccupiedSeatLongPress;
  final ValueChanged<String> onProfileTap;
  final String? selectedMoveUserId;
  final Set<String> speakingUserIds;
  final PkSession? activePk;
  final Map<int, RoomReaction> seatReactions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Use a single stable aspect ratio and fixed gaps so tile positions
      // never shift regardless of content state, screen size, or animations.
      const colGap = 8.0;
      const rowGap = 6.0;
      const aspectRatio = 0.95;
      // Minimum height = sum of all fixed zones in _LiveSeatBubble so the
      // tile never clips its content on high-density small screens.
      const minBubbleHeight =
          _kAvatarAreaHeight + 2 + 11 + _micSeatSupportSlotHeight + 12; // 91 px
      final tileWidth = (constraints.maxWidth - colGap * (cols - 1)) / cols;
      final tileHeight =
          math.max(tileWidth / aspectRatio, minBubbleHeight);

      final rows = <List<_StageSeat>>[];
      for (var i = 0; i < seats.length; i += cols) {
        final end = (i + cols).clamp(0, seats.length);
        rows.add(seats.sublist(i, end));
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) const SizedBox(height: rowGap),
            _buildRow(rows[r], tileWidth, tileHeight, colGap),
          ],
        ],
      );
    });
  }

  Widget _buildRow(
    List<_StageSeat> row,
    double tileWidth,
    double tileHeight,
    double gap,
  ) {
    final isFull = row.length == cols;
    return Row(
      mainAxisAlignment:
          isFull ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
      children: [
        for (var c = 0; c < row.length; c++) ...[
          if (c > 0) SizedBox(width: gap),
          // RepaintBoundary isolates each seat's animation from its neighbours,
          // preventing speaking-wave or smiley-accent repaints from propagating
          // and causing perceived layout instability.
          RepaintBoundary(
            child: SizedBox(
              width: tileWidth,
              height: tileHeight,
              child: _LiveSeatBubble(
                seat: row[c],
                isArabic: isArabic,
                isHost: isHost,
                isSpeaking: speakingUserIds.contains(row[c].member?.userId ?? ''),
                onEmptySeatTap: onEmptySeatTap,
                onOccupiedSeatTap: onOccupiedSeatTap,
                onOccupiedSeatLongPress: onOccupiedSeatLongPress,
                onProfileTap: onProfileTap,
                selectedForMove: row[c].member?.userId == selectedMoveUserId,
                pkTeam: pkSeatTeam(
                    row[c].member?.userId ?? '', activePk),
                activeReaction: seatReactions[row[c].number],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ParticipantsChip extends StatelessWidget {
  const _ParticipantsChip({
    required this.count,
    required this.isArabic,
    required this.onTap,
  });

  final int count;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF241638).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF5A3A86)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            const Icon(
              Icons.people_alt_rounded,
              size: 14,
              color: Color(0xFFF0C15A),
            ),
            const SizedBox(width: 5),
            Text(
              count.toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF4EBD8),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomParticipantsSheet extends StatelessWidget {
  const _RoomParticipantsSheet({
    required this.members,
    required this.currentUserId,
    required this.isArabic,
    required this.refreshing,
    required this.supportByUserId,
    required this.roleBusyUserId,
    required this.roleLabel,
    required this.isHost,
    required this.onRefresh,
    required this.onProfileTap,
    required this.onPromote,
    required this.onMoveToListener,
    required this.onRemove,
  });

  final List<RoomMember> members;
  final String? currentUserId;
  final bool isArabic;
  final bool refreshing;
  final Map<String, int> supportByUserId;
  final String? roleBusyUserId;
  final String Function(String role) roleLabel;
  final bool isHost;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onProfileTap;
  final ValueChanged<RoomMember> onPromote;
  final ValueChanged<RoomMember> onMoveToListener;
  final ValueChanged<RoomMember> onRemove;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;

    return FractionallySizedBox(
      heightFactor: 0.70,
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: const BoxDecoration(
            color: Color(0xFF100718),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(
              top: BorderSide(color: Color(0xFF5A3A86), width: 1.2),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 82,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF5A3A86),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: isArabic
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          isArabic
                              ? '\u0627\u0644\u0645\u0634\u0627\u0631\u0643\u0648\u0646'
                              : 'Participants',
                          textAlign: textAlign,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isArabic
                              ? '${members.length} \u0641\u064a \u0627\u0644\u063a\u0631\u0641\u0629'
                              : '${members.length} in room',
                          textAlign: textAlign,
                          style: const TextStyle(
                            color: Color(0xFFB9A9D4),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: isArabic
                        ? '\u062a\u062d\u062f\u064a\u062b'
                        : 'Refresh',
                    onPressed: refreshing ? null : onRefresh,
                    icon: refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: members.isEmpty
                    ? Center(
                        child: Text(
                          isArabic
                              ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0645\u0634\u0627\u0631\u0643\u0648\u0646 \u0646\u0634\u0637\u0648\u0646 \u0628\u0639\u062f.'
                              : 'No active participants yet.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFD8CFEA)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: members.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final member = members[index];
                          final isSelf = member.userId == currentUserId;

                          return _CompactParticipantRow(
                            member: member,
                            isSelf: isSelf,
                            isArabic: isArabic,
                            roleLabel: roleLabel(member.role),
                            supportAmount: supportByUserId[member.userId] ?? 0,
                            isBusy: roleBusyUserId == member.userId,
                            showHostActions:
                                isHost && !isSelf && member.role != 'host',
                            onProfileTap: () => onProfileTap(member.userId),
                            onPromote: () => onPromote(member),
                            onMoveToListener: () => onMoveToListener(member),
                            onRemove: () => onRemove(member),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactParticipantRow extends StatelessWidget {
  const _CompactParticipantRow({
    required this.member,
    required this.isSelf,
    required this.isArabic,
    required this.roleLabel,
    required this.supportAmount,
    required this.isBusy,
    required this.showHostActions,
    required this.onProfileTap,
    required this.onPromote,
    required this.onMoveToListener,
    required this.onRemove,
  });

  final RoomMember member;
  final bool isSelf;
  final bool isArabic;
  final String roleLabel;
  final int supportAmount;
  final bool isBusy;
  final bool showHostActions;
  final VoidCallback onProfileTap;
  final VoidCallback onPromote;
  final VoidCallback onMoveToListener;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final vipLevel = member.effectiveVipLevel;
    final isSpeaker = member.role == 'speaker';
    final isListener = member.role == 'listener';

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onProfileTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1B102A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF3E285E)),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            _RoomAvatar(
              avatarUrl: member.avatarUrl,
              frameKey: member.selectedAvatarFrameKey,
              vipLevel: vipLevel,
              size: 42,
              selected: false,
              fallbackIcon: member.isMuted
                  ? Icons.mic_off_rounded
                  : Icons.person_rounded,
              onTap: onProfileTap,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    textDirection: isArabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      Flexible(
                        child: Text(
                          member.fallbackName(isArabic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: vipLevel > 0
                                ? VipVisualStyle.nameColor(vipLevel, context)
                                : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (isSelf) ...[
                        const SizedBox(width: 6),
                        _MiniPill(
                          label: isArabic ? '\u0623\u0646\u062a' : 'You',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        member.displayCode,
                        style: const TextStyle(
                          color: Color(0xFF9E91B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (vipLevel > 0)
                        VipBadge(vipLevel: vipLevel, compact: true),
                      if (member.role == 'host')
                        _MiniPill(
                          label: isArabic ? '\u0645\u0636\u064a\u0641' : 'Host',
                          gold: true,
                        ),
                      _MiniPill(label: roleLabel),
                      if (member.isMuted)
                        _MiniPill(
                          label: isArabic
                              ? '\u0645\u0643\u062a\u0648\u0645'
                              : 'Muted',
                        ),
                      _SupportPill(amount: supportAmount, compact: true),
                    ],
                  ),
                ],
              ),
            ),
            if (showHostActions) ...[
              const SizedBox(width: 8),
              Wrap(
                spacing: 6,
                children: [
                  if (isListener)
                    _TinyIconButton(
                      icon: Icons.record_voice_over_rounded,
                      busy: isBusy,
                      onTap: onPromote,
                    ),
                  if (isSpeaker)
                    _TinyIconButton(
                      icon: Icons.hearing_rounded,
                      busy: isBusy,
                      onTap: onMoveToListener,
                    ),
                  _TinyIconButton(
                    icon: Icons.person_remove_rounded,
                    busy: isBusy,
                    danger: true,
                    onTap: onRemove,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label, this.gold = false});

  final String label;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: gold
            ? const Color(0xFFF0C15A).withValues(alpha: 0.18)
            : const Color(0xFF2A1A3D),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: gold ? const Color(0xFFF0C15A) : const Color(0xFF5A3A86),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: gold ? const Color(0xFFF0C15A) : const Color(0xFFD8CFEA),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TinyIconButton extends StatelessWidget {
  const _TinyIconButton({
    required this.icon,
    required this.busy,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final bool busy;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF5C7A) : const Color(0xFFF0C15A);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: busy ? null : onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.72)),
        ),
        child: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(icon, size: 16, color: color),
      ),
    );
  }
}

class _StageSeat {
  const _StageSeat({
    required this.number,
    required this.name,
    required this.role,
    required this.isMuted,
    required this.isEmpty,
    required this.supportAmount,
    this.member,
  });

  factory _StageSeat.empty(int number) {
    return _StageSeat(
      number: number,
      name: '',
      role: 'empty',
      isMuted: true,
      isEmpty: true,
      supportAmount: 0,
    );
  }

  factory _StageSeat.fromMember({
    required int number,
    required RoomMember member,
    required bool isArabic,
    required int supportAmount,
  }) {
    return _StageSeat(
      number: number,
      name: member.fallbackName(isArabic),
      role: member.role,
      isMuted: member.isMuted,
      isEmpty: false,
      supportAmount: supportAmount,
      member: member,
    );
  }

  final int number;
  final String name;
  final String role;
  final bool isMuted;
  final bool isEmpty;
  final int supportAmount;
  final RoomMember? member;
}

class _EmptySeatAction {
  const _EmptySeatAction.moveSelf() : member = null, moveSelf = true;

  const _EmptySeatAction.moveMember(this.member) : moveSelf = false;

  final RoomMember? member;
  final bool moveSelf;
}

class _OccupiedSeatAction {
  const _OccupiedSeatAction.selectForMove()
    : seatNumber = null,
      selectForMove = true;

  const _OccupiedSeatAction.moveToListener()
    : seatNumber = null,
      selectForMove = false;

  const _OccupiedSeatAction.moveToSeat(this.seatNumber) : selectForMove = false;

  final int? seatNumber;
  final bool selectForMove;
}

class _LiveSeatBubble extends StatelessWidget {
  const _LiveSeatBubble({
    required this.seat,
    required this.isArabic,
    required this.isHost,
    required this.isSpeaking,
    required this.onEmptySeatTap,
    required this.onOccupiedSeatTap,
    required this.onOccupiedSeatLongPress,
    required this.onProfileTap,
    required this.selectedForMove,
    this.pkTeam,
    this.activeReaction,
  });

  final _StageSeat seat;
  final bool isArabic;
  final bool isHost;
  final bool isSpeaking;
  final ValueChanged<int> onEmptySeatTap;
  final void Function(RoomMember member, int seatNumber) onOccupiedSeatTap;
  final void Function(RoomMember member, int seatNumber)
  onOccupiedSeatLongPress;
  final ValueChanged<String> onProfileTap;
  final bool selectedForMove;
  // 'a', 'b', or null ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â non-null only when PK is active and seat is assigned.
  final String? pkTeam;
  final RoomReaction? activeReaction;

  @override
  Widget build(BuildContext context) {
    final canAssignSeat = seat.isEmpty;
    final canManageSeat = !seat.isEmpty && isHost && seat.member != null;
    final occupiedByHost = seat.role == 'host';
    final effectiveVipLevel = seat.member?.effectiveVipLevel ?? 0;

    // Size hierarchy: host > occupied > empty
    final outerSize = occupiedByHost
        ? _hostSeatOuterSize
        : seat.isEmpty
            ? _emptySeatSize
            : _seatOuterSize;
    final avatarRadius =
        (occupiedByHost ? _hostSeatAvatarSize : _seatAvatarSize) / 2;

    final label = seat.isEmpty
        ? (isArabic ? '\u0645\u0627\u064a\u0643 ${seat.number}' : 'Mic ${seat.number}')
        : seat.name;
    // Team color derived from pkTeam ('a'=red, 'b'=blue, null=no PK).
    final Color? pkColor = pkTeam == 'a'
        ? kPkRed
        : pkTeam == 'b'
            ? kPkBlue
            : null;

    // Only show badge for important states; suppress "Tap" to reduce noise.
    final badge = selectedForMove
        ? (isArabic ? '\u0646\u0642\u0644' : 'Move')
        : seat.isEmpty
            ? ''   // No badge on empty seats \u2014 seat number in circle is enough
            : occupiedByHost
                ? (isArabic ? '\u0645\u0636\u064a\u0641' : 'Host')
                : pkTeam == 'a'
                    ? 'A'
                    : pkTeam == 'b'
                        ? 'B'
                        : '';

    final Color borderColor = selectedForMove
        ? const Color(0xFF67E8A5)
        : occupiedByHost
            ? const Color(0xFFF0C15A)
            : seat.isEmpty
                ? Colors.white.withValues(alpha: 0.26)
                : pkColor != null
                    ? pkColor.withValues(alpha: 0.85)
                    : const Color(0xFF8B26D9).withValues(alpha: 0.55);

    final double borderWidth = occupiedByHost ? 2.4 : 1.8;

    final List<BoxShadow> glowShadows = [
      if (selectedForMove) ...[
        BoxShadow(
          color: const Color(0xFF67E8A5).withValues(alpha: 0.60),
          blurRadius: 28,
          spreadRadius: 3,
        ),
        BoxShadow(
          color: const Color(0xFF67E8A5).withValues(alpha: 0.25),
          blurRadius: 48,
          spreadRadius: 6,
        ),
      ] else if (occupiedByHost) ...[
        BoxShadow(
          color: const Color(0xFFF0C15A).withValues(alpha: 0.70),
          blurRadius: 18,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: const Color(0xFFD99A2B).withValues(alpha: 0.35),
          blurRadius: 34,
          spreadRadius: 4,
        ),
        BoxShadow(
          color: const Color(0xFFF0C15A).withValues(alpha: 0.15),
          blurRadius: 52,
          spreadRadius: 6,
        ),
      ] else if (!seat.isEmpty) ...[
        if (pkColor != null) ...[
          BoxShadow(
            color: pkColor.withValues(alpha: 0.55),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: pkColor.withValues(alpha: 0.25),
            blurRadius: 32,
            spreadRadius: 3,
          ),
        ] else ...[
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.45),
            blurRadius: 14,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.20),
            blurRadius: 26,
            spreadRadius: 3,
          ),
        ],
      ],
    ];

    // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Fixed-height avatar zone ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
    // All states (empty / occupied / host / VIP) use the same _kAvatarAreaHeight
    // so the grid cell measured height never changes on seat transition.
    // Stack keeps Clip.none so VIP frames render visually larger without
    // contributing to layout height.
    final Widget avatarZone = GestureDetector(
      onTap: canAssignSeat
          ? () => onEmptySeatTap(seat.number)
          : canManageSeat
              ? () => onOccupiedSeatTap(seat.member!, seat.number)
              : null,
      onLongPress: canManageSeat
          ? () => onOccupiedSeatLongPress(seat.member!, seat.number)
          : null,
      child: SizedBox(
        height: _kAvatarAreaHeight,
        child: Center(
          child: seat.isEmpty
              ? Container(
                  width: outerSize,
                  height: outerSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Glass circle ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â background shows through the empty seat.
                    color: Colors.white.withValues(alpha: 0.07),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B26D9).withValues(alpha: 0.18),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mic_none_rounded,
                        color: Colors.white.withValues(alpha: 0.48),
                        size: _micSeatIconSize,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${seat.number}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.32),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              : SizedBox(
                  width: outerSize,
                  height: outerSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // PK team pulse ring (shown behind avatar during active PK).
                      if (pkColor != null)
                        IgnorePointer(
                          child: PkPulseRing(
                            color: pkColor,
                            radius: outerSize / 2 + 4,
                          ),
                        ),
                      // 0. Dark glass backing ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â keeps avatar readable over custom
                      //    backgrounds and adds depth to the mic-seat circle.
                      IgnorePointer(
                        child: Container(
                          width: outerSize,
                          height: outerSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.42),
                                Colors.black.withValues(alpha: 0.22),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // 1. Mic-seat ring + outer glow ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â anchors the avatar to
                      //    the seat slot visually (same role as the empty-seat
                      //    circle). VIP frame suppresses the explicit border
                      //    because the frame already provides its own ring.
                      IgnorePointer(
                        child: Container(
                          width: outerSize,
                          height: outerSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: effectiveVipLevel == 0
                                ? Border.all(
                                    color: borderColor, width: borderWidth)
                                : null,
                            boxShadow: glowShadows,
                          ),
                        ),
                      ),

                      // 2. VIP mic wave ring ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â expands outward via Clip.none.
                      IgnorePointer(
                        child: VipMicWaveRing(
                          vipLevel: effectiveVipLevel,
                          isActive: !seat.isMuted && isSpeaking,
                          isHost: occupiedByHost,
                          outerSize: outerSize,
                        ),
                      ),

                      // 3. Avatar + frame (centered inside the seat ring).
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: seat.member == null
                            ? null
                            : () => onProfileTap(seat.member!.userId),
                        child: AvatarWithFrame(
                          imageUrl: seat.member?.avatarUrl,
                          radius: avatarRadius,
                          frameKey: seat.member?.selectedAvatarFrameKey,
                          vipLevel: effectiveVipLevel,
                          showVipBadge: false,
                          compact: !occupiedByHost,
                          fallbackIcon: Icons.person_rounded,
                        ),
                      ),

                      // 4. Mic status badge ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â bottom-right of avatar ring.
                      //    Red = muted, green = live. 22 px for clear tap area.
                      Positioned(
                        bottom: 1,
                        right: 1,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: seat.isMuted
                                ? const Color(0xFFE63946)
                                : const Color(0xFF22C55E),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.90),
                              width: 1.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (seat.isMuted
                                        ? const Color(0xFFE63946)
                                        : const Color(0xFF22C55E))
                                    .withValues(alpha: 0.60),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Icon(
                            seat.isMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),

                    ],
                  ),
                ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Zone 1: avatar ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â always _kAvatarAreaHeight ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
        // Zone 1 + reaction overlay
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            avatarZone,
            if (activeReaction != null && activeReaction!.isActive)
              SeatReactionOverlay(
                key: ValueKey(activeReaction!.expiresAt),
                emoji: activeReaction!.emoji,
                onExpired: () {},
              ),
          ],
        ),

        // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Zone 2: name ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â always 14 px ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
        const SizedBox(height: 2),
        SizedBox(
          height: 11,
          child: Align(
            alignment: Alignment.topCenter,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: seat.isEmpty
                    ? Colors.white.withValues(alpha: 0.38)
                    : effectiveVipLevel > 0
                        ? VipVisualStyle.nameColor(effectiveVipLevel, context)
                        : Colors.white.withValues(alpha: 0.88),
                shadows: [
                  const Shadow(
                      blurRadius: 5,
                      color: Colors.black87,
                      offset: Offset(0, 1)),
                  Shadow(
                      blurRadius: 10,
                      color: Colors.black.withValues(alpha: 0.50)),
                ],
              ),
            ),
          ),
        ),

        // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Zone 3: support pill ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â always _micSeatSupportSlotHeight ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
        // Space is always reserved; content shown only when needed.
        SizedBox(
          height: _micSeatSupportSlotHeight,
          child: seat.supportAmount > 0
              ? Center(
                  child: _SupportPill(
                      amount: seat.supportAmount, compact: true),
                )
              : null,
        ),

        // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Zone 4: role badge ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â 18 px, hidden when badge is empty ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
        SizedBox(
          height: 12,
          child: badge.isEmpty
              ? null
              : Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _micSeatBadgeHorizontalPadding,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: selectedForMove
                          ? const Color(0xFF67E8A5).withValues(alpha: 0.20)
                          : occupiedByHost
                              ? const Color(0xFFF0C15A).withValues(alpha: 0.18)
                              : pkColor != null
                                  ? pkColor.withValues(alpha: 0.22)
                                  : const Color(0xFF8B26D9).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selectedForMove
                            ? const Color(0xFF67E8A5).withValues(alpha: 0.8)
                            : occupiedByHost
                                ? const Color(0xFFF0C15A).withValues(alpha: 0.7)
                                : pkColor != null
                                    ? pkColor.withValues(alpha: 0.85)
                                    : const Color(0xFF8B26D9).withValues(alpha: 0.4),
                        width: pkColor != null ? 1.0 : 0.7,
                      ),
                    ),
                    child: Text(
                      badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: selectedForMove
                            ? const Color(0xFF67E8A5)
                            : occupiedByHost
                                ? const Color(0xFFF0C15A)
                                : pkColor ?? Colors.white.withValues(alpha: 0.75),
                        shadows: const [
                          Shadow(blurRadius: 4, color: Colors.black),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
// Seat smiley accent ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â cute floating decoration at the top-right of a seat.
// Each seat gets a different emoji and animation phase so they don't all bob
// in sync. Wrapped in IgnorePointer at the call site.
// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬

class _SeatSmileyAccent extends StatefulWidget {
  const _SeatSmileyAccent({
    required this.isHost,
    required this.vipLevel,
    required this.seatNumber,
  });

  final bool isHost;
  final int vipLevel;
  final int seatNumber;

  @override
  State<_SeatSmileyAccent> createState() => _SeatSmileyAccentState();
}

class _SeatSmileyAccentState extends State<_SeatSmileyAccent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _float;

  @override
  void initState() {
    super.initState();
    // Phase duration by seat number so seats bob at different rates.
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1700 + (widget.seatNumber % 4) * 250),
    )..repeat(reverse: true);
    _float = Tween<double>(begin: -2.5, end: 2.5)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String emoji;
    final Color glow;
    final double size;

    if (widget.isHost) {
      emoji = 'Ã¢Å“Â¨'; // sparks
      glow = const Color(0xFFF0C15A);
      size = 22;
    } else if (widget.vipLevel >= 7) {
      emoji = String.fromCharCode(0x1F4AB); // dizzy
      glow = const Color(0xFFCE93D8);
      size = 20;
    } else if (widget.vipLevel >= 4) {
      emoji = String.fromCharCode(0x1F31F); // star
      glow = const Color(0xFF9C27B0);
      size = 19;
    } else if (widget.vipLevel >= 1) {
      emoji = String.fromCharCode(0x1F338); // cherry
      glow = const Color(0xFFFF80AB);
      size = 18;
    } else {
      emoji = String.fromCharCode(0x1F60A); // smile
      glow = const Color(0xFF8B26D9);
      size = 18;
    }

    return AnimatedBuilder(
      animation: _float,
      builder: (_, _) => Transform.translate(
        offset: Offset(0, _float.value),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.30),
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: 0.50),
                blurRadius: 10,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: Text(
              emoji,
              style: TextStyle(fontSize: size * 0.55, height: 1.0),
            ),
          ),
        ),
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
// Floating chat overlay ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â translucent bubbles floating above the bottom bar.
// Shows the most recent chat messages and gift activity.
// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬

// ignore: unused_element
class _LiveChatPanel extends StatelessWidget {
  const _LiveChatPanel({
    required this.roomName,
    required this.isArabic,
    required this.gifts,
    required this.loadingGifts,
    required this.onProfileTap,
    required this.chatMessages,
  });

  final String roomName;
  final bool isArabic;
  final List<RoomGiftTransaction> gifts;
  final bool loadingGifts;
  final ValueChanged<String> onProfileTap;
  final List<RoomMessage> chatMessages;

  @override
  Widget build(BuildContext context) {
    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Directionality(
      textDirection: textDir,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label row
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0C15A).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          const Color(0xFFF0C15A).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.card_giftcard_rounded,
                        color: Color(0xFFF0C15A),
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isArabic ? '\u0627\u0644\u0647\u062f\u0627\u064a\u0627' : 'Gifts',
                        style: const TextStyle(
                          color: Color(0xFFF0C15A),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (loadingGifts) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFFF0C15A)),
                  ),
                ],
              ],
            ),
          ),
          // Chat bubble list
          if (gifts.isEmpty && !loadingGifts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  isArabic ? '\u0644\u0627 \u062a\u0648\u062c\u062f \u0647\u062f\u0627\u064a\u0627 \u0628\u0639\u062f' : 'No gifts yet',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            ...gifts.map(
              (gift) => _GiftFeedRow(
                gift: gift,
                isArabic: isArabic,
                onProfileTap: onProfileTap,
              ),
            ),
          // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Live chat comments ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
          if (chatMessages.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_rounded, color: Colors.white.withValues(alpha: 0.7), size: 13),
                        const SizedBox(width: 5),
                        Text(
                          isArabic ? '\u062f\u0631\u062f\u0634\u0629' : 'Chat',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ...chatMessages.reversed.take(6).toList().reversed.map(
              (msg) => _ChatBubbleRow(
                message: msg,
                isArabic: isArabic,
                onProfileTap: msg.isSystem
                    ? null
                    : () => onProfileTap(msg.senderId),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Live room chat bubble ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â uses VipVisualResolver from vip_prestige.dart ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬

class _ChatBubbleRow extends StatefulWidget {
  const _ChatBubbleRow({
    required this.message,
    required this.isArabic,
    this.onProfileTap,
  });

  final RoomMessage message;
  final bool isArabic;
  final VoidCallback? onProfileTap;

  @override
  State<_ChatBubbleRow> createState() => _ChatBubbleRowState();
}

class _ChatBubbleRowState extends State<_ChatBubbleRow>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    final lvl = widget.message.senderVipLevel;
    if (lvl >= 7) {
      _ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: lvl == 9 ? 1600 : 2200),
      )..repeat(reverse: true);
      _pulse = Tween<double>(begin: 0.60, end: 1.0)
          .animate(CurvedAnimation(parent: _ctrl!, curve: Curves.easeInOut));
    } else {
      _pulse = const AlwaysStoppedAnimation(1.0);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isArabic = context.isArabic;

    if (msg.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text(
              msg.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    final vipLevel = msg.senderVipLevel.clamp(0, 9);
    final prestige = VipSpecResolver.resolve(vipLevel);
    final nameColor = vipLevel > 0 ? prestige.nameColor : const Color(0xFF9BE8FF);
    final isHost = msg.senderRole == 'host';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          GestureDetector(
            onTap: widget.onProfileTap,
            child: _buildAvatar(prestige, msg, vipLevel),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (ctx, _) => _buildBubble(
                ctx, prestige, msg, nameColor, isHost, isArabic, vipLevel,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(VipSpec prestige, RoomMessage msg, int vipLevel) {
    final hasRing = prestige.avatarRingWidth > 0;
    // Compact avatar: 26px for a lighter-feeling chat overlay.
    final avatar = _RoomAvatar(
      avatarUrl: msg.senderAvatarUrl,
      frameKey: null,
      vipLevel: hasRing ? 0 : vipLevel,
      size: 26,
      selected: false,
      fallbackIcon: Icons.person_rounded,
    );
    if (!hasRing) return avatar;

    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: prestige.avatarRingColor,
                  width: prestige.avatarRingWidth,
                ),
                boxShadow: vipLevel >= 4
                    ? [
                        BoxShadow(
                          color: prestige.avatarRingColor.withValues(alpha: 0.40),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
          avatar,
        ],
      ),
    );
  }

  Widget _buildBubble(
    BuildContext context,
    VipSpec prestige,
    RoomMessage msg,
    Color nameColor,
    bool isHost,
    bool isArabic,
    int vipLevel,
  ) {
    final glowFactor = _pulse.value;
    final isRtl = isArabic;
    final crossAxis = isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final cr = prestige.cardCornerRadius;
    final tailR = vipLevel >= 3 ? cr : 4.0;

    final radius = BorderRadius.only(
      topLeft: Radius.circular(isRtl ? tailR : cr),
      topRight: Radius.circular(isRtl ? cr : tailR),
      bottomLeft: Radius.circular(cr),
      bottomRight: Radius.circular(cr),
    );

    final shadows = prestige.buildGlowShadows(pulseFactor: glowFactor);

    final isGradient = prestige.bubbleGradient[0] != prestige.bubbleGradient[1];
    final deco = isGradient
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: prestige.bubbleGradient,
            ),
            borderRadius: radius,
            border: Border.all(color: prestige.borderColor, width: prestige.borderWidth),
            boxShadow: shadows,
          )
        : BoxDecoration(
            color: prestige.surfaceTint,
            borderRadius: radius,
            border: Border.all(color: prestige.borderColor, width: prestige.borderWidth),
            boxShadow: shadows,
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: deco,
      child: Column(
        crossAxisAlignment: crossAxis,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Flexible(
                child: Text(
                  msg.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: nameColor,
                    fontSize: 11,
                    fontWeight: prestige.nameFontWeight,
                  ),
                ),
              ),
              if (isHost) ...[
                const SizedBox(width: 4),
                _buildBadge(
                  'HOST',
                  const Color(0xFFF0C15A),
                  const Color(0x30F0C15A),
                  borderColor: const Color(0xFFF0C15A).withValues(alpha: 0.40),
                ),
              ],
              if (vipLevel > 0) ...[
                const SizedBox(width: 3),
                _buildBadge(
                  'VIP $vipLevel',
                  prestige.badgeTextColor,
                  prestige.badgeGradient.first.withValues(alpha: 0.22),
                  borderColor: prestige.borderColor.withValues(alpha: 0.50),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          if (msg.isImage && msg.imageUrl != null)
            _ChatImageThumbnail(imageUrl: msg.imageUrl!)
          else
            Text(
              msg.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.25,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBadge(
    String label,
    Color textColor,
    Color bg, {
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: borderColor != null
            ? Border.all(color: borderColor, width: 0.6)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _GiftRoomBanner extends StatelessWidget {
  const _GiftRoomBanner({
    required this.gift,
    required this.isArabic,
    required this.onProfileTap,
  });

  final RoomGiftTransaction gift;
  final bool isArabic;
  final ValueChanged<String> onProfileTap;

  @override
  Widget build(BuildContext context) {
    final senderVip = gift.sender?.effectiveVipLevel ?? 0;
    final receiverVip = gift.receiver?.effectiveVipLevel ?? 0;
    final text = isArabic
        ? '${gift.senderLabel} \u062f\u0639\u0645 ${gift.receiverLabel} \u0628\u0647\u062f\u064a\u0629 ${gift.giftName}'
        : '${gift.senderLabel} supported ${gift.receiverLabel} with ${gift.giftName}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B1A45), Color(0xFF18103A), Color(0xFF0F0820)],
        ),
        border: Border.all(
          color: Color(0xFFD4A017).withValues(alpha: 0.72),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          _RoomAvatar(
            avatarUrl: gift.sender?.avatarUrl,
            frameKey: gift.sender?.selectedAvatarFrameKey,
            vipLevel: senderVip,
            size: 38,
            selected: false,
            fallbackIcon: Icons.person_rounded,
            onTap: gift.sender == null
                ? null
                : () => onProfileTap(gift.sender!.userId),
          ),
          const SizedBox(width: 8),
          _GiftMiniImage(gift: gift.giftPreview, size: 38),
          const SizedBox(width: 8),
          _RoomAvatar(
            avatarUrl: gift.receiver?.avatarUrl,
            frameKey: gift.receiver?.selectedAvatarFrameKey,
            vipLevel: receiverVip,
            size: 38,
            selected: true,
            fallbackIcon: Icons.person_rounded,
            onTap: gift.receiver == null
                ? null
                : () => onProfileTap(gift.receiver!.userId),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: senderVip > 0
                        ? VipVisualStyle.nameColor(senderVip, context)
                        : Colors.white,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (senderVip > 0 || receiverVip > 0) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (senderVip > 0)
                        VipBadge(vipLevel: senderVip, compact: true),
                      if (receiverVip > 0)
                        VipBadge(vipLevel: receiverVip, compact: true),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VipEntryRoomBanner extends StatefulWidget {
  const _VipEntryRoomBanner({required this.member, required this.isArabic});

  final RoomMember member;
  final bool isArabic;

  @override
  State<_VipEntryRoomBanner> createState() => _VipEntryRoomBannerState();
}

class _VipEntryRoomBannerState extends State<_VipEntryRoomBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _aura;

  @override
  void initState() {
    super.initState();
    final prestige = VipSpecResolver.resolve(widget.member.effectiveVipLevel);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _aura = Tween<double>(begin: 0.65, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    if (prestige.isElite) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.member.effectiveVipLevel;
    final prestige = VipSpecResolver.resolve(level);
    final isArabic = context.isArabic;

    final text = isArabic
        ? '${widget.member.fallbackName(isArabic)} \u062f\u062e\u0644 \u0627\u0644\u063a\u0631\u0641\u0629 \u0643\u0640 VIP $level'
        : '${widget.member.fallbackName(isArabic)} entered as VIP $level';

    // Tier-based border radius: more rounded for higher VIP
    final br = BorderRadius.circular(
      prestige.isElite ? 22 : prestige.entryTier.index >= VipEntryTier.glow.index ? 20 : 16,
    );

    return AnimatedBuilder(
      animation: _aura,
      builder: (ctx, child) {
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: prestige.isElite ? 12 : 10,
          ),
          decoration: BoxDecoration(
            borderRadius: br,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: prestige.bannerGradient,
            ),
            boxShadow: prestige.buildGlowShadows(pulseFactor: _aura.value),
            border: prestige.isElite
                ? Border.all(
                    color: prestige.borderColor.withValues(alpha: 0.60),
                    width: 1.4,
                  )
                : null,
          ),
          child: child,
        );
      },
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          // Avatar with VIP halo ring
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: prestige.buildGlowShadows(pulseFactor: 0.8),
            ),
            child: _RoomAvatar(
              avatarUrl: widget.member.avatarUrl,
              frameKey: widget.member.selectedAvatarFrameKey,
              vipLevel: level,
              size: prestige.isElite ? 42 : 38,
              selected: false,
              fallbackIcon: Icons.person_rounded,
            ),
          ),
          const SizedBox(width: 10),
          VipBadge(vipLevel: level, compact: true),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: prestige.entryTextColor,
                fontSize: prestige.isElite ? 13 : 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (prestige.isLegendary) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.local_fire_department_rounded,
              color: prestige.entryTextColor.withValues(alpha: 0.85),
              size: 18,
            ),
          ],
        ],
      ),
    );
  }
}

class _GiftMiniImage extends StatelessWidget {
  const _GiftMiniImage({required this.gift, required this.size});

  final RoomGift gift;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFFFD978), Color(0xFFE0A83A), Color(0xFF8B26D9)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.22),
            blurRadius: 10,
          ),
        ],
      ),
      child: Image.network(
        gift.imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            gift.materialIcon,
            color: const Color(0xFF160B26),
            size: size * 0.52,
          );
        },
      ),
    );
  }
}

class _GiftFeedRow extends StatelessWidget {
  const _GiftFeedRow({
    required this.gift,
    required this.isArabic,
    required this.onProfileTap,
  });

  final RoomGiftTransaction gift;
  final bool isArabic;
  final ValueChanged<String> onProfileTap;

  @override
  Widget build(BuildContext context) {
    final senderVip = gift.sender?.effectiveVipLevel ?? 0;
    final receiverVip = gift.receiver?.effectiveVipLevel ?? 0;
    final text = isArabic
        ? '\u0623\u0631\u0633\u0644 ${gift.senderLabel} \u0647\u062f\u064a\u0629 ${gift.giftName} \u0625\u0644\u0649 ${gift.receiverLabel}'
        : '${gift.senderLabel} sent ${gift.giftName} to ${gift.receiverLabel}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sender avatar
          GestureDetector(
            onTap: gift.sender == null
                ? null
                : () => onProfileTap(gift.sender!.userId),
            child: _RoomAvatar(
              avatarUrl: gift.sender?.avatarUrl,
              frameKey: gift.sender?.selectedAvatarFrameKey,
              vipLevel: senderVip,
              size: 32,
              selected: false,
              fallbackIcon: Icons.person_rounded,
            ),
          ),
          const SizedBox(width: 8),
          // Chat bubble
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.only(
                  topLeft: isArabic
                      ? const Radius.circular(14)
                      : const Radius.circular(4),
                  topRight: isArabic
                      ? const Radius.circular(4)
                      : const Radius.circular(14),
                  bottomLeft: const Radius.circular(14),
                  bottomRight: const Radius.circular(14),
                ),
                border: Border.all(
                  color: senderVip > 0
                      ? const Color(0xFFF0C15A).withValues(alpha: 0.30)
                      : Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                textDirection:
                    isArabic ? TextDirection.rtl : TextDirection.ltr,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Gift image
                  _GiftMiniImage(gift: gift.giftPreview, size: 26),
                  const SizedBox(width: 8),
                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: isArabic
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          textAlign: isArabic
                              ? TextAlign.right
                              : TextAlign.left,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: senderVip > 0
                                ? VipVisualStyle.nameColor(
                                    senderVip, context)
                                : Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        if (senderVip > 0 || receiverVip > 0) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 3,
                            children: [
                              if (senderVip > 0)
                                VipBadge(
                                    vipLevel: senderVip, compact: true),
                              if (receiverVip > 0)
                                VipBadge(
                                    vipLevel: receiverVip, compact: true),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftEventOverlay extends StatelessWidget {
  const _GiftEventOverlay({required this.events, required this.isArabic});

  final List<_RoomGiftEvent> events;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 74, 18, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: events
                .map(
                  (event) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GiftEventBanner(event: event, isArabic: isArabic),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _GiftEventBanner extends StatelessWidget {
  const _GiftEventBanner({required this.event, required this.isArabic});

  final _RoomGiftEvent event;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final giftName = isArabic ? event.gift.arabicName : event.gift.name;

    final qty = event.quantity > 1 ? ' \u00d7${event.quantity}' : '';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * -10),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B1A45), Color(0xFF160B26)],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Color(0xFFD4A017).withValues(alpha: 0.68),
            width: 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF0C15A).withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            _GiftArtwork(gift: event.gift, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isArabic ? '\u0647\u062f\u064a\u0629' : 'Gift sent',
                    style: const TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isArabic
                        ? '$giftName$qty \u0625\u0644\u0649 ${event.receiverName}'
                        : '$giftName$qty to ${event.receiverName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: isArabic ? TextAlign.right : TextAlign.left,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

class _GiftSendResult {
  const _GiftSendResult({
    required this.gift,
    required this.receiverUserId,
    required this.receiverName,
    required this.quantity,
  });

  final RoomGift gift;
  final String receiverUserId;
  final String receiverName;
  final int quantity;
}

class _RoomGiftEvent {
  const _RoomGiftEvent({
    required this.id,
    required this.gift,
    required this.receiverName,
    required this.quantity,
  });

  final int id;
  final RoomGift gift;
  final String receiverName;
  final int quantity;
}

class _ActiveLuxuryGiftVideo {
  const _ActiveLuxuryGiftVideo({
    required this.key,
    required this.giftName,
    required this.receiverName,
    required this.assetPath,
  });

  final Key key;
  final String giftName;
  final String receiverName;
  final String assetPath;
}

class _RedEnvelopeBanner extends StatelessWidget {
  const _RedEnvelopeBanner({
    required this.envelope,
    required this.isArabic,
    required this.loading,
    required this.isSender,
    required this.onClaim,
    required this.onDismiss,
  });

  final Map<String, dynamic> envelope;
  final bool isArabic;
  final bool loading;
  final bool isSender;
  final VoidCallback onClaim;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final total = envelope['total_coins'] as int? ?? 0;
    final count = envelope['envelope_count'] as int? ?? 1;
    final claimed = envelope['claimed_count'] as int? ?? 0;
    final remaining = count - claimed;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8B0000), Color(0xFFBF1B0B), Color(0xFF8B0000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE63946).withValues(alpha: 0.45),
              blurRadius: 20,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(alpha: 0.15),
              blurRadius: 8,
              spreadRadius: -4,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            // Glowing bag icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFFFFE066), Color(0xFFC8850A)],
                  radius: 0.7,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.55),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.card_giftcard_rounded,
                  size: 28,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Text block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.card_giftcard_rounded,
                        size: 14,
                        color: Color(0xFFFFD700),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isArabic ? 'Ø­Ù‚ÙŠØ¨Ø© Ø§Ù„Ø­Ø¸!' : 'Lucky Bag!',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isArabic
                        ? '$total | $remaining'
                        : '$total coins | $remaining left',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Sender sees a "Sent" badge; receivers see the claim button.
            if (isSender)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0A00).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  isArabic ? 'تم الإرسال' : 'Sent',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              )
            else if (loading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Color(0xFFFFD700)),
              )
            else
              GestureDetector(
                onTap: onClaim,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFE066), Color(0xFFC8850A)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFFFFD700).withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.card_giftcard_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isArabic ? 'افتح' : 'Open',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),            const SizedBox(width: 8),

            // Dismiss
            GestureDetector(
              onTap: onDismiss,
              child: Icon(
                Icons.close_rounded,
                color: Colors.white.withValues(alpha: 0.5),
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _LuxuryGiftVideoConfig {
  const _LuxuryGiftVideoConfig({required this.assetPath});

  final String assetPath;

  static _LuxuryGiftVideoConfig? fromCode(String code) {
    switch (code) {
      case 'golden_lion':
        return const _LuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/golden_lion_roar.mp4',
        );
      case 'baalbek_temple':
        return const _LuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/baalbek_temple_royal.mp4',
        );
      case 'odrob':
        return const _LuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/odrob_royal.mp4',
        );
      default:
        return null;
    }
  }
}

class _LuxuryGiftVideoOverlay extends StatefulWidget {
  const _LuxuryGiftVideoOverlay({
    required this.playback,
    required this.onDone,
    this.soundEnabled = true,
  });

  final _ActiveLuxuryGiftVideo playback;
  final VoidCallback onDone;
  final bool soundEnabled;

  @override
  State<_LuxuryGiftVideoOverlay> createState() =>
      _LuxuryGiftVideoOverlayState();
}

class _LuxuryGiftVideoOverlayState extends State<_LuxuryGiftVideoOverlay> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset(widget.playback.assetPath)
      ..setVolume(widget.soundEnabled ? 1.0 : 0.0)
      ..initialize().then((_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _ready = true;
        });

        _controller.play();
      });

    _controller.addListener(_handleVideoState);
  }

  void _handleVideoState() {
    if (!_controller.value.isInitialized) {
      return;
    }

    if (_controller.value.position >= _controller.value.duration) {
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleVideoState);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;

    // ── Safe bounds ───────────────────────────────────────────────────────────
    // The body Stack uses extendBodyBehindAppBar: true, so coordinate (0,0)
    // inside the body is the raw top-left of the screen (behind the status bar).
    // We start the stage just below the AppBar so room controls stay visible.
    final double topBound = mq.padding.top + kToolbarHeight;

    // The bottom action bar sits at Positioned(bottom: 0) and is ~80 px tall;
    // add the system nav inset so we never cover gesture-navigation handles.
    const double kBottomBarH = 88.0;
    final double bottomBound = kBottomBarH + mq.padding.bottom;

    // ── Video child ───────────────────────────────────────────────────────────
    // BoxFit.cover scales the video so its SHORTEST side fills the stage width,
    // cropping top/bottom if needed. This eliminates the black letterbox bars
    // that BoxFit.contain creates for portrait-aspect videos like Golden Lion.
    // ClipRect confines the overflow to the stage bounds.
    final Widget videoChild = _ready
        ? FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller.value.size.width,
              height: _controller.value.size.height,
              child: VideoPlayer(_controller),
            ),
          )
        : const Center(child: CircularProgressIndicator());

    // ── Info card width ───────────────────────────────────────────────────────
    // Card spans ~88 % of screen width, centred, overlaid at the bottom of the
    // stage so it costs zero video height.
    final double cardHPad = screenW * 0.06; // 6 % each side → 88 % card width

    return Positioned(
      key: widget.playback.key,
      top: topBound,
      bottom: bottomBound,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Full-stage video: cover-fills width, clips vertical overflow.
            ClipRect(child: SizedBox.expand(child: videoChild)),

            // Info card overlaid at the bottom of the stage — does NOT reduce
            // the video area since it is Positioned, not in a Column.
            Positioned(
              bottom: 14,
              left: cardHPad,
              right: cardHPad,
              child: _LuxuryGiftInfoCard(
                giftName: widget.playback.giftName,
                receiverName: widget.playback.receiverName,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LuxuryGiftInfoCard extends StatelessWidget {
  const _LuxuryGiftInfoCard({
    required this.giftName,
    required this.receiverName,
  });

  final String giftName;
  final String receiverName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2B1A45).withValues(alpha: 0.92),
            const Color(0xFF160B26).withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Color(0xFFD4A017).withValues(alpha: 0.75),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.22),
            blurRadius: 18,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            giftName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_rounded,
                color: Color(0xFFD4A017),
                size: 13,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  receiverName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.90),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GiftSheet extends StatefulWidget {
  const _GiftSheet({
    required this.isArabic,
    required this.receivers,
    required this.gifts,
    required this.roleLabel,
    this.initialReceiverUserId,
  });

  final bool isArabic;
  final List<RoomMember> receivers;
  final List<RoomGift> gifts;
  final String Function(String role) roleLabel;
  final String? initialReceiverUserId;

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  RoomMember? _selectedReceiver;
  RoomGift? _selectedGift;
  String _selectedCategoryKey = 'hot';
  int _quantity = 1;
  int _userCoinsBalance = 0;

  @override
  void initState() {
    super.initState();

    final initialReceiverUserId = widget.initialReceiverUserId;
    if (initialReceiverUserId != null) {
      for (final receiver in widget.receivers) {
        if (receiver.userId == initialReceiverUserId) {
          _selectedReceiver = receiver;
          break;
        }
      }
    }

    _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      final wallet = await const WalletService().fetchWallet();
      if (mounted) setState(() => _userCoinsBalance = wallet.coinsBalance);
    } catch (_) {
      // Balance display is best-effort; gift sending is validated server-side.
    }
  }

  void _chooseGift(RoomGift gift) {
    setState(() {
      _selectedGift = gift;
    });

    if (_selectedReceiver == null) {
      _showReceiverRequiredMessage();
      return;
    }
  }

  void _sendGift() {
    final receiver = _selectedReceiver;
    final gift = _selectedGift;

    if (receiver == null) {
      _showReceiverRequiredMessage();
      return;
    }

    if (gift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u0627\u062e\u062a\u0631 \u0647\u062f\u064a\u0629 \u0623\u0648\u0644\u0627\u064b.'
                : 'Choose a gift first.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _GiftSendResult(
        gift: gift,
        receiverUserId: receiver.userId,
        receiverName: receiver.fallbackName(context.isArabic),
        quantity: _quantity,
      ),
    );
  }

  void _showReceiverRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.isArabic
              ? '\u0627\u062e\u062a\u0631 \u0634\u062e\u0635\u0627\u064b \u0644\u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0647\u062f\u064a\u0629.'
              : 'Choose someone to receive the gift.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    final visibleGifts = widget.gifts
        .where((gift) => gift.categoryKey == _selectedCategoryKey)
        .toList();
    final gifts = visibleGifts.isEmpty ? widget.gifts : visibleGifts;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            MediaQuery.of(context).viewInsets.bottom > 0
                ? MediaQuery.of(context).viewInsets.bottom
                : 8,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF06030A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              _GiftSheetGrabber(isArabic: context.isArabic),
              const SizedBox(height: 10),
              _GiftReceiverRail(
                isArabic: context.isArabic,
                receivers: widget.receivers,
                selectedReceiver: _selectedReceiver,
                roleLabel: widget.roleLabel,
                onSelected: (receiver) {
                  setState(() {
                    _selectedReceiver = receiver;
                  });
                },
              ),
              const SizedBox(height: 12),
              _GiftCategoryTabs(
                isArabic: context.isArabic,
                selectedCategoryKey: _selectedCategoryKey,
                onSelected: (key) {
                  setState(() {
                    _selectedCategoryKey = key;
                    if (_selectedGift?.categoryKey != key) {
                      _selectedGift = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth < 320 ? 3 : 4;
                    return GridView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: gifts.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 6,
                        childAspectRatio: 0.78,
                      ),
                      itemBuilder: (context, index) {
                        final gift = gifts[index];
                        return _GiftCard(
                          gift: gift,
                          isArabic: context.isArabic,
                          selected: _selectedGift?.name == gift.name,
                          onTap: () => _chooseGift(gift),
                        );
                      },
                    );
                  },
                ),
              ),
              _GiftSendBar(
                isArabic: context.isArabic,
                quantity: _quantity,
                selectedGift: _selectedGift,
                userCoinsBalance: _userCoinsBalance,
                onQuantityTap: () {
                  setState(() {
                    _quantity = _quantity == 1 ? 10 : 1;
                  });
                },
                onSend: _sendGift,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiftSheetGrabber extends StatelessWidget {
  const _GiftSheetGrabber({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Text(
          isArabic ? '\u0627\u0644\u0647\u062f\u0627\u064a\u0627' : 'Gifts',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const Spacer(),
        Container(
          width: 54,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFF332344),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _GiftReceiverRail extends StatelessWidget {
  const _GiftReceiverRail({
    required this.isArabic,
    required this.receivers,
    required this.selectedReceiver,
    required this.roleLabel,
    required this.onSelected,
  });

  final bool isArabic;
  final List<RoomMember> receivers;
  final RoomMember? selectedReceiver;
  final String Function(String role) roleLabel;
  final ValueChanged<RoomMember> onSelected;

  @override
  Widget build(BuildContext context) {
    if (receivers.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12091D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF4A3470)),
        ),
        child: Text(
          isArabic ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0645\u0633\u062a\u0644\u0645\u0648\u0646 \u0622\u062e\u0631\u0648\u0646.' : 'No other active users.',
          textAlign: isArabic ? TextAlign.right : TextAlign.left,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFD8CFEA),
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: isArabic,
        itemCount: receivers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final receiver = receivers[index];
          final selected = selectedReceiver?.userId == receiver.userId;

          return _GiftReceiverBubble(
            receiver: receiver,
            selected: selected,
            isArabic: isArabic,
            publicUserId: receiver.displayCode,
            avatarUrl: receiver.avatarUrl,
            roleLabel: roleLabel(receiver.role),
            onTap: () => onSelected(receiver),
          );
        },
      ),
    );
  }
}

class _RoomAvatar extends StatelessWidget {
  const _RoomAvatar({
    required this.avatarUrl,
    required this.frameKey,
    required this.vipLevel,
    required this.size,
    required this.selected,
    required this.fallbackIcon,
    this.onTap,
  });

  final String? avatarUrl;
  final String? frameKey;
  final int vipLevel;
  final double size;
  final bool selected;
  final IconData fallbackIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFFF0C15A) : Colors.transparent,
          width: 2,
        ),
      ),
      child: AvatarWithFrame(
        imageUrl: avatarUrl,
        radius: (size - 4) / 2,
        frameKey: frameKey,
        vipLevel: vipLevel,
        showVipBadge: vipLevel > 0 && size >= 42,
        fallbackIcon: fallbackIcon,
      ),
    );

    if (onTap == null) {
      return avatar;
    }

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: avatar,
    );
  }
}

class _GiftReceiverBubble extends StatelessWidget {
  const _GiftReceiverBubble({
    required this.receiver,
    required this.selected,
    required this.isArabic,
    required this.publicUserId,
    required this.avatarUrl,
    required this.roleLabel,
    required this.onTap,
  });

  final RoomMember receiver;
  final bool selected;
  final bool isArabic;
  final String publicUserId;
  final String? avatarUrl;
  final String roleLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = receiver.fallbackName(isArabic);
    final vipLevel = receiver.effectiveVipLevel;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: SizedBox(
        width: 82,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoomAvatar(
              avatarUrl: avatarUrl,
              frameKey: receiver.selectedAvatarFrameKey,
              vipLevel: receiver.effectiveVipLevel,
              size: 54,
              selected: selected,
              fallbackIcon: receiver.role == 'listener'
                  ? Icons.person_rounded
                  : Icons.mic_rounded,
            ),
            const SizedBox(height: 5),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: vipLevel > 0
                    ? VipVisualStyle.nameColor(vipLevel, context)
                    : selected
                    ? Colors.white
                    : const Color(0xFFD8CFEA),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (vipLevel > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: VipBadge(vipLevel: vipLevel, compact: true),
              ),
            Text(
              publicUserId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9E91B8),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftCategoryTabs extends StatelessWidget {
  const _GiftCategoryTabs({
    required this.isArabic,
    required this.selectedCategoryKey,
    required this.onSelected,
  });

  final bool isArabic;
  final String selectedCategoryKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final categories = [
      _GiftCategoryTabData(
        key: 'event',
        label: isArabic ? '\u062d\u062f\u062b' : 'Event',
      ),
      _GiftCategoryTabData(
        key: 'hot',
        label: isArabic ? '\u0631\u0627\u0626\u062c' : 'Hot',
      ),
      _GiftCategoryTabData(
        key: 'lucky',
        label: isArabic ? '\u062d\u0638' : 'Lucky',
      ),
      const _GiftCategoryTabData(key: 'vip', label: 'VIP'),
    ];

    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: categories.map((category) {
        final selected = category.key == selectedCategoryKey;

        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelected(category.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF8C819E),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: selected ? 22 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0C15A),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _GiftCategoryTabData {
  const _GiftCategoryTabData({required this.key, required this.label});

  final String key;
  final String label;
}

class _GiftArtwork extends StatelessWidget {
  const _GiftArtwork({required this.gift, required this.size});

  final RoomGift gift;
  final double size;

  @override
  Widget build(BuildContext context) {
    final localPath = gift.localAssetPath;

    Widget imageWidget;
    if (localPath != null) {
      imageWidget = Image.asset(
        localPath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          gift.materialIcon,
          color: const Color(0xFFF0C15A),
          size: size * 0.56,
        ),
      );
    } else {
      imageWidget = Image.network(
        gift.imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          gift.materialIcon,
          color: const Color(0xFFF0C15A),
          size: size * 0.56,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const RadialGradient(
          colors: [Color(0xFF2B0B3E), Color(0xFF12091D), Color(0xFF06030A)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD10DFF).withValues(alpha: 0.20),
            blurRadius: 16,
          ),
        ],
      ),
      child: imageWidget,
    );
  }
}

class _GiftCard extends StatelessWidget {
  const _GiftCard({
    required this.gift,
    required this.isArabic,
    required this.selected,
    required this.onTap,
  });

  final RoomGift gift;
  final bool isArabic;
  final bool selected;
  final VoidCallback onTap;

  String _fmtPrice(int p) {
    if (p >= 1000000) return '${(p / 1000000).toStringAsFixed(1)}M';
    if (p >= 1000) return '${(p / 1000).toStringAsFixed(p % 1000 == 0 ? 0 : 1)}K';
    return p.toString();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 7, 5, 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF42105C) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFD10DFF) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFFD10DFF).withValues(alpha: 0.28),
                    blurRadius: 14,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final sz = (constraints.maxWidth * 0.82).clamp(32.0, 56.0);
                    return _GiftArtwork(gift: gift, size: sz);
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isArabic ? gift.arabicName : gift.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  color: Color(0xFFF0C15A),
                  size: 11,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    _fmtPrice(gift.priceCoins),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD8CFEA),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftSendBar extends StatelessWidget {
  const _GiftSendBar({
    required this.isArabic,
    required this.quantity,
    required this.selectedGift,
    required this.userCoinsBalance,
    required this.onQuantityTap,
    required this.onSend,
  });

  final bool isArabic;
  final int quantity;
  final RoomGift? selectedGift;
  final int userCoinsBalance;
  final VoidCallback onQuantityTap;
  final VoidCallback onSend;

  String _formatCoins(int c) {
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(1)}M';
    if (c >= 1000)    return '${(c / 1000).toStringAsFixed(1)}K';
    return c.toString();
  }

  @override
  Widget build(BuildContext context) {
    final total = (selectedGift?.priceCoins ?? 0) * quantity;
    final displayValue = selectedGift == null
        ? _formatCoins(userCoinsBalance)
        : _formatCoins(total);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
        decoration: BoxDecoration(
          color: const Color(0xFF06030A).withValues(alpha: 0.96),
          border: Border(
            top: BorderSide(
              color: const Color(0xFF4A3470).withValues(alpha: 0.45),
            ),
          ),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            // \u2500\u2500 coin balance \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
            const Icon(
              Icons.monetization_on_rounded,
              color: Color(0xFFF0C15A),
              size: 20,
            ),
            const SizedBox(width: 4),
            Flexible(
              flex: 3,
              child: Text(
                displayValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 3),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF8C819E),
              size: 18,
            ),
            const Spacer(),
            // \u2500\u2500 quantity toggle \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
            GestureDetector(
              onTap: onQuantityTap,
              child: Container(
                constraints: const BoxConstraints(minWidth: 64, maxWidth: 84),
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D1A20),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      quantity.toString(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF8C819E),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // \u2500\u2500 send button \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
            Flexible(
              flex: 4,
              child: SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: onSend,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB000FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(
                    isArabic ? '\u0625\u0631\u0633\u0627\u0644' : 'Send',
                    maxLines: 1,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveBottomActionBar extends StatefulWidget {
  const _LiveBottomActionBar({
    required this.isArabic,
    required this.connectingAudio,
    required this.micEnabled,
    required this.isOnMic,
    required this.leaving,
    required this.isSendingMessage,
    required this.myVipLevel,
    required this.isUploadingImage,
    required this.onToggleMic,
    required this.onLeaveRoom,
    required this.onGiftTap,
    required this.onMoreTap,
    required this.onReactionTap,
    required this.onSendMessage,
    required this.onSendImage,
    this.bottomPad = 0,
  });

  final bool isArabic;
  final bool connectingAudio;
  final bool micEnabled;
  final bool isOnMic;
  final bool leaving;
  final bool isSendingMessage;
  final int myVipLevel;
  final bool isUploadingImage;
  final VoidCallback onToggleMic;
  final VoidCallback onLeaveRoom;
  final VoidCallback onGiftTap;
  final VoidCallback onMoreTap;
  final VoidCallback onReactionTap;
  final Future<void> Function(String) onSendMessage;
  final Future<void> Function() onSendImage;
  final double bottomPad;

  @override
  State<_LiveBottomActionBar> createState() => _LiveBottomActionBarState();
}

class _LiveBottomActionBarState extends State<_LiveBottomActionBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _isTyping = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() => _isFocused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || widget.isSendingMessage) return;
    
    FocusManager.instance.primaryFocus?.unfocus();_ctrl.clear();
    setState(() => _isTyping = false);
    _focus.requestFocus();
    try {
      await widget.onSendMessage(text);
    } catch (_) {
      if (mounted) {
        _ctrl.text = text;
        _ctrl.selection = TextSelection.collapsed(offset: text.length);
        setState(() => _isTyping = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const kPurple = Color(0xFF8B26D9);
    const kGold = Color(0xFFF0C15A);
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 50;

    final borderColor = _isFocused
        ? kPurple.withValues(alpha: 0.80)
        : Colors.white.withValues(alpha: 0.12);

    final micColor = widget.isOnMic
        ? (widget.micEnabled ? kGold : const Color(0xFFE63946))
        : Colors.white.withValues(alpha: 0.35);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.48),
            Colors.black.withValues(alpha: 0.85),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: _isFocused
                ? kPurple.withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + widget.bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: composer
            Row(
              textDirection:
                  context.isArabic ? TextDirection.rtl : TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Center: expandable text pill
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isFocused
                          ? const Color(0xFF160B26).withValues(alpha: 0.90)
                          : const Color(0xFF1A0B33).withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderColor, width: 1.2),
                      boxShadow: _isFocused
                          ? [
                              BoxShadow(
                                color: kPurple.withValues(alpha: 0.22),
                                blurRadius: 14,
                                spreadRadius: 1,
                              )
                            ]
                          : const [],
                    ),
                    child: Row(
                      textDirection: context.isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 14,
                          color: kPurple.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            focusNode: _focus,
                            textDirection: context.isArabic
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.3,
                            ),
                            maxLength: 300,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            buildCounter: (context,
                                    {required currentLength,
                                    required isFocused,
                                    maxLength}) =>
                                null,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: context.isArabic
                                  ? 'ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¹ÃƒËœÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã†â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â´Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¹...'
                                  : 'Say something...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.28),
                                fontSize: 13.5,
                              ),
                            ),
                            onChanged: (v) =>
                                setState(() => _isTyping = v.trim().isNotEmpty),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                        // Image send button — locked (dimmed) below VIP7,
                        // active for VIP7+. Always visible so users know
                        // the feature exists.
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: widget.myVipLevel >= 7
                              ? (widget.isUploadingImage
                                  ? null
                                  : widget.onSendImage)
                              : widget.onSendImage,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              if (widget.isUploadingImage &&
                                  widget.myVipLevel >= 7)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: Color(0x8DFFFFFF),
                                  ),
                                )
                              else
                                Icon(
                                  Icons.image_outlined,
                                  size: 18,
                                  color: Colors.white.withValues(
                                    alpha: widget.myVipLevel >= 7 ? 0.55 : 0.22,
                                  ),
                                ),
                              if (widget.myVipLevel < 7)
                                Positioned(
                                  right: -3,
                                  bottom: -3,
                                  child: Icon(
                                    Icons.lock,
                                    size: 9,
                                    color: Colors.white.withValues(alpha: 0.45),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Right: send button (always visible, dimmed when empty)
                GestureDetector(
                  onTap: (_isTyping && !widget.isSendingMessage) ? _submit : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isTyping
                            ? [
                                const Color(0xFF9B3EE8),
                                const Color(0xFF6A1CB0),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.10),
                                Colors.white.withValues(alpha: 0.06),
                              ],
                      ),
                      border: Border.all(
                        color: _isTyping
                            ? kPurple.withValues(alpha: 0.60)
                            : Colors.white.withValues(alpha: 0.12),
                        width: 1.2,
                      ),
                      boxShadow: _isTyping
                          ? [
                              BoxShadow(
                                color: kPurple.withValues(alpha: 0.40),
                                blurRadius: 14,
                                spreadRadius: 1,
                              )
                            ]
                          : const [],
                    ),
                    child: widget.isSendingMessage
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _isTyping
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.35),
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            color: _isTyping
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.30),
                            size: 18,
                          ),
                  ),
                ),
              ],
            ),

            // Row 2: quick actions (hidden when keyboard is open)
            if (!keyboardOpen) ...[
              const SizedBox(height: 6),
              Row(
                textDirection: context.isArabic
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _QuickActionBtn(
                    icon: widget.isOnMic
                        ? (widget.micEnabled
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded)
                        : Icons.mic_none_rounded,
                    color: micColor,
                    highlighted: widget.isOnMic && widget.micEnabled,
                    busy: widget.connectingAudio,
                    onTap: widget.isOnMic && !widget.connectingAudio
                        ? widget.onToggleMic
                        : null,
                    opacity: widget.isOnMic ? 1.0 : 0.40,
                  ),
                  _QuickActionBtn(
                    icon: Icons.tune_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    onTap: widget.onMoreTap,
                  ),
                  _QuickActionBtn(
                    icon: Icons.card_giftcard_rounded,
                    color: kGold,
                    onTap: widget.onGiftTap,
                  ),
                  _QuickActionBtn(
                    icon: Icons.emoji_emotions_outlined,
                    color: Colors.white.withValues(alpha: 0.85),
                    onTap: () => widget.onReactionTap(),
                  ),
                  _QuickActionBtn(
                    icon: Icons.logout_rounded,
                    color: const Color(0xFFFF5C7A),
                    busy: widget.leaving,
                    onTap: widget.leaving ? null : widget.onLeaveRoom,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
/// Compact circular icon button for the bottom action bar.
/// Compact icon button for the quick-actions row (below composer).
class _QuickActionBtn extends StatelessWidget {
  const _QuickActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.highlighted = false,
    this.busy = false,
    this.opacity = 1.0,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool busy;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? opacity : 1.0,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: highlighted
                ? color.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.07),
            border: Border.all(
              color: highlighted
                  ? color.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.10),
              width: 1.0,
            ),
          ),
          child: busy
              ? Center(
                  child: SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: color),
                  ),
                )
              : Icon(icon, color: color, size: 17),
        ),
      ),
    );
  }
}

class _SupportPill extends StatelessWidget {
  const _SupportPill({required this.amount, required this.compact});

  final int amount;
  final bool compact;

  String get _label {
    if (amount >= 1000000) {
      final v = amount / 1000000;
      return '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      final v = amount / 1000;
      return '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)}k';
    }
    return amount.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B1A45), Color(0xFF160B26)],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Color(0xFFD4A017).withValues(alpha: 0.70),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.32),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monetization_on_rounded,
            color: const Color(0xFFFFD700),
            size: compact ? 10 : 12,
          ),
          SizedBox(width: compact ? 2 : 3),
          Text(
            _label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFFFFE566),
              fontWeight: FontWeight.w800,
              fontSize: compact ? 9 : 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
// Scrollable chat feed (replaces _FloatingChatOverlay, shows all messages)
// ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

class _RoomChatFeed extends StatefulWidget {
  const _RoomChatFeed({
    required this.chatMessages,
    required this.isArabic,
    required this.onProfileTap,
    required this.bottomPad,
  });

  final List<RoomMessage> chatMessages;
  final bool isArabic;
  final ValueChanged<String> onProfileTap;
  final double bottomPad;

  @override
  State<_RoomChatFeed> createState() => _RoomChatFeedState();
}

class _RoomChatFeedState extends State<_RoomChatFeed> {
  final ScrollController _ctrl = ScrollController();
  bool _userScrolledUp = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_ctrl.hasClients) return;
    final atBottom = _ctrl.position.maxScrollExtent - _ctrl.offset < 80;
    if (atBottom == _userScrolledUp) {
      setState(() => _userScrolledUp = !atBottom);
    }
  }

  @override
  void didUpdateWidget(_RoomChatFeed old) {
    super.didUpdateWidget(old);
    if (widget.chatMessages.length != old.chatMessages.length &&
        !_userScrolledUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ctrl.hasClients && mounted) {
          _ctrl.animateTo(
            _ctrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chatMessages.isEmpty) return const SizedBox.shrink();
    return Directionality(
      textDirection:
          context.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: ListView.builder(
        controller: _ctrl,
        padding: EdgeInsets.fromLTRB(10, 8, 10, widget.bottomPad),
        itemCount: widget.chatMessages.length,
        itemBuilder: (context, index) {
          final msg = widget.chatMessages[index];
          return _ChatBubbleRow(
            message: msg,
            isArabic: context.isArabic,
            onProfileTap:
                msg.isSystem ? null : () => widget.onProfileTap(msg.senderId),
          );
        },
      ),
    );
  }
}

// ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
// Premium vault-closing overlay
// ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

class _RoomClosingOverlay extends StatefulWidget {
  const _RoomClosingOverlay({
    super.key,
    required this.isOwnerClosing,
    required this.isArabic,
  });

  final bool isOwnerClosing;
  final bool isArabic;

  @override
  State<_RoomClosingOverlay> createState() => _RoomClosingOverlayState();
}

class _RoomClosingOverlayState extends State<_RoomClosingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _ringCtrl;
  late final AnimationController _lockScaleCtrl;
  late final AnimationController _shimmerCtrl;

  late final Animation<double> _fadeAnim;
  late final Animation<double> _lockScaleAnim;
  late final Animation<double> _shimmerAnim;

  bool _disposed = false;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _lockScaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _lockScaleAnim = CurvedAnimation(
      parent: _lockScaleCtrl,
      curve: Curves.elasticOut,
    );
    _shimmerAnim = CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut);

    _fadeCtrl.forward();
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || _disposed) return;
      if (!_lockScaleCtrl.isAnimating &&
          _lockScaleCtrl.status == AnimationStatus.dismissed) {
        _lockScaleCtrl.forward();
      }
      if (!_ringCtrl.isAnimating) _ringCtrl.repeat();
    });
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _disposed) return;
      if (!_shimmerCtrl.isAnimating) _shimmerCtrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _fadeCtrl.stop();
    _ringCtrl.stop();
    _lockScaleCtrl.stop();
    _shimmerCtrl.stop();
    _fadeCtrl.dispose();
    _ringCtrl.dispose();
    _lockScaleCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = context.isArabic;
    final isOwner = widget.isOwnerClosing;

    final titleText = isOwner
        ? (isAr ? 'ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã…Â  ÃƒËœÃ‚Â¥ÃƒËœÃ‚ÂºÃƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚ÂºÃƒËœÃ‚Â±Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â©...' : 'Closing Room...')
        : (isAr ? 'ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã…Â  Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂºÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Â© ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚ÂºÃƒËœÃ‚Â±Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â©...' : 'Leaving Room...');
    final subtitleText = isOwner
        ? (isAr ? 'Ãƒâ„¢Ã…Â ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚ÂºÃƒËœÃ‚Â±Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â©' : 'Securing the room')
        : (isAr ? 'ÃƒËœÃ‚Â¥Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â° ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¡' : 'See you around');

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        color: Colors.black.withValues(alpha: 0.88),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Vault ring + lock
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF0C15A).withValues(alpha: 0.18),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    // Rotating vault ring
                    AnimatedBuilder(
                      animation: _ringCtrl,
                      builder: (_, _) => CustomPaint(
                        size: const Size(130, 130),
                        painter: _VaultRingPainter(progress: _ringCtrl.value),
                      ),
                    ),
                    // Lock icon with scale-in + shimmer
                    ScaleTransition(
                      scale: _lockScaleAnim,
                      child: AnimatedBuilder(
                        animation: _shimmerAnim,
                        builder: (_, _) {
                          final shimmerColor = Color.lerp(
                            const Color(0xFFF0C15A),
                            const Color(0xFFFFFFAA),
                            _shimmerAnim.value,
                          )!;
                          return Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  shimmerColor.withValues(alpha: 0.22),
                                  const Color(0xFF2A0A50).withValues(alpha: 0.9),
                                ],
                              ),
                              border: Border.all(
                                color: shimmerColor.withValues(alpha: 0.50),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              isOwner
                                  ? Icons.lock_rounded
                                  : Icons.logout_rounded,
                              color: shimmerColor,
                              size: 32,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Title
              Text(
                titleText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                subtitleText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFBCAED6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),

              // Subtle loading dots
              _PulsingDots(),
            ],
          ),
        ),
      ),
    );
  }
}

// Vault ring: rotating arc segments like a combination lock.
class _VaultRingPainter extends CustomPainter {
  const _VaultRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF2A1050).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );

    // Animated arc segments
    const segmentCount = 8;
    const gapFraction = 0.08;
    final segmentSweep = (1.0 - gapFraction * segmentCount) / segmentCount;
    final goldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < segmentCount; i++) {
      final startFraction = i / segmentCount + gapFraction / 2;
      final startAngle = (startFraction + progress) * 2 * math.pi;
      final sweepAngle = segmentSweep * 2 * math.pi;

      final relPos = ((startFraction + progress) % 1.0);
      final opacity = relPos < 0.5 ? relPos * 2 : (1.0 - relPos) * 2;
      goldPaint.color = Color.lerp(
        const Color(0xFF4A2A80),
        const Color(0xFFF0C15A),
        opacity.clamp(0.15, 1.0),
      )!;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        goldPaint,
      );
    }

    // Notch markers (vault dial ticks)
    final notchPaint = Paint()
      ..color = const Color(0xFFF0C15A).withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12 + progress * 0.3) * 2 * math.pi;
      final inner = radius + 6;
      final outer = radius + 10;
      canvas.drawLine(
        Offset(center.dx + inner * math.cos(angle), center.dy + inner * math.sin(angle)),
        Offset(center.dx + outer * math.cos(angle), center.dy + outer * math.sin(angle)),
        notchPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_VaultRingPainter old) => old.progress != progress;
}

// Three pulsing dots indicating loading.
class _PulsingDots extends StatefulWidget {
  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
            final scale = 0.6 + 0.4 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8 * scale,
              height: 8 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF0C15A).withValues(alpha: 0.5 + 0.5 * scale),
              ),
            );
          }),
        );
      },
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
// Room exit action sheet
// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

enum _RoomExitAction { minimize, exit, closeRoom }

class _RoomExitSheet extends StatelessWidget {
  const _RoomExitSheet({required this.isOwner, required this.isArabic});
  final bool isOwner;
  final bool isArabic;

  String _t(String ar, String en) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF130828),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0xFF4A1A8A), width: 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20, 16, 20, MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grabber
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _t('Ã˜Â®Ã™Å Ã˜Â§Ã˜Â±Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â©', 'Room Options'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),

          // Minimize
          _ExitOption(
            icon: Icons.picture_in_picture_alt_rounded,
            iconColor: const Color(0xFF8B26D9),
            iconBg: const Color(0xFF2A0E50),
            title: _t('Ã˜ÂªÃ˜ÂµÃ˜ÂºÃ™Å Ã˜Â± Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â©', 'Minimize'),
            subtitle: _t(
              'Ã˜Â§Ã™â€žÃ˜Â¹Ã™Ë†Ã˜Â¯Ã˜Â© Ã™â€žÃ™â€žÃ˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€š Ã™â€¦Ã˜Â¹ Ã˜Â¨Ã™â€šÃ˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â© Ã™â€ Ã˜Â´Ã˜Â·Ã˜Â©',
              'Browse the app while staying in the room',
            ),
            onTap: () => Navigator.of(context).pop(_RoomExitAction.minimize),
          ),
          const SizedBox(height: 10),

          // Exit room (always available Ã¢â‚¬â€ even owner can leave without closing)
          _ExitOption(
            icon: Icons.logout_rounded,
            iconColor: const Color(0xFFFF6B6B),
            iconBg: const Color(0xFF3A1010),
            title: _t('Ã™â€¦Ã˜ÂºÃ˜Â§Ã˜Â¯Ã˜Â±Ã˜Â© Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â©', 'Exit Room'),
            subtitle: _t(
              'Ã˜Â³Ã˜ÂªÃ˜ÂºÃ˜Â§Ã˜Â¯Ã˜Â± Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â© Ã™Ë†Ã˜ÂªÃ˜Â¸Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â© Ã™â€¦Ã™ÂÃ˜ÂªÃ™Ë†Ã˜Â­Ã˜Â©',
              'Leave the room Ã¢â‚¬â€ it stays open for others',
            ),
            onTap: () => Navigator.of(context).pop(_RoomExitAction.exit),
          ),

          // Close room Ã¢â‚¬â€ owner only
          if (isOwner) ...[
            const SizedBox(height: 10),
            _ExitOption(
              icon: Icons.cancel_rounded,
              iconColor: const Color(0xFFFF3B3B),
              iconBg: const Color(0xFF3A0808),
              title: _t('Ã˜Â¥Ã˜ÂºÃ™â€žÃ˜Â§Ã™â€š Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â©', 'Close Room'),
              subtitle: _t(
                'Ã˜Â³Ã˜ÂªÃ™ÂÃ˜ÂºÃ™â€žÃ™â€š Ã˜Â§Ã™â€žÃ˜ÂºÃ˜Â±Ã™ÂÃ˜Â© Ã™â€žÃ˜Â¬Ã™â€¦Ã™Å Ã˜Â¹ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜Â§Ã˜Â±Ã™Æ’Ã™Å Ã™â€ ',
                'End the room for all participants',
              ),
              onTap: () => Navigator.of(context).pop(_RoomExitAction.closeRoom),
            ),
          ],

          const SizedBox(height: 12),

          // Cancel
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                _t('Ã˜Â¥Ã™â€žÃ˜ÂºÃ˜Â§Ã˜Â¡', 'Cancel'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExitOption extends StatelessWidget {
  const _ExitOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.25),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}


// =============================================================================
// Lucky Bag Entrance Overlay
// Shown full-screen when a Lucky Bag is sent. Auto-dismisses after ~2s.
// =============================================================================

class _LuckyBagEntranceOverlay extends StatefulWidget {
  const _LuckyBagEntranceOverlay({
    super.key,
    required this.onDone,
    required this.soundEnabled,
  });

  final VoidCallback onDone;
  final bool soundEnabled;

  @override
  State<_LuckyBagEntranceOverlay> createState() =>
      _LuckyBagEntranceOverlayState();
}

class _LuckyBagEntranceOverlayState extends State<_LuckyBagEntranceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _masterFade;
  late final Animation<double> _sparkle;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.2, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 28,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.18, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.7)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 25,
      ),
    ]).animate(_ctrl);

    _masterFade = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(
          tween: ConstantTween(1.0), weight: 55),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_ctrl);

    _sparkle = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.15, 0.85, curve: Curves.easeInOut),
    );

    _ctrl.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });

    unawaited(_tryPlaySound());
  }

  Future<void> _tryPlaySound() async {
    if (!widget.soundEnabled) return;
    debugPrint('[GIFT-AUDIO] play overlay sound without pausing music (lucky_bag_open)');
    final player = AudioPlayer(handleInterruptions: false);
    try {
      await player.setAsset('assets/sounds/lucky_bag_open.mp3');
      await player.play();
      await player.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed);
    } catch (_) {
      // TODO: add assets/sounds/lucky_bag_open.mp3 when sound assets are ready.
    } finally {
      await player.dispose();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final fade = _masterFade.value;
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6B0000).withValues(alpha: 0.85 * fade),
                    Colors.black.withValues(alpha: 0.75 * fade),
                  ],
                  radius: 1.2,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Glowing bag icon with sparkle coins around it
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer glow ring
                          Opacity(
                            opacity: _sparkle.value,
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFFD700)
                                        .withValues(alpha: 0.55),
                                    blurRadius: 60,
                                    spreadRadius: 20,
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFFE63946)
                                        .withValues(alpha: 0.3),
                                    blurRadius: 40,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Main bag icon
                          Transform.scale(
                            scale: _scale.value,
                            child: const Icon(
                              Icons.card_giftcard_rounded,
                              size: 110,
                              color: Color(0xFFFFD700),
                            ),
                          ),
                          // Orbiting coin sparkles
                          ..._buildSparkles(_sparkle.value),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Title
                    Transform.scale(
                      scale: (_scale.value).clamp(0.5, 1.0),
                      child: Column(
                        children: [
                          Text(
                            'Lucky Bag!',
                            style: TextStyle(
                              color: const Color(0xFFFFD700),
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              shadows: [
                                Shadow(
                                  color: const Color(0xFFE63946)
                                      .withValues(alpha: 0.8),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap to win coins!',
                            style: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.65),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildSparkles(double t) {
    // 8 coin icons in a circle, fading/drifting outward
    const count = 8;
    const radius = 72.0;
    return List.generate(count, (i) {
      final angle = (i / count) * 2 * math.pi;
      final drift = t * 14;
      final x = math.cos(angle) * (radius + drift);
      final y = math.sin(angle) * (radius + drift);
      final opacity = (math.sin(t * math.pi)).clamp(0.0, 1.0);
      return Positioned(
        left: 100 + x - 10,
        top:  100 + y - 10,
        child: Opacity(
          opacity: opacity,
          child: const Icon(
            Icons.monetization_on_rounded,
            size: 20,
            color: Color(0xFFFFD700),
          ),
        ),
      );
    });
  }
}

// =============================================================================
// Lucky Bag Win Overlay
// Shown when a claim succeeds. Shows coin rain + animated win text.
// =============================================================================

class _LuckyBagWinOverlay extends StatefulWidget {
  const _LuckyBagWinOverlay({
    super.key,
    required this.coins,
    required this.onDone,
    required this.soundEnabled,
  });

  final int coins;
  final VoidCallback onDone;
  final bool soundEnabled;

  @override
  State<_LuckyBagWinOverlay> createState() => _LuckyBagWinOverlayState();
}

class _LuckyBagWinOverlayState extends State<_LuckyBagWinOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _masterFade;
  late final Animation<double> _textScale;
  late final Animation<double> _textBounce;
  late final Animation<int> _countUp;

  // Pre-computed random-ish coin positions (deterministic, no dart:math Random seed needed)
  static const _coinXFractions = [
    0.05, 0.15, 0.25, 0.38, 0.50, 0.62, 0.75, 0.85, 0.92, 0.32,
  ];
  static const _coinDelayFractions = [
    0.00, 0.08, 0.04, 0.12, 0.02, 0.10, 0.06, 0.14, 0.03, 0.09,
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _masterFade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 63),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_ctrl);

    _textScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.12)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.12, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 10,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
    ]).animate(_ctrl);

    _textBounce = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 20),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -12.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -12.0, end: 0.0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
    ]).animate(_ctrl);

    _countUp = IntTween(begin: 0, end: widget.coins).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.15, 0.65, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });

    unawaited(_tryPlayWinSound());
  }

  Future<void> _tryPlayWinSound() async {
    if (!widget.soundEnabled) return;
    debugPrint('[GIFT-AUDIO] play overlay sound without pausing music (lucky_bag_win)');
    final player = AudioPlayer(handleInterruptions: false);
    try {
      await player.setAsset('assets/sounds/lucky_bag_win.wav');
      await player.play();
      await player.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed);
    } catch (_) {
      // TODO: add assets/sounds/lucky_bag_win.wav when sound assets are ready.
    } finally {
      await player.dispose();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final fade = _masterFade.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: fade,
            child: Stack(
              children: [
                // Subtle dark overlay
                Container(
                  color: Colors.black.withValues(alpha: 0.35 * fade),
                ),

                // Falling coins
                ..._buildRain(screenWidth, screenHeight),

                // Win text card in center
                Center(
                  child: Transform.translate(
                    offset: Offset(0, _textBounce.value),
                    child: Transform.scale(
                      scale: _textScale.value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 36, vertical: 24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF8B0000),
                              Color(0xFFBF1B0B),
                              Color(0xFF8B0000),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFFFFD700)
                                .withValues(alpha: 0.6),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFD700)
                                  .withValues(alpha: 0.35),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: const Color(0xFFE63946)
                                  .withValues(alpha: 0.4),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.card_giftcard_rounded,
                              size: 52,
                              color: Color(0xFFFFD700),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'You got',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.monetization_on_rounded,
                                  color: Color(0xFFFFD700),
                                  size: 32,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_countUp.value}',
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 48,
                                    fontWeight: FontWeight.w900,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'coins!',
                              style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  double _coinProgressFor(double t, double delay) {
    final end = math.min(1.0, delay + 0.55);
    if (t <= delay) return 0.0;
    if (t >= end) return 1.0;
    final x = (t - delay) / (end - delay);
    return Curves.easeIn.transform(x);
  }

  List<Widget> _buildRain(double w, double h) {
    final t = _ctrl.value;
    return List.generate(10, (i) {
      final xFrac = _coinXFractions[i];
      final delay = _coinDelayFractions[i];
      final p = _coinProgressFor(t, delay);
      final y = -30.0 + p * (h + 40);
      final opacity = p < 0.85 ? 1.0 : (1.0 - (p - 0.85) / 0.15);
      return Positioned(
        left: xFrac * w - 12,
        top: y,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: p * 2 * math.pi * (i.isEven ? 1 : -1),
            child: Icon(
              Icons.monetization_on_rounded,
              size: 22 + (i % 3) * 4.0,
              color: const Color(0xFFFFD700),
            ),
          ),
        ),
      );
    });
  }
}

// =============================================================================

// ── Chat image thumbnail + full-screen preview ────────────────────────────────

class _ChatImageThumbnail extends StatelessWidget {
  const _ChatImageThumbnail({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPreview(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl,
          width: 160,
          height: 120,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : Container(
                  width: 160,
                  height: 120,
                  color: Colors.white.withValues(alpha: 0.08),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                      color: Colors.white54,
                    ),
                  ),
                ),
          errorBuilder: (ctx, err, stack) => Container(
            width: 160,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.broken_image_rounded,
                color: Colors.white38, size: 32),
          ),
        ),
      ),
    );
  }

  void _showPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, stack) => const Icon(
                      Icons.broken_image_rounded,
                      color: Colors.white38,
                      size: 64),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
