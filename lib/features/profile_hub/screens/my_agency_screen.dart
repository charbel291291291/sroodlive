import 'package:flutter/material.dart';

import '../models/profile_hub_models.dart';
import '../services/agency_service.dart';
import '../widgets/profile_hub_widgets.dart';

class MyAgencyScreen extends StatefulWidget {
  const MyAgencyScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<MyAgencyScreen> createState() => _MyAgencyScreenState();
}

class _MyAgencyScreenState extends State<MyAgencyScreen> {
  final AgencyService _service = const AgencyService();
  late Future<({AgencyMembership? membership, List<AgencyApplication> apps})>
  _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({AgencyMembership? membership, List<AgencyApplication> apps})>
  _load() async {
    final membership = await _service.getMyMembership();
    final apps = await _service.getMyApplications();
    return (membership: membership, apps: apps);
  }

  void _retry() => setState(() => _future = _load());

  String _titleForType(String type) {
    return switch (type) {
      'join_agency' => widget.isArabic ? 'انضم إلى وكالة' : 'Join Agency',
      'create_agency' => widget.isArabic ? 'أنشئ وكالة' : 'Create Agency',
      'become_host' => widget.isArabic ? 'كن مضيفا' : 'Become Host',
      _ => type,
    };
  }

  String _subtitleForType(String type) {
    return switch (type) {
      'join_agency' =>
        widget.isArabic
            ? 'انضم إلى وكالة موجودة عبر دعوة أو موافقة.'
            : 'Join an existing agency by invitation or approval.',
      'create_agency' =>
        widget.isArabic
            ? 'ابدأ وكالتك الخاصة وأدر المضيفين.'
            : 'Start your own agency and manage hosts.',
      'become_host' =>
        widget.isArabic
            ? 'قدم لتصبح مضيف غرف صوتية وتربح من نشاطك.'
            : 'Apply to become a live room host and earn from activity.',
      _ => widget.isArabic ? 'طلب وكالة' : 'Agency application',
    };
  }

  String _defaultMessageForType(String type) {
    return switch (type) {
      'join_agency' =>
        widget.isArabic
            ? 'أريد الانضمام إلى وكالة موجودة.'
            : 'I want to join an existing agency.',
      'create_agency' =>
        widget.isArabic
            ? 'أريد إنشاء وكالة جديدة وإدارة المضيفين.'
            : 'I want to create a new agency and manage hosts.',
      'become_host' =>
        widget.isArabic
            ? 'أريد أن أصبح مضيف غرف صوتية.'
            : 'I want to become a live room host.',
      _ => widget.isArabic ? 'طلب وكالة' : 'Agency application',
    };
  }

