import 'dart:async';
import 'package:srood_live/shared/utils/error_utils.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/avatar_with_frame.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../../profile/services/follow_service.dart';
import '../models/private_message.dart';
import '../services/private_message_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class PrivateChatScreen extends StatefulWidget {
  const PrivateChatScreen({
    required this.targetUserId,
    required this.targetName,
    required this.isArabic,
    this.targetAvatarUrl,
    this.targetFrameKey,
    super.key,
  });

  final String targetUserId;
  final String targetName; // initial hint shown while real profile loads
  final String? targetAvatarUrl;
  final String? targetFrameKey;
  final bool isArabic;

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final PrivateMessageService _service = const PrivateMessageService();
  final _followService = const FollowService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  RealtimeChannel? _channel;

  bool _loading = true;
  bool _sending = false;
  bool _isMutualFriend = false;
  String? _conversationId;
  String? _error;
  List<PrivateMessage> _messages = const [];

  // Resolved profile (overrides constructor hint when loaded)
  String? _resolvedName;
  String? _resolvedAvatarUrl;
  String? _resolvedFrameKey;

  String get _displayName {
    if (_resolvedName != null && _resolvedName!.isNotEmpty) {
      return _resolvedName!;
    }
    if (widget.targetName.isNotEmpty &&
        !widget.targetName.startsWith('User ')) {
      return widget.targetName;
    }
    return context.isArabic ? 'مستخدم' : 'Unknown user';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    final currentUserId =
        SupabaseService.requiredClient.auth.currentUser?.id ?? 'unknown';
    debugPrint('[MessagesProfile] currentUserId=$currentUserId');
    debugPrint('[MessagesProfile] otherUserId=${widget.targetUserId}');

    // Check mutual follow and fetch profile in parallel.
    final results = await Future.wait([
      _service.fetchTargetProfile(widget.targetUserId).catchError((_) => null),
      _followService
          .isMutualFollow(widget.targetUserId)
          .catchError((_) => false),
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final mutual = results[1] as bool;

    if (profile != null) {
      final name = _pickName(profile);
      debugPrint('[MessagesProfile] profileLoaded name=$name');
      if (mounted) {
        setState(() {
          _resolvedName = name;
          _resolvedAvatarUrl = profile['avatar_url']?.toString();
          _resolvedFrameKey = profile['selected_avatar_frame_key']?.toString();
        });
      }
    } else {
      debugPrint(
        '[MessagesProfile] fallback reason=profile_null_rls_or_missing',
      );
    }

    if (!mutual) {
      if (mounted) {
        setState(() {
          _isMutualFriend = false;
          _loading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isMutualFriend = true);

    // Mutual friends — open or load the conversation.
    String? cid;
    try {
      cid = await _service.getOrCreateConversation(widget.targetUserId);
      debugPrint('[MessagesProfile] conversationId=$cid');
    } catch (e, st) {
      debugError('PrivateChatScreen._load', e, st);
    }

    if (cid == null) {
      if (mounted) {
        setState(() {
          _error = context.isArabic
              ? 'تعذّر فتح المحادثة'
              : 'Could not open conversation';
          _loading = false;
        });
      }
      return;
    }

    try {
      final msgs = await _service.fetchMessages(cid);
      unawaited(_service.markConversationRead(cid));
      if (!mounted) return;
      setState(() {
        _conversationId = cid;
        _messages = msgs;
        _loading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      _subscribe(cid);
    } catch (e, st) {
      if (!mounted) return;
      debugError('PrivateChatScreen._loadMessages', e, st);
      setState(() {
        _error = friendlyMessage(e, isArabic: context.isArabic);
        _loading = false;
      });
    }
  }

  String _pickName(Map<String, dynamic> p) {
    for (final key in ['display_name', 'nickname', 'full_name', 'username']) {
      final v = p[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  void _subscribe(String cid) {
    _channel = SupabaseService.requiredClient
        .channel('chat_screen_$cid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'private_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: cid,
          ),
          callback: (_) {
            if (mounted) unawaited(_reload());
          },
        )
        .subscribe();
  }

  Future<void> _reload() async {
    final cid = _conversationId;
    if (cid == null) return;
    final msgs = await _service.fetchMessages(cid);
    unawaited(_service.markConversationRead(cid));
    if (!mounted) return;
    setState(() => _messages = msgs);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients &&
        _scrollController.position.hasContentDimensions) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Send / Delete
  // ---------------------------------------------------------------------------

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.sendMessage(targetUserId: widget.targetUserId, body: body);
      _controller.clear();
      final cid = _conversationId;
      if (cid != null) {
        final msgs = await _service.fetchMessages(cid);
        if (mounted) {
          setState(() => _messages = msgs);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        }
      } else {
        await _load();
      }
    } catch (e, st) {
      if (!mounted) return;
      debugError('PrivateChatScreen._send', e, st);
      SroodToast.show(
        context,
        friendlyMessage(e, isArabic: context.isArabic),
        type: SroodToastType.error,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmDelete(PrivateMessage msg) async {
    final isArabic = context.isArabic;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF160B24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A2060),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFFF5C7A),
                ),
                title: Text(
                  isArabic ? 'حذف الرسالة' : 'Delete message',
                  style: const TextStyle(
                    color: Color(0xFFFF5C7A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.of(sheetCtx).pop(true),
              ),
              ListTile(
                leading: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF9E91B8),
                ),
                title: Text(
                  isArabic ? 'إلغاء' : 'Cancel',
                  style: const TextStyle(color: Color(0xFF9E91B8)),
                ),
                onTap: () => Navigator.of(sheetCtx).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteMessage(msg.id);
      // Optimistic update
      setState(() {
        _messages = _messages.map((m) {
          if (m.id == msg.id) {
            return PrivateMessage(
              id: m.id,
              conversationId: m.conversationId,
              senderId: m.senderId,
              receiverId: m.receiverId,
              body: m.body,
              createdAt: m.createdAt,
              readAt: m.readAt,
              deletedAt: DateTime.now(),
            );
          }
          return m;
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      SroodToast.show(
        context,
        context.isArabic ? 'فشل الحذف' : 'Delete failed',
        type: SroodToastType.error,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _openTargetProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(
          userId: widget.targetUserId,
          isArabic: context.isArabic,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    final currentUserId = SupabaseService.requiredClient.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: const Color(0xFF08060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(isArabic),
              const Divider(color: Color(0xFF1E1030), height: 1),
              Expanded(child: _buildMessages(currentUserId, isArabic)),
              _buildInput(isArabic),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(bool isArabic) {
    final avatarUrl = _resolvedAvatarUrl ?? widget.targetAvatarUrl;
    final frameKey = _resolvedFrameKey ?? widget.targetFrameKey;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
          GestureDetector(
            onTap: _openTargetProfile,
            child: AvatarWithFrame(
              imageUrl: avatarUrl,
              radius: 20,
              frameKey: frameKey,
              compact: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _openTargetProfile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'Online',
                    style: TextStyle(
                      color: Color(0xFF63E6A1),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

  Widget _buildMessages(String? currentUserId, bool isArabic) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B26D9)),
      );
    }

    // Not mutual friends — show a wall instead of chat history.
    if (!_isMutualFriend) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0A2E),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Color(0xFF8B26D9),
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isArabic ? 'لا يمكنك المراسلة' : 'Cannot Send Messages',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isArabic
                    ? 'يجب أن تتابع بعضكما البعض لتتمكنا من التحدث.\nاطلب المتابعة أولاً.'
                    : 'You must follow each other to chat.\nFollow them and ask them to follow you back.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _openTargetProfile,
                icon: const Icon(
                  Icons.person_add_rounded,
                  color: Color(0xFF8B26D9),
                  size: 18,
                ),
                label: Text(
                  isArabic ? 'عرض الملف الشخصي' : 'View Profile',
                  style: const TextStyle(
                    color: Color(0xFF8B26D9),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFF5C7A), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: Text(
                isArabic ? 'إعادة' : 'Retry',
                style: const TextStyle(color: Color(0xFFF0C15A)),
              ),
            ),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              color: Color(0xFF2A1840),
              size: 56,
            ),
            const SizedBox(height: 14),
            Text(
              isArabic ? 'ابدأ المحادثة' : 'Start the conversation',
              style: const TextStyle(
                color: Color(0xFF9E91B8),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        itemCount: _messages.length,
        itemBuilder: (_, i) {
          final msg = _messages[i];
          final mine = msg.senderId == currentUserId;
          final showDate =
              i == 0 || !_sameDay(_messages[i - 1].createdAt, msg.createdAt);

          return Column(
            children: [
              if (showDate) _DateDivider(dt: msg.createdAt, isArabic: isArabic),
              _MessageBubble(
                message: msg,
                mine: mine,
                isArabic: isArabic,
                onDelete: mine && !msg.isDeleted
                    ? () => _confirmDelete(msg)
                    : null,
                onTapOther: !mine ? _openTargetProfile : null,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInput(bool isArabic) {
    if (!_isMutualFriend && !_loading) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0718),
        border: Border(top: BorderSide(color: Color(0xFF1E1030))),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFF160B24),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF4A3470)),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: isArabic ? 'اكتب رسالة...' : 'Write a message...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF6E5A8A),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _sending
                    ? const Color(0xFF3A174F)
                    : const Color(0xFF8B26D9),
                shape: BoxShape.circle,
              ),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.isArabic,
    this.onDelete,
    this.onTapOther,
  });

  final PrivateMessage message;
  final bool mine;
  final bool isArabic;
  final VoidCallback? onDelete;
  final VoidCallback? onTapOther;

  @override
  Widget build(BuildContext context) {
    final time = _timeLabel(message.createdAt);
    final deleted = message.isDeleted;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        margin: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              textDirection: mine ? TextDirection.rtl : TextDirection.ltr,
              children: [
                // Delete button — visible only on own non-deleted messages
                if (mine && !deleted)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onDelete?.call();
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A0A2E),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(
                            0xFFFF5C7A,
                          ).withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        size: 14,
                        color: Color(0xFFFF5C7A),
                      ),
                    ),
                  ),
                Flexible(
                  child: GestureDetector(
                    onTap: mine ? null : onTapOther,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: deleted
                            ? const Color(0xFF1A1030)
                            : (mine
                                  ? const Color(0xFFF0C15A)
                                  : const Color(0xFF241638)),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: mine
                              ? const Radius.circular(18)
                              : const Radius.circular(4),
                          bottomRight: mine
                              ? const Radius.circular(4)
                              : const Radius.circular(18),
                        ),
                        border: deleted
                            ? Border.all(
                                color: const Color(
                                  0xFF3A2060,
                                ).withValues(alpha: 0.4),
                              )
                            : (mine
                                  ? null
                                  : Border.all(
                                      color: const Color(
                                        0xFF3A2060,
                                      ).withValues(alpha: 0.5),
                                    )),
                      ),
                      child: deleted
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.do_not_disturb_alt_rounded,
                                  size: 13,
                                  color: Color(0xFF6E5A8A),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isArabic
                                      ? 'تم حذف الرسالة'
                                      : 'Message deleted',
                                  style: const TextStyle(
                                    color: Color(0xFF6E5A8A),
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              message.body,
                              style: TextStyle(
                                color: mine
                                    ? const Color(0xFF160B26)
                                    : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                    ),
                  ),
                ), // Flexible
              ], // Row
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                time,
                style: const TextStyle(
                  color: Color(0xFF6E5A8A),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime? dt) {
    if (dt == null) return '';
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ---------------------------------------------------------------------------
// Date divider
// ---------------------------------------------------------------------------

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.dt, required this.isArabic});

  final DateTime? dt;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    if (dt == null) return const SizedBox.shrink();
    final l = dt!.toLocal();
    final label = '${l.day}/${l.month}/${l.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFF2A1840))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6E5A8A),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFF2A1840))),
        ],
      ),
    );
  }
}
