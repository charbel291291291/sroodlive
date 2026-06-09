import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/avatar_with_frame.dart';
import '../models/private_message.dart';
import '../services/private_message_service.dart';

class PrivateChatSheet extends StatefulWidget {
  const PrivateChatSheet({
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
  State<PrivateChatSheet> createState() => _PrivateChatSheetState();
}

class _PrivateChatSheetState extends State<PrivateChatSheet> {
  final PrivateMessageService _service = const PrivateMessageService();
  final TextEditingController _controller = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _messagesChannel;

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
    _messagesChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final conversationId = await _service.getOrCreateConversation(
        widget.targetUserId,
      );
      final messages = await _service.fetchMessages(conversationId);
      // Mark all received messages in this conversation as read.
      unawaited(_service.markConversationRead(conversationId));

      if (!mounted) return;

      setState(() {
        _conversationId = conversationId;
        _messages = messages;
        _loading = false;
        _error = null;
      });

      // Scroll to the latest message after the list renders.
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

      // Subscribe to new messages in real time.
      _subscribeToMessages(conversationId);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _subscribeToMessages(String conversationId) {
    _messagesChannel = SupabaseService.requiredClient
        .channel('chat_$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'private_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) {
            if (!mounted) return;
            unawaited(_reloadMessages());
          },
        )
        .subscribe();
  }

  Future<void> _reloadMessages() async {
    final cid = _conversationId;
    if (cid == null) return;
    final messages = await _service.fetchMessages(cid);
    unawaited(_service.markConversationRead(cid));
    if (!mounted) return;
    setState(() => _messages = messages);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients &&
        _scrollController.position.hasContentDimensions) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) {
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await _service.sendMessage(targetUserId: widget.targetUserId, body: body);
      _controller.clear();

      final conversationId = _conversationId;
      if (conversationId != null) {
        final messages = await _service.fetchMessages(conversationId);
        if (mounted) {
          setState(() => _messages = messages);
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      } else {
        await _load();
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = SupabaseService.requiredClient.auth.currentUser?.id;
    final maxWidth = MediaQuery.sizeOf(context).width >= 600
        ? 460.0
        : double.infinity;

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            height: MediaQuery.sizeOf(context).height * 0.72,
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF100718),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Row(
                  textDirection: widget.isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    AvatarWithFrame(
                      imageUrl: widget.targetAvatarUrl,
                      radius: 22,
                      frameKey: widget.targetFrameKey,
                      compact: true,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.targetName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFFF5C7A)),
                          ),
                        )
                      : _messages.isEmpty
                      ? Center(
                          child: Text(
                            widget.isArabic
                                ? '\u0627\u0628\u062f\u0623 \u0627\u0644\u0645\u062d\u0627\u062f\u062b\u0629'
                                : 'Start the conversation',
                            style: const TextStyle(color: Color(0xFFD8CFEA)),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final mine = message.senderId == currentUserId;

                            return Align(
                              alignment: mine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: mine
                                      ? const Color(0xFFF0C15A)
                                      : const Color(0xFF241638),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text(
                                  message.body,
                                  style: TextStyle(
                                    color: mine
                                        ? const Color(0xFF160B26)
                                        : Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 10),
                Row(
                  textDirection: widget.isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textDirection: widget.isArabic
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: widget.isArabic
                              ? '\u0627\u0643\u062a\u0628 \u0631\u0633\u0627\u0644\u0629...'
                              : 'Write a message...',
                          filled: true,
                          fillColor: const Color(0xFF1B102A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
