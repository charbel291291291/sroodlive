import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../core/vip/vip_prestige.dart';
import '../../../shared/widgets/avatar_with_frame.dart';
import '../../../shared/widgets/vip_badge.dart';
import '../../../shared/widgets/vip_username.dart';
import '../../profile/widgets/room_user_profile_sheet.dart';
import '../models/room.dart';
import '../models/room_gift.dart';
import '../models/room_member.dart';
import '../services/gifts_service.dart';
import '../services/livekit_room_service.dart';
import '../services/rooms_service.dart';
import '../services/room_management_service.dart';
import '../services/room_messages_service.dart';
import '../utils/vip_room_features.dart';
import '../../vip/services/vip_privilege_service.dart';
import '../widgets/room_tools_sheet.dart';
import 'room_owner_management_screen.dart';

// Seat sizes — host > occupied > empty, never the reverse.
const double _hostSeatAvatarSize = 82.0;  // visual: 82*1.35=110.7px frame
const double _hostSeatOuterSize  = 86.0;  // layout anchor (host)
const double _seatAvatarSize     = 72.0;  // visual: 72*1.35=97.2px frame (VIP)
const double _seatOuterSize      = 76.0;  // layout anchor (normal)
const double _emptySeatSize      = 80.0;  // slightly larger than normal ring
const double _micSeatIconSize    = 26.0;
const double _micSeatBadgeHorizontalPadding = 8.0;
const double _micSeatSupportSlotHeight      = 20.0;
// Fixed height for the avatar zone inside every grid cell.
// Must be >= _hostSeatOuterSize (86) so the host avatar is never clipped.
// All seat states (empty/normal/host/VIP) use the same zone height so the
// grid cell measured height never changes when a seat transitions state.
const double _kAvatarAreaHeight = 92.0;


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

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
  final RoomsService _roomsService = const RoomsService();
  final GiftsService _giftsService = const GiftsService();
  final LiveKitRoomService _liveKitRoomService = LiveKitRoomService();

  bool _leaving = false;
  bool _connectingAudio = false;
  bool _connectedAudio = false;
  bool _syncingMicConnection = false;
  bool _wasCurrentUserOnMic = false;
  bool _micEnabled = true;
  bool _lockBusy = false;
  late bool _roomLocked;
  int _moderatorCount = 0;
  String? _roleBusyUserId;
  String? _activeAnnouncementText;

  List<RoomMember> _members = const [];
  RealtimeChannel? _membersChannel;
  RealtimeChannel? _giftTransactionsChannel;
  Timer? _heartbeatTimer;
  Timer? _membersRefreshTimer;
  Timer? _giftBannerTimer;
  Timer? _giftFeedCleanupTimer;
  Timer? _vipEntryBannerTimer;
  final List<_RoomGiftEvent> _giftEvents = [];
  final List<Timer> _giftEventTimers = [];
  final Map<String, int> _giftSupportByUserId = {};
  List<RoomGiftTransaction> _roomGifts = const [];
  RoomGiftTransaction? _latestGiftBanner;
  RoomMember? _latestVipEntryMember;
  _ActiveLuxuryGiftVideo? _activeLuxuryGiftVideo;
  Timer? _luxuryGiftVideoTimer;
  bool _loadingGifts = false;
  bool _isSendingGift = false;
  RoomMember? _selectedMicMoveMember;
  int _giftEventSeed = 0;

  // ── Room chat / comments ──────────────────────────────────────────────────
  final _msgService = const RoomMessagesService();
  final List<RoomMessage> _chatMessages = [];
  RealtimeChannel? _messagesChannel;
  bool _isSendingMessage = false;

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

  bool get _speakerSeatsFull => _activeSpeakerCount >= widget.room.maxSeats;

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

  @override
  void initState() {
    super.initState();
    _roomLocked = widget.room.isLocked;
    // _loadMembers() ends by calling _syncMicConnectionWithSeat(), which now
    // connects to the room audio for listening even when the user is not on a
    // mic seat — so every participant hears the room.
    _loadMembers();
    _loadRoomGifts();
    _loadModeratorCount();
    _loadAnnouncement();
    _startHeartbeat();
    _startMembersRefresh();
    _startGiftFeedCleanupTimer();
    _subscribeToMembers();
    _subscribeToGiftTransactions();
    _loadMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _membersRefreshTimer?.cancel();
    _giftBannerTimer?.cancel();
    _giftFeedCleanupTimer?.cancel();
    _vipEntryBannerTimer?.cancel();
    for (final timer in _giftEventTimers) {
      timer.cancel();
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

    _liveKitRoomService.disconnect();
    super.dispose();
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

    _membersRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
          callback: (_) {
            if (!mounted) return;

            unawaited(_loadMembers(showLoading: false, detectVipEntry: true));
          },
        )
        .subscribe();
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
            // waiting for the DB read — avoids the read-before-write race on
            // the receiver's phone.
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
              if (config != null && _activeLuxuryGiftVideo == null) {
                String receiverLabel = '';
                for (final m in _members) {
                  if (m.userId == receiverId) {
                    receiverLabel = m.fallbackName(widget.isArabic);
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
                  widget.isArabic
                      ? 'تعذر الاتصال بث الهدايا المباشر. قد لا تظهر الهدايا فوراً.'
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

    if (showLoading) {
      setState(() {
        _loadingGifts = true;
      });
    }

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
    } finally {
      if (mounted && showLoading) {
        setState(() {
          _loadingGifts = false;
        });
      }
    }
  }

  void _showRoomGiftBanner(RoomGiftTransaction gift) {
    _giftBannerTimer?.cancel();

    setState(() {
      _latestGiftBanner = gift;
    });

    _giftBannerTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      setState(() {
        if (_latestGiftBanner?.id == gift.id) {
          _latestGiftBanner = null;
        }
      });
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

      setState(() {
        _latestVipEntryMember = member;
      });

      _vipEntryBannerTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;

        setState(() {
          if (_latestVipEntryMember?.userId == member.userId) {
            _latestVipEntryMember = null;
          }
        });
      });
      break;
    }
  }

  Future<String?> _askForNewRoomPassword() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            widget.isArabic
                ? '\u0636\u0639 \u0643\u0644\u0645\u0629 \u0645\u0631\u0648\u0631 \u0644\u0644\u063a\u0631\u0641\u0629'
                : 'Set room password',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              hintText: widget.isArabic
                  ? '\u0623\u0642\u0644 \u0634\u064a 3 \u0623\u062d\u0631\u0641'
                  : 'Minimum 3 characters',
            ),
            onSubmitted: (_) {
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                widget.isArabic ? '\u0625\u0644\u063a\u0627\u0621' : 'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: Text(widget.isArabic ? '\u0642\u0641\u0644' : 'Lock'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null || result.trim().isEmpty) {
      return null;
    }

    return result.trim();
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

  // ── Room messages ──────────────────────────────────────────────────────────

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
    if (text.trim().isEmpty) return;
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

  void _clearChat() {
    // Clear the visible chat feed. Host-only UX action.
    setState(() {
      _roomGifts = const [];
      _chatMessages.clear();
      _chatMessages.add(RoomMessage.local(
        roomId: widget.room.id,
        message: widget.isArabic
            ? 'قام المضيف بمسح الدردشة.'
            : 'The room owner has cleaned the chat.',
      ));
    });
  }

  void _sendSalute() {
    if (_currentUserId == null) return;
    final senderName = _members
            .where((m) => m.userId == _currentUserId)
            .firstOrNull
            ?.displayName ??
        (widget.isArabic ? 'مستخدم' : 'User');
    final text = widget.isArabic
        ? '$senderName أرسل تحية للغرفة 👋'
        : '$senderName sent a salute to the room 👋';
    setState(() {
      _chatMessages.add(RoomMessage.local(
        roomId: widget.room.id,
        message: text,
      ));
    });
  }

  void _openToolsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RoomToolsSheet(
        room: widget.room,
        isArabic: widget.isArabic,
        isOwner: _iAmRoomOwner,
        isHost: _iAmHost,
        moderatorCount: _moderatorCount,
        isLocked: _roomLocked,
        onToggleLock: _toggleRoomLock,
        onClearChat: _clearChat,
        onSalute: _sendSalute,
      ),
    );
  }

  Future<void> _toggleRoomLock() async {
    if (!_iAmHost || _lockBusy) {
      return;
    }

    final nextValue = !_roomLocked;
    String? password;

    if (nextValue) {
      password = await _askForNewRoomPassword();

      if (password == null) {
        return;
      }
    }

    setState(() {
      _lockBusy = true;
    });

    try {
      await _roomsService.setRoomLocked(
        roomId: widget.room.id,
        isLocked: nextValue,
        password: password,
      );

      if (!mounted) return;

      setState(() {
        _roomLocked = nextValue;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic
                ? (nextValue
                      ? '\u062a\u0645 \u0642\u0641\u0644 \u0627\u0644\u063a\u0631\u0641\u0629 \u0628\u0643\u0644\u0645\u0629 \u0645\u0631\u0648\u0631'
                      : '\u062a\u0645 \u0641\u062a\u062d \u0627\u0644\u063a\u0631\u0641\u0629')
                : (nextValue ? 'Room locked with password' : 'Room unlocked'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      final message = error is RoomPasswordRequiredException
          ? (widget.isArabic
                ? '\u0643\u0644\u0645\u0629 \u0645\u0631\u0648\u0631 \u0627\u0644\u063a\u0631\u0641\u0629 \u0645\u0637\u0644\u0648\u0628\u0629.'
                : 'Room password is required.')
          : error.toString();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _lockBusy = false;
        });
      }
    }
  }

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
              crossAxisAlignment: widget.isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isArabic
                      ? '\u0627\u0644\u0627\u0646\u062a\u0642\u0627\u0644 \u0625\u0644\u0649 \u0645\u0627\u064a\u0643 $seatNumber'
                      : 'Move to Mic $seatNumber',
                  textAlign: widget.isArabic ? TextAlign.right : TextAlign.left,
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
                      widget.isArabic
                          ? '\u0627\u0646\u0642\u0644\u0646\u064a \u0625\u0644\u0649 \u0647\u0630\u0627 \u0627\u0644\u0645\u0627\u064a\u0643'
                          : 'Move myself here',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_iAmHost && availableMembers.isEmpty)
                  Text(
                    widget.isArabic
                        ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0623\u0639\u0636\u0627\u0621 \u0645\u062a\u0627\u062d\u0648\u0646 \u0644\u0647\u0630\u0627 \u0627\u0644\u0645\u0627\u064a\u0643.'
                        : 'No available users for this mic.',
                    textAlign: widget.isArabic
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
                        name: member.fallbackName(widget.isArabic),
                        vipLevel: member.effectiveVipLevel,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        textAlign: widget.isArabic
                            ? TextAlign.right
                            : TextAlign.left,
                      ),
                      subtitle: Text(
                        _roleLabel(member.role),
                        textAlign: widget.isArabic
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
            widget.isArabic
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
            widget.isArabic
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
            widget.isArabic
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
        final textAlign = widget.isArabic ? TextAlign.right : TextAlign.left;
        final crossAxisAlignment = widget.isArabic
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
                  member.fallbackName(widget.isArabic),
                  textAlign: textAlign,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isArabic
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
                      widget.isArabic
                          ? '\u0627\u062e\u062a\u0631\u0647 \u062b\u0645 \u0627\u0636\u063a\u0637 \u0645\u0627\u064a\u0643 \u0641\u0627\u0631\u063a'
                          : 'Select, then tap empty mic',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (emptySeats.isNotEmpty) ...[
                  Text(
                    widget.isArabic
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
                    textDirection: widget.isArabic
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
                      widget.isArabic
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
                      widget.isArabic
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
            widget.isArabic
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
          widget.isArabic
              ? '\u0627\u0636\u063a\u0637 \u0639\u0644\u0649 \u0645\u0627\u064a\u0643 \u0641\u0627\u0631\u063a \u0644\u0646\u0642\u0644 ${member.fallbackName(widget.isArabic)}.'
              : 'Tap an empty mic to move ${member.fallbackName(widget.isArabic)}.',
        ),
      ),
    );
  }

  List<int> _emptySeatNumbers({String? exceptUserId}) {
    final maxSeats = widget.room.maxSeats <= 0 ? 12 : widget.room.maxSeats;
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
              widget.isArabic
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
            widget.isArabic
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
            widget.isArabic
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
            widget.isArabic
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
            widget.isArabic
                ? 'هذا المستخدم VIP محمي من الطرد'
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
            widget.isArabic
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
    final status = await Permission.microphone.status;

    if (status.isGranted) {
      return true;
    }

    final result = await Permission.microphone.request();

    if (result.isGranted) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final permanentlyDenied = result.isPermanentlyDenied;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isArabic
              ? (permanentlyDenied
                    ? '\u062a\u0645 \u062d\u0638\u0631 \u0625\u0630\u0646 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646. \u0627\u0641\u062a\u062d \u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a \u0648\u0627\u0633\u0645\u062d \u0628\u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646.'
                    : '\u064a\u062d\u062a\u0627\u062c SrOOd Live \u0625\u0644\u0649 \u0625\u0630\u0646 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646 \u0644\u0644\u062a\u062d\u062f\u062b \u0641\u064a \u0627\u0644\u063a\u0631\u0641.')
              : (permanentlyDenied
                    ? 'Microphone permission is blocked. Open app settings and allow microphone.'
                    : 'Srood Live needs microphone permission so you can speak in rooms.'),
        ),
        action: permanentlyDenied
            ? SnackBarAction(
                label: widget.isArabic
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
    if (_syncingMicConnection || !mounted) {
      return;
    }

    final member = _myMember;
    final shouldPublishMic = _memberIsOnMic(member);
    final justTookSeat = shouldPublishMic && !_wasCurrentUserOnMic;

    _syncingMicConnection = true;
    var attemptingPublish = false;

    try {
      // Always connect so we can HEAR the room \u2014 even as a pure listener who
      // never takes a mic seat. The microphone is published separately, only
      // when the user is actually on a seat. This is what makes audio two-way:
      // previously a listener never connected at all and heard nobody.
      if (!_connectedAudio) {
        if (mounted) {
          setState(() {
            _connectingAudio = true;
          });
        }

        await _liveKitRoomService.connect(
          roomId: widget.room.id,
          microphoneEnabled: false,
        );

        if (mounted) {
          setState(() {
            _connectedAudio = true;
          });
        }

        if (kDebugMode) {
          debugPrint(
            '[Room] Audio connected (listening) room=${widget.room.id}',
          );
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

        if (justTookSeat && member?.isMuted == true) {
          await _roomsService.setMyMuteStatus(
            roomId: widget.room.id,
            isMuted: false,
          );
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

      setState(() {
        _connectedAudio = _liveKitRoomService.room != null;
        _micEnabled = false;
        _wasCurrentUserOnMic = false;
      });

      // Only surface the microphone error when we were actually trying to
      // publish \u2014 a listen-only connection issue shouldn't blame the mic.
      if (attemptingPublish) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isArabic
                  ? '\u062a\u0639\u0630\u0631 \u062a\u0634\u063a\u064a\u0644 \u0627\u0644\u0645\u0627\u064a\u0643. \u062a\u0623\u0643\u062f \u0645\u0646 \u0625\u0630\u0646 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646.'
                  : 'Could not start the microphone. Please check microphone permission.',
            ),
          ),
        );
      }
    } finally {
      _syncingMicConnection = false;

      if (mounted) {
        setState(() {
          _connectingAudio = false;
        });
      }
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

  Future<void> _leaveRoom() async {
    setState(() {
      _leaving = true;
    });

    try {
      await _liveKitRoomService.disconnect();
      await _roomsService.leaveRoom(widget.room.id);

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic
                ? '\u063a\u0627\u062f\u0631\u062a \u0627\u0644\u063a\u0631\u0641\u0629: ${widget.room.name}'
                : 'Left room: ${widget.room.name}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _leaving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'host':
        return widget.isArabic ? '\u0645\u0636\u064a\u0641' : 'Host';
      case 'speaker':
        return widget.isArabic ? '\u0645\u062a\u062d\u062f\u062b' : 'Speaker';
      default:
        return widget.isArabic ? '\u0645\u0633\u062a\u0645\u0639' : 'Listener';
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
          isArabic: widget.isArabic,
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
          // Moderation callbacks — only provided when caller can act
          onToggleMute: (canModerate && !isTargetOwner && target != null)
              ? (muted) async {
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
            widget.isArabic
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
          isArabic: widget.isArabic,
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
          ? (widget.isArabic
                ? '\u0631\u0635\u064a\u062f\u0643 \u063a\u064a\u0631 \u0643\u0627\u0641\u064d'
                : 'Not enough coins')
          : (widget.isArabic
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
          widget.isArabic
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
              isArabic: widget.isArabic,
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

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          widget.isArabic ? '\u0627\u0644\u063a\u0631\u0641\u0629' : 'Room',
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
              tooltip: widget.isArabic ? '\u0625\u062f\u0627\u0631\u0629 \u0627\u0644\u063a\u0631\u0641\u0629' : 'Manage Room',
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.35),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RoomOwnerManagementScreen(
                    room: widget.room,
                    isArabic: widget.isArabic,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // \u2500\u2500 1. Full-screen immersive background \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          _FullRoomBackground(room: widget.room),

          // \u2500\u2500 2. Scrollable content + pinned bottom bar \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          SafeArea(
            bottom: false,
            child: Stack(
              children: [
                RefreshIndicator(
                  onRefresh: () => _loadMembers(),
                  color: const Color(0xFF8B26D9),
                  backgroundColor: const Color(0xFF1A0D33),
                  child: ListView(
                    // Extra bottom padding for the pinned bar
                    padding: EdgeInsets.fromLTRB(
                        14, 0, 14, 100 + bottomPad),
                    children: [
                      _CompactRoomHeader(
                        room: widget.room,
                        activeSpeakerCount: _activeSpeakerCount,
                        isLocked: _roomLocked,
                        isHost: _iAmHost,
                        isArabic: widget.isArabic,
                        announcement: _activeAnnouncementText,
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _latestGiftBanner == null
                            ? const SizedBox.shrink()
                            : Padding(
                                key: ValueKey(_latestGiftBanner!.id),
                                padding: const EdgeInsets.only(top: 10),
                                child: _GiftRoomBanner(
                                  gift: _latestGiftBanner!,
                                  isArabic: widget.isArabic,
                                  onProfileTap: _openUserProfileSheet,
                                ),
                              ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _latestGiftBanner != null ||
                                _latestVipEntryMember == null
                            ? const SizedBox.shrink()
                            : Padding(
                                key: ValueKey(
                                    _latestVipEntryMember!.userId),
                                padding: const EdgeInsets.only(top: 10),
                                child: _VipEntryRoomBanner(
                                  member: _latestVipEntryMember!,
                                  isArabic: widget.isArabic,
                                ),
                              ),
                      ),
                      const SizedBox(height: 14),
                      _LiveRoomStage(
                        members: _members,
                        maxSeats: widget.room.maxSeats,
                        isArabic: widget.isArabic,
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
                      ),
                      const SizedBox(height: 14),
                      _LiveChatPanel(
                        roomName: widget.room.name,
                        isArabic: widget.isArabic,
                        gifts: _roomGifts,
                        loadingGifts: _loadingGifts,
                        onProfileTap: _openUserProfileSheet,
                        chatMessages: _chatMessages,
                      ),
                    ],
                  ),
                ),

                // \u2500\u2500 Pinned bottom action bar \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _LiveBottomActionBar(
                    isArabic: widget.isArabic,
                    connectingAudio: _connectingAudio,
                    micEnabled: _micEnabled,
                    isOnMic: _isCurrentUserOnMic,
                    leaving: _leaving,
                    isSendingMessage: _isSendingMessage,
                    onToggleMic: _toggleMic,
                    onLeaveRoom: _leaveRoom,
                    onGiftTap: _openGiftSheet,
                    onMoreTap: _openToolsSheet,
                    onSendMessage: _sendChatMessage,
                    bottomPad: bottomPad,
                  ),
                ),
              ],
            ),
          ),

          // \u2500\u2500 3. Gift floating event overlay \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          _GiftEventOverlay(
              events: _giftEvents, isArabic: widget.isArabic),

          // \u2500\u2500 4. Full-screen luxury gift video \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          if (_activeLuxuryGiftVideo != null)
            _LuxuryGiftVideoOverlay(
              playback: _activeLuxuryGiftVideo!,
              onDone: _clearLuxuryGiftVideo,
            ),
        ],
      ),
    );
  }
}

