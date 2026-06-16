import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/charisma_models.dart';
import '../services/charisma_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF080510);
const _kSurface = Color(0xFF110D25);
const _kCard    = Color(0xFF160F2E);
const _kBorder  = Color(0xFF2A1E50);
const _kPurple  = Color(0xFF8B26D9);
const _kGold    = Color(0xFFF0C15A);
const _kGreen   = Color(0xFF22C55E);
const _kRed     = Color(0xFFEF4444);
const _kCrown   = Color(0xFFFFD700);

// ─────────────────────────────────────────────────────────────────────────────

class CharismaChallengeScreen extends StatefulWidget {
  const CharismaChallengeScreen({super.key, required this.isArabic});

  final bool isArabic;

  @override
  State<CharismaChallengeScreen> createState() =>
      _CharismaChallengeScreenState();
}

class _CharismaChallengeScreenState extends State<CharismaChallengeScreen> {
  static const _service = CharismaService();

  bool _loading = true;
  String? _error;
  List<CharismaActiveChallenge> _challenges = [];
  String? _expandedId;
  final Map<String, List<CharismaLeaderboardEntry>> _boards = {};
  final Map<String, bool> _boardLoading = {};
  final Set<String> _joiningIds = {};
  final Set<String> _votingIds = {};
  bool _isAdmin = false;
  bool _actionLoading = false;
  Timer? _ticker;

  bool get _ar => context.isArabic;

