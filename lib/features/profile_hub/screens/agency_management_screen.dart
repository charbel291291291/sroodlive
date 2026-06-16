import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../profile/screens/user_profile_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class AgencyManagementScreen extends StatefulWidget {
  const AgencyManagementScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<AgencyManagementScreen> createState() => _AgencyManagementScreenState();
}

class _AgencyMember {
  final String memberId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String role;
  final String status;
  final DateTime? joinedAt;

  const _AgencyMember({
    required this.memberId,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.role,
    required this.status,
    this.joinedAt,
  });
}

class _AgencyApp {
  final String id;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String status;
  final String? message;
  final DateTime? createdAt;

  const _AgencyApp({
    required this.id,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.status,
    this.message,
    this.createdAt,
  });
}

class _AgencyManagementScreenState extends State<AgencyManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _agency;
  List<_AgencyMember> _members = const [];
  List<_AgencyApp> _applications = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = SupabaseService.requiredClient.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      // Find agency owned by current user
      final agencyRaw = await SupabaseService.requiredClient
          .from('agencies')
          .select(
            'id, name, country, commission_rate, monthly_target_coins, monthly_target_hours',
          )
          .eq('owner_user_id', userId)
          .maybeSingle();

      if (agencyRaw == null) {
        if (!mounted) return;
        setState(() {
          _agency = null;
          _loading = false;
        });
        return;
      }

      final agencyId = agencyRaw['id'] as String;

      final [membersRaw, appsRaw] = await Future.wait([
        SupabaseService.requiredClient
            .from('agency_members')
            .select(
              'id, user_id, role, status, joined_at, profiles(display_name, avatar_url)',
            )
            .eq('agency_id', agencyId)
            .order('joined_at', ascending: false),
        SupabaseService.requiredClient
            .from('agency_applications')
            .select(
              'id, user_id, status, message, created_at, profiles(display_name, avatar_url)',
            )
            .eq('agency_id', agencyId)
            .order('created_at', ascending: false)
            .limit(50),
      ]);

      _AgencyMember mapMember(Map<String, dynamic> r) {
        final p = r['profiles'] is Map<String, dynamic>
            ? r['profiles'] as Map<String, dynamic>
            : <String, dynamic>{};
        return _AgencyMember(
          memberId: r['id'] as String,
          userId: r['user_id'] as String,
          displayName: p['display_name'] as String? ?? '',
          avatarUrl: p['avatar_url'] as String?,
          role: r['role'] as String? ?? 'host',
          status: r['status'] as String? ?? 'active',
          joinedAt: r['joined_at'] != null
              ? DateTime.tryParse(r['joined_at'].toString())
              : null,
        );
      }

      _AgencyApp mapApp(Map<String, dynamic> r) {
        final p = r['profiles'] is Map<String, dynamic>
            ? r['profiles'] as Map<String, dynamic>
            : <String, dynamic>{};
        return _AgencyApp(
          id: r['id'] as String,
          userId: r['user_id'] as String,
          displayName: p['display_name'] as String? ?? '',
          avatarUrl: p['avatar_url'] as String?,
          status: r['status'] as String? ?? 'pending',
          message: r['message'] as String?,
          createdAt: r['created_at'] != null
              ? DateTime.tryParse(r['created_at'].toString())
              : null,
        );
      }

      if (!mounted) return;
      setState(() {
        _agency = agencyRaw;
        _members = (membersRaw as List)
            .map((r) => mapMember(r as Map<String, dynamic>))
            .toList();
        _applications = (appsRaw as List)
            .map((r) => mapApp(r as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updateMemberStatus(String memberId, String status) async {
    try {
      await SupabaseService.requiredClient
          .from('agency_members')
          .update({'status': status})
          .eq('id', memberId);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFF3A1020),
        ),
      );
    }
  }

  Future<void> _updateAppStatus(String appId, String status) async {
    try {
      await SupabaseService.requiredClient
          .from('agency_applications')
          .update({'status': status})
          .eq('id', appId);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFF3A1020),
        ),
      );
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
        child: SafeArea(child: _buildBody(isArabic)),
      ),
    );
  }

  Widget _buildBody(bool isArabic) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B26D9)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFF5C7A),
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: Text(
                isArabic ? 'إعادة' : 'Retry',
                style: const TextStyle(color: Color(0xFFF0C15A)),
              ),
            ),
          ],
        ),
      );
    }

    if (_agency == null) {
      return Column(
        children: [
          _buildHeader(isArabic, null),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF160B24),
                        border: Border.all(color: const Color(0xFF4A3470)),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: Color(0xFF8B26D9),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isArabic ? 'ليس لديك وكالة' : "You don't own an agency",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isArabic
                          ? 'قدّم طلباً لإنشاء وكالة من صفحة وكالتي'
                          : 'Apply to create an agency from My Agency page',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9E91B8),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final agencyName = _agency!['name'] as String? ?? '';
    final commissionRate =
        (_agency!['commission_rate'] as num?)?.toDouble() ?? 0;
    final targetCoins = _agency!['monthly_target_coins'] as int? ?? 0;

    return Column(
      children: [
        _buildHeader(isArabic, agencyName),

        // Agency stats card
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF160B24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF6E3AA8).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              _stat(_members.length.toString(), isArabic ? 'عضو' : 'Members'),
              _statDiv(),
              _stat(
                '${commissionRate.toStringAsFixed(0)}%',
                isArabic ? 'العمولة' : 'Commission',
              ),
              _statDiv(),
              _stat(
                _formatCoins(targetCoins),
                isArabic ? 'هدف شهري' : 'Monthly target',
              ),
              _statDiv(),
              _stat(
                _applications
                    .where((a) => a.status == 'pending')
                    .length
                    .toString(),
                isArabic ? 'طلبات' : 'Pending',
              ),
            ],
          ),
        ),

        // Tab bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: isArabic ? 'الأعضاء' : 'Members'),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isArabic ? 'الطلبات' : 'Applications',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_applications.any((a) => a.status == 'pending')) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4D6D),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_applications.where((a) => a.status == 'pending').length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMembersList(isArabic),
              _buildApplicationsList(isArabic),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(bool isArabic, String? agencyName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
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
                  agencyName ??
                      (isArabic ? 'إدارة الوكالة' : 'Agency Management'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isArabic
                      ? 'إدارة الأعضاء والطلبات'
                      : 'Manage members and applications',
                  style: const TextStyle(
                    color: Color(0xFFBCAED6),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

  Widget _buildMembersList(bool isArabic) {
    if (_members.isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'لا يوجد أعضاء بعد' : 'No members yet',
          style: const TextStyle(
            color: Color(0xFF6E5A8A),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _members.length,
        itemBuilder: (context, i) {
          final m = _members[i];
          return _MemberTile(
            member: m,
            isArabic: isArabic,
            onViewProfile: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    UserProfileScreen(userId: m.userId, isArabic: isArabic),
              ),
            ),
            onKick: m.status == 'active'
                ? () => _confirmAction(
                    isArabic ? 'إزالة العضو؟' : 'Remove member?',
                    isArabic
                        ? 'هل تريد إزالة هذا العضو من الوكالة؟'
                        : 'Remove this member from the agency?',
                    isArabic ? 'إزالة' : 'Remove',
                    () => _updateMemberStatus(m.memberId, 'removed'),
                    isArabic,
                  )
                : null,
          );
        },
      ),
    );
  }

  Widget _buildApplicationsList(bool isArabic) {
    if (_applications.isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'لا توجد طلبات' : 'No applications',
          style: const TextStyle(
            color: Color(0xFF6E5A8A),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _applications.length,
        itemBuilder: (context, i) {
          final app = _applications[i];
          return _ApplicationTile(
            app: app,
            isArabic: isArabic,
            onViewProfile: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    UserProfileScreen(userId: app.userId, isArabic: isArabic),
              ),
            ),
            onApprove: app.status == 'pending'
                ? () => _updateAppStatus(app.id, 'approved')
                : null,
            onReject: app.status == 'pending'
                ? () => _updateAppStatus(app.id, 'rejected')
                : null,
          );
        },
      ),
    );
  }

  void _confirmAction(
    String title,
    String body,
    String confirmLabel,
    VoidCallback onConfirm,
    bool isArabic,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B102A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(body, style: const TextStyle(color: Color(0xFFD8CFEA))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              isArabic ? 'إلغاء' : 'Cancel',
              style: const TextStyle(color: Color(0xFF9E91B8)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            child: Text(
              confirmLabel,
              style: const TextStyle(
                color: Color(0xFFFF5C7A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDiv() =>
      Container(width: 1, height: 24, color: const Color(0xFF2A1A40));

  String _formatCoins(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ---------------------------------------------------------------------------
// Member tile
// ---------------------------------------------------------------------------

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isArabic,
    required this.onViewProfile,
    this.onKick,
  });

  final _AgencyMember member;
  final bool isArabic;
  final VoidCallback onViewProfile;
  final VoidCallback? onKick;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (member.status) {
      'active' => const Color(0xFF3ECC8C),
      'removed' => const Color(0xFFFF5C7A),
      _ => const Color(0xFFF0C15A),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6E3AA8).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          GestureDetector(
            onTap: onViewProfile,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF241638),
              backgroundImage: member.avatarUrl != null
                  ? NetworkImage(member.avatarUrl!)
                  : null,
              child: member.avatarUrl == null
                  ? Text(
                      member.displayName.isNotEmpty
                          ? member.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onViewProfile,
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    textDirection: isArabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          member.status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        member.role,
                        style: const TextStyle(
                          color: Color(0xFF9E91B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (onKick != null)
            IconButton(
              onPressed: onKick,
              icon: const Icon(
                Icons.person_remove_rounded,
                color: Color(0xFFFF5C7A),
                size: 20,
              ),
              tooltip: isArabic ? 'إزالة' : 'Remove',
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Application tile
// ---------------------------------------------------------------------------

class _ApplicationTile extends StatelessWidget {
  const _ApplicationTile({
    required this.app,
    required this.isArabic,
    required this.onViewProfile,
    this.onApprove,
    this.onReject,
  });

  final _AgencyApp app;
  final bool isArabic;
  final VoidCallback onViewProfile;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (app.status) {
      'approved' => const Color(0xFF3ECC8C),
      'rejected' => const Color(0xFFFF5C7A),
      _ => const Color(0xFFF0C15A),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: app.status == 'pending'
              ? const Color(0xFFF0C15A).withValues(alpha: 0.4)
              : const Color(0xFF6E3AA8).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              GestureDetector(
                onTap: onViewProfile,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF241638),
                  backgroundImage: app.avatarUrl != null
                      ? NetworkImage(app.avatarUrl!)
                      : null,
                  child: app.avatarUrl == null
                      ? Text(
                          app.displayName.isNotEmpty
                              ? app.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  app.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  app.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (app.message?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              app.message!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFBCAED6),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 10),
            Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                if (onApprove != null)
                  Expanded(
                    child: GestureDetector(
                      onTap: onApprove,
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D2A1A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFF3ECC8C,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          isArabic ? 'قبول' : 'Approve',
                          style: const TextStyle(
                            color: Color(0xFF3ECC8C),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (onApprove != null && onReject != null)
                  const SizedBox(width: 8),
                if (onReject != null)
                  Expanded(
                    child: GestureDetector(
                      onTap: onReject,
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A0D14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFFFF5C7A,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          isArabic ? 'رفض' : 'Reject',
                          style: const TextStyle(
                            color: Color(0xFFFF5C7A),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