class _CompactRoomHeader extends StatelessWidget {
  const _CompactRoomHeader({
    required this.room,
    required this.activeSpeakerCount,
    required this.isLocked,
    required this.isHost,
    required this.isArabic,
    this.announcement,
  });

  final Room room;
  final int activeSpeakerCount;
  final bool isLocked;
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
                    child: Image.network(
                      room.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => const _RoomDefaultBg(),
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
                          Colors.black.withValues(alpha: hasCover ? 0.45 : 0.0),
                          Colors.black.withValues(alpha: hasCover ? 0.75 : 0.0),
                        ],
                      ),
                    ),
                  ),
                ),

                // Content row
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // Room icon / avatar
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0C15A).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFF0C15A)
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Icon(
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
                                fontSize: 16,
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MiniRoomStatusPill(
                            icon: Icons.event_seat_rounded,
                            label: '$activeSpeakerCount/${room.maxSeats}',
                          ),
                          const SizedBox(height: 4),
                          _MiniRoomStatusPill(
                            icon: isLocked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            label: isArabic
                                ? (isLocked ? '\u0645\u0642\u0641\u0644\u0629' : '\u0645\u0641\u062a\u0648\u062d\u0629')
                                : (isLocked ? 'Locked' : 'Open'),
                          ),
                          if (isHost) ...[
                            const SizedBox(height: 4),
                            _MiniRoomStatusPill(
                              icon: Icons.admin_panel_settings_rounded,
                              label: isArabic ? '\u0645\u0636\u064a\u0641' : 'Host',
                            ),
                          ],
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
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
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
                        maxLines: 2,
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
  const _FullRoomBackground({required this.room});
  final Room room;

  @override
  Widget build(BuildContext context) {
    final coverUrl = room.coverUrl;
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base image or gradient
          if (coverUrl != null)
            Image.network(
              coverUrl,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) =>
                  const _RoomGradientBg(),
            )
          else
            const _RoomGradientBg(),

          // Cinematic dark overlay — stronger at top (AppBar area) and bottom
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: coverUrl != null ? 0.55 : 0.0),
                  Colors.black.withValues(alpha: 0.60),
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.45, 1.0],
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
        // Gold glow — top center
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
        // Purple glow — bottom right
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
        // Blue glow — bottom left
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
  const _MiniRoomStatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

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
          Icon(icon, size: 12, color: const Color(0xFFF0C15A)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final seats = _buildSeats();
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.black.withValues(alpha: 0.30),
        border: Border.all(
          color: const Color(0xFF8B26D9).withValues(alpha: 0.30),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.10),
            blurRadius: 32,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          // Stage header row
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              // Left: title + seat count
              Expanded(
                child: Column(
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    Text(
                      isArabic ? '\u0645\u0646\u0635\u0629 \u0627\u0644\u0635\u0648\u062a' : 'Voice Stage',
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                        shadows: [
                          Shadow(blurRadius: 6, color: Colors.black45),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      textDirection: isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF4ADE80),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            isArabic
                                ? '$activeSpeakerCount/$maxSeats \u0645\u0642\u0639\u062f \u0646\u0634\u0637'
                                : '$activeSpeakerCount/$maxSeats active',
                            textAlign: textAlign,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ParticipantsChip(
                          count: memberCount,
                          isArabic: isArabic,
                          onTap: onParticipantsTap,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Right: animated EQ icon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD978), Color(0xFFD99A2B)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF0C15A).withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Color(0xFF160B26),
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Seat grid
          LayoutBuilder(
            builder: (context, constraints) {
              final compactGrid = constraints.maxWidth < 340;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 8),
                itemCount: seats.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: compactGrid ? 8 : 10,
                  crossAxisSpacing: compactGrid ? 6 : 8,
                  childAspectRatio: compactGrid ? 0.42 : 0.44,
                ),
                itemBuilder: (context, index) {
                  return _LiveSeatBubble(
                    seat: seats[index],
                    isArabic: isArabic,
                    isHost: isHost,
                    onEmptySeatTap: onEmptySeatTap,
                    onOccupiedSeatTap: onOccupiedSeatTap,
                    onOccupiedSeatLongPress: onOccupiedSeatLongPress,
                    onProfileTap: onProfileTap,
                    selectedForMove:
                        seats[index].member?.userId == selectedMoveUserId,
                  );
                },
              );
            },
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
    required this.onEmptySeatTap,
    required this.onOccupiedSeatTap,
    required this.onOccupiedSeatLongPress,
    required this.onProfileTap,
    required this.selectedForMove,
  });

  final _StageSeat seat;
  final bool isArabic;
  final bool isHost;
  final ValueChanged<int> onEmptySeatTap;
  final void Function(RoomMember member, int seatNumber) onOccupiedSeatTap;
  final void Function(RoomMember member, int seatNumber)
  onOccupiedSeatLongPress;
  final ValueChanged<String> onProfileTap;
  final bool selectedForMove;

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
    final badge = selectedForMove
        ? (isArabic ? '\u0646\u0642\u0644' : 'Move')
        : seat.isEmpty
            ? (isArabic ? '\u0627\u0636\u063a\u0637' : 'Tap')
            : occupiedByHost
                ? (isArabic ? '\u0645\u0636\u064a\u0641' : 'Host')
                : (isArabic ? '\u0645\u062a\u062d\u062f\u062b' : 'Speaker');

    final Color borderColor = selectedForMove
        ? const Color(0xFF67E8A5)
        : occupiedByHost
            ? const Color(0xFFF0C15A)
            : seat.isEmpty
                ? Colors.white.withValues(alpha: 0.18)
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
          color: const Color(0xFFF0C15A).withValues(alpha: 0.55),
          blurRadius: 16,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: const Color(0xFFD99A2B).withValues(alpha: 0.25),
          blurRadius: 28,
          spreadRadius: 2,
        ),
      ] else if (!seat.isEmpty) ...[
        BoxShadow(
          color: const Color(0xFF8B26D9).withValues(alpha: 0.35),
          blurRadius: 12,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: const Color(0xFF8B26D9).withValues(alpha: 0.15),
          blurRadius: 22,
          spreadRadius: 2,
        ),
      ],
    ];

    // ── Fixed-height avatar zone ──────────────────────────────────────────────
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
                    color: Colors.white.withValues(alpha: 0.07),
                    border: Border.all(color: borderColor, width: borderWidth),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4ADE80).withValues(alpha: 0.14),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: Colors.white.withValues(alpha: 0.55),
                    size: _micSeatIconSize,
                  ),
                )
              : SizedBox(
                  width: outerSize,
                  height: outerSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // Glow layer rendered behind the avatar.
                      // When a VIP frame is present the frame provides its own ring,
                      // so we suppress the explicit border to avoid a small inner circle.
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
                      // VIP mic wave ring — expands outward via Clip.none Stack.
                      IgnorePointer(
                        child: VipMicWaveRing(
                          vipLevel: effectiveVipLevel,
                          isActive: !seat.isMuted,
                          isHost: occupiedByHost,
                          outerSize: outerSize,
                        ),
                      ),
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
                          fallbackIcon: seat.isMuted
                              ? Icons.mic_off_rounded
                              : Icons.person_rounded,
                        ),
                      ),
                      if (seat.isMuted)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFE63946),
                              border: Border.all(
                                  color: Colors.black, width: 1.5),
                            ),
                            child: const Icon(
                              Icons.mic_off_rounded,
                              color: Colors.white,
                              size: 11,
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
        // ── Zone 1: avatar — always _kAvatarAreaHeight ────────────────────
        avatarZone,

        // ── Zone 2: name — always 16 px ───────────────────────────────────
        const SizedBox(height: 2),
        SizedBox(
          height: 16,
          child: Align(
            alignment: Alignment.topCenter,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: seat.isEmpty
                    ? Colors.white.withValues(alpha: 0.45)
                    : effectiveVipLevel > 0
                        ? VipVisualStyle.nameColor(effectiveVipLevel, context)
                        : Colors.white,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
          ),
        ),

        // ── Zone 3: support pill — always _micSeatSupportSlotHeight ───────
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

        // ── Zone 4: role badge — always 22 px ────────────────────────────
        // VIP badge removed from here; the VIP frame already provides the
        // visual cue and the badge was causing a "floating circle" artefact.
        SizedBox(
          height: 22,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: _micSeatBadgeHorizontalPadding,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: selectedForMove
                    ? const Color(0xFF67E8A5).withValues(alpha: 0.20)
                    : occupiedByHost
                        ? const Color(0xFFF0C15A).withValues(alpha: 0.18)
                        : canAssignSeat
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFF8B26D9).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selectedForMove
                      ? const Color(0xFF67E8A5).withValues(alpha: 0.8)
                      : occupiedByHost
                          ? const Color(0xFFF0C15A).withValues(alpha: 0.7)
                          : canAssignSeat
                              ? Colors.white.withValues(alpha: 0.2)
                              : const Color(0xFF8B26D9).withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: Text(
                badge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: selectedForMove
                      ? const Color(0xFF67E8A5)
                      : occupiedByHost
                          ? const Color(0xFFF0C15A)
                          : canAssignSeat
                              ? Colors.white.withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
          // ── Live chat comments ──────────────────────────────────────────
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

// ── Live room chat bubble — uses VipVisualResolver from vip_prestige.dart ────

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
    final isArabic = widget.isArabic;

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
    final prestige = VipVisualResolver.resolve(vipLevel);
    final nameColor = vipLevel > 0 ? prestige.nameColor : const Color(0xFF9BE8FF);
    final isHost = msg.senderRole == 'host';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          GestureDetector(
            onTap: widget.onProfileTap,
            child: _buildAvatar(prestige, msg, vipLevel),
          ),
          const SizedBox(width: 7),
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

  Widget _buildAvatar(VipPrestige prestige, RoomMessage msg, int vipLevel) {
    final hasRing = prestige.avatarRingWidth > 0;
    final avatar = _RoomAvatar(
      avatarUrl: msg.senderAvatarUrl,
      frameKey: null,
      vipLevel: hasRing ? 0 : vipLevel,
      size: 28,
      selected: false,
      fallbackIcon: Icons.person_rounded,
    );
    if (!hasRing) return avatar;

    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              width: 32,
              height: 32,
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
                          blurRadius: 8,
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
    VipPrestige prestige,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
          const SizedBox(height: 3),
          Text(
            msg.message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.3,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF3A174F), Color(0xFF20102F), Color(0xFF12091D)],
        ),
        border: Border.all(color: const Color(0xFFF0C15A)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
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
    final prestige = VipVisualResolver.resolve(widget.member.effectiveVipLevel);
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
    final prestige = VipVisualResolver.resolve(level);
    final isArabic = widget.isArabic;

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
              colors: prestige.gradientColors,
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

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * -18),
            child: Transform.scale(scale: 0.92 + (value * 0.08), child: child),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF2B0A3D), Color(0xFF5A127A), Color(0xFFE0A83A)],
          ),
          border: Border.all(color: const Color(0xFFFFD978)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB000FF).withValues(alpha: 0.38),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            _GiftArtwork(gift: event.gift, size: 58),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    isArabic
                        ? '\u0647\u062f\u064a\u0629 \u062c\u062f\u064a\u062f\u0629'
                        : 'Gift sent',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isArabic
                        ? '$giftName x${event.quantity} \u0625\u0644\u0649 ${event.receiverName}'
                        : '$giftName x${event.quantity} to ${event.receiverName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: isArabic ? TextAlign.right : TextAlign.left,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
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
  const _LuxuryGiftVideoOverlay({required this.playback, required this.onDone});

  final _ActiveLuxuryGiftVideo playback;
  final VoidCallback onDone;

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
      ..setVolume(1)
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
    return Positioned.fill(
      key: widget.playback.key,
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.72),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_ready)
                SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller.value.size.width,
                      height: _controller.value.size.height,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                )
              else
                const Center(child: CircularProgressIndicator()),
              Positioned(
                left: 20,
                right: 20,
                bottom: 70,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Color(0xFFFFD76A)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.playback.giftName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFD76A),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.playback.receiverName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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

  @override
  void initState() {
    super.initState();

    final initialReceiverUserId = widget.initialReceiverUserId;
    if (initialReceiverUserId == null) {
      return;
    }

    for (final receiver in widget.receivers) {
      if (receiver.userId == initialReceiverUserId) {
        _selectedReceiver = receiver;
        break;
      }
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
            widget.isArabic
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
        receiverName: receiver.fallbackName(widget.isArabic),
        quantity: _quantity,
      ),
    );
  }

  void _showReceiverRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isArabic
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
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            14,
            12,
            14,
            12 + MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF06030A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              _GiftSheetGrabber(isArabic: widget.isArabic),
              const SizedBox(height: 10),
              _GiftReceiverRail(
                isArabic: widget.isArabic,
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
                isArabic: widget.isArabic,
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
                child: GridView.builder(
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: gifts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.70,
                  ),
                  itemBuilder: (context, index) {
                    final gift = gifts[index];

                    return _GiftCard(
                      gift: gift,
                      isArabic: widget.isArabic,
                      selected: _selectedGift?.name == gift.name,
                      onTap: () => _chooseGift(gift),
                    );
                  },
                ),
              ),
              _GiftSendBar(
                isArabic: widget.isArabic,
                quantity: _quantity,
                selectedGift: _selectedGift,
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF12091D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF4A3470)),
        ),
        child: Text(
          isArabic
              ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0645\u0633\u062a\u0644\u0645\u0648\u0646 \u0622\u062e\u0631\u0648\u0646.'
              : 'No other active users.',
          textAlign: isArabic ? TextAlign.right : TextAlign.left,
          style: const TextStyle(
            color: Color(0xFFD8CFEA),
            fontWeight: FontWeight.w800,
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
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
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
      child: Image.network(
        gift.imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            gift.materialIcon,
            color: const Color(0xFFF0C15A),
            size: size * 0.56,
          );
        },
      ),
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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF42105C) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFD10DFF) : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFFD10DFF).withValues(alpha: 0.28),
                    blurRadius: 18,
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(child: _GiftArtwork(gift: gift, size: 54)),
            ),
            const SizedBox(height: 5),
            Text(
              isArabic ? gift.arabicName : gift.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  color: Color(0xFFF0C15A),
                  size: 13,
                ),
                const SizedBox(width: 3),
                Text(
                  gift.priceCoins.toString(),
                  style: const TextStyle(
                    color: Color(0xFFD8CFEA),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
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
    required this.onQuantityTap,
    required this.onSend,
  });

  final bool isArabic;
  final int quantity;
  final RoomGift? selectedGift;
  final VoidCallback onQuantityTap;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final total = (selectedGift?.priceCoins ?? 0) * quantity;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
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
          const Icon(
            Icons.monetization_on_rounded,
            color: Color(0xFFF0C15A),
            size: 22,
          ),
          const SizedBox(width: 5),
          Text(
            selectedGift == null ? '139' : total.toString(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 5),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF8C819E),
            size: 20,
          ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onQuantityTap,
            child: Container(
              width: 92,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF1D1A20),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    quantity.toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF8C819E),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 48,
            width: 132,
            child: FilledButton(
              onPressed: onSend,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB000FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Text(
                isArabic ? '\u0625\u0631\u0633\u0627\u0644' : 'Send',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
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
    required this.onToggleMic,
    required this.onLeaveRoom,
    required this.onGiftTap,
    required this.onMoreTap,
    required this.onSendMessage,
    this.bottomPad = 0,
  });

  final bool isArabic;
  final bool connectingAudio;
  final bool micEnabled;
  final bool isOnMic;
  final bool leaving;
  final bool isSendingMessage;
  final VoidCallback onToggleMic;
  final VoidCallback onLeaveRoom;
  final VoidCallback onGiftTap;
  final VoidCallback onMoreTap;
  final Future<void> Function(String) onSendMessage;
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
    _ctrl.clear();
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
    const kGold = Color(0xFFF0C15A);
    const kPurple = Color(0xFF8B26D9);
    const kBg = Color(0xFF08030F);

    final pillBorderColor = _isFocused
        ? kGold.withValues(alpha: 0.75)
        : _isTyping
            ? kGold.withValues(alpha: 0.45)
            : kPurple.withValues(alpha: 0.32);

    final pillShadows = _isFocused
        ? [
            BoxShadow(
              color: kGold.withValues(alpha: 0.18),
              blurRadius: 16,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: kPurple.withValues(alpha: 0.12),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ]
        : _isTyping
            ? [
                BoxShadow(
                  color: kGold.withValues(alpha: 0.10),
                  blurRadius: 12,
                ),
              ]
            : const <BoxShadow>[];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0A0515).withValues(alpha: 0.82),
            const Color(0xFF060210).withValues(alpha: 0.96),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: _isFocused
                ? kGold.withValues(alpha: 0.22)
                : kPurple.withValues(alpha: 0.14),
            width: 0.8,
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + widget.bottomPad),
      child: Row(
        textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _isFocused
                    ? kBg.withValues(alpha: 0.95)
                    : const Color(0xFF0E0620).withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: pillBorderColor,
                  width: _isFocused ? 1.4 : 1.0,
                ),
                boxShadow: pillShadows,
              ),
              child: Row(
                textDirection:
                    widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  if (!_isTyping && !_isFocused) ...[
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: kPurple.withValues(alpha: 0.45),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      textDirection: widget.isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.25,
                      ),
                      maxLength: 300,
                      maxLines: 1,
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
                        hintText: widget.isArabic
                            ? 'أهلاً، اكتب شيئاً...'
                            : 'Say something...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.30),
                          fontSize: 13.5,
                        ),
                      ),
                      onChanged: (v) =>
                          setState(() => _isTyping = v.trim().isNotEmpty),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: _isTyping
                        ? GestureDetector(
                            onTap: widget.isSendingMessage ? null : _submit,
                            child: Container(
                              width: 30,
                              height: 30,
                              margin: EdgeInsets.only(
                                left: widget.isArabic ? 0 : 6,
                                right: widget.isArabic ? 6 : 0,
                              ),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: widget.isSendingMessage
                                      ? [
                                          kGold.withValues(alpha: 0.35),
                                          kGold.withValues(alpha: 0.25),
                                        ]
                                      : [kGold, const Color(0xFFE0A800)],
                                ),
                                boxShadow: widget.isSendingMessage
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: kGold.withValues(alpha: 0.38),
                                          blurRadius: 10,
                                        ),
                                      ],
                              ),
                              child: widget.isSendingMessage
                                  ? const Padding(
                                      padding: EdgeInsets.all(7),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF160B26),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Color(0xFF160B26),
                                      size: 15,
                                    ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _BarIconButton(
            icon: Icons.card_giftcard_rounded,
            color: kGold,
            onTap: widget.onGiftTap,
          ),
          const SizedBox(width: 6),
          _BarIconButton(
            icon: Icons.more_horiz_rounded,
            color: Colors.white,
            onTap: widget.onMoreTap,
          ),
          if (widget.isOnMic) ...[
            const SizedBox(width: 6),
            _BarIconButton(
              icon: widget.micEnabled
                  ? Icons.mic_rounded
                  : Icons.mic_off_rounded,
              color: widget.micEnabled ? kGold : const Color(0xFFE63946),
              highlighted: true,
              busy: widget.connectingAudio,
              onTap: widget.connectingAudio ? null : widget.onToggleMic,
            ),
          ],
          const SizedBox(width: 6),
          _BarIconButton(
            icon: Icons.logout_rounded,
            color: const Color(0xFFFF5C7A),
            busy: widget.leaving,
            onTap: widget.leaving ? null : widget.onLeaveRoom,
          ),
        ],
      ),
    );
  }
}
/// Compact circular icon button for the bottom action bar.
class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.highlighted = false,
    this.busy = false,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1.0,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: highlighted
                ? color.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.09),
            border: Border.all(
              color: highlighted
                  ? color.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.15),
              width: 1.2,
            ),
          ),
          child: busy
              ? Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: color),
                  ),
                )
              : Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}


class _SupportPill extends StatelessWidget {
  const _SupportPill({required this.amount, required this.compact});

  final int amount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD978), Color(0xFFE0A83A)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.24),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monetization_on_rounded,
            color: const Color(0xFF160B26),
            size: compact ? 11 : 13,
          ),
          SizedBox(width: compact ? 2 : 3),
          Text(
            amount.toString(),
            style: TextStyle(
              color: const Color(0xFF160B26),
              fontWeight: FontWeight.w900,
              fontSize: compact ? 10 : 11,
            ),
          ),
        ],
      ),
    );
  }
}


