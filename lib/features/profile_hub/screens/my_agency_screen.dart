import 'package:flutter/material.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

import '../models/profile_hub_models.dart';
import '../services/agency_service.dart';
import '../widgets/profile_hub_widgets.dart';
import 'agency_owner_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class MyAgencyScreen extends StatefulWidget {
  const MyAgencyScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<MyAgencyScreen> createState() => _MyAgencyScreenState();
}

class _MyAgencyScreenState extends State<MyAgencyScreen> {
  final AgencyService _service = const AgencyService();
  late Future<
    ({
      AgencyMembership? membership,
      List<AgencyApplication> apps,
      Map<String, dynamic>? ownedAgency,
      Map<String, dynamic> hostStatus,
    })
  >
  _future;
  bool _submittingApplication = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<
    ({
      AgencyMembership? membership,
      List<AgencyApplication> apps,
      Map<String, dynamic>? ownedAgency,
      Map<String, dynamic> hostStatus,
    })
  >
  _load() async {
    final membershipFuture = _service.getMyMembership();
    final appsFuture = _service.getMyApplications();
    final ownedAgencyFuture = _service.getMyOwnedAgency();
    final hostStatusFuture = _service.getMyHostStatus();
    return (
      membership: await membershipFuture,
      apps: await appsFuture,
      ownedAgency: await ownedAgencyFuture,
      hostStatus: await hostStatusFuture,
    );
  }

  void _retry() => setState(() => _future = _load());

  String _titleForType(String type) {
    return switch (type) {
      'join_agency' => context.isArabic ? 'انضم إلى وكالة' : 'Join Agency',
      'create_agency' => context.isArabic ? 'أنشئ وكالة' : 'Create Agency',
      'become_host' => context.isArabic ? 'كن مضيفا' : 'Become Host',
      _ => type,
    };
  }

  String _subtitleForType(String type) {
    return switch (type) {
      'join_agency' =>
        context.isArabic
            ? 'انضم إلى وكالة موجودة عبر دعوة أو موافقة.'
            : 'Join an existing agency by invitation or approval.',
      'create_agency' =>
        context.isArabic
            ? 'ابدأ وكالتك الخاصة وأدر المضيفين.'
            : 'Start your own agency and manage hosts.',
      'become_host' =>
        context.isArabic
            ? 'قدم لتصبح مضيف غرف صوتية وتربح من نشاطك.'
            : 'Apply to become a live room host and earn from activity.',
      _ => context.isArabic ? 'طلب وكالة' : 'Agency application',
    };
  }

  String _defaultMessageForType(String type) {
    return switch (type) {
      'join_agency' =>
        context.isArabic
            ? 'أريد الانضمام إلى وكالة موجودة.'
            : 'I want to join an existing agency.',
      'create_agency' =>
        context.isArabic
            ? 'أريد إنشاء وكالة جديدة وإدارة المضيفين.'
            : 'I want to create a new agency and manage hosts.',
      'become_host' =>
        context.isArabic
            ? 'أريد أن أصبح مضيف غرف صوتية.'
            : 'I want to become a live room host.',
      _ => context.isArabic ? 'طلب وكالة' : 'Agency application',
    };
  }

