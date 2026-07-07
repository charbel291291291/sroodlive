import 'package:flutter/material.dart';

import '../services/agency_service.dart';
import '../widgets/profile_hub_widgets.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

/// Minimal admin review screen for HOST-agency applications (become_host /
/// join_agency / create_agency). Deliberately separate from recharge agencies.
/// All actions go through admin SECURITY DEFINER RPCs (server-side role-checked);
/// approving a join application creates the agency_hosts membership.
class AdminHostAgencyReviewScreen extends StatefulWidget {
  const AdminHostAgencyReviewScreen({super.key});

  @override
  State<AdminHostAgencyReviewScreen> createState() =>
      _AdminHostAgencyReviewScreenState();
}

class _AdminHostAgencyReviewScreenState
    extends State<AdminHostAgencyReviewScreen> {
  final _service = const AgencyService();

  List<Map<String, dynamic>> _apps = const [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'pending';
  final Set<String> _busy = {};

  static const _statuses = ['pending', 'approved', 'rejected'];

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
      final apps = await _service.adminListHostAgencyApplications(
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _apps = apps;
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

  Future<void> _review(String id, bool approve) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await _service.adminReviewApplication(
        applicationId: id,
        approve: approve,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
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
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            ar ? 'طلبات الوكالات (المضيفون)' : 'Host-agency applications',
            style: const TextStyle(color: Colors.white, fontSize: 17),
          ),
        ),
        body: Column(
          children: [
            _filterBar(ar),
            Expanded(
              child: RefreshIndicator(onRefresh: _load, child: _buildList(ar)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterBar(bool ar) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Row(
      children: _statuses.map((s) {
        final sel = s == _statusFilter;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(s),
            selected: sel,
            onSelected: (_) {
              setState(() => _statusFilter = s);
              _load();
            },
          ),
        );
      }).toList(),
    ),
  );

  Widget _buildList(bool ar) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: profileHubGold),
      );
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ar ? 'تعذر التحميل' : 'Failed to load',
                  style: const TextStyle(color: profileHubMuted),
                ),
                TextButton(
                  onPressed: _load,
                  child: Text(ar ? 'إعادة' : 'Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_apps.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              ar ? 'لا توجد طلبات.' : 'No applications.',
              style: const TextStyle(color: profileHubMuted),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _apps.length,
      itemBuilder: (_, i) => _card(_apps[i], ar),
    );
  }

  Widget _card(Map<String, dynamic> app, bool ar) {
    final id = app['application_id']?.toString() ?? '';
    final type = app['application_type']?.toString() ?? '';
    final status = app['status']?.toString() ?? '';
    final busy = _busy.contains(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: profileHubCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: profileHubBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  app['display_name']?.toString() ?? 'Player',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: profileHubBorder,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  type,
                  style: const TextStyle(color: profileHubGold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${ar ? 'الوكالة' : 'Agency'}: ${app['agency_name']?.toString() ?? '—'}'
            '${app['agency_code'] != null ? ' (${app['agency_code']})' : ''}',
            style: const TextStyle(color: profileHubMuted, fontSize: 12),
          ),
          if ((app['requested_agency_name']?.toString() ?? '').isNotEmpty)
            Text(
              '${ar ? 'الاسم المطلوب' : 'Requested name'}: '
              '${app['requested_agency_name']}',
              style: const TextStyle(color: profileHubGold, fontSize: 12),
            ),
          if ((app['country']?.toString() ?? '').isNotEmpty)
            Text(
              '${ar ? 'الدولة' : 'Country'}: ${app['country']}',
              style: const TextStyle(color: profileHubMuted, fontSize: 12),
            ),
          if ((app['experience']?.toString() ?? '').isNotEmpty)
            Text(
              '${ar ? 'الخبرة' : 'Experience'}: ${app['experience']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: profileHubMuted, fontSize: 12),
            ),
          if ((app['message']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              app['message'].toString(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (status == 'pending') ...[
            const SizedBox(height: 8),
            if (busy)
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _review(id, false),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFFEF4444),
                      size: 18,
                    ),
                    label: Text(
                      ar ? 'رفض' : 'Reject',
                      style: const TextStyle(color: Color(0xFFEF4444)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _review(id, true),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(ar ? 'قبول' : 'Approve'),
                  ),
                ],
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                status,
                style: TextStyle(
                  color: status == 'approved'
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
