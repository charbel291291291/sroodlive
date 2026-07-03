import 'package:flutter/material.dart';

import '../services/agency_service.dart';
import '../widgets/profile_hub_widgets.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

/// Focused Agency Owner screen (Phase 2). Shows the owner's active host roster
/// and pending join applications, and lets the owner approve/reject via the
/// owner-scoped SECURITY DEFINER RPC. Host agencies only — not recharge
/// agencies. All authorization is enforced server-side by owner_user_id.
class AgencyOwnerScreen extends StatefulWidget {
  const AgencyOwnerScreen({super.key});

  @override
  State<AgencyOwnerScreen> createState() => _AgencyOwnerScreenState();
}

class _AgencyOwnerScreenState extends State<AgencyOwnerScreen> {
  final _service = const AgencyService();

  Map<String, dynamic>? _agency;
  List<Map<String, dynamic>> _hosts = const [];
  List<Map<String, dynamic>> _pending = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busyApps = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final agency = await _service.getMyOwnedAgency();
      if (agency == null) {
        if (!mounted) return;
        setState(() {
          _agency = null;
          _loading = false;
        });
        return;
      }
      final results = await Future.wait([
        _service.ownerListHosts(),
        _service.ownerListPendingApplications(),
      ]);
      if (!mounted) return;
      setState(() {
        _agency = agency;
        _hosts = results[0];
        _pending = results[1];
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

  Future<void> _review(String applicationId, bool approve) async {
    if (_busyApps.contains(applicationId)) return;
    setState(() => _busyApps.add(applicationId));
    try {
      await _service.ownerReviewApplication(
        applicationId: applicationId,
        approve: approve,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyApps.remove(applicationId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendly(e.toString()))),
      );
    }
  }

  String _friendly(String e) {
    if (e.contains('not_agency_owner')) {
      return context.isArabic ? 'غير مصرح' : 'Not authorized';
    }
    if (e.contains('application_not_pending')) {
      return context.isArabic ? 'تمت معالجة الطلب' : 'Already processed';
    }
    return context.isArabic ? 'حدث خطأ، حاول مجددًا' : 'Something went wrong';
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.isArabic;
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: profileHubBg,
        appBar: AppBar(
          backgroundColor: profileHubBg,
          elevation: 0,
          title: Text(ar ? 'إدارة الوكالة' : 'My Agency',
              style: const TextStyle(color: Colors.white, fontSize: 18)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(ar),
        ),
      ),
    );
  }

  Widget _buildBody(bool ar) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: profileHubGold));
    }
    if (_error != null) {
      return _centered(Column(mainAxisSize: MainAxisSize.min, children: [
        Text(ar ? 'تعذر التحميل' : 'Failed to load',
            style: const TextStyle(color: profileHubMuted)),
        const SizedBox(height: 12),
        TextButton(onPressed: _load, child: Text(ar ? 'إعادة المحاولة' : 'Retry')),
      ]));
    }
    if (_agency == null) {
      return _centered(Text(
        ar ? 'لا تملك وكالة نشطة.' : 'You do not own an agency.',
        style: const TextStyle(color: profileHubMuted),
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _agencyHeader(ar),
        const SizedBox(height: 18),
        _sectionTitle(ar ? 'طلبات قيد الانتظار' : 'Pending applications',
            _pending.length),
        const SizedBox(height: 8),
        if (_pending.isEmpty)
          _emptyHint(ar ? 'لا توجد طلبات.' : 'No pending applications.')
        else
          ..._pending.map(_pendingCard),
        const SizedBox(height: 20),
        _sectionTitle(ar ? 'المضيفات النشطات' : 'Active hosts', _hosts.length),
        const SizedBox(height: 8),
        if (_hosts.isEmpty)
          _emptyHint(ar ? 'لا يوجد مضيفات بعد.' : 'No active hosts yet.')
        else
          ..._hosts.map(_hostCard),
      ],
    );
  }

  Widget _agencyHeader(bool ar) {
    final code = _agency?['agency_code']?.toString() ?? '—';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: profileHubCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: profileHubBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_agency?['name']?.toString() ?? '',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(ar ? 'كود الانضمام' : 'Join code',
                    style: const TextStyle(color: profileHubMuted, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: profileHubGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: profileHubGold.withValues(alpha: 0.5)),
            ),
            child: Text(code,
                style: const TextStyle(
                    color: profileHubGold,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard(Map<String, dynamic> app) {
    final id = app['application_id']?.toString() ?? '';
    final busy = _busyApps.contains(id);
    final ar = context.isArabic;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: profileHubCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: profileHubBorder),
      ),
      child: Row(
        children: [
          _avatar(app['avatar_url']?.toString(), app['display_name']?.toString()),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app['display_name']?.toString() ?? 'Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                if ((app['message']?.toString() ?? '').isNotEmpty)
                  Text(app['message'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: profileHubMuted, fontSize: 12)),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            IconButton(
              onPressed: () => _review(id, true),
              icon: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF22C55E)),
              tooltip: ar ? 'قبول' : 'Approve',
            ),
            IconButton(
              onPressed: () => _review(id, false),
              icon: const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444)),
              tooltip: ar ? 'رفض' : 'Reject',
            ),
          ],
        ],
      ),
    );
  }

  Widget _hostCard(Map<String, dynamic> host) {
    final ar = context.isArabic;
    final joined = host['joined_at']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: profileHubCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: profileHubBorder),
      ),
      child: Row(
        children: [
          _avatar(host['avatar_url']?.toString(), host['display_name']?.toString()),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(host['display_name']?.toString() ?? 'Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                Text(
                  '${ar ? 'انضمت' : 'Joined'}: ${joined != null && joined.length >= 10 ? joined.substring(0, 10) : '—'}',
                  style: const TextStyle(color: profileHubMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(host['status']?.toString() ?? 'active',
                style: const TextStyle(
                    color: Color(0xFF22C55E),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String? url, String? name) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: profileHubBorder,
      backgroundImage:
          (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
      child: (url == null || url.isEmpty)
          ? Text((name != null && name.isNotEmpty) ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white))
          : null,
    );
  }

  Widget _sectionTitle(String label, int count) => Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: profileHubBorder,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$count',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      );

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: const TextStyle(color: profileHubMuted)),
      );

  Widget _centered(Widget child) =>
      ListView(children: [const SizedBox(height: 120), Center(child: child)]);
}
