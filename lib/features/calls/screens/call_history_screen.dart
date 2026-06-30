import 'package:flutter/material.dart';
import 'package:srood_live/shared/utils/error_utils.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryState {
  final String id;
  final String peerName;
  final String? peerAvatarUrl;
  final bool isVideo;
  final bool isMissed;
  final bool isOutgoing;
  final Duration? duration;
  final DateTime calledAt;

  const _CallHistoryState({
    required this.id,
    required this.peerName,
    this.peerAvatarUrl,
    required this.isVideo,
    required this.isMissed,
    required this.isOutgoing,
    this.duration,
    required this.calledAt,
  });
}

class _CallHistoryScreenState extends State<CallHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isLoading = true;
  List<_CallHistoryState> _calls = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCalls();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCalls() async {
    setState(() => _isLoading = true);
    try {
      final user = SupabaseService.requiredClient.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final data = await SupabaseService.requiredClient
          .from('calls')
          .select('''
            id, is_video, ended_at, created_at, duration_seconds,
            caller_id, callee_id,
            caller:profiles!calls_caller_id_fkey(id, display_name, avatar_url),
            callee:profiles!calls_callee_id_fkey(id, display_name, avatar_url)
          ''')
          .or('caller_id.eq.${user.id},callee_id.eq.${user.id}')
          .order('created_at', ascending: false)
          .limit(60);

      final calls = (data as List).map((row) {
        final isOutgoing = row['caller_id'] == user.id;
        final peer = isOutgoing ? row['callee'] : row['caller'];
        final durationSecs = row['duration_seconds'] as int?;
        final isMissed =
            row['ended_at'] == null ||
            (durationSecs != null && durationSecs == 0);

        return _CallHistoryState(
          id: row['id'] as String,
          peerName: peer?['display_name'] as String? ?? 'Unknown',
          peerAvatarUrl: peer?['avatar_url'] as String?,
          isVideo: row['is_video'] as bool? ?? false,
          isMissed: isMissed,
          isOutgoing: isOutgoing,
          duration: durationSecs != null && durationSecs > 0
              ? Duration(seconds: durationSecs)
              : null,
          calledAt:
              DateTime.tryParse(row['created_at'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _calls = calls;
        _isLoading = false;
      });
    } catch (e, st) {
      debugError('CallHistoryScreen._load', e, st);
      if (!mounted) return;
      setState(() => _isLoading = false);
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isArabic),
              _buildTabBar(isArabic),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF8B26D9),
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildList(_calls, isArabic),
                          _buildList(
                            _calls.where((c) => !c.isVideo).toList(),
                            isArabic,
                          ),
                          _buildList(
                            _calls.where((c) => c.isVideo).toList(),
                            isArabic,
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

  Widget _buildHeader(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 0),
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
                  isArabic ? 'سجل المكالمات' : 'Call history',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadCalls,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFF0C15A)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isArabic) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFF3A174F),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF8B26D9)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF9E91B8),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        tabs: [
          Tab(text: isArabic ? 'الكل' : 'All'),
          Tab(text: isArabic ? 'صوتية' : 'Voice'),
          Tab(text: isArabic ? 'مرئية' : 'Video'),
        ],
      ),
    );
  }

  Widget _buildList(List<_CallHistoryState> calls, bool isArabic) {
    if (calls.isEmpty) {
      return _buildEmpty(isArabic);
    }

    return RefreshIndicator(
      onRefresh: _loadCalls,
      color: const Color(0xFF8B26D9),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: calls.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _CallTile(call: calls[i], isArabic: isArabic),
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
              Icons.call_rounded,
              color: Color(0xFF9E91B8),
              size: 38,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isArabic ? 'لا يوجد سجل مكالمات' : 'No call history',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic ? 'مكالماتك ستظهر هنا' : 'Your calls will appear here',
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

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call, required this.isArabic});

  final _CallHistoryState call;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final Color statusColor = call.isMissed
        ? const Color(0xFFFF6B8A)
        : const Color(0xFF63E6A1);

    final String durationLabel = call.duration != null
        ? _formatDuration(call.duration!)
        : (call.isMissed
              ? (isArabic ? 'فائتة' : 'Missed')
              : (isArabic ? 'لم يُجب' : 'No answer'));

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
                backgroundImage: call.peerAvatarUrl != null
                    ? NetworkImage(call.peerAvatarUrl!)
                    : null,
                child: call.peerAvatarUrl == null
                    ? Text(
                        call.peerName.isNotEmpty
                            ? call.peerName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              Positioned(
                right: isArabic ? null : 0,
                left: isArabic ? 0 : null,
                bottom: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFF08060F),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF08060F),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    size: 11,
                    color: const Color(0xFF9E91B8),
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
                  call.peerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  textDirection: dir,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      call.isOutgoing
                          ? Icons.call_made_rounded
                          : Icons.call_received_rounded,
                      size: 13,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      durationLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatDate(call.calledAt, isArabic),
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {},
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A174F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF8B26D9).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(
                    call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    color: const Color(0xFFF0C15A),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt, bool isArabic) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return isArabic ? 'أمس' : 'Yesterday';
    return '${dt.day}/${dt.month}';
  }
}
