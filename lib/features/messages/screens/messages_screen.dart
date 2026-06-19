import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/vip_framed_avatar.dart';
import '../../../shared/widgets/vip_username.dart';
import '../models/private_conversation.dart';
import '../services/private_message_service.dart';
import 'private_chat_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    required this.isArabic,
    this.onUnreadChanged,
    super.key,
  });

  final bool isArabic;

  /// Called whenever the total unread count changes. Used to update the
  /// nav-bar badge in [HomeScreen].
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with AutomaticKeepAliveClientMixin {
  final _service = const PrivateMessageService();

  List<PrivateConversationPreview> _conversations = [];
  bool _loading = true;
  String? _error;
  RealtimeChannel? _inboxChannel;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToIncoming();
  }

  @override
  void dispose() {
    _inboxChannel?.unsubscribe();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
    }

    try {
      final convos = await _service.fetchConversations();
      if (!mounted) return;

      final totalUnread = convos.fold(0, (sum, c) => sum + c.unreadCount);
      widget.onUnreadChanged?.call(totalUnread);

      setState(() {
        _conversations = convos;
        _loading = false;
        _error = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  void _subscribeToIncoming() {
    final userId = SupabaseService.client?.auth.currentUser?.id;
    if (userId == null) return;

    _inboxChannel = SupabaseService.requiredClient
        .channel('inbox_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'private_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: userId,
          ),
          callback: (_) {
            if (!mounted) return;
            unawaited(_load(silent: true));
          },
        )
        .subscribe();
  }

  // ---------------------------------------------------------------------------
  // Conversation actions (long-press)
  // ---------------------------------------------------------------------------

  Future<void> _showConversationActions(
    PrivateConversationPreview convo,
  ) async {
    final isArabic = context.isArabic;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ConversationActionsSheet(
        convo: convo,
        isArabic: isArabic,
        onPin: () async {
          Navigator.of(context).pop();
          await _service.pinConversation(convo.conversationId);
          if (mounted) unawaited(_load(silent: true));
        },
        onUnpin: () async {
          Navigator.of(context).pop();
          await _service.unpinConversation(convo.conversationId);
          if (mounted) unawaited(_load(silent: true));
        },
        onArchive: () async {
          Navigator.of(context).pop();
          await _service.archiveConversation(convo.conversationId);
          if (mounted) unawaited(_load(silent: true));
        },
        onDelete: () async {
          Navigator.of(context).pop();
          final confirmed = await _confirmDelete(convo, isArabic);
          if (!confirmed) return;
          await _service.deleteConversationForMe(convo.conversationId);
          if (mounted) unawaited(_load(silent: true));
        },
      ),
    );
  }

  Future<bool> _confirmDelete(
    PrivateConversationPreview convo,
    bool isArabic,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B102A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isArabic ? 'حذف المحادثة' : 'Delete conversation',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.none,
          ),
        ),
        content: Text(
          isArabic
              ? 'سيتم إخفاء هذه المحادثة عنك فقط. هل تريد المتابعة؟'
              : 'This will hide the conversation only for you. Continue?',
          style: const TextStyle(
            color: Color(0xFFD8CFEA),
            decoration: TextDecoration.none,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              isArabic ? 'إلغاء' : 'Cancel',
              style: const TextStyle(color: Color(0xFF7A6890)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              isArabic ? 'حذف' : 'Delete',
              style: const TextStyle(
                color: Color(0xFFFF5C7A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Open chat
  // ---------------------------------------------------------------------------

  Future<void> _openChat(PrivateConversationPreview convo) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateChatScreen(
          targetUserId: convo.otherUserId,
          targetName: convo.otherNickname,
          targetAvatarUrl: convo.otherAvatarUrl,
          targetFrameKey: convo.otherFrameId,
          isArabic: context.isArabic,
        ),
      ),
    );
    // Refresh when chat closes (unread counts may have changed).
    if (mounted) unawaited(_load(silent: true));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(isArabic: context.isArabic),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFF0C15A),
          strokeWidth: 2.5,
        ),
      );
    }

    if (_error != null) {
      return _ErrorState(
        message: _error!,
        isArabic: context.isArabic,
        onRetry: _load,
      );
    }

    if (_conversations.isEmpty) {
      return _EmptyState(isArabic: context.isArabic);
    }

    return RefreshIndicator(
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _conversations.length,
        separatorBuilder: (_, _) => const Divider(
          color: Color(0xFF1E1030),
          height: 1,
          indent: 76,
          endIndent: 16,
        ),
        itemBuilder: (context, index) {
          final convo = _conversations[index];
          return _ConversationTile(
            convo: convo,
            isArabic: context.isArabic,
            onTap: () => _openChat(convo),
            onLongPress: () => _showConversationActions(convo),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Text(
            isArabic ? 'الرسائل' : 'Messages',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              decoration: TextDecoration.none,
            ),
          ),
          const Spacer(),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF1B102A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3D2260), width: 1),
            ),
            child: const Icon(
              Icons.edit_rounded,
              color: Color(0xFFD8CFEA),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation tile
// ---------------------------------------------------------------------------

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.convo,
    required this.isArabic,
    required this.onTap,
    this.onLongPress,
  });

  final PrivateConversationPreview convo;
  final bool isArabic;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final hasUnread = convo.unreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: const Color(0xFF8B26D9).withValues(alpha: 0.12),
        highlightColor: const Color(0xFF8B26D9).withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              // Avatar with optional VIP frame
              VipFramedAvatar(
                size: 52,
                imageUrl: convo.otherAvatarUrl,
                vipLevel: convo.otherVipLevel,
              ),
              const SizedBox(width: 12),

              // Name + last message
              Expanded(
                child: Column(
                  crossAxisAlignment: isArabic
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Name row: username + timestamp
                    Row(
                      textDirection: isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      children: [
                        Expanded(
                          child: VipUsername(
                            name: convo.otherNickname,
                            vipLevel: convo.otherVipLevel,
                            fontSize: 15,
                            fontWeight: hasUnread
                                ? FontWeight.w900
                                : FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (convo.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.push_pin_rounded,
                              color: const Color(0xFFF0C15A).withValues(alpha: 0.75),
                              size: 13,
                            ),
                          ),
                        Text(
                          _formatTime(convo.lastMessageAt, isArabic),
                          style: TextStyle(
                            color: hasUnread
                                ? const Color(0xFFF0C15A)
                                : const Color(0xFF7A6890),
                            fontSize: 11,
                            fontWeight: hasUnread
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),

                    // Last message row: preview + unread badge
                    Row(
                      textDirection: isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      children: [
                        Expanded(
                          child: Text(
                            convo.lastMessage ??
                                (isArabic
                                    ? 'ابدأ المحادثة...'
                                    : 'Start the conversation...'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: isArabic
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            style: TextStyle(
                              color: hasUnread
                                  ? const Color(0xFFD8CFEA)
                                  : const Color(0xFF7A6890),
                              fontSize: 13,
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          _UnreadBadge(count: convo.unreadCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? dt, bool isArabic) {
    if (dt == null) return '';
    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = now.difference(local);

    if (diff.inSeconds < 60) return isArabic ? 'الآن' : 'now';
    if (diff.inMinutes < 60) {
      return isArabic ? '${diff.inMinutes}د' : '${diff.inMinutes}m';
    }
    if (diff.inHours < 24) {
      return isArabic ? '${diff.inHours}س' : '${diff.inHours}h';
    }
    if (diff.inDays < 7) {
      return isArabic ? '${diff.inDays}ي' : '${diff.inDays}d';
    }
    return '${local.day}/${local.month}';
  }
}

// ---------------------------------------------------------------------------
// Unread badge
// ---------------------------------------------------------------------------

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';

    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4D6D),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF2D1247), Color(0xFF12091D)],
                ),
                border: Border.all(
                  color: const Color(0xFF5A3A86).withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFF8B26D9),
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isArabic ? 'لا رسائل بعد' : 'No messages yet',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'ابدأ محادثة من خلال زيارة ملف أحد المستخدمين'
                  : 'Start a conversation by visiting\nsomeone\'s profile',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF7A6890),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.isArabic,
    required this.onRetry,
  });

  final String message;
  final bool isArabic;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFF5C7A),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(
                isArabic ? 'إعادة المحاولة' : 'Retry',
                style: const TextStyle(color: Color(0xFFF0C15A)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation actions bottom sheet
// ---------------------------------------------------------------------------

class _ConversationActionsSheet extends StatelessWidget {
  const _ConversationActionsSheet({
    required this.convo,
    required this.isArabic,
    required this.onPin,
    required this.onUnpin,
    required this.onArchive,
    required this.onDelete,
  });

  final PrivateConversationPreview convo;
  final bool isArabic;
  final VoidCallback onPin;
  final VoidCallback onUnpin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1B102A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        0,
        12,
        0,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF3D2260),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Name header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              convo.otherNickname,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Divider(
            color: const Color(0xFF3D2260).withValues(alpha: 0.6),
            height: 24,
          ),

          // Pin / Unpin
          _ActionTile(
            icon: Icons.push_pin_rounded,
            label: convo.isPinned
                ? (isArabic ? 'إلغاء التثبيت' : 'Unpin')
                : (isArabic ? 'تثبيت المحادثة' : 'Pin'),
            iconColor: const Color(0xFFF0C15A),
            onTap: convo.isPinned ? onUnpin : onPin,
          ),

          // Archive
          _ActionTile(
            icon: Icons.archive_rounded,
            label: isArabic ? 'أرشفة المحادثة' : 'Archive',
            iconColor: const Color(0xFF8B8BFF),
            onTap: onArchive,
          ),

          // Delete
          _ActionTile(
            icon: Icons.delete_outline_rounded,
            label: isArabic ? 'حذف المحادثة' : 'Delete',
            iconColor: const Color(0xFFFF5C7A),
            onTap: onDelete,
          ),

          // Cancel
          const SizedBox(height: 4),
          Divider(
            color: const Color(0xFF3D2260).withValues(alpha: 0.6),
            height: 1,
          ),
          _ActionTile(
            icon: Icons.close_rounded,
            label: isArabic ? 'إغلاق' : 'Cancel',
            iconColor: const Color(0xFF7A6890),
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
