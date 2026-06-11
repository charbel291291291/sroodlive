import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../profile/screens/user_profile_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardEntry {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int vipLevel;
  final int score;

  const _LeaderboardEntry({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.vipLevel,
    required this.score,
  });
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _error;

  List<_LeaderboardEntry> _earners = const [];
  List<_LeaderboardEntry> _gifters = const [];
  List<_LeaderboardEntry> _streamers = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final [earnersRaw, giftersRaw, streamersRaw] = await Future.wait([
        SupabaseService.requiredClient
            .from('v_leaderboard_earners')
            .select('id, display_name, avatar_url, vip_level, score'),
        SupabaseService.requiredClient
            .from('v_leaderboard_gifters')
            .select('id, display_name, avatar_url, vip_level, score'),
        SupabaseService.requiredClient
            .from('v_leaderboard_followed')
            .select('id, display_name, avatar_url, vip_level, score'),
      ]);

      _LeaderboardEntry toEntry(Map<String, dynamic> r) =>
          _LeaderboardEntry(
            userId: r['id'] as String,
            displayName: r['display_name'] as String? ?? '',
            avatarUrl: r['avatar_url'] as String?,
            vipLevel: r['vip_level'] as int? ?? 0,
            score: r['score'] as int? ?? 0,
          );

      if (!mounted) return;
      setState(() {
        _earners = (earnersRaw as List).map((r) => toEntry(r as Map<String, dynamic>)).toList();
        _gifters = (giftersRaw as List).map((r) => toEntry(r as Map<String, dynamic>)).toList();
        _streamers = (streamersRaw as List).map((r) => toEntry(r as Map<String, dynamic>)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
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
          child: Column(
            children: [
              _buildHeader(isArabic),
              _buildTabBar(isArabic),
              Expanded(child: _buildBody(isArabic)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Padding(
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'المتصدرون' : 'Leaderboard',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 26,
                    fontWeight: FontWeight.w900, height: 1.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isArabic ? 'أفضل المستخدمين هذا الشهر' : 'Top users this month',
                  style: const TextStyle(
                    color: Color(0xFFBCAED6), fontSize: 12, fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFF0C15A)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isArabic) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: const Color(0xFF3A174F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF8B26D9)),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF9E91B8),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(text: isArabic ? 'أكثر تلقياً' : 'Top Earners'),
          Tab(text: isArabic ? 'أكثر إهداءً' : 'Top Gifters'),
          Tab(text: isArabic ? 'أكثر متابعة' : 'Most Followed'),
        ],
      ),
    );
  }

  Widget _buildBody(bool isArabic) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8B26D9)));
    }
    if (_error != null) {
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

    return TabBarView(
      controller: _tabController,
      children: [
        _buildList(_earners, isArabic, isArabic ? 'هدية' : 'gifts'),
        _buildList(_gifters, isArabic, isArabic ? 'هدية مرسلة' : 'gifts sent'),
        _buildList(_streamers, isArabic, isArabic ? 'متابع' : 'followers'),
      ],
    );
  }

  Widget _buildList(List<_LeaderboardEntry> entries, bool isArabic, String unit) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'لا توجد بيانات بعد' : 'No data yet',
          style: const TextStyle(color: Color(0xFF6E5A8A), fontSize: 15, fontWeight: FontWeight.w700),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: entries.length,
        itemBuilder: (context, i) => _LeaderboardTile(
          rank: i + 1,
          entry: entries[i],
          unit: unit,
          isArabic: isArabic,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => UserProfileScreen(
                userId: entries[i].userId,
                isArabic: isArabic,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({
    required this.rank,
    required this.entry,
    required this.unit,
    required this.isArabic,
    required this.onTap,
  });

  final int rank;
  final _LeaderboardEntry entry;
  final String unit;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;

    final rankColors = [
      const Color(0xFFF0C15A), // gold
      const Color(0xFFB8C4D0), // silver
      const Color(0xFFCD7F32), // bronze
    ];
    final rankBg = [
      const Color(0xFF3A2A10),
      const Color(0xFF1A2030),
      const Color(0xFF2A1810),
    ];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isTop3 ? rankBg[rank - 1].withValues(alpha: 0.6) : const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isTop3
                ? rankColors[rank - 1].withValues(alpha: 0.5)
                : const Color(0xFF6E3AA8).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            // Rank badge
            SizedBox(
              width: 32,
              child: isTop3
                  ? Icon(_rankIcon(rank), color: rankColors[rank - 1], size: 22)
                  : Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9E91B8), fontSize: 14, fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(width: 10),

            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF241638),
              backgroundImage:
                  entry.avatarUrl != null ? NetworkImage(entry.avatarUrl!) : null,
              child: entry.avatarUrl == null
                  ? Text(
                      entry.displayName.isNotEmpty
                          ? entry.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Name
            Expanded(
              child: Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isTop3 ? Colors.white : const Color(0xFFD8CFEA),
                  fontSize: 15,
                  fontWeight: isTop3 ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),

            // Score
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatScore(entry.score),
                  style: TextStyle(
                    color: isTop3 ? rankColors[rank - 1] : const Color(0xFFF0C15A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  unit,
                  style: const TextStyle(
                    color: Color(0xFF9E91B8), fontSize: 10, fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _rankIcon(int rank) {
    return switch (rank) {
      1 => Icons.emoji_events_rounded,
      2 => Icons.military_tech_rounded,
      _ => Icons.workspace_premium_rounded,
    };
  }

  String _formatScore(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}
