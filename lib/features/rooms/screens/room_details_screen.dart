import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/room.dart';
import '../models/room_member.dart';
import '../services/livekit_room_service.dart';
import '../services/livekit_token_service.dart';
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
  final LiveKitTokenService _liveKitTokenService = const LiveKitTokenService();
  final LiveKitRoomService _liveKitRoomService = LiveKitRoomService();

  bool _leaving = false;
  bool _testingToken = false;
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
    _subscribeToMembers();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();

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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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

  Future<void> _changeMemberRole({
    required RoomMember member,
    required String role,
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
      );

      await _loadMembers();

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

  Future<void> _testLiveKitToken() async {
    setState(() {
      _testingToken = true;
    });

    try {
      final response = await _liveKitTokenService.getToken(
        roomId: widget.room.id,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic
                ? 'LiveKit token \u062c\u0627\u0647\u0632: ${response.roomName}'
                : 'LiveKit token ready: ${response.roomName}',
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
          _testingToken = false;
        });
      }
    }
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
        child: RefreshIndicator(
          onRefresh: () => _loadMembers(),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
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
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0C15A).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: Color(0xFFF0C15A),
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.room.name,
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.room.description?.isNotEmpty == true
                          ? widget.room.description!
                          : (widget.isArabic
                                ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0648\u0635\u0641'
                                : 'No description'),
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFFD8CFEA),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      textDirection: widget.isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        _RoomDetailPill(
                          icon: Icons.language_rounded,
                          label: widget.room.language.toUpperCase(),
                        ),
                        _RoomDetailPill(
                          icon: Icons.event_seat_rounded,
                          label: '$_activeSpeakerCount/${widget.room.maxSeats}',
                        ),
                        _RoomDetailPill(
                          icon: _roomLocked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          label: widget.isArabic
                              ? (_roomLocked
                                    ? '\u0645\u0642\u0641\u0644\u0629'
                                    : '\u0645\u0641\u062a\u0648\u062d\u0629')
                              : (_roomLocked ? 'Locked' : 'Open'),
                        ),
                      ],
                    ),
                    if (_iAmHost) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: widget.isArabic
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: _RoomDetailPill(
                          icon: Icons.admin_panel_settings_rounded,
                          label: widget.isArabic
                              ? '\u0623\u0646\u062a \u0627\u0644\u0645\u0636\u064a\u0641'
                              : 'You host',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _LiveRoomStage(
                members: _members,
                maxSeats: widget.room.maxSeats,
                isArabic: widget.isArabic,
                activeSpeakerCount: _activeSpeakerCount,
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
                          showHostControls: _iAmHost && member.role != 'host',
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
                    Text(
                      widget.isArabic
                          ? '\u0627\u0644\u0635\u0648\u062a \u0627\u0644\u0645\u0628\u0627\u0634\u0631'
                          : 'Live audio',
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isArabic
                          ? '\u0627\u062a\u0635\u0644 \u0628\u063a\u0631\u0641\u0629 \u0627\u0644\u0635\u0648\u062a \u0627\u0644\u0645\u0628\u0627\u0634\u0631.'
                          : 'Connect to the live audio room.',
                      textAlign: textAlign,
                      style: const TextStyle(color: Color(0xFFD8CFEA)),
                    ),
                    const SizedBox(height: 18),
                    if (!_iCanUseMic)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF241638),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF5A3A86)),
                        ),
                        child: Text(
                          widget.isArabic
                              ? '\u0623\u0646\u062a \u0645\u0633\u062a\u0645\u0639 \u062d\u0627\u0644\u064a\u0627\u064b. \u0627\u0637\u0644\u0628 \u0645\u0646 \u0627\u0644\u0645\u0636\u064a\u0641 \u062a\u0631\u0642\u064a\u062a\u0643 \u0625\u0644\u0649 \u0645\u062a\u062d\u062f\u062b \u0644\u0627\u0633\u062a\u062e\u062f\u0627\u0645 \u0627\u0644\u0645\u0627\u064a\u0643.'
                              : 'You are a listener. Ask the host to make you a speaker to use the mic.',
                          textAlign: textAlign,
                          style: const TextStyle(
                            color: Color(0xFFD8CFEA),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Icon(
                      _connectedAudio
                          ? Icons.graphic_eq_rounded
                          : Icons.mic_none_rounded,
                      color: const Color(0xFFF0C15A),
                      size: 52,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed:
                          _connectedAudio || _connectingAudio || !_iCanUseMic
                          ? null
                          : _connectAudio,
                      icon: _connectingAudio
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_rounded),
                      label: Text(
                        widget.isArabic
                            ? '\u062a\u0634\u063a\u064a\u0644 \u0627\u0644\u0635\u0648\u062a'
                            : 'Connect audio',
                      ),
                    ),
                    if (_connectedAudio) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _toggleMic,
                        icon: Icon(
                          _micEnabled
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                        ),
                        label: Text(
                          _micEnabled
                              ? (widget.isArabic
                                    ? '\u0643\u062a\u0645 \u0627\u0644\u0645\u0627\u064a\u0643'
                                    : 'Mute mic')
                              : (widget.isArabic
                                    ? '\u0641\u062a\u062d \u0627\u0644\u0645\u0627\u064a\u0643'
                                    : 'Unmute mic'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _disconnectAudio,
                        icon: const Icon(Icons.link_off_rounded),
                        label: Text(
                          widget.isArabic
                              ? '\u0641\u0635\u0644 \u0627\u0644\u0635\u0648\u062a'
                              : 'Disconnect audio',
                        ),
                      ),
                    ],
                  ],
                ),
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
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _testingToken ? null : _testLiveKitToken,
                icon: _testingToken
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.key_rounded),
                label: Text(
                  widget.isArabic
                      ? '\u0627\u062e\u062a\u0628\u0627\u0631 LiveKit Token'
                      : 'Test LiveKit Token',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _leaving ? null : _leaveRoom,
                icon: _leaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
                label: Text(
                  widget.isArabic
                      ? '\u0645\u063a\u0627\u062f\u0631\u0629 \u0627\u0644\u063a\u0631\u0641\u0629'
                      : 'Leave room',
                ),
              ),
            ],
          ),
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
  });

  final List<RoomMember> members;
  final int maxSeats;
  final bool isArabic;
  final int activeSpeakerCount;

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
              mainAxisSpacing: 22,
              crossAxisSpacing: 12,
              childAspectRatio: 0.58,
            ),
            itemBuilder: (context, index) {
              return _LiveSeatBubble(seat: seats[index], isArabic: isArabic);
            },
          ),
        ],
      ),
    );
  }

  List<_StageSeat> _buildSeats() {
    final stageMembers = members
        .where((member) => member.role == 'host' || member.role == 'speaker')
        .toList();

    final seats = <_StageSeat>[];

    for (final member in stageMembers) {
      seats.add(
        _StageSeat(
          name: member.fallbackName(isArabic),
          role: member.role,
          isMuted: member.isMuted,
          isEmpty: false,
        ),
      );
    }

    final safeMaxSeats = maxSeats <= 0 ? 12 : maxSeats;
    while (seats.length < safeMaxSeats) {
      seats.add(
        const _StageSeat(name: '', role: 'empty', isMuted: true, isEmpty: true),
      );
    }

    return seats.take(safeMaxSeats).toList();
  }
}

