import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import '../services/follow_service.dart';
import 'user_profile_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

/// Shows a followers / following / friends list for [userId].
/// [kind] is one of 'followers', 'following', 'friends'.
class FollowListScreen extends StatefulWidget {
  const FollowListScreen({
    required this.userId,
    required this.kind,
    required this.isArabic,
    super.key,
  });

  final String userId;
  final String kind; // 'followers' | 'following' | 'friends'
  final bool isArabic;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  final FollowService _followService = const FollowService();
  bool _isLoading = true;
  bool _hasError = false;
  List<FollowUser> _users = const [];
  final Map<String, bool> _pending = {};
  String? _meId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      _meId = me;
      if (me == null) {
        setState(() => _isLoading = false);
        return;
      }
      // Counts and list share the same source: the get_follow_list RPC over
      // user_follows. viewer_follows comes back per row, so no N+1 queries.
      final users = await _followService.getFollowList(widget.userId, widget.kind);
      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _toggleFollow(FollowUser user) async {
    if (_pending[user.id] == true) return;
    setState(() => _pending[user.id] = true);
    try {
      if (user.viewerFollows) {
        await _followService.unfollowUser(user.id);
      } else {
        await _followService.followUser(user.id);
      }
      if (!mounted) return;
      setState(() => user.viewerFollows = !user.viewerFollows);
    } catch (_) {
      // leave state unchanged on failure
    }
    if (!mounted) return;
    setState(() => _pending.remove(user.id));
  }

  String get _title {
    final ar = widget.isArabic;
    switch (widget.kind) {
      case 'followers':
        return ar ? 'المتابعون' : 'Followers';
      case 'friends':
        return ar ? 'الأصدقاء' : 'Friends';
      default:
        return ar ? 'يتابع' : 'Following';
    }
  }

  String get _emptyText {
    final ar = widget.isArabic;
    switch (widget.kind) {
      case 'followers':
        return ar ? 'لا يوجد متابعون' : 'No followers yet';
      case 'friends':
        return ar ? 'لا يوجد أصدقاء' : 'No friends yet';
      default:
        return ar ? 'لا يتابع أحداً' : 'Not following anyone';
    }
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
              _buildHeader(_title, isArabic),
              Expanded(child: _buildBody(isArabic)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isArabic) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B26D9)),
      );
    }
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFFF6B8A), size: 38),
            const SizedBox(height: 12),
            Text(
              isArabic ? 'تعذّر تحميل القائمة' : 'Could not load the list',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: Text(isArabic ? 'إعادة المحاولة' : 'Retry',
                  style: const TextStyle(color: Color(0xFFF0C15A))),
            ),
          ],
        ),
      );
    }
    if (_users.isEmpty) return _buildEmpty(isArabic);
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF8B26D9),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: _users.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _UserTile(
          user: _users[i],
          isArabic: isArabic,
          isSelf: _users[i].id == _meId,
          isPending: _pending[_users[i].id] == true,
          onToggleFollow: () => _toggleFollow(_users[i]),
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
          if (!_isLoading && !_hasError)
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
            child: const Icon(Icons.people_outline_rounded,
                color: Color(0xFF9E91B8), size: 38),
          ),
          const SizedBox(height: 16),
          Text(
            _emptyText,
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
    required this.isSelf,
    required this.isPending,
    required this.onToggleFollow,
  });

  final FollowUser user;
  final bool isArabic;
  final bool isSelf;
  final bool isPending;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen(userId: user.id, isArabic: isArabic),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF6E3AA8).withValues(alpha: 0.4)),
        ),
        child: Row(
          textDirection: dir,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFF241638),
              backgroundImage:
                  user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
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
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Row(
                    textDirection: dir,
                    children: [
                      Flexible(
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
                      if (user.gender != null && _genderColor(user.gender) != null) ...[
                        const SizedBox(width: 6),
                        _GenderChip(gender: user.gender!),
                      ],
                      if (user.vipLevel > 0) ...[
                        const SizedBox(width: 6),
                        _VipChip(level: user.vipLevel),
                      ],
                    ],
                  ),
                  if (user.publicUserId != null &&
                      user.publicUserId!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'ID: ${user.publicUserId}',
                      style: const TextStyle(
                        color: Color(0xFF9E91B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // No follow button on your own row.
            if (!isSelf) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: isPending ? null : onToggleFollow,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: user.viewerFollows
                        ? const Color(0xFF1B102B)
                        : const Color(0xFF8B26D9),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: user.viewerFollows
                          ? const Color(0xFF4A3470)
                          : const Color(0xFF8B26D9),
                    ),
                  ),
                  child: isPending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          user.viewerFollows
                              ? (isArabic ? 'إلغاء المتابعة' : 'Following')
                              : (isArabic ? 'متابعة' : 'Follow'),
                          style: TextStyle(
                            color: user.viewerFollows
                                ? const Color(0xFFBCAED6)
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color? _genderColor(String? gender) {
    switch (gender?.toLowerCase()) {
      case 'male':
        return const Color(0xFF3B9BFF); // blue
      case 'female':
        return const Color(0xFFFF5C8A); // rose/red
      default:
        return null;
    }
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({required this.gender});
  final String gender;

  @override
  Widget build(BuildContext context) {
    final male = gender.toLowerCase() == 'male';
    final color = male ? const Color(0xFF3B9BFF) : const Color(0xFFFF5C8A);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Icon(
        male ? Icons.male_rounded : Icons.female_rounded,
        size: 12,
        color: color,
      ),
    );
  }
}

class _VipChip extends StatelessWidget {
  const _VipChip({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF0C15A).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF0C15A).withValues(alpha: 0.5)),
      ),
      child: Text(
        'VIP $level',
        style: const TextStyle(
          color: Color(0xFFF0C15A),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
