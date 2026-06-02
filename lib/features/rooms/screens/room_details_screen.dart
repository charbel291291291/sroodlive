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
  String? _roleBusyUserId;

  List<RoomMember> _members = const [];
  RealtimeChannel? _membersChannel;

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
    _loadMembers();
    _subscribeToMembers();
  }

  @override
  void dispose() {
    final membersChannel = _membersChannel;

    if (membersChannel != null) {
      unawaited(SupabaseService.requiredClient.removeChannel(membersChannel));
    }

    _liveKitRoomService.disconnect();
    super.dispose();
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
                  ? '?? ??? ????? ???? ????? ????'
                  : 'Audio disconnected because you are now a listener',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
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

  Future<void> _changeMemberRole({
    required RoomMember member,
    required String role,
  }) async {
    setState(() {
      _roleBusyUserId = member.userId;
    });

    try {
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
            widget.isArabic ? '?? ????? ?????' : 'Role updated',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
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
                ? 'LiveKit token ????: ${response.roomName}'
                : 'LiveKit token ready: ${response.roomName}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
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
                ? '???? ?? ?????? ?????? ??? ????? ?????? ??????'
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
            widget.isArabic ? '?? ??????? ??????' : 'Audio connected',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
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
    await _roomsService.setMyMuteStatus(
      roomId: widget.room.id,
      isMuted: true,
    );

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
                ? '???? ?? ??????: ${widget.room.name}'
                : 'Left room: ${widget.room.name}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _leaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'host':
        return widget.isArabic ? '????' : 'Host';
      case 'speaker':
        return widget.isArabic ? '?????' : 'Speaker';
      default:
        return widget.isArabic ? '?????' : 'Listener';
    }
  }

  String _joinedLabel(DateTime joinedAt) {
    final local = joinedAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return widget.isArabic ? '???? $hour:$minute' : 'Joined $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final textAlign = widget.isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment =
        widget.isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isArabic ? '??????' : 'Room'),
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
                  color: const Color(0xFF14141F),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFF2A2A38),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD6A84F).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: Color(0xFFD6A84F),
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
                          : (widget.isArabic ? '???? ???' : 'No description'),
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFFB8B8C7),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      textDirection:
                          widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
                      children: [
                        _RoomDetailPill(
                          icon: Icons.language_rounded,
                          label: widget.room.language.toUpperCase(),
                        ),
                        const SizedBox(width: 8),
                        _RoomDetailPill(
                          icon: Icons.event_seat_rounded,
                          label: '${_members.length}/${widget.room.maxSeats}',
                        ),
                        if (_iAmHost) ...[
                          const SizedBox(width: 8),
                          _RoomDetailPill(
                            icon: Icons.admin_panel_settings_rounded,
                            label: widget.isArabic ? '??? ??????' : 'You host',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF14141F),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFF2A2A38),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    Row(
                      textDirection:
                          widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
                      children: [
                        Expanded(
                          child: Text(
                            widget.isArabic ? '?????????' : 'Participants',
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
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_members.isEmpty && !_loadingMembers)
                      Text(
                        widget.isArabic
                            ? '?? ???? ??????? ?????.'
                            : 'No active participants yet.',
                        textAlign: textAlign,
                        style: const TextStyle(
                          color: Color(0xFFB8B8C7),
                        ),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF14141F),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFF2A2A38),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    Text(
                      widget.isArabic ? '????? ???????' : 'Live audio',
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isArabic
                          ? '???? ??????? ??????? ????????.'
                          : 'Connect to the live audio room.',
                      textAlign: textAlign,
                      style: const TextStyle(
                        color: Color(0xFFB8B8C7),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!_iCanUseMic)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF232332),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF303044),
                          ),
                        ),
                        child: Text(
                          widget.isArabic
                              ? '??? ????? ?????. ???? ?? ?????? ?????? ??? ????? ?????? ??????.'
                              : 'You are a listener. Ask the host to make you a speaker to use the mic.',
                          textAlign: textAlign,
                          style: const TextStyle(
                            color: Color(0xFFB8B8C7),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Icon(
                      _connectedAudio
                          ? Icons.graphic_eq_rounded
                          : Icons.mic_none_rounded,
                      color: const Color(0xFFD6A84F),
                      size: 52,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _connectedAudio || _connectingAudio || !_iCanUseMic
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
                        widget.isArabic ? '????? ?????' : 'Connect audio',
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
                              ? (widget.isArabic ? '????? ??????' : 'Mute mic')
                              : (widget.isArabic ? '????? ??????' : 'Unmute mic'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _disconnectAudio,
                        icon: const Icon(Icons.link_off_rounded),
                        label: Text(
                          widget.isArabic ? '??? ?????' : 'Disconnect audio',
                        ),
                      ),
                    ],
                  ],
                ),
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
                  widget.isArabic ? '?????? LiveKit Token' : 'Test LiveKit Token',
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
                label: Text(widget.isArabic ? '?????? ?? ??????' : 'Leave room'),
              ),
            ],
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
        color: const Color(0xFF232332),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF303044),
        ),
      ),
      child: Column(
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFD6A84F).withValues(alpha: 0.18),
                child: Icon(
                  isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: const Color(0xFFD6A84F),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                        color: Color(0xFFB8B8C7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment:
                    isArabic ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  _SmallStatusPill(label: role),
                  const SizedBox(height: 6),
                  _SmallStatusPill(
                    label: isMuted
                        ? (isArabic ? '????' : 'Muted')
                        : (isArabic ? '?????' : 'Live mic'),
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
                        isArabic ? '????? ??????' : 'Make speaker',
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
                        isArabic ? '????? ??????' : 'Move to listener',
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
  const _SmallStatusPill({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF14141F),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFFD6A84F),
        ),
      ),
    );
  }
}

class _RoomDetailPill extends StatelessWidget {
  const _RoomDetailPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF232332),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFD6A84F)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

