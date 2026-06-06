import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/avatar_with_frame.dart';
import '../../../shared/widgets/vip_badge.dart';
import '../../profile/widgets/room_user_profile_sheet.dart';
import '../models/room.dart';
import '../models/room_gift.dart';
import '../models/room_member.dart';
import '../services/gifts_service.dart';
import '../services/livekit_room_service.dart';
import '../services/rooms_service.dart';
import '../utils/vip_room_features.dart';

const double _micSeatAvatarSize = 59;
const double _micSeatOuterSize = 64;
const double _micSeatIconSize = 26;
const double _micSeatBadgeHorizontalPadding = 8;
const double _micSeatSupportSlotHeight = 20;

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
  String? _roleBusyUserId;

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
  RoomMember? _selectedMicMoveMember;
  int _giftEventSeed = 0;

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
    _loadMembers();
    _loadRoomGifts();
    _startHeartbeat();
    _startMembersRefresh();
    _startGiftFeedCleanupTimer();
    _subscribeToMembers();
    _subscribeToGiftTransactions();
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
          callback: (_) {
            if (!mounted) return;

            unawaited(
              _loadRoomGifts(showLoading: false, showNewestBanner: true),
            );
          },
        )
        .subscribe();
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
                      title: Text(
                        member.fallbackName(widget.isArabic),
                        textAlign: widget.isArabic
                            ? TextAlign.right
                            : TextAlign.left,
                        style: const TextStyle(fontWeight: FontWeight.w800),
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

  Future<void> _syncMicConnectionWithSeat() async {
    if (_syncingMicConnection || !mounted) {
      return;
    }

    final member = _myMember;
    final shouldPublishMic = _memberIsOnMic(member);
    final justTookSeat = shouldPublishMic && !_wasCurrentUserOnMic;

    _syncingMicConnection = true;

    try {
      if (shouldPublishMic) {
        final desiredMicEnabled = justTookSeat
            ? true
            : !(member?.isMuted ?? false);

        if (!_connectedAudio) {
          if (mounted) {
            setState(() {
              _connectingAudio = true;
            });
          }

          await _liveKitRoomService.connect(
            roomId: widget.room.id,
            microphoneEnabled: desiredMicEnabled,
          );
        } else {
          await _liveKitRoomService.setMicrophoneEnabled(desiredMicEnabled);
        }

        if (justTookSeat && member?.isMuted == true) {
          await _roomsService.setMyMuteStatus(
            roomId: widget.room.id,
            isMuted: false,
          );
        }

        if (!mounted) return;

        setState(() {
          _connectedAudio = true;
          _micEnabled = desiredMicEnabled;
          _wasCurrentUserOnMic = true;
        });
        return;
      }

      if (_connectedAudio) {
        await _liveKitRoomService.setMicrophoneEnabled(false);
      }

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic
                ? '\u062a\u0639\u0630\u0631 \u062a\u0634\u063a\u064a\u0644 \u0627\u0644\u0645\u0627\u064a\u0643. \u062a\u0623\u0643\u062f \u0645\u0646 \u0625\u0630\u0646 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646.'
                : 'Could not start the microphone. Please check microphone permission.',
          ),
        ),
      );
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
        );
      },
    );
  }

  Future<void> _openGiftSheet({String? targetUserId}) async {
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
      await _giftsService.sendGift(
        roomId: widget.room.id,
        receiverId: result.receiverUserId,
        gift: result.gift,
      );
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isArabic ? '\u0627\u0644\u063a\u0631\u0641\u0629' : 'Room',
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () => _loadMembers(),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _CompactRoomHeader(
                    room: widget.room,
                    activeSpeakerCount: _activeSpeakerCount,
                    isLocked: _roomLocked,
                    isHost: _iAmHost,
                    isArabic: widget.isArabic,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _latestGiftBanner == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(_latestGiftBanner!.id),
                            padding: const EdgeInsets.only(top: 12),
                            child: _GiftRoomBanner(
                              gift: _latestGiftBanner!,
                              isArabic: widget.isArabic,
                              onProfileTap: _openUserProfileSheet,
                            ),
                          ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child:
                        _latestGiftBanner != null ||
                            _latestVipEntryMember == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(_latestVipEntryMember!.userId),
                            padding: const EdgeInsets.only(top: 12),
                            child: _VipEntryRoomBanner(
                              member: _latestVipEntryMember!,
                              isArabic: widget.isArabic,
                            ),
                          ),
                  ),
                  const SizedBox(height: 18),
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
                  if (_iAmHost) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _lockBusy ? null : _toggleRoomLock,
                      icon: _lockBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _roomLocked
                                  ? Icons.lock_open_rounded
                                  : Icons.lock_rounded,
                            ),
                      label: Text(
                        widget.isArabic
                            ? (_roomLocked
                                  ? '\u0641\u062a\u062d \u0627\u0644\u063a\u0631\u0641\u0629'
                                  : '\u0642\u0641\u0644 \u0627\u0644\u063a\u0631\u0641\u0629')
                            : (_roomLocked ? 'Unlock room' : 'Lock room'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _LiveChatPanel(
                    roomName: widget.room.name,
                    isArabic: widget.isArabic,
                    gifts: _roomGifts,
                    loadingGifts: _loadingGifts,
                    onProfileTap: _openUserProfileSheet,
                  ),
                  const SizedBox(height: 18),
                  _LiveBottomActionBar(
                    isArabic: widget.isArabic,
                    connectingAudio: _connectingAudio,
                    micEnabled: _micEnabled,
                    isOnMic: _isCurrentUserOnMic,
                    leaving: _leaving,
                    onToggleMic: _toggleMic,
                    onLeaveRoom: _leaveRoom,
                    onGiftTap: _openGiftSheet,
                  ),
                ],
              ),
            ),
            _GiftEventOverlay(events: _giftEvents, isArabic: widget.isArabic),
            if (_activeLuxuryGiftVideo != null)
              _LuxuryGiftVideoOverlay(
                playback: _activeLuxuryGiftVideo!,
                onDone: _clearLuxuryGiftVideo,
              ),
          ],
        ),
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
  });

  final Room room;
  final int activeSpeakerCount;
  final bool isLocked;
  final bool isHost;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF0C15A).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.mic_rounded,
              color: Color(0xFFF0C15A),
              size: 21,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: crossAxisAlignment,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  room.name,
                  textAlign: textAlign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  room.description?.isNotEmpty == true
                      ? room.description!
                      : (isArabic
                            ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0648\u0635\u0641'
                            : 'No description'),
                  textAlign: textAlign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFCFC6DE),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _MiniRoomStatusPill(
            icon: Icons.event_seat_rounded,
            label: '$activeSpeakerCount/${room.maxSeats}',
          ),
          const SizedBox(width: 6),
          _MiniRoomStatusPill(
            icon: isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            label: isArabic
                ? (isLocked
                      ? '\u0645\u0642\u0641\u0644\u0629'
                      : '\u0645\u0641\u062a\u0648\u062d\u0629')
                : (isLocked ? 'Locked' : 'Open'),
          ),
          if (isHost) ...[
            const SizedBox(width: 6),
            _MiniRoomStatusPill(
              icon: Icons.admin_panel_settings_rounded,
              label: isArabic ? '\u0645\u0636\u064a\u0641' : 'Host',
            ),
          ],
        ],
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D1247), Color(0xFF170B27), Color(0xFF0C0614)],
        ),
        border: Border.all(color: Color(0xFF6F4A9B)),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF8B26D9).withValues(alpha: 0.18),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    Text(
                      isArabic
                          ? '\u0645\u0646\u0635\u0629 \u0627\u0644\u0635\u0648\u062a'
                          : 'Voice Stage',
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      textDirection: isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      children: [
                        Flexible(
                          child: Text(
                            isArabic
                                ? '$activeSpeakerCount/$maxSeats \u0645\u0642\u0627\u0639\u062f \u0646\u0634\u0637\u0629'
                                : '$activeSpeakerCount/$maxSeats active seats',
                            textAlign: textAlign,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFD8CFEA),
                              fontWeight: FontWeight.w700,
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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD978), Color(0xFFD99A2B)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFF0C15A).withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Color(0xFF160B26),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final compactGrid = constraints.maxWidth < 360;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: seats.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: compactGrid ? 14 : 18,
                  crossAxisSpacing: compactGrid ? 8 : 10,
                  childAspectRatio: compactGrid ? 0.50 : 0.52,
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
    final label = seat.isEmpty
        ? (isArabic
              ? '\u0645\u0627\u064a\u0643 ${seat.number}'
              : 'Mic ${seat.number}')
        : seat.name;
    final badge = selectedForMove
        ? (isArabic ? '\u0646\u0642\u0644' : 'Move')
        : seat.isEmpty
        ? (isArabic ? '\u0627\u0636\u063a\u0637' : 'Tap')
        : occupiedByHost
        ? (isArabic ? '\u0645\u0636\u064a\u0641' : 'Host')
        : (isArabic ? '\u0645\u062a\u062d\u062f\u062b' : 'Speaker');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: canAssignSeat
              ? () => onEmptySeatTap(seat.number)
              : canManageSeat
              ? () => onOccupiedSeatTap(seat.member!, seat.number)
              : null,
          onLongPress: canManageSeat
              ? () => onOccupiedSeatLongPress(seat.member!, seat.number)
              : null,
          child: Container(
            width: _micSeatOuterSize,
            height: _micSeatOuterSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: seat.isEmpty
                  ? const LinearGradient(
                      colors: [Color(0xFF241638), Color(0xFF130A20)],
                    )
                  : null,
              border: Border.all(
                color: selectedForMove
                    ? const Color(0xFF67E8A5)
                    : seat.isEmpty
                    ? const Color(0xFF5A3A86)
                    : Colors.transparent,
                width: selectedForMove ? 2.4 : 0,
              ),
              boxShadow: selectedForMove
                  ? [
                      BoxShadow(
                        color: const Color(0xFF67E8A5).withValues(alpha: 0.42),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : seat.isEmpty
                  ? []
                  : [],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (seat.isEmpty)
                  const Icon(
                    Icons.add_rounded,
                    color: Color(0xFFD8CFEA),
                    size: _micSeatIconSize,
                  )
                else
                  Center(
                    child: SizedBox(
                      width: _micSeatOuterSize,
                      height: _micSeatOuterSize,
                      child: Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: seat.member == null
                              ? null
                              : () => onProfileTap(seat.member!.userId),
                          child: AvatarWithFrame(
                            imageUrl: seat.member?.avatarUrl,
                            radius: _micSeatAvatarSize / 2,
                            frameKey: seat.member?.selectedAvatarFrameKey,
                            vipLevel: effectiveVipLevel,
                            showVipBadge: effectiveVipLevel > 0,
                            compact: true,
                            fallbackIcon: seat.isMuted
                                ? Icons.mic_off_rounded
                                : Icons.person_rounded,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!seat.isEmpty && seat.isMuted)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.32),
                    ),
                    child: const Icon(
                      Icons.mic_off_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: seat.isEmpty
                ? const Color(0xFF9E91B8)
                : effectiveVipLevel > 0
                ? VipVisualStyle.nameColor(effectiveVipLevel, context)
                : Colors.white,
          ),
        ),
        if (seat.supportAmount > 0) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: _micSeatSupportSlotHeight,
            child: Center(
              child: _SupportPill(amount: seat.supportAmount, compact: true),
            ),
          ),
        ],
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: _micSeatBadgeHorizontalPadding,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: canAssignSeat || occupiedByHost
                ? const Color(0xFFF0C15A).withValues(alpha: 0.18)
                : selectedForMove
                ? const Color(0xFF67E8A5).withValues(alpha: 0.18)
                : const Color(0xFF241638),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selectedForMove
                  ? const Color(0xFF67E8A5)
                  : occupiedByHost
                  ? const Color(0xFFF0C15A)
                  : const Color(0xFF5A3A86),
            ),
          ),
          child: Text(
            badge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: selectedForMove
                  ? const Color(0xFF67E8A5)
                  : occupiedByHost
                  ? const Color(0xFFF0C15A)
                  : const Color(0xFFD8CFEA),
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
  });

  final String roomName;
  final bool isArabic;
  final List<RoomGiftTransaction> gifts;
  final bool loadingGifts;
  final ValueChanged<String> onProfileTap;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final textDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: textDirection,
            children: [
              const Icon(
                Icons.card_giftcard_rounded,
                color: Color(0xFFF0C15A),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isArabic
                      ? '\u0627\u0644\u0647\u062f\u0627\u064a\u0627'
                      : 'Gifts',
                  textAlign: textAlign,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              if (loadingGifts)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (gifts.isEmpty && !loadingGifts)
            Text(
              isArabic
                  ? '\u0644\u0627 \u062a\u0648\u062c\u062f \u0647\u062f\u0627\u064a\u0627 \u0628\u0639\u062f'
                  : 'No gifts yet',
              textAlign: textAlign,
              style: const TextStyle(
                color: Color(0xFFD8CFEA),
                fontWeight: FontWeight.w800,
                fontSize: 13,
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
        ],
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

class _VipEntryRoomBanner extends StatelessWidget {
  const _VipEntryRoomBanner({required this.member, required this.isArabic});

  final RoomMember member;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final level = member.effectiveVipLevel;
    final text = isArabic
        ? '${member.fallbackName(isArabic)} \u062f\u062e\u0644 \u0627\u0644\u063a\u0631\u0641\u0629 \u0643\u0640 VIP $level'
        : '${member.fallbackName(isArabic)} entered as VIP $level';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: VipVisualStyle.gradient(level)),
        boxShadow: VipVisualStyle.glow(level),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          _RoomAvatar(
            avatarUrl: member.avatarUrl,
            frameKey: member.selectedAvatarFrameKey,
            vipLevel: level,
            size: 38,
            selected: false,
            fallbackIcon: Icons.person_rounded,
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
              style: const TextStyle(
                color: Color(0xFF160B26),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
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
        children: [
          _RoomAvatar(
            avatarUrl: gift.sender?.avatarUrl,
            frameKey: gift.sender?.selectedAvatarFrameKey,
            vipLevel: senderVip,
            size: 28,
            selected: false,
            fallbackIcon: Icons.person_rounded,
            onTap: gift.sender == null
                ? null
                : () => onProfileTap(gift.sender!.userId),
          ),
          const SizedBox(width: 6),
          _GiftMiniImage(gift: gift.giftPreview, size: 28),
          const SizedBox(width: 6),
          _RoomAvatar(
            avatarUrl: gift.receiver?.avatarUrl,
            frameKey: gift.receiver?.selectedAvatarFrameKey,
            vipLevel: receiverVip,
            size: 28,
            selected: false,
            fallbackIcon: Icons.person_rounded,
            onTap: gift.receiver == null
                ? null
                : () => onProfileTap(gift.receiver!.userId),
          ),
          const SizedBox(width: 8),
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
                        : const Color(0xFFD8CFEA),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (senderVip > 0 || receiverVip > 0) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 4,
                    runSpacing: 3,
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
    arabicName: 'الأسد الذهبي',
    priceCoins: 999,
    icon: '',
    sortOrder: 90,
  ),
  RoomGift(
    id: 'local-baalbek-temple',
    code: 'baalbek_temple',
    name: 'Baalbek Temple',
    arabicName: 'قلعة بعلبك',
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

class _LiveBottomActionBar extends StatelessWidget {
  const _LiveBottomActionBar({
    required this.isArabic,
    required this.connectingAudio,
    required this.micEnabled,
    required this.isOnMic,
    required this.leaving,
    required this.onToggleMic,
    required this.onLeaveRoom,
    required this.onGiftTap,
  });

  final bool isArabic;
  final bool connectingAudio;
  final bool micEnabled;
  final bool isOnMic;
  final bool leaving;
  final VoidCallback onToggleMic;
  final VoidCallback onLeaveRoom;
  final VoidCallback onGiftTap;

  @override
  Widget build(BuildContext context) {
    final micLabel = micEnabled
        ? (isArabic ? '\u0643\u062a\u0645' : 'Mute')
        : (isArabic ? '\u0641\u062a\u062d' : 'Unmute');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF241638), Color(0xFF160B26)],
        ),
        border: Border.all(color: const Color(0xFF5A3A86)),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          _LiveActionButton(
            icon: Icons.card_giftcard_rounded,
            label: isArabic ? '\u0647\u062f\u064a\u0629' : 'Gift',
            highlighted: false,
            busy: false,
            disabled: false,
            onPressed: onGiftTap,
          ),
          if (isOnMic) ...[
            const SizedBox(width: 8),
            _LiveActionButton(
              icon: micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
              label: micLabel,
              highlighted: true,
              busy: connectingAudio,
              disabled: connectingAudio,
              onPressed: onToggleMic,
            ),
          ],
          const SizedBox(width: 8),
          _LiveActionButton(
            icon: Icons.logout_rounded,
            label: isArabic ? '\u062e\u0631\u0648\u062c' : 'Leave',
            highlighted: false,
            danger: true,
            busy: leaving,
            disabled: leaving,
            onPressed: onLeaveRoom,
          ),
        ],
      ),
    );
  }
}

class _LiveActionButton extends StatelessWidget {
  const _LiveActionButton({
    required this.icon,
    required this.label,
    required this.highlighted,
    required this.busy,
    required this.disabled,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;
  final bool busy;
  final bool disabled;
  final bool danger;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? const Color(0xFFFF5C7A)
        : highlighted
        ? const Color(0xFFF0C15A)
        : const Color(0xFFD8CFEA);

    return Expanded(
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: disabled ? null : onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: highlighted
                  ? const Color(0xFFF0C15A).withValues(alpha: 0.16)
                  : const Color(0xFF12091D),
              border: Border.all(
                color: highlighted
                    ? const Color(0xFFF0C15A)
                    : const Color(0xFF4A3470),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, color: color, size: 21),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
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
