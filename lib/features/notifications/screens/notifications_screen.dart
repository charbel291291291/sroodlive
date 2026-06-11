import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../../gifts/screens/gift_history_screen.dart';
import '../../rooms/models/room.dart';
import '../../rooms/screens/room_details_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final String? actorName;
  final String? actorAvatarUrl;
  final String? actorId;
  final String? targetId;

  const _AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.actorName,
    this.actorAvatarUrl,
    this.actorId,
    this.targetId,
  });
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  List<_AppNotification> _notifications = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final user = SupabaseService.requiredClient.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final data = await SupabaseService.requiredClient
          .from('notifications')
          .select('id, type, title, body, is_read, created_at, actor_name, actor_avatar_url, actor_id, target_id')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);

      final items = (data as List).map((row) {
        return _AppNotification(
          id: row['id'] as String,
          type: row['type'] as String? ?? 'system',
          title: row['title'] as String? ?? '',
          body: row['body'] as String? ?? '',
          isRead: row['is_read'] as bool? ?? false,
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
          actorName: row['actor_name'] as String?,
          actorAvatarUrl: row['actor_avatar_url'] as String?,
          actorId: row['actor_id'] as String?,
          targetId: row['target_id'] as String?,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _notifications = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      final user = SupabaseService.requiredClient.auth.currentUser;
      if (user == null) return;
      await SupabaseService.requiredClient
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((n) => _AppNotification(
                  id: n.id,
                  type: n.type,
                  title: n.title,
                  body: n.body,
                  isRead: true,
                  createdAt: n.createdAt,
                  actorName: n.actorName,
                  actorAvatarUrl: n.actorAvatarUrl,
                  actorId: n.actorId,
                  targetId: n.targetId,
                ))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _markRead(String id) async {
    try {
      await SupabaseService.requiredClient
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
    } catch (_) {}
  }

  void _navigateFor(_AppNotification n) {
    switch (n.type) {
      case 'follow':
        if (n.actorId != null) {
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => UserProfileScreen(userId: n.actorId!, isArabic: widget.isArabic),
          ));
        }
      case 'gift':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => GiftHistoryScreen(isArabic: widget.isArabic),
        ));
      case 'room':
        if (n.targetId != null) _openRoom(n.targetId!);
      default:
        break;
    }
  }

  Future<void> _openRoom(String roomId) async {
    try {
      final row = await SupabaseService.requiredClient
          .from('rooms')
          .select('id, owner_id, name, description, language, livekit_room_name, max_seats, is_private, is_locked, is_closed, created_at')
          .eq('id', roomId)
          .single();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RoomDetailsScreen(room: Room.fromJson(row), isArabic: widget.isArabic),
      ));
    } catch (_) {}
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'follow' => Icons.person_add_rounded,
      'gift' => Icons.card_giftcard_rounded,
      'like' => Icons.favorite_rounded,
      'comment' => Icons.comment_rounded,
      'call' => Icons.call_rounded,
      'room' => Icons.meeting_room_rounded,
      'wallet' => Icons.account_balance_wallet_rounded,
      'badge' => Icons.military_tech_rounded,
      'level' => Icons.trending_up_rounded,
      _ => Icons.notifications_rounded,
    };
  }

  Color _colorForType(String type) {
    return switch (type) {
      'follow' => const Color(0xFF8B26D9),
      'gift' => const Color(0xFFF0C15A),
      'like' => const Color(0xFFFF4D6D),
      'wallet' => const Color(0xFF63E6A1),
      'badge' || 'level' => const Color(0xFFF0C15A),
      _ => const Color(0xFF9E91B8),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final unreadCount = _notifications.where((n) => !n.isRead).length;

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
              _buildHeader(isArabic, unreadCount),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF8B26D9),
                        ),
                      )
                    : _notifications.isEmpty
                        ? _buildEmpty(isArabic)
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: const Color(0xFF8B26D9),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                              itemCount: _notifications.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final n = _notifications[i];
                                return _NotificationTile(
                                  notification: n,
                                  isArabic: isArabic,
                                  icon: _iconForType(n.type),
                                  iconColor: _colorForType(n.type),
                                  onTap: () {
                                    if (!n.isRead) {
                                      _markRead(n.id);
                                      setState(() {
                                        _notifications[i] = _AppNotification(
                                          id: n.id,
                                          type: n.type,
                                          title: n.title,
                                          body: n.body,
                                          isRead: true,
                                          createdAt: n.createdAt,
                                          actorName: n.actorName,
                                          actorAvatarUrl: n.actorAvatarUrl,
                                          actorId: n.actorId,
                                          targetId: n.targetId,
                                        );
                                      });
                                    }
                                    _navigateFor(n);
                                  },
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic, int unreadCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 8, 4),
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
          const SizedBox(width: 4),
          Expanded(
            child: Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Text(
                  isArabic ? 'الإشعارات' : 'Notifications',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B26D9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                isArabic ? 'قراءة الكل' : 'Mark all read',
                style: const TextStyle(
                  color: Color(0xFFF0C15A),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isArabic) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1B102B),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF4A3470)),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: Color(0xFF9E91B8),
              size: 38,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isArabic ? 'لا توجد إشعارات' : 'No notifications',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic ? 'ستظهر إشعاراتك هنا' : 'Your notifications will appear here',
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.isArabic,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final _AppNotification notification;
  final bool isArabic;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final isUnread = !notification.isRead;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUnread
              ? const Color(0xFF1D0D30)
              : const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUnread
                ? const Color(0xFF8B26D9).withValues(alpha: 0.5)
                : const Color(0xFF6E3AA8).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          textDirection: dir,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                notification.actorAvatarUrl != null
                    ? CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFF241638),
                        backgroundImage:
                            NetworkImage(notification.actorAvatarUrl!),
                      )
                    : Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: iconColor, size: 22),
                      ),
                if (isUnread)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF8B26D9),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: isUnread ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  if (notification.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFBCAED6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(notification.createdAt, isArabic),
                    style: const TextStyle(
                      color: Color(0xFF6E5A8A),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

  String _timeAgo(DateTime dt, bool isArabic) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return isArabic ? 'الآن' : 'Just now';
    if (diff.inMinutes < 60) {
      return isArabic ? 'منذ ${diff.inMinutes} دقيقة' : '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return isArabic ? 'منذ ${diff.inHours} ساعة' : '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return isArabic ? 'منذ ${diff.inDays} يوم' : '${diff.inDays}d ago';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
