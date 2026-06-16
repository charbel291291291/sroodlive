import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import '../services/follow_service.dart';
import 'user_profile_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class FollowListScreen extends StatefulWidget {
  const FollowListScreen({
    required this.userId,
    required this.isFollowers,
    required this.isArabic,
    super.key,
  });

  final String userId;
  final bool isFollowers;
  final bool isArabic;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _UserEntry {
  final String id;
  final String displayName;
  final String? avatarUrl;
  bool isFollowingBack = false;

  _UserEntry({required this.id, required this.displayName, this.avatarUrl});
}

class _FollowListScreenState extends State<FollowListScreen> {
  final FollowService _followService = const FollowService();
  bool _isLoading = true;
  List<_UserEntry> _users = const [];
  final Map<String, bool> _pending = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null) {
        setState(() => _isLoading = false);
        return;
      }

      List<dynamic> rows;

      if (widget.isFollowers) {
        rows = await SupabaseService.requiredClient
            .from('user_follows')
            .select(
              'follower:profiles!user_follows_follower_id_fkey(id, display_name, avatar_url)',
            )
            .eq('following_id', widget.userId);
      } else {
        rows = await SupabaseService.requiredClient
            .from('user_follows')
            .select(
              'following:profiles!user_follows_following_id_fkey(id, display_name, avatar_url)',
            )
            .eq('follower_id', widget.userId);
      }

      final users = rows
          .map((row) {
            final profile =
                (widget.isFollowers ? row['follower'] : row['following'])
                    as Map?;
            return _UserEntry(
              id: profile?['id'] as String? ?? '',
              displayName: profile?['display_name'] as String? ?? 'Unknown',
              avatarUrl: profile?['avatar_url'] as String?,
            );
          })
          .where((u) => u.id.isNotEmpty && u.id != me)
          .toList();

      // Check which ones we follow back
      await Future.wait(
        users.map((u) async {
          u.isFollowingBack = await _followService.isFollowing(u.id);
        }),
      );

      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow(_UserEntry user) async {
    if (_pending[user.id] == true) return;
    setState(() => _pending[user.id] = true);

    try {
      if (user.isFollowingBack) {
        await _followService.unfollowUser(user.id);
      } else {
        await _followService.followUser(user.id);
      }
      if (!mounted) return;
      setState(() => user.isFollowingBack = !user.isFollowingBack);
    } catch (_) {}

    if (!mounted) return;
    setState(() => _pending.remove(user.id));
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    final title = isArabic
        ? (widget.isFollowers ? 'المتابعون' : 'يتابع')
        : (widget.isFollowers ? 'Followers' : 'Following');

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
              _buildHeader(title, isArabic),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF8B26D9),
                        ),
                      )
                    : _users.isEmpty
                    ? _buildEmpty(isArabic)
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: const Color(0xFF8B26D9),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: _users.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _UserTile(
                            user: _users[i],
                            isArabic: isArabic,
                            isPending: _pending[_users[i].id] == true,
                            onToggleFollow: () => _toggleFollow(_users[i]),
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

  Widget _buildHeader(String title, bool isArabic) {
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
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Text(
            '${_users.length}',
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontSize: 16,
              fontWeight: FontWeight.w800,
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
              Icons.people_outline_rounded,
              color: Color(0xFF9E91B8),
              size: 38,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isArabic
                ? (widget.isFollowers ? 'لا يوجد متابعون' : 'لا يتابع أحداً')
                : (widget.isFollowers
                      ? 'No followers yet'
                      : 'Not following anyone'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.isArabic,
    required this.isPending,
    required this.onToggleFollow,
  });

  final _UserEntry user;
  final bool isArabic;
  final bool isPending;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              UserProfileScreen(userId: user.id, isArabic: isArabic),
        ),
      ),
      child: Container(
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
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                user.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: isPending ? null : onToggleFollow,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: user.isFollowingBack
                      ? const Color(0xFF1B102B)
                      : const Color(0xFF8B26D9),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: user.isFollowingBack
                        ? const Color(0xFF4A3470)
                        : const Color(0xFF8B26D9),
                  ),
                ),
                child: isPending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        user.isFollowingBack
                            ? (isArabic ? 'إلغاء المتابعة' : 'Unfollow')
                            : (isArabic ? 'متابعة' : 'Follow'),
                        style: TextStyle(
                          color: user.isFollowingBack
                              ? const Color(0xFFBCAED6)
                              : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