  @override
  void initState() {
    super.initState();
    _load();
    _checkAdmin();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {}); // refresh countdown labels
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    try {
      final roles = await SupabaseService.requiredClient
          .from('app_user_roles')
          .select('role')
          .eq('user_id', SupabaseService.requiredClient.auth.currentUser!.id);
      final list = (roles as List).map((r) => r['role'] as String).toList();
      if (mounted) {
        setState(() => _isAdmin =
            list.any((r) => ['super_admin', 'admin'].contains(r)));
      }
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await _service.getActiveChallenges();
      if (!mounted) return;
      setState(() {
        _challenges = data;
        _loading    = false;
      });
      // Auto-expand single challenge
      if (_challenges.length == 1 && _expandedId == null) {
        _toggleExpand(_challenges.first.challenge.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _loadBoard(String challengeId) async {
    if (_boardLoading[challengeId] == true) return;
    setState(() => _boardLoading[challengeId] = true);
    try {
      final board = await _service.getLeaderboard(challengeId);
      if (!mounted) return;
      setState(() {
        _boards[challengeId]      = board;
        _boardLoading[challengeId] = false;
      });
    } catch (_) {
      if (mounted) setState(() => _boardLoading[challengeId] = false);
    }
  }

  void _toggleExpand(String id) {
    setState(() => _expandedId = _expandedId == id ? null : id);
    if (_expandedId == id) _loadBoard(id);
  }

  Future<void> _join(CharismaActiveChallenge ac) async {
    if (_joiningIds.contains(ac.challenge.id)) return;
    setState(() => _joiningIds.add(ac.challenge.id));
    try {
      await _service.joinChallenge(ac.challenge.id);
      await _load(silent: true);
      if (_expandedId == ac.challenge.id) _loadBoard(ac.challenge.id);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _joiningIds.remove(ac.challenge.id));
    }
  }

  Future<void> _vote(CharismaActiveChallenge ac, CharismaLeaderboardEntry entry) async {
    if (_votingIds.contains(entry.entryId)) return;
    setState(() => _votingIds.add(entry.entryId));
    try {
      await _service.vote(entry.entryId);
      _loadBoard(ac.challenge.id);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _votingIds.remove(entry.entryId));
    }
  }

  Future<void> _crown(CharismaActiveChallenge ac) async {
    final confirm = await _confirmDialog(
      _ar ? 'تتويج الفائز' : 'Crown Winner',
      _ar
          ? 'سيتم إعلان الفائز وإرسال المكافأة. هل أنت متأكد؟'
          : 'The top participant will win 100,000 coins + frame. Confirm?',
    );
    if (confirm != true) return;
    setState(() => _actionLoading = true);
    try {
      final result = await _service.adminCrownWinner(ac.challenge.id);
      await _load(silent: true);
      if (mounted) _showWinnerDialog(result);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _cancel(CharismaActiveChallenge ac) async {
    final confirm = await _confirmDialog(
      _ar ? 'إلغاء التحدي' : 'Cancel Challenge',
      _ar ? 'هل تريد إلغاء هذا التحدي؟' : 'Cancel this challenge?',
    );
    if (confirm != true) return;
    setState(() => _actionLoading = true);
    try {
      await _service.adminCancelChallenge(ac.challenge.id);
      await _load(silent: true);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<bool?> _confirmDialog(String title, String body) =>
      showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _kCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(body,  style: const TextStyle(color: Colors.white70, fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text(_ar ? 'إلغاء' : 'Cancel',
                    style: const TextStyle(color: Colors.white38))),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: Text(_ar ? 'تأكيد' : 'Confirm',
                    style: const TextStyle(color: _kGold))),
          ],
        ),
      );

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: _kRed));
  }

  void _showWinnerDialog(Map<String, dynamic> result) {
    final coins = (result['reward_coins'] as num?)?.toInt() ?? 100000;
    final votes = (result['vote_count']   as num?)?.toInt() ?? 0;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('👑', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(
                _ar ? 'تم تتويج الفائز!' : 'Winner Crowned!',
                style: const TextStyle(
                    color: _kCrown, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _ar ? '$votes صوت' : '$votes votes',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _RewardBadge(coins: coins, isArabic: _ar),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPurple,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_ar ? 'تم' : 'Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _localizeError(String msg) {
    if (msg.contains('already_joined'))       return _ar ? 'لقد انضممت مسبقاً'           : 'You already joined this challenge';
    if (msg.contains('already_voted'))        return _ar ? 'لقد صوّت لهذا المشارك'        : 'You already voted for this participant';
    if (msg.contains('self_vote'))            return _ar ? 'لا يمكنك التصويت لنفسك'       : 'You cannot vote for yourself';
    if (msg.contains('challenge_not_active')) return _ar ? 'التحدي غير نشط'               : 'Challenge is not active';
    if (msg.contains('no_participants'))      return _ar ? 'لا يوجد مشاركون بعد'          : 'No participants yet';
    if (msg.contains('insufficient_permissions')) return _ar ? 'ليس لديك صلاحية'          : 'You do not have permission';
    if (msg.contains('not_authenticated'))    return _ar ? 'يرجى تسجيل الدخول'            : 'Please sign in';
    return msg;
  }

  static String _fmtTime(Duration d) {
    if (d.isNegative) return '';
    if (d.inDays > 0)    return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0)   return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _kSurface, shape: BoxShape.circle,
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ar ? 'تحدي الكاريزما' : 'Charisma Challenge',
                  style: const TextStyle(color: _kGold, fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Text(
                  _ar ? 'نافس على تاج الكاريزما 👑' : 'Compete for the charisma crown 👑',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _load(),
            child: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kPurple));
    }
    if (_error != null) {
      return _buildError();
    }
    if (_challenges.isEmpty) {
      return _buildEmpty();
    }
    return RefreshIndicator(
      color: _kPurple,
      backgroundColor: _kCard,
      onRefresh: () => _load(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: _challenges.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildChallengeCard(_challenges[i]),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(_ar ? 'حدث خطأ' : 'Something went wrong',
              style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _load,
            child: Text(_ar ? 'إعادة المحاولة' : 'Retry',
                style: const TextStyle(color: _kPurple)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👑', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              _ar ? 'لا يوجد تحدي كاريزما حالياً' : 'No active charisma challenge right now',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              _ar ? 'تابع الإشعارات لمعرفة موعد التحدي القادم'
                  : 'Check back soon for the next challenge',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ── Challenge card ─────────────────────────────────────────────────────────

  Widget _buildChallengeCard(CharismaActiveChallenge ac) {
    final c = ac.challenge;
    final isExpanded = _expandedId == c.id;
    final timeLeft = c.timeRemaining;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: c.isCrowned ? _kCrown : (c.isActive ? _kPurple.withValues(alpha: 0.6) : _kBorder),
          width: c.isCrowned ? 1.5 : 1,
        ),
        boxShadow: c.isCrowned
            ? [BoxShadow(color: _kCrown.withValues(alpha: 0.15), blurRadius: 16)]
            : null,
      ),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ScopeBadge(scope: c.scope, isArabic: _ar),
                    const SizedBox(width: 8),
                    _StatusBadge(status: c.status, isArabic: _ar),
                    const Spacer(),
                    if (c.isActive && timeLeft.inSeconds > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer_outlined, color: Colors.white38, size: 12),
                          const SizedBox(width: 3),
                          Text(_fmtTime(timeLeft),
                              style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  c.localizedTitle(_ar),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                _RewardBadge(coins: c.rewardCoins, isArabic: _ar, compact: true),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.people_rounded, color: Colors.white38, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _ar
                          ? '${ac.participantCount} مشارك'
                          : '${ac.participantCount} participants',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Join / Status row ────────────────────────────────────────────
          if (!c.isFinished || ac.hasJoined)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildJoinRow(ac),
            ),

          // ── Leaderboard (expanded) ───────────────────────────────────────
          if (isExpanded) ...[
            const Divider(color: _kBorder, height: 1),
            _buildLeaderboardSection(ac),
          ],

          // ── Expand toggle ────────────────────────────────────────────────
          GestureDetector(
            onTap: () => _toggleExpand(c.id),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.only(
                  bottomLeft:  Radius.circular(isExpanded ? 18 : 18),
                  bottomRight: Radius.circular(isExpanded ? 18 : 18),
                  topLeft:     Radius.circular(isExpanded ? 0  : 0),
                  topRight:    Radius.circular(isExpanded ? 0  : 0),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isExpanded
                        ? (_ar ? 'إخفاء الترتيب' : 'Hide Leaderboard')
                        : (_ar ? 'عرض الترتيب' : 'View Leaderboard'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white38, size: 18,
                  ),
                ],
              ),
            ),
          ),

          // ── Admin controls ───────────────────────────────────────────────
          if (_isAdmin && !c.isCrowned && !c.isCancelled)
            _buildAdminRow(ac),
        ],
      ),
    );
  }

  Widget _buildJoinRow(CharismaActiveChallenge ac) {
    final c       = ac.challenge;
    final joining = _joiningIds.contains(c.id);

    if (ac.hasJoined) {
      final entry = ac.myEntry!;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _kGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: _kGreen, size: 16),
            const SizedBox(width: 8),
            Text(
              _ar ? 'أنت مشارك ✦ ${entry.voteCount} صوت' : 'Joined ✦ ${entry.voteCount} votes',
              style: const TextStyle(color: _kGreen, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (entry.isPerformed) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _ar ? 'أدّيت' : 'Performed',
                  style: const TextStyle(color: _kGold, fontSize: 10),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (!c.isActive) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: joining ? null : () => _join(ac),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPurple,
          disabledBackgroundColor: _kBorder,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        icon: joining
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.star_rounded, size: 18),
        label: Text(
          _ar ? 'انضم للتحدي' : 'Join Challenge',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ── Leaderboard ────────────────────────────────────────────────────────────

  Widget _buildLeaderboardSection(CharismaActiveChallenge ac) {
    final cid = ac.challenge.id;
    if (_boardLoading[cid] == true) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2)),
      );
    }
    final board = _boards[cid] ?? [];
    if (board.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            _ar ? 'لا يوجد مشاركون بعد' : 'No participants yet',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              const Icon(Icons.leaderboard_rounded, color: _kGold, size: 16),
              const SizedBox(width: 6),
              Text(
                _ar ? 'الترتيب' : 'Leaderboard',
                style: const TextStyle(color: _kGold, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        ...board.map((e) => _buildParticipantCard(ac, e)),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildParticipantCard(CharismaActiveChallenge ac, CharismaLeaderboardEntry e) {
    final c       = ac.challenge;
    final isWinner = e.isWinner;
    final voting  = _votingIds.contains(e.entryId);
    final canVote = c.isActive && !e.isMe && !e.hasVoted && !voting;

    final rankColor = switch (e.rank) {
      1 => _kCrown,
      2 => const Color(0xFFC0C0C0),
      3 => const Color(0xFFCD7F32),
      _ => Colors.white38,
    };
    final rankLabel = switch (e.rank) {
      1 => '🥇', 2 => '🥈', 3 => '🥉',
      _ => '#${e.rank}',
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isWinner
            ? _kCrown.withValues(alpha: 0.08)
            : (e.isMe ? _kPurple.withValues(alpha: 0.08) : _kSurface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWinner ? _kCrown.withValues(alpha: 0.4)
              : (e.isMe ? _kPurple.withValues(alpha: 0.3) : Colors.transparent),
        ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 32,
            child: Text(rankLabel,
                style: TextStyle(color: rankColor, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          // Avatar
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kBorder,
              image: e.profile.avatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(e.profile.avatarUrl!),
                      fit: BoxFit.cover)
                  : null,
            ),
            child: e.profile.avatarUrl == null
                ? const Icon(Icons.person_rounded, color: Colors.white38, size: 20)
                : null,
          ),
          const SizedBox(width: 10),
          // Name + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        e.profile.effectiveName,
                        style: TextStyle(
                          color: isWinner ? _kCrown : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (e.isMe) ...[
                      const SizedBox(width: 4),
                      const Text('★', style: TextStyle(color: _kGold, fontSize: 11)),
                    ],
                    if (isWinner) ...[
                      const SizedBox(width: 4),
                      const Text('👑', style: TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
                Text(
                  _ar
                      ? '${e.voteCount} صوت'
                      : '${e.voteCount} vote${e.voteCount == 1 ? "" : "s"}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          // Vote button
          if (canVote || e.hasVoted)
            GestureDetector(
              onTap: canVote ? () => _vote(ac, e) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: e.hasVoted
                      ? _kGold.withValues(alpha: 0.15)
                      : _kPurple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: e.hasVoted ? _kGold.withValues(alpha: 0.5) : _kPurple.withValues(alpha: 0.5),
                  ),
                ),
                child: voting
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2))
                    : Text(
                        e.hasVoted
                            ? (_ar ? '✓ صوّت' : '✓ Voted')
                            : (_ar ? 'صوّت' : 'Vote'),
                        style: TextStyle(
                          color: e.hasVoted ? _kGold : _kPurple,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Admin controls ─────────────────────────────────────────────────────────

  Widget _buildAdminRow(CharismaActiveChallenge ac) {
    final c = ac.challenge;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: _AdminBtn(
              label: _ar ? '👑 تتويج الفائز' : '👑 Crown Winner',
              color: _kCrown,
              loading: _actionLoading,
              enabled: (c.isActive || c.isEnded) && ac.participantCount > 0,
              onTap: () => _crown(ac),
            ),
          ),
          const SizedBox(width: 8),
          _AdminBtn(
            label: _ar ? 'إلغاء' : 'Cancel',
            color: _kRed,
            loading: _actionLoading,
            enabled: !c.isFinished,
            onTap: () => _cancel(ac),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({required this.scope, required this.isArabic});
  final String scope;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final isOfficial = scope == 'official';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isOfficial
            ? _kGold.withValues(alpha: 0.15)
            : _kPurple.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isOfficial
              ? _kGold.withValues(alpha: 0.4)
              : _kPurple.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        isOfficial
            ? (isArabic ? 'رسمي' : 'Official')
            : (isArabic ? 'وكالة'  : 'Agency'),
        style: TextStyle(
          color: isOfficial ? _kGold : _kPurple,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.isArabic});
  final String status;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active'    => (isArabic ? '🟢 نشط'     : '🟢 Active',    _kGreen),
      'scheduled' => (isArabic ? '⏳ قادم'     : '⏳ Upcoming',  Colors.white54),
      'ended'     => (isArabic ? '⏹ انتهى'    : '⏹ Ended',     Colors.white38),
      'crowned'   => (isArabic ? '👑 متوَّج'   : '👑 Crowned',   _kCrown),
      _           => (isArabic ? 'ملغى'        : 'Cancelled',    _kRed),
    };
    return Text(label, style: TextStyle(color: color, fontSize: 11));
  }
}

class _RewardBadge extends StatelessWidget {
  const _RewardBadge({
    required this.coins,
    required this.isArabic,
    this.compact = false,
  });
  final int coins;
  final bool isArabic;
  final bool compact;

  String get _fmt {
    if (coins >= 1000000) return '${(coins / 1000000).toStringAsFixed(1)}M';
    if (coins >= 1000)    return '${(coins / 1000).toStringAsFixed(0)}K';
    return '$coins';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1560), Color(0xFF1A0D3D)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('👑', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            isArabic ? '$_fmt عملة + إطار خاص' : '$_fmt coins + special frame',
            style: TextStyle(
              color: _kGold,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminBtn extends StatelessWidget {
  const _AdminBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : _kBorder.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? color.withValues(alpha: 0.5) : _kBorder),
        ),
        child: Center(
          child: loading
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(label,
                  style: TextStyle(
                      color: active ? color : Colors.white24,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