  Future<void> _openApplication(String type) async {
    if (_submittingApplication) return;
    final formKey = GlobalKey<FormState>();
    final messageController = TextEditingController();
    final phoneController = TextEditingController();
    final countryController = TextEditingController();
    final experienceController = TextEditingController();
    final agencyCodeController = TextEditingController();
    final agencyNameController = TextEditingController();

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
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: context.isArabic
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleForType(type),
                      textAlign: context.isArabic
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
                      textAlign: context.isArabic
                          ? TextAlign.right
                          : TextAlign.left,
                      style: const TextStyle(
                        color: profileHubMuted,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Join requires the agency's code; the server resolves and
                    // validates the agency (client never sends agency_id).
                    if (type == 'join_agency') ...[
                      TextFormField(
                        controller: agencyCodeController,
                        textCapitalization: TextCapitalization.characters,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? (context.isArabic
                                  ? 'كود الوكالة مطلوب'
                                  : 'Agency code is required')
                            : null,
                        decoration: InputDecoration(
                          labelText: context.isArabic
                              ? 'كود الوكالة'
                              : 'Agency code',
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (type == 'create_agency') ...[
                      TextFormField(
                        controller: agencyNameController,
                        maxLength: 80,
                        validator: (value) {
                          final length = value?.trim().length ?? 0;
                          if (length < 3) {
                            return context.isArabic
                                ? 'اسم الوكالة يجب أن يكون 3 أحرف على الأقل'
                                : 'Agency name must be at least 3 characters';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: context.isArabic
                              ? 'اسم الوكالة'
                              : 'Agency name',
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: context.isArabic ? 'الهاتف' : 'Phone',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: countryController,
                      decoration: InputDecoration(
                        labelText: context.isArabic ? 'الدولة' : 'Country',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: experienceController,
                      decoration: InputDecoration(
                        labelText: context.isArabic ? 'الخبرة' : 'Experience',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: messageController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: context.isArabic ? 'رسالتك' : 'Message',
                        hintText: _defaultMessageForType(type),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (formKey.currentState?.validate() ?? false) {
                            Navigator.of(context).pop(true);
                          }
                        },
                        child: Text(
                          context.isArabic
                              ? 'إرسال الطلب'
                              : 'Submit application',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      if (submitted == true) {
        setState(() => _submittingApplication = true);
        await _service.submitApplication(
          applicationType: type,
          message: messageController.text.trim().isEmpty
              ? _defaultMessageForType(type)
              : messageController.text.trim(),
          phone: phoneController.text.trim(),
          country: countryController.text.trim(),
          experience: experienceController.text.trim(),
          agencyCode: agencyCodeController.text.trim().isEmpty
              ? null
              : agencyCodeController.text.trim(),
          agencyName: agencyNameController.text.trim().isEmpty
              ? null
              : agencyNameController.text.trim(),
        );
        if (!mounted) return;
        SroodToast.show(
          context,
          context.isArabic ? 'تم إرسال الطلب' : 'Application submitted',
          type: SroodToastType.success,
        );
        _retry();
      }
    } catch (error) {
      if (!mounted) return;
      SroodToast.show(
        context,
        _applicationError(error),
        type: SroodToastType.error,
      );
    } finally {
      if (mounted && _submittingApplication) {
        setState(() => _submittingApplication = false);
      }
      messageController.dispose();
      phoneController.dispose();
      countryController.dispose();
      experienceController.dispose();
      agencyCodeController.dispose();
      agencyNameController.dispose();
    }
  }

  String _applicationError(Object error) {
    final value = error.toString();
    if (value.contains('duplicate_pending_application')) {
      return context.isArabic
          ? 'لديك طلب مماثل قيد المراجعة'
          : 'A similar application is already pending';
    }
    if (value.contains('invalid_or_inactive_agency')) {
      return context.isArabic
          ? 'كود الوكالة غير صالح أو الوكالة غير نشطة'
          : 'The agency code is invalid or inactive';
    }
    if (value.contains('agency_already_owned')) {
      return context.isArabic
          ? 'أنت تملك وكالة بالفعل'
          : 'You already own an agency';
    }
    return context.isArabic
        ? 'تعذر إرسال الطلب. حاول مرة أخرى.'
        : 'Could not submit the application. Please try again.';
  }

  String _loadErrorMessage(Object? error) {
    final value = error?.toString() ?? '';
    if (value.contains('get_my_agency_membership') ||
        value.contains('PGRST202')) {
      return context.isArabic
          ? 'ميزة الوكالة تحتاج تحديث قاعدة البيانات. حاول مجددًا بعد التحديث.'
          : 'Agency data is being updated. Please try again after the database update.';
    }
    return context.isArabic
        ? 'تعذر تحميل بيانات الوكالة. حاول مرة أخرى.'
        : 'Could not load agency data. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

    return ProfileHubScaffold(
      title: isArabic ? 'وكالتي' : 'My agency',
      isArabic: isArabic,
      children: [
        FutureBuilder<
          ({
            AgencyMembership? membership,
            List<AgencyApplication> apps,
            Map<String, dynamic>? ownedAgency,
            Map<String, dynamic> hostStatus,
          })
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
                message: _loadErrorMessage(snapshot.error),
                onRetry: _retry,
                isArabic: isArabic,
              );
            }

            final membership = snapshot.data!.membership;
            final applications = snapshot.data!.apps;
            final ownedAgency = snapshot.data!.ownedAgency;
            final isApprovedHost =
                snapshot.data!.hostStatus['is_approved_host'] == true;
            final pendingTypes = applications
                .where((application) => application.status == 'pending')
                .map((application) => application.applicationType)
                .toSet();

            return Column(
              children: [
                // Agency owners get a focused management entry point.
                if (ownedAgency != null)
                  ProfileMenuItem(
                    icon: Icons.manage_accounts_rounded,
                    title: isArabic ? 'إدارة وكالتي' : 'Manage my agency',
                    subtitle: isArabic
                        ? 'المضيفات النشطات والطلبات قيد الانتظار.'
                        : 'Active hosts and pending applications.',
                    isArabic: isArabic,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AgencyOwnerScreen(),
                        ),
                      );
                      if (mounted) _retry();
                    },
                  ),
                if (membership == null && ownedAgency == null)
                  ProfileEmptyState(
                    icon: Icons.groups_rounded,
                    title: isArabic ? 'لا توجد وكالة بعد' : 'No agency yet',
                    description: isArabic
                        ? 'اختر بين الانضمام إلى وكالة إنشاء وكالة أو التقديم كمضيف.'
                        : 'Choose to join an agency, create one, or apply as a host.',
                    isArabic: isArabic,
                  ),
                if (membership != null)
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
                if (membership == null && isApprovedHost)
                  ProfileInfoCard(
                    icon: Icons.verified_rounded,
                    title: isArabic ? 'مضيف معتمد' : 'Approved host',
                    body: isArabic
                        ? 'تم اعتمادك لاستضافة الغرف المباشرة.'
                        : 'You are approved to host live rooms.',
                    isArabic: isArabic,
                  ),
                if (membership == null && ownedAgency == null) ...[
                  if (!pendingTypes.contains('join_agency'))
                    ProfileMenuItem(
                      icon: Icons.group_add_rounded,
                      title: isArabic ? 'انضم إلى وكالة' : 'Join Agency',
                      subtitle: isArabic
                          ? 'انضم إلى وكالة موجودة عبر دعوة أو موافقة.'
                          : 'Join an existing agency by invitation or approval.',
                      isArabic: isArabic,
                      onTap: () => _openApplication('join_agency'),
                    ),
                  if (!pendingTypes.contains('create_agency'))
                    ProfileMenuItem(
                      icon: Icons.add_business_rounded,
                      title: isArabic ? 'أنشئ وكالة' : 'Create Agency',
                      subtitle: isArabic
                          ? 'ابدأ وكالتك الخاصة وأدر المضيفين.'
                          : 'Start your own agency and manage hosts.',
                      isArabic: isArabic,
                      onTap: () => _openApplication('create_agency'),
                    ),
                ],
                if (!isApprovedHost && !pendingTypes.contains('become_host'))
                  ProfileMenuItem(
                    icon: Icons.mic_external_on_rounded,
                    title: isArabic ? 'كن مضيفا' : 'Become Host',
                    subtitle: isArabic
                        ? 'قدم لتصبح مضيف غرف صوتية وتربح من نشاطك.'
                        : 'Apply to become a live room host and earn from activity.',
                    isArabic: isArabic,
                    onTap: () => _openApplication('become_host'),
                  ),
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
                      message: [
                        if (app.agencyName?.isNotEmpty == true) app.agencyName!,
                        if (app.message?.isNotEmpty == true) app.message!,
                        if (app.adminReply?.isNotEmpty == true)
                          '${isArabic ? 'رد الإدارة' : 'Review'}: ${app.adminReply}',
                      ].join('\n'),
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
