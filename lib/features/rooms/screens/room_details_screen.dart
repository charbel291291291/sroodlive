import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/room.dart';
import '../models/room_member.dart';
import '../services/livekit_room_service.dart';
import '../services/rooms_service.dart';

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
  final LiveKitRoomService _liveKitRoomService = LiveKitRoomService();

  bool _leaving = false;
  bool _connectingAudio = false;
  bool _connectedAudio = false;
  bool _micEnabled = true;
  bool _loadingMembers = true;
  bool _lockBusy = false;
  late bool _roomLocked;
  String? _roleBusyUserId;

  List<RoomMember> _members = const [];
  RealtimeChannel? _membersChannel;
  Timer? _heartbeatTimer;
  Timer? _membersRefreshTimer;
  final List<_RoomGiftEvent> _giftEvents = [];
  final List<Timer> _giftEventTimers = [];
  final Map<String, int> _giftSupportByUserId = {};
  int _giftEventSeed = 0;

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

  bool get _iCanUseMic => _memberCanUseMic(_myMember);

  int get _activeSpeakerCount {
    return _members
        .where((member) => member.role == 'host' || member.role == 'speaker')
        .length;
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

  @override
  void initState() {
    super.initState();
    _roomLocked = widget.room.isLocked;
    _loadMembers();
    _startHeartbeat();
    _startMembersRefresh();
    _subscribeToMembers();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _membersRefreshTimer?.cancel();
    for (final timer in _giftEventTimers) {
      timer.cancel();
    }

    final membersChannel = _membersChannel;

    if (membersChannel != null) {
      unawaited(SupabaseService.requiredClient.removeChannel(membersChannel));
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

            unawaited(_loadMembers(showLoading: false));
          },
        )
        .subscribe();
  }

  Future<void> _loadMembers({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loadingMembers = true;
      });
    }

    try {
      final members = await _roomsService.getActiveRoomMembers(widget.room.id);

      if (!mounted) return;

      setState(() {
        _members = members;
      });

      RoomMember? currentMember;
      final currentUserId = _currentUserId;

      if (currentUserId != null) {
        for (final member in members) {
          if (member.userId == currentUserId) {
            currentMember = member;
            break;
          }
        }
      }

      if (_connectedAudio && !_memberCanUseMic(currentMember)) {
        await _liveKitRoomService.disconnect();
        await _roomsService.setMyMuteStatus(
          roomId: widget.room.id,
          isMuted: true,
        );

        if (!mounted) return;

        setState(() {
          _connectedAudio = false;
          _micEnabled = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isArabic
                  ? '\u062a\u0645 \u0641\u0635\u0644 \u0627\u0644\u0635\u0648\u062a \u0644\u0623\u0646\u0643 \u0623\u0635\u0628\u062d\u062a \u0645\u0633\u062a\u0645\u0639\u0627\u064b'
                  : 'Audio disconnected because you are now a listener',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;

      if (showLoading) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        if (showLoading) {
          setState(() {
            _loadingMembers = false;
          });
        }
      }
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
    if (!_iAmHost) {
      return;
    }

    final availableMembers = _members
        .where((member) => member.role != 'host')
        .toList();

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
                      ? '\u0646\u0642\u0644 \u0645\u0633\u062a\u0645\u0639 \u0625\u0644\u0649 \u0645\u0627\u064a\u0643 $seatNumber'
                      : 'Move listener to Mic $seatNumber',
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
                if (availableMembers.isEmpty)
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
                ...availableMembers.map(
                  (member) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF241638),
                      child: Icon(
                        Icons.person_rounded,
                        color: Color(0xFFF0C15A),
                      ),
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

  Future<void> _moveMyselfToSeat(int seatNumber) async {
    try {
      await _roomsService.updateMySeatNumber(
        roomId: widget.room.id,
        seatNumber: seatNumber,
      );

      _replaceMemberLocally(_myMember, seatNumber: seatNumber);

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

    if (action.seatNumber != null) {
      await _changeMemberRole(
        member: member,
        role: 'speaker',
        seatNumber: action.seatNumber,
      );
      return;
    }

    await _changeMemberRole(member: member, role: 'listener');
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
        );
      }).toList();
    });
  }

  Future<void> _connectAudio() async {
    if (!_iCanUseMic) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic
                ? '\u0627\u0637\u0644\u0628 \u0645\u0646 \u0627\u0644\u0645\u0636\u064a\u0641 \u062a\u0631\u0642\u064a\u062a\u0643 \u0625\u0644\u0649 \u0645\u062a\u062d\u062f\u062b \u0644\u0627\u0633\u062a\u062e\u062f\u0627\u0645 \u0627\u0644\u0645\u0627\u064a\u0643'
                : 'Ask the host to make you a speaker to use the mic',
          ),
        ),
      );
      return;
    }

    setState(() {
      _connectingAudio = true;
    });

    try {
      await _liveKitRoomService.connect(
        roomId: widget.room.id,
        microphoneEnabled: true,
      );

      await _roomsService.setMyMuteStatus(
        roomId: widget.room.id,
        isMuted: false,
      );

      if (!mounted) return;

      setState(() {
        _connectedAudio = true;
        _micEnabled = true;
      });

      await _loadMembers();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic
                ? '\u062a\u0645 \u0627\u0644\u0627\u062a\u0635\u0627\u0644 \u0628\u0627\u0644\u0635\u0648\u062a'
                : 'Audio connected',
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
          _connectingAudio = false;
        });
      }
    }
  }

  Future<void> _toggleMic() async {
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

  Future<void> _disconnectAudio() async {
    await _liveKitRoomService.disconnect();
    await _roomsService.setMyMuteStatus(roomId: widget.room.id, isMuted: true);

    if (!mounted) return;

    setState(() {
      _connectedAudio = false;
      _micEnabled = true;
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

  String _joinedLabel(DateTime joinedAt) {
    final local = joinedAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return widget.isArabic
        ? '\u0627\u0646\u0636\u0645 $hour:$minute'
        : 'Joined $hour:$minute';
  }

  Future<void> _openGiftSheet() async {
    final currentUserId = _currentUserId;
    final receivers =
        _members.where((member) => member.userId != currentUserId).toList()
          ..sort(
            (a, b) =>
                _giftReceiverRank(a.role).compareTo(_giftReceiverRank(b.role)),
          );

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
          roleLabel: _roleLabel,
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

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
          (result.gift.price * result.quantity);
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

  @override
  Widget build(BuildContext context) {
    final textAlign = widget.isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = widget.isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

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
                  const SizedBox(height: 18),
                  _LiveRoomStage(
                    members: _members,
                    maxSeats: widget.room.maxSeats,
                    isArabic: widget.isArabic,
                    activeSpeakerCount: _activeSpeakerCount,
                    isHost: _iAmHost,
                    onEmptySeatTap: _pickListenerForSeat,
                    onOccupiedSeatTap: _showMemberSeatActions,
                    supportByUserId: _giftSupportByUserId,
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171125),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: const Color(0xFF4A3470)),
                    ),
                    child: Column(
                      crossAxisAlignment: crossAxisAlignment,
                      children: [
                        Row(
                          textDirection: widget.isArabic
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          children: [
                            Expanded(
                              child: Text(
                                widget.isArabic
                                    ? '\u0627\u0644\u0645\u0634\u0627\u0631\u0643\u0648\u0646'
                                    : 'Participants',
                                textAlign: textAlign,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _loadingMembers ? null : _loadMembers,
                              icon: _loadingMembers
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_members.isEmpty && !_loadingMembers)
                          Text(
                            widget.isArabic
                                ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0645\u0634\u0627\u0631\u0643\u0648\u0646 \u0646\u0634\u0637\u0648\u0646 \u0628\u0639\u062f.'
                                : 'No active participants yet.',
                            textAlign: textAlign,
                            style: const TextStyle(color: Color(0xFFD8CFEA)),
                          )
                        else
                          ..._members.map(
                            (member) => _ParticipantTile(
                              name: member.fallbackName(widget.isArabic),
                              role: _roleLabel(member.role),
                              rawRole: member.role,
                              joinedAt: _joinedLabel(member.joinedAt),
                              isMuted: member.isMuted,
                              isArabic: widget.isArabic,
                              supportAmount:
                                  _giftSupportByUserId[member.userId] ?? 0,
                              showHostControls:
                                  _iAmHost && member.role != 'host',
                              isBusy: _roleBusyUserId == member.userId,
                              onPromote: () => _changeMemberRole(
                                member: member,
                                role: 'speaker',
                              ),
                              onMoveToListener: () => _changeMemberRole(
                                member: member,
                                role: 'listener',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _LiveChatPanel(
                    roomName: widget.room.name,
                    isArabic: widget.isArabic,
                  ),
                  const SizedBox(height: 18),
                  _LiveBottomActionBar(
                    isArabic: widget.isArabic,
                    connectedAudio: _connectedAudio,
                    connectingAudio: _connectingAudio,
                    micEnabled: _micEnabled,
                    canUseMic: _iCanUseMic,
                    leaving: _leaving,
                    onConnectAudio: _connectAudio,
                    onToggleMic: _toggleMic,
                    onDisconnectAudio: _disconnectAudio,
                    onLeaveRoom: _leaveRoom,
                    onGiftTap: _openGiftSheet,
                  ),
                ],
              ),
            ),
            _GiftEventOverlay(events: _giftEvents, isArabic: widget.isArabic),
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
    required this.supportByUserId,
  });

  final List<RoomMember> members;
  final int maxSeats;
  final bool isArabic;
  final int activeSpeakerCount;
  final bool isHost;
  final ValueChanged<int> onEmptySeatTap;
  final void Function(RoomMember member, int seatNumber) onOccupiedSeatTap;
  final Map<String, int> supportByUserId;

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
                    Text(
                      isArabic
                          ? '$activeSpeakerCount/$maxSeats \u0645\u0642\u0627\u0639\u062f \u0646\u0634\u0637\u0629'
                          : '$activeSpeakerCount/$maxSeats active seats',
                      textAlign: textAlign,
                      style: const TextStyle(
                        color: Color(0xFFD8CFEA),
                        fontWeight: FontWeight.w700,
                      ),
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: seats.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 26,
              crossAxisSpacing: 12,
              childAspectRatio: 0.50,
            ),
            itemBuilder: (context, index) {
              return _LiveSeatBubble(
                seat: seats[index],
                isArabic: isArabic,
                isHost: isHost,
                onEmptySeatTap: onEmptySeatTap,
                onOccupiedSeatTap: onOccupiedSeatTap,
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
  const _OccupiedSeatAction.moveToListener() : seatNumber = null;

  const _OccupiedSeatAction.moveToSeat(this.seatNumber);

  final int? seatNumber;
}

class _LiveSeatBubble extends StatelessWidget {
  const _LiveSeatBubble({
    required this.seat,
    required this.isArabic,
    required this.isHost,
    required this.onEmptySeatTap,
    required this.onOccupiedSeatTap,
  });

  final _StageSeat seat;
  final bool isArabic;
  final bool isHost;
  final ValueChanged<int> onEmptySeatTap;
  final void Function(RoomMember member, int seatNumber) onOccupiedSeatTap;

  @override
  Widget build(BuildContext context) {
    final canAssignSeat = seat.isEmpty && isHost;
    final canManageSeat = !seat.isEmpty && isHost && seat.member != null;
    final occupiedByHost = seat.role == 'host';
    final label = seat.isEmpty
        ? (isArabic
              ? '\u0645\u0627\u064a\u0643 ${seat.number}'
              : 'Mic ${seat.number}')
        : seat.name;
    final badge = seat.isEmpty
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
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: seat.isEmpty
                  ? const LinearGradient(
                      colors: [Color(0xFF241638), Color(0xFF130A20)],
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFF0C15A), Color(0xFF8B26D9)],
                    ),
              border: Border.all(
                color: seat.isEmpty
                    ? const Color(0xFF5A3A86)
                    : const Color(0xFFFFD978),
                width: 1.4,
              ),
              boxShadow: seat.isEmpty
                  ? []
                  : [
                      BoxShadow(
                        color: const Color(0xFFF0C15A).withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: Icon(
              seat.isEmpty
                  ? Icons.add_rounded
                  : seat.isMuted
                  ? Icons.mic_off_rounded
                  : Icons.mic_rounded,
              color: seat.isEmpty ? const Color(0xFFD8CFEA) : Colors.white,
              size: 26,
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
            color: seat.isEmpty ? const Color(0xFF9E91B8) : Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        _SupportPill(amount: seat.supportAmount, compact: true),
        if (seat.supportAmount > 0) const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: canAssignSeat || occupiedByHost
                ? const Color(0xFFF0C15A).withValues(alpha: 0.18)
                : const Color(0xFF241638),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: occupiedByHost
                  ? const Color(0xFFF0C15A)
                  : const Color(0xFF5A3A86),
            ),
          ),
          child: Text(
            badge,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: occupiedByHost
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
  const _LiveChatPanel({required this.roomName, required this.isArabic});

  final String roomName;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          const Icon(
            Icons.chat_bubble_rounded,
            color: Color(0xFFF0C15A),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isArabic
                  ? '\u0627\u0644\u062f\u0631\u062f\u0634\u0629 \u0633\u062a\u0641\u0639\u0644 \u0644\u0627\u062d\u0642\u0627\u064b'
                  : 'Chat will be enabled later',
              textAlign: textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD8CFEA),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF241638),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isArabic ? '\u0642\u0631\u064a\u0628\u0627\u064b' : 'Soon',
              style: const TextStyle(
                color: Color(0xFFF0C15A),
                fontWeight: FontWeight.w900,
                fontSize: 10,
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

class _GiftItem {
  const _GiftItem({
    required this.name,
    required this.arabicName,
    required this.artwork,
    required this.icon,
    required this.price,
  });

  final String name;
  final String arabicName;
  final String artwork;
  final IconData icon;
  final int price;
}

class _GiftSendResult {
  const _GiftSendResult({
    required this.gift,
    required this.receiverUserId,
    required this.receiverName,
    required this.quantity,
  });

  final _GiftItem gift;
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
  final _GiftItem gift;
  final String receiverName;
  final int quantity;
}

class _GiftSheet extends StatefulWidget {
  const _GiftSheet({
    required this.isArabic,
    required this.receivers,
    required this.roleLabel,
  });

  final bool isArabic;
  final List<RoomMember> receivers;
  final String Function(String role) roleLabel;

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  static const List<_GiftItem> _gifts = [
    _GiftItem(
      name: 'Rose',
      arabicName: '\u0648\u0631\u062f\u0629',
      artwork: '\uD83C\uDF39',
      icon: Icons.local_florist_rounded,
      price: 10,
    ),
    _GiftItem(
      name: 'Star',
      arabicName: '\u0646\u062c\u0645\u0629',
      artwork: '\u2B50',
      icon: Icons.star_rounded,
      price: 50,
    ),
    _GiftItem(
      name: 'Crown',
      arabicName: '\u062a\u0627\u062c',
      artwork: '\uD83D\uDC51',
      icon: Icons.workspace_premium_rounded,
      price: 250,
    ),
    _GiftItem(
      name: 'Rocket',
      arabicName: '\u0635\u0627\u0631\u0648\u062e',
      artwork: '\uD83D\uDE80',
      icon: Icons.rocket_launch_rounded,
      price: 1000,
    ),
  ];

  RoomMember? _selectedReceiver;
  _GiftItem? _selectedGift;
  int _quantity = 1;

  void _chooseGift(_GiftItem gift) {
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
              _GiftCategoryTabs(isArabic: widget.isArabic),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: _gifts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  itemBuilder: (context, index) {
                    final gift = _gifts[index];

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
      height: 82,
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
            roleLabel: roleLabel(receiver.role),
            onTap: () => onSelected(receiver),
          );
        },
      ),
    );
  }
}

class _GiftReceiverBubble extends StatelessWidget {
  const _GiftReceiverBubble({
    required this.receiver,
    required this.selected,
    required this.isArabic,
    required this.roleLabel,
    required this.onTap,
  });

  final RoomMember receiver;
  final bool selected;
  final bool isArabic;
  final String roleLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = receiver.fallbackName(isArabic);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: selected
                      ? const [Color(0xFFB000FF), Color(0xFFF0C15A)]
                      : const [Color(0xFF2D1247), Color(0xFF12091D)],
                ),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFF0C15A)
                      : const Color(0xFF4A3470),
                  width: 2,
                ),
              ),
              child: Icon(
                receiver.role == 'listener'
                    ? Icons.person_rounded
                    : Icons.mic_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFD8CFEA),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              roleLabel,
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
  const _GiftCategoryTabs({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final labels = isArabic
        ? const [
            '\u062d\u062f\u062b',
            '\u0631\u0627\u0626\u062c',
            '\u062d\u0638',
            'VIP',
          ]
        : const ['Event', 'Hot', 'Lucky', 'VIP'];

    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: labels.map((label) {
        final selected =
            label == (isArabic ? '\u0631\u0627\u0626\u062c' : 'Hot');

        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
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
        );
      }).toList(),
    );
  }
}

class _GiftArtwork extends StatelessWidget {
  const _GiftArtwork({required this.gift, required this.size});

  final _GiftItem gift;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFFFF1A8), Color(0xFFE0A83A), Color(0xFF8B26D9)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.28),
            blurRadius: 18,
          ),
        ],
      ),
      child: Text(gift.artwork, style: TextStyle(fontSize: size * 0.52)),
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

  final _GiftItem gift;
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
              child: Center(child: _GiftArtwork(gift: gift, size: 50)),
            ),
            const Spacer(),
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
                  gift.price.toString(),
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
  final _GiftItem? selectedGift;
  final VoidCallback onQuantityTap;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final total = (selectedGift?.price ?? 0) * quantity;

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
    required this.connectedAudio,
    required this.connectingAudio,
    required this.micEnabled,
    required this.canUseMic,
    required this.leaving,
    required this.onConnectAudio,
    required this.onToggleMic,
    required this.onDisconnectAudio,
    required this.onLeaveRoom,
    required this.onGiftTap,
  });

  final bool isArabic;
  final bool connectedAudio;
  final bool connectingAudio;
  final bool micEnabled;
  final bool canUseMic;
  final bool leaving;
  final VoidCallback onConnectAudio;
  final VoidCallback onToggleMic;
  final VoidCallback onDisconnectAudio;
  final VoidCallback onLeaveRoom;
  final VoidCallback onGiftTap;

  @override
  Widget build(BuildContext context) {
    final micLabel = connectedAudio
        ? (micEnabled
              ? (isArabic ? '\u0643\u062a\u0645' : 'Mute')
              : (isArabic ? '\u0641\u062a\u062d' : 'Unmute'))
        : (isArabic ? '\u062a\u0634\u063a\u064a\u0644' : 'Connect');

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
            icon: connectedAudio
                ? (micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded)
                : Icons.wifi_tethering_rounded,
            label: micLabel,
            highlighted: true,
            busy: connectingAudio,
            disabled: !canUseMic || connectingAudio,
            onPressed: connectedAudio ? onToggleMic : onConnectAudio,
          ),
          const SizedBox(width: 8),
          _LiveActionButton(
            icon: Icons.link_off_rounded,
            label: isArabic ? '\u0641\u0635\u0644' : 'Off',
            highlighted: false,
            busy: false,
            disabled: !connectedAudio,
            onPressed: onDisconnectAudio,
          ),
          const SizedBox(width: 8),
          _LiveActionButton(
            icon: Icons.card_giftcard_rounded,
            label: isArabic ? '\u0647\u062f\u064a\u0629' : 'Gift',
            highlighted: false,
            busy: false,
            disabled: false,
            onPressed: onGiftTap,
          ),
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

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.name,
    required this.role,
    required this.rawRole,
    required this.joinedAt,
    required this.isMuted,
    required this.isArabic,
    required this.supportAmount,
    required this.showHostControls,
    required this.isBusy,
    required this.onPromote,
    required this.onMoveToListener,
  });

  final String name;
  final String role;
  final String rawRole;
  final String joinedAt;
  final bool isMuted;
  final bool isArabic;
  final int supportAmount;
  final bool showHostControls;
  final bool isBusy;
  final VoidCallback onPromote;
  final VoidCallback onMoveToListener;

  @override
  Widget build(BuildContext context) {
    final canPromote = rawRole == 'listener';
    final canMoveToListener = rawRole == 'speaker';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF241638),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF5A3A86)),
      ),
      child: Column(
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              CircleAvatar(
                backgroundColor: const Color(
                  0xFFF0C15A,
                ).withValues(alpha: 0.18),
                child: Icon(
                  isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: const Color(0xFFF0C15A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: isArabic
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      textAlign: isArabic ? TextAlign.right : TextAlign.left,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      joinedAt,
                      textAlign: isArabic ? TextAlign.right : TextAlign.left,
                      style: const TextStyle(
                        color: Color(0xFFD8CFEA),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _SupportPill(amount: supportAmount, compact: false),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  _SmallStatusPill(label: role),
                  const SizedBox(height: 6),
                  _SmallStatusPill(
                    label: isMuted
                        ? (isArabic
                              ? '\u0645\u0643\u062a\u0648\u0645'
                              : 'Muted')
                        : (isArabic
                              ? '\u0645\u0627\u064a\u0643 \u0645\u0641\u062a\u0648\u062d'
                              : 'Live mic'),
                  ),
                ],
              ),
            ],
          ),
          if (showHostControls) ...[
            const SizedBox(height: 12),
            Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                if (canPromote)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy ? null : onPromote,
                      icon: isBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.record_voice_over_rounded),
                      label: Text(
                        isArabic
                            ? '\u062c\u0639\u0644\u0647 \u0645\u062a\u062d\u062f\u062b\u0627\u064b'
                            : 'Make speaker',
                      ),
                    ),
                  ),
                if (canMoveToListener)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy ? null : onMoveToListener,
                      icon: isBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.hearing_rounded),
                      label: Text(
                        isArabic
                            ? '\u0625\u0639\u0627\u062f\u062a\u0647 \u0645\u0633\u062a\u0645\u0639\u0627\u064b'
                            : 'Move to listener',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
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

class _SmallStatusPill extends StatelessWidget {
  const _SmallStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF171125),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFFF0C15A),
        ),
      ),
    );
  }
}