class _StageSeat {
  const _StageSeat({
    required this.name,
    required this.role,
    required this.isMuted,
    required this.isEmpty,
  });

  final String name;
  final String role;
  final bool isMuted;
  final bool isEmpty;
}

class _LiveSeatBubble extends StatelessWidget {
  const _LiveSeatBubble({required this.seat, required this.isArabic});

  final _StageSeat seat;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final isHost = seat.role == 'host';
    final label = seat.isEmpty
        ? (isArabic ? '\u0641\u0627\u0631\u063a' : 'Empty')
        : seat.name;
    final badge = seat.isEmpty
        ? (isArabic ? '\u0645\u0642\u0639\u062f' : 'Seat')
        : isHost
        ? (isArabic ? '\u0645\u0636\u064a\u0641' : 'Host')
        : (isArabic ? '\u0645\u062a\u062d\u062f\u062b' : 'Speaker');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isHost
                ? const Color(0xFFF0C15A).withValues(alpha: 0.18)
                : const Color(0xFF241638),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isHost ? const Color(0xFFF0C15A) : const Color(0xFF5A3A86),
            ),
          ),
          child: Text(
            badge,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: isHost ? const Color(0xFFF0C15A) : const Color(0xFFD8CFEA),
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
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xFF12091D),
        border: Border.all(color: const Color(0xFF4A3470)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.14),
            blurRadius: 22,
            offset: const Offset(0, 12),
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
                child: Text(
                  isArabic
                      ? '\u0627\u0644\u062f\u0631\u062f\u0634\u0629'
                      : 'Room Chat',
                  textAlign: textAlign,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF241638),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF5A3A86)),
                ),
                child: Text(
                  isArabic ? '\u0645\u0628\u0627\u0634\u0631' : 'Live',
                  style: const TextStyle(
                    color: Color(0xFFF0C15A),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _LiveChatBubble(
            isArabic: isArabic,
            icon: Icons.campaign_rounded,
            title: isArabic ? '\u062f\u0639\u0648\u0629' : 'Invite',
            message: isArabic
                ? '\u0627\u062f\u0639\u064f \u0623\u0635\u062f\u0642\u0627\u0621\u0643 \u0625\u0644\u0649 \u0627\u0644\u063a\u0631\u0641\u0629.'
                : 'Invite friends into your room.',
            highlighted: true,
          ),
          const SizedBox(height: 10),
          _LiveChatBubble(
            isArabic: isArabic,
            icon: Icons.shield_rounded,
            title: isArabic ? '\u062a\u0646\u0628\u064a\u0647' : 'Notice',
            message: isArabic
                ? '\u0627\u062d\u062a\u0631\u0645 \u0627\u0644\u0645\u0636\u064a\u0641 \u0648\u0627\u0644\u0645\u0633\u062a\u0645\u0639\u064a\u0646. \u0627\u0644\u0645\u062e\u0627\u0644\u0641\u0627\u062a \u0642\u062f \u062a\u0624\u062f\u064a \u0625\u0644\u0649 \u062d\u0638\u0631.'
                : 'Respect the host and listeners. Violations can lead to a ban.',
            highlighted: false,
          ),
          const SizedBox(height: 10),
          _LiveChatBubble(
            isArabic: isArabic,
            icon: Icons.login_rounded,
            title: roomName,
            message: isArabic
                ? '\u062f\u062e\u0644\u062a \u0627\u0644\u063a\u0631\u0641\u0629.'
                : 'You entered the room.',
            highlighted: false,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF241638),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF5A3A86)),
            ),
            child: Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Expanded(
                  child: Text(
                    isArabic
                        ? '\u0627\u0644\u062f\u0631\u062f\u0634\u0629 \u0633\u062a\u0641\u0639\u0644 \u0641\u064a \u0645\u0631\u062d\u0644\u0629 \u0644\u0627\u062d\u0642\u0629'
                        : 'Chat input will be enabled in a later phase',
                    textAlign: textAlign,
                    style: const TextStyle(
                      color: Color(0xFFD8CFEA),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.chat_bubble_rounded, color: Color(0xFFF0C15A)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveChatBubble extends StatelessWidget {
  const _LiveChatBubble({
    required this.isArabic,
    required this.icon,
    required this.title,
    required this.message,
    required this.highlighted,
  });

  final bool isArabic;
  final IconData icon;
  final String title;
  final String message;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFF3A174F) : const Color(0xFF1B102B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted
              ? const Color(0xFFF0C15A).withValues(alpha: 0.45)
              : const Color(0xFF4A3470),
        ),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: highlighted
                ? const Color(0xFFF0C15A)
                : const Color(0xFFD8CFEA),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: crossAxisAlignment,
              children: [
                Text(
                  title,
                  textAlign: textAlign,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  textAlign: textAlign,
                  style: const TextStyle(
                    color: Color(0xFFD8CFEA),
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
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
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isArabic
                        ? '\u0627\u0644\u0647\u062f\u0627\u064a\u0627 \u0633\u062a\u0636\u0627\u0641 \u0641\u064a \u0645\u0631\u062d\u0644\u0629 \u0644\u0627\u062d\u0642\u0629.'
                        : 'Gifts will be added in a later phase.',
                  ),
                ),
              );
            },
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

class _RoomDetailPill extends StatelessWidget {
  const _RoomDetailPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF241638),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFF0C15A)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
