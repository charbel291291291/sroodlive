import 'package:flutter/material.dart';
import 'package:srood_live/shared/utils/error_utils.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class BlockUserScreen extends StatefulWidget {
  const BlockUserScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<BlockUserScreen> createState() => _BlockUserScreenState();
}

class _BlockedUser {
  final String id;
  final String blockedUserId;
  final String displayName;
  final String? avatarUrl;
  final DateTime blockedAt;

  const _BlockedUser({
    required this.id,
    required this.blockedUserId,
    required this.displayName,
    this.avatarUrl,
    required this.blockedAt,
  });
}

class _BlockUserScreenState extends State<BlockUserScreen> {
  bool _isLoading = true;
  List<_BlockedUser> _blocked = const [];
  final Map<String, bool> _unblockPending = {};

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
          .from('user_blocks')
          .select('''
            id, blocked_user_id, created_at,
            blocked:profiles!user_blocks_blocked_user_id_fkey(id, display_name, avatar_url)
          ''')
          .eq('blocker_id', user.id)
          .order('created_at', ascending: false);

      final items = (data as List).map((row) {
        final profile = row['blocked'] as Map?;
        return _BlockedUser(
          id: row['id'] as String,
          blockedUserId: row['blocked_user_id'] as String,
          displayName: profile?['display_name'] as String? ?? 'Unknown',
          avatarUrl: profile?['avatar_url'] as String?,
          blockedAt:
              DateTime.tryParse(row['created_at'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _blocked = items;
        _isLoading = false;
      });
    } catch (e, st) {
      debugError('BlockUserScreen._load', e, st);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unblock(_BlockedUser user) async {
    if (_unblockPending[user.id] == true) return;

    final isArabic = context.isArabic;
    final confirmed = await _showConfirmDialog(user.displayName, isArabic);
    if (!confirmed) return;

    setState(() => _unblockPending[user.id] = true);
    try {
      await SupabaseService.requiredClient
          .from('user_blocks')
          .delete()
          .eq('id', user.id);
      if (!mounted) return;
      setState(() => _blocked.removeWhere((b) => b.id == user.id));
    } catch (e) {
      if (!mounted) return;
      SroodToast.show(context, 'Error: $e', type: SroodToastType.error);
    } finally {
      if (mounted) setState(() => _unblockPending.remove(user.id));
    }
  }

  Future<bool> _showConfirmDialog(String name, bool isArabic) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1B102B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Color(0xFF4A3470)),
            ),
            title: Text(
              isArabic ? 'إلغاء الحظر' : 'Unblock user',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              isArabic
                  ? 'هل تريد إلغاء حظر $name؟'
                  : 'Do you want to unblock $name?',
              style: const TextStyle(color: Color(0xFFBCAED6)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  isArabic ? 'إلغاء' : 'Cancel',
                  style: const TextStyle(color: Color(0xFF9E91B8)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  isArabic ? 'إلغاء الحظر' : 'Unblock',
                  style: const TextStyle(
                    color: Color(0xFF63E6A1),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

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
              _buildHeader(isArabic),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF8B26D9),
                        ),
                      )
                    : _blocked.isEmpty
                    ? _buildEmpty(isArabic)
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: const Color(0xFF8B26D9),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: _blocked.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _BlockedUserTile(
                            user: _blocked[i],
                            isArabic: isArabic,
                            isPending: _unblockPending[_blocked[i].id] == true,
                            onUnblock: () => _unblock(_blocked[i]),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 4),
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
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'المستخدمون المحظورون' : 'Blocked users',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  isArabic
                      ? '${_blocked.length} مستخدم محظور'
                      : '${_blocked.length} blocked',
                  style: const TextStyle(
                    color: Color(0xFF9E91B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
              Icons.block_rounded,
              color: Color(0xFF9E91B8),
              size: 38,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isArabic ? 'لا يوجد مستخدمون محظورون' : 'No blocked users',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'المستخدمون الذين تحظرهم يظهرون هنا'
                : 'Users you block will appear here',
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

class _BlockedUserTile extends StatelessWidget {
  const _BlockedUserTile({
    required this.user,
    required this.isArabic,
    required this.isPending,
    required this.onUnblock,
  });

  final _BlockedUser user;
  final bool isArabic;
  final bool isPending;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF6E3AA8).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        textDirection: dir,
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF241638),
                backgroundImage: user.avatarUrl != null
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? Text(
                        user.displayName.isNotEmpty
                            ? user.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.block_rounded,
                    color: Color(0xFFFF6B8A),
                    size: 16,
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
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isArabic
                      ? 'محظور منذ ${_dateLabel(user.blockedAt)}'
                      : 'Blocked ${_dateLabel(user.blockedAt)}',
                  style: const TextStyle(
                    color: Color(0xFF9E91B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: isPending ? null : onUnblock,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1B102B),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF4A3470)),
              ),
              child: isPending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF63E6A1),
                      ),
                    )
                  : Text(
                      isArabic ? 'إلغاء الحظر' : 'Unblock',
                      style: const TextStyle(
                        color: Color(0xFF63E6A1),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// Standalone block action — call this from any profile/user tile
Future<void> blockUser({
  required BuildContext context,
  required String targetUserId,
  required String targetName,
  required bool isArabic,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1B102B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFF4A3470)),
      ),
      title: Text(
        isArabic ? 'حظر المستخدم' : 'Block user',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: Text(
        isArabic
            ? 'هل تريد حظر $targetName؟ لن يتمكن من رؤية ملفك أو التواصل معك.'
            : 'Block $targetName? They won\'t be able to see your profile or contact you.',
        style: const TextStyle(color: Color(0xFFBCAED6), height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            isArabic ? 'إلغاء' : 'Cancel',
            style: const TextStyle(color: Color(0xFF9E91B8)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            isArabic ? 'حظر' : 'Block',
            style: const TextStyle(
              color: Color(0xFFFF6B8A),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    final me = SupabaseService.requiredClient.auth.currentUser;
    if (me == null) return;
    await SupabaseService.requiredClient.from('user_blocks').upsert({
      'blocker_id': me.id,
      'blocked_user_id': targetUserId,
    });
    if (!context.mounted) return;
    SroodToast.show(context, isArabic ? 'تم حظر $targetName' : '$targetName blocked', type: SroodToastType.success);
  } catch (e) {
    if (!context.mounted) return;
    SroodToast.show(context, 'Error: $e', type: SroodToastType.error);
  }
}