  Future<void> _openApplication(String type) async {
    final messageController = TextEditingController();
    final phoneController = TextEditingController();
    final countryController = TextEditingController();
    final experienceController = TextEditingController();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: profileHubCard,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              MediaQuery.viewInsetsOf(context).bottom + 18,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: widget.isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleForType(type),
                    textAlign: widget.isArabic
                        ? TextAlign.right
                        : TextAlign.left,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _subtitleForType(type),
                    textAlign: widget.isArabic
                        ? TextAlign.right
                        : TextAlign.left,
                    style: const TextStyle(
                      color: profileHubMuted,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneController,
                    decoration: InputDecoration(
                      labelText: widget.isArabic ? 'الهاتف' : 'Phone',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: countryController,
                    decoration: InputDecoration(
                      labelText: widget.isArabic ? 'الدولة' : 'Country',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: experienceController,
                    decoration: InputDecoration(
                      labelText: widget.isArabic ? 'الخبرة' : 'Experience',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: messageController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: widget.isArabic ? 'رسالتك' : 'Message',
                      hintText: _defaultMessageForType(type),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(
                        widget.isArabic ? 'إرسال الطلب' : 'Submit application',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (submitted == true) {
      await _service.submitApplication(
        applicationType: type,
        message: messageController.text.trim().isEmpty
            ? _defaultMessageForType(type)
            : messageController.text.trim(),
        phone: phoneController.text.trim(),
        country: countryController.text.trim(),
        experience: experienceController.text.trim(),
      );
      _retry();
    }

    messageController.dispose();
    phoneController.dispose();
    countryController.dispose();
    experienceController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return ProfileHubScaffold(
      title: isArabic ? 'وكالتي' : 'My agency',
      isArabic: isArabic,
      children: [
        FutureBuilder<
          ({AgencyMembership? membership, List<AgencyApplication> apps})
        >(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return ProfileErrorState(
                message: snapshot.error?.toString() ?? 'Failed to load agency.',
                onRetry: _retry,
                isArabic: isArabic,
              );
            }

            final membership = snapshot.data!.membership;
            final applications = snapshot.data!.apps;

            return Column(
              children: [
                if (membership == null)
                  ProfileEmptyState(
                    icon: Icons.groups_rounded,
                    title: isArabic ? 'لا توجد وكالة بعد' : 'No agency yet',
                    description: isArabic
                        ? 'اختر بين الانضمام إلى وكالة إنشاء وكالة أو التقديم كمضيف.'
                        : 'Choose to join an agency, create one, or apply as a host.',
                    isArabic: isArabic,
                  )
                else
                  ProfileInfoCard(
                    icon: Icons.apartment_rounded,
                    title: membership.agencyName,
                    body:
                        '${isArabic ? 'الدور' : 'Role'}: ${membership.role}\n'
                        '${isArabic ? 'الحالة' : 'Status'}: ${membership.status}\n'
                        '${isArabic ? 'العمولة' : 'Commission'}: ${(membership.commissionRate * 100).toStringAsFixed(1)}%\n'
                        '${isArabic ? 'هدف العملات' : 'Coin target'}: ${membership.monthlyTargetCoins}\n'
                        '${isArabic ? 'هدف الساعات' : 'Hour target'}: ${membership.monthlyTargetHours}',
                    isArabic: isArabic,
                  ),
                if (membership == null) ...[
                  ProfileMenuItem(
                    icon: Icons.group_add_rounded,
                    title: isArabic ? 'انضم إلى وكالة' : 'Join Agency',
                    subtitle: isArabic
                        ? 'انضم إلى وكالة موجودة عبر دعوة أو موافقة.'
                        : 'Join an existing agency by invitation or approval.',
                    isArabic: isArabic,
                    onTap: () => _openApplication('join_agency'),
                  ),
                  ProfileMenuItem(
                    icon: Icons.add_business_rounded,
                    title: isArabic ? 'أنشئ وكالة' : 'Create Agency',
                    subtitle: isArabic
                        ? 'ابدأ وكالتك الخاصة وأدر المضيفين.'
                        : 'Start your own agency and manage hosts.',
                    isArabic: isArabic,
                    onTap: () => _openApplication('create_agency'),
                  ),
                  ProfileMenuItem(
                    icon: Icons.mic_external_on_rounded,
                    title: isArabic ? 'كن مضيفا' : 'Become Host',
                    subtitle: isArabic
                        ? 'قدم لتصبح مضيف غرف صوتية وتربح من نشاطك.'
                        : 'Apply to become a live room host and earn from activity.',
                    isArabic: isArabic,
                    onTap: () => _openApplication('become_host'),
                  ),
                ],
                ProfileSectionTitle(
                  title: isArabic ? 'الطلبات' : 'Applications',
                  isArabic: isArabic,
                ),
                if (applications.isEmpty)
                  ProfileEmptyState(
                    icon: Icons.assignment_rounded,
                    title: isArabic ? 'لا توجد طلبات' : 'No applications',
                    description: isArabic
                        ? 'طلبات الوكالة أو المضيف ستظهر هنا بعد إرسالها.'
                        : 'Agency and host applications will appear here after submission.',
                    isArabic: isArabic,
                  )
                else
                  ...applications.map(
                    (app) => TicketCard(
                      title: _titleForType(app.applicationType),
                      status: app.status,
                      message: app.message ?? '',
                      date: app.createdAt,
                      isArabic: isArabic,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
