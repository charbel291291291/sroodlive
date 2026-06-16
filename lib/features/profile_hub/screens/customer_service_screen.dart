import 'package:flutter/material.dart';

import '../models/profile_hub_models.dart';
import '../services/support_service.dart';
import '../widgets/profile_hub_widgets.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class CustomerServiceScreen extends StatefulWidget {
  const CustomerServiceScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<CustomerServiceScreen> createState() => _CustomerServiceScreenState();
}

class _CustomerServiceScreenState extends State<CustomerServiceScreen> {
  final SupportService _service = const SupportService();
  late Future<List<SupportTicket>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.getMyTickets();
  }

  void _retry() => setState(() => _future = _service.getMyTickets());

  List<({String key, IconData icon, String en, String ar, String subtitle})>
  get _categories => [
    (
      key: 'recharge_support',
      icon: Icons.add_card_rounded,
      en: 'Recharge Support',
      ar: 'دعم الشحن',
      subtitle: 'Payments, references, pending recharge',
    ),
    (
      key: 'account_problem',
      icon: Icons.manage_accounts_rounded,
      en: 'Account Problem',
      ar: 'مشكلة حساب',
      subtitle: 'Login, profile, access',
    ),
    (
      key: 'report_user',
      icon: Icons.report_rounded,
      en: 'Report User',
      ar: 'إبلاغ عن مستخدم',
      subtitle: 'Harassment, scams, impersonation',
    ),
    (
      key: 'report_room',
      icon: Icons.meeting_room_rounded,
      en: 'Report Room',
      ar: 'إبلاغ عن غرفة',
      subtitle: 'Room safety and moderation',
    ),
    (
      key: 'agency_support',
      icon: Icons.groups_rounded,
      en: 'Agency Support',
      ar: 'دعم الوكالات',
      subtitle: 'Hosts, targets, applications',
    ),
    (
      key: 'vip_gifts_support',
      icon: Icons.workspace_premium_rounded,
      en: 'VIP and Gifts Support',
      ar: 'دعم VIP والهدايا',
      subtitle: 'VIP, gifts, badges, frames',
    ),
    (
      key: 'other',
      icon: Icons.support_agent_rounded,
      en: 'Other Problem',
      ar: 'مشكلة أخرى',
      subtitle: 'Anything else',
    ),
  ];

  Future<void> _openForm(String category, String title) async {
    final subjectController = TextEditingController(text: title);
    final messageController = TextEditingController();
    final referenceController = TextEditingController();
    final isArabic = context.isArabic;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: profileHubCard,
      isScrollControlled: true,
      builder: (context) => SafeArea(
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
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectController,
                  decoration: InputDecoration(
                    labelText: isArabic ? 'الموضوع' : 'Subject',
                  ),
                ),
                if (category == 'recharge_support') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: referenceController,
                    decoration: InputDecoration(
                      labelText: isArabic ? 'رقم الدفع' : 'Payment reference',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: messageController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: isArabic ? 'اشرح المشكلة' : 'Describe the issue',
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(isArabic ? 'إرسال' : 'Submit'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (submitted == true && messageController.text.trim().isNotEmpty) {
      await _service.createTicket(
        category: category,
        subject: subjectController.text.trim().isEmpty
            ? title
            : subjectController.text.trim(),
        message: messageController.text.trim(),
        paymentReference: referenceController.text.trim(),
      );
      _retry();
    }

    subjectController.dispose();
    messageController.dispose();
    referenceController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

    return ProfileHubScaffold(
      title: isArabic ? 'خدمة العملاء' : 'Customer Service',
      isArabic: isArabic,
      children: [
        ..._categories.map(
          (category) => ProfileMenuItem(
            icon: category.icon,
            title: isArabic ? category.ar : category.en,
            subtitle: category.subtitle,
            gradientIcon: category.key == 'recharge_support',
            isArabic: isArabic,
            onTap: () =>
                _openForm(category.key, isArabic ? category.ar : category.en),
          ),
        ),
        ProfileSectionTitle(
          title: isArabic ? 'تذاكري' : 'My support tickets',
          isArabic: isArabic,
        ),
        FutureBuilder<List<SupportTicket>>(
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
                message:
                    snapshot.error?.toString() ??
                    'Failed to load support tickets.',
                onRetry: _retry,
                isArabic: isArabic,
              );
            }
            final tickets = snapshot.data!;
            if (tickets.isEmpty) {
              return ProfileEmptyState(
                icon: Icons.support_agent_rounded,
                title: isArabic ? 'لا توجد تذاكر' : 'No support tickets yet',
                description: isArabic
                    ? 'اختر تصنيفاً بالأعلى لإرسال طلب دعم.'
                    : 'Choose a category above to create a support ticket.',
                isArabic: isArabic,
              );
            }
            return Column(
              children: tickets
                  .map(
                    (ticket) => TicketCard(
                      title: ticket.subject,
                      status: ticket.status,
                      message: [
                        ticket.category,
                        ticket.message,
                        if (ticket.adminReply != null) ticket.adminReply!,
                      ].join('\n'),
                      date: ticket.createdAt,
                      isArabic: isArabic,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}
