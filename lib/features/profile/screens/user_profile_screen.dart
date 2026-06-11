import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/vip_badge.dart';
import '../../../shared/widgets/vip_username.dart';
import '../../gifts/screens/gift_catalog_screen.dart';
import '../../messages/screens/private_chat_screen.dart';
import '../../social/screens/report_user_screen.dart';
import '../services/follow_service.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    required this.userId,
    required this.isArabic,
    super.key,
  });

  final String userId;
  final bool isArabic;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _followService = const FollowService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  bool _isFollowing = false;
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final [profileRaw, isFollowing] = await Future.wait<dynamic>([
        SupabaseService.requiredClient
            .from('profiles')
            .select('id, username, display_name, bio, avatar_url, vip_level, followers_count, following_count, gifts_received_count, visitors_count')
            .eq('id', widget.userId)
            .single(),
        _followService.isFollowing(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = profileRaw as Map<String, dynamic>;
        _isFollowing = isFollowing as bool;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    setState(() => _followBusy = true);
    try {
      if (_isFollowing) {
        await _followService.unfollowUser(widget.userId);
      } else {
        await _followService.followUser(widget.userId);
      }
      setState(() {
        _isFollowing = !_isFollowing;
        final p = _profile!;
        final current = (p['followers_count'] as int?) ?? 0;
        p['followers_count'] = _isFollowing ? current + 1 : (current - 1).clamp(0, 999999);
      });
    } catch (_) {}
    if (mounted) setState(() => _followBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

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
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B26D9)))
              : _error != null
                  ? _buildError(isArabic)
                  : _buildContent(isArabic),
        ),
      ),
    );
  }

  Widget _buildError(bool isArabic) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFFF5C7A), size: 36),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _load,
            child: Text(isArabic ? 'إعادة' : 'Retry',
                style: const TextStyle(color: Color(0xFFF0C15A))),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isArabic) {
    final p = _profile!;
    final displayName = p['display_name'] as String? ?? '';
    final username = p['username'] as String? ?? '';
    final bio = p['bio'] as String? ?? '';
    final avatarUrl = p['avatar_url'] as String?;
    final vipLevel = p['vip_level'] as int? ?? 0;
    final followers = p['followers_count'] as int? ?? 0;
    final following = p['following_count'] as int? ?? 0;
    final gifts = p['gifts_received_count'] as int? ?? 0;
    final visitors = p['visitors_count'] as int? ?? 0;

    final isSelf = SupabaseService.client?.auth.currentUser?.id == widget.userId;

    return Column(
      children: [
        // AppBar
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
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
              const Spacer(),
              if (!isSelf)
                IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportUserScreen(
                        targetUserId: widget.userId,
                        targetName: displayName,
                        isArabic: isArabic,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.flag_outlined, color: Color(0xFF9E91B8), size: 22),
                ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B26D9), Color(0xFF3A174F)],
                    ),
                    border: Border.all(color: const Color(0xFF8B26D9), width: 2),
                  ),
                  child: ClipOval(
                    child: avatarUrl != null
                        ? Image.network(avatarUrl, fit: BoxFit.cover,
                            errorBuilder: (context, e, st) => _avatarPlaceholder(displayName))
                        : _avatarPlaceholder(displayName),
                  ),
                ),
                const SizedBox(height: 12),

                // Name + VIP badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    VipUsername(
                      name: displayName,
                      vipLevel: vipLevel,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                    if (vipLevel > 0) ...[
                      const SizedBox(width: 6),
                      VipBadge(vipLevel: vipLevel, compact: true),
                    ],
                  ],
                ),

                if (username.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('@$username',
                      style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 13)),
                ],

                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    bio,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 14, height: 1.5),
                  ),
                ],

                const SizedBox(height: 20),

                // Stats row
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF160B24),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF6E3AA8).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      _stat(followers.toString(), isArabic ? 'متابعون' : 'Followers'),
                      _statDivider(),
                      _stat(following.toString(), isArabic ? 'يتابع' : 'Following'),
                      _statDivider(),
                      _stat(gifts.toString(), isArabic ? 'هدايا' : 'Gifts'),
                      _statDivider(),
                      _stat(visitors.toString(), isArabic ? 'زيارات' : 'Visits'),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Action buttons
                if (!isSelf) ...[
                  Row(
                    children: [
                      // Follow/Unfollow
                      Expanded(
                        child: _ActionButton(
                          label: _isFollowing
                              ? (isArabic ? 'إلغاء المتابعة' : 'Unfollow')
                              : (isArabic ? 'متابعة' : 'Follow'),
                          icon: _isFollowing ? Icons.person_remove_rounded : Icons.person_add_rounded,
                          color: _isFollowing ? const Color(0xFF4A3470) : const Color(0xFF8B26D9),
                          loading: _followBusy,
                          onTap: _toggleFollow,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Message
                      Expanded(
                        child: _ActionButton(
                          label: isArabic ? 'رسالة' : 'Message',
                          icon: Icons.chat_bubble_rounded,
                          color: const Color(0xFF1A3A55),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PrivateChatScreen(
                                targetUserId: widget.userId,
                                targetName: displayName,
                                targetAvatarUrl: avatarUrl,
                                isArabic: isArabic,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Gift button full width
                  _ActionButton(
                    label: isArabic ? 'إرسال هدية' : 'Send a gift',
                    icon: Icons.card_giftcard_rounded,
                    color: const Color(0xFF3A2A10),
                    textColor: const Color(0xFFF0C15A),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => GiftCatalogScreen(
                          isArabic: isArabic,
                          targetUserId: widget.userId,
                          targetName: displayName,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _avatarPlaceholder(String name) {
    return Container(
      color: const Color(0xFF241638),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 1, height: 28, color: const Color(0xFF2A1A40));
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.textColor = Colors.white,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: loading
            ? const Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: textColor, size: 18),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w800)),
                ],
              ),
      ),
    );
  }
}
