import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/avatar_with_frame.dart';
import '../models/private_message.dart';
import '../services/private_message_service.dart';

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
  final String targetName;
  final String? targetAvatarUrl;
  final String? targetFrameKey;
  final bool isArabic;

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final PrivateMessageService _service = const PrivateMessageService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  RealtimeChannel? _channel;

  bool _loading = true;
  bool _sending = false;
  String? _conversationId;
  String? _error;
  List<PrivateMessage> _messages = const [];

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

  Future<void> _load() async {
    try {
      final cid = await _service.getOrCreateConversation(widget.targetUserId);
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _subscribe(String cid) {
    _channel = SupabaseService.requiredClient
        .channel('chat_screen_$cid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
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

  Future<void> _send() async {
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
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
          AvatarWithFrame(
            imageUrl: widget.targetAvatarUrl,
            radius: 20,
            frameKey: widget.targetFrameKey,
            compact: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.targetName,
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
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.call_rounded,
              color: Color(0xFFF0C15A),
              size: 22,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.videocam_rounded,
              color: Color(0xFFF0C15A),
              size: 22,
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
              _MessageBubble(message: msg, mine: mine, isArabic: isArabic),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInput(bool isArabic) {
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.isArabic,
  });

  final PrivateMessage message;
  final bool mine;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final time = _timeLabel(message.createdAt);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        margin: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? const Color(0xFFF0C15A) : const Color(0xFF241638),
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
                border: mine
                    ? null
                    : Border.all(
                        color: const Color(0xFF3A2060).withValues(alpha: 0.5),
                      ),
              ),
              child: Text(
                message.body,
                style: TextStyle(
                  color: mine ? const Color(0xFF160B26) : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
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
