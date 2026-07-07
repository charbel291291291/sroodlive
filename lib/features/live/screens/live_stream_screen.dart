import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({
    required this.roomId,
    required this.roomName,
    required this.hostName,
    required this.hostAvatarUrl,
    required this.isHost,
    required this.isArabic,
    super.key,
  });

  final String roomId;
  final String roomName;
  final String hostName;
  final String? hostAvatarUrl;
  final bool isHost;
  final bool isArabic;

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveComment {
  final String userId;
  final String userName;
  final String text;
  final DateTime sentAt;

  const _LiveComment({
    required this.userId,
    required this.userName,
    required this.text,
    required this.sentAt,
  });
}

class _LiveStreamScreenState extends State<LiveStreamScreen>
    with TickerProviderStateMixin {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _pulseController;

  bool _isConnecting = true;
  bool _isMuted = false;
  bool _isCameraOff = false;
  final bool _showComments = true;
  int _viewerCount = 0;
  int _likeCount = 0;
  Duration _duration = Duration.zero;
  Timer? _durationTimer;
  List<_LiveComment> _comments = const [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _viewerCount = 42;
      });
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _duration += const Duration(seconds: 1));
      });
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    _commentController.clear();
    final me = SupabaseService.requiredClient.auth.currentUser;
    if (me == null) return;
    setState(() {
      _comments = [
        ..._comments,
        _LiveComment(
          userId: me.id,
          userName: me.userMetadata?['display_name'] as String? ?? 'You',
          text: text,
          sentAt: DateTime.now(),
        ),
      ];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
    try {
      await SupabaseService.requiredClient.from('live_comments').insert({
        'room_id': widget.roomId,
        'user_id': me.id,
        'text': text,
      });
    } catch (_) {}
  }

  Future<void> _endStream() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF160B24),
        title: Text(
          context.isArabic ? 'إنهاء البث' : 'End stream',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          context.isArabic
              ? 'هل تريد إنهاء البث المباشر؟'
              : 'Are you sure you want to end the live stream?',
          style: const TextStyle(color: Color(0xFFBCAED6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.isArabic ? 'إلغاء' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.isArabic ? 'إنهاء' : 'End',
              style: const TextStyle(color: Color(0xFFFF4D6D)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await SupabaseService.requiredClient
          .from('rooms')
          .update({'is_live': false})
          .eq('id', widget.roomId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildVideoBackground(),
          if (_isConnecting) _buildConnecting(isArabic),
          if (!_isConnecting) ...[
            _buildTopOverlay(isArabic),
            if (widget.isHost) _buildHostControls(isArabic),
            _buildBottomSection(isArabic),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoBackground() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0415), Color(0xFF050208)],
        ),
      ),
      child: _isCameraOff
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 72,
                    backgroundColor: const Color(0xFF241638),
                    backgroundImage: widget.hostAvatarUrl != null
                        ? NetworkImage(widget.hostAvatarUrl!)
                        : null,
                    child: widget.hostAvatarUrl == null
                        ? Text(
                            widget.hostName.isNotEmpty
                                ? widget.hostName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.hostName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.isArabic ? 'الكاميرا مغلقة' : 'Camera off',
                    style: const TextStyle(
                      color: Color(0xFF9E91B8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 72,
                    backgroundColor: const Color(0xFF241638),
                    backgroundImage: widget.hostAvatarUrl != null
                        ? NetworkImage(widget.hostAvatarUrl!)
                        : null,
                    child: widget.hostAvatarUrl == null
                        ? Text(
                            widget.hostName.isNotEmpty
                                ? widget.hostName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.hostName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildConnecting(bool isArabic) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, _) => Transform.scale(
                scale: 1.0 + _pulseController.value * 0.18,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.3),
                    border: Border.all(
                      color: const Color(0xFF8B26D9),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.live_tv_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isArabic ? 'جارٍ الاتصال...' : 'Connecting...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopOverlay(bool isArabic) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            child: Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isArabic
                          ? Icons.arrow_forward_rounded
                          : Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _LiveBadge(duration: _fmt(_duration)),
                const SizedBox(width: 8),
                _ViewerBadge(count: _viewerCount),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHostControls(bool isArabic) {
    return Positioned(
      right: isArabic ? null : 12,
      left: isArabic ? 12 : null,
      top: 0,
      bottom: 0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CircleControl(
            icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            active: _isMuted,
            onTap: () => setState(() => _isMuted = !_isMuted),
          ),
          const SizedBox(height: 12),
          _CircleControl(
            icon: _isCameraOff
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            active: _isCameraOff,
            onTap: () => setState(() => _isCameraOff = !_isCameraOff),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection(bool isArabic) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showComments) _buildCommentsList(isArabic),
          _buildBottomBar(isArabic),
        ],
      ),
    );
  }

  Widget _buildCommentsList(bool isArabic) {
    if (_comments.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 180,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _comments.length,
        itemBuilder: (_, i) {
          final c = _comments[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFF241638),
                  child: Text(
                    c.userName.isNotEmpty ? c.userName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${c.userName}  ',
                            style: const TextStyle(
                              color: Color(0xFFF0C15A),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          TextSpan(
                            text: c.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar(bool isArabic) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xDD000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: TextField(
                    controller: _commentController,
                    textDirection: isArabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    onSubmitted: (_) => _sendComment(),
                    decoration: InputDecoration(
                      hintText: isArabic
                          ? 'أضف تعليقاً...'
                          : 'Add a comment...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _likeCount++),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFFF4D6D),
                    size: 20,
                  ),
                ),
              ),
              if (widget.isHost) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _endStream,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF4D6D),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.stop_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.duration});

  final String duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4D6D),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            duration,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerBadge extends StatelessWidget {
  const _ViewerBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_rounded, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleControl extends StatelessWidget {
  const _CircleControl({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF3A174F)
              : Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? const Color(0xFF8B26D9)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Icon(
          icon,
          color: active
              ? const Color(0xFFCCA0FF)
              : Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
