import 'package:flutter/material.dart';

import '../models/profile_hub_models.dart';
import '../services/feedback_service.dart';
import '../widgets/profile_hub_widgets.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final FeedbackService _service = const FeedbackService();
  late Future<List<FeedbackTicket>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.getMyTickets();
  }

  void _retry() => setState(() => _future = _service.getMyTickets());

  Future<void> _openForm() async {
    final isArabic = widget.isArabic;
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    var category = 'suggestion';

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: profileHubCard,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
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
                    isArabic ? 'ملاحظات جديدة' : 'New feedback',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    items:
                        const [
                              'bug',
                              'suggestion',
                              'complaint',
                              'room_problem',
                              'gift_problem',
                              'wallet_problem',
                              'vip_problem',
                              'other',
                            ]
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setSheetState(() => category = value ?? 'other'),
                    decoration: InputDecoration(
                      labelText: isArabic ? 'التصنيف' : 'Category',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: isArabic ? 'العنوان' : 'Title',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: messageController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: isArabic ? 'الرسالة' : 'Message',
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
      ),
    );

    if (submitted == true &&
        titleController.text.trim().isNotEmpty &&
        messageController.text.trim().isNotEmpty) {
      await _service.createTicket(
        category: category,
        title: titleController.text.trim(),
        message: messageController.text.trim(),
      );
      _retry();
    }

    titleController.dispose();
    messageController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return ProfileHubScaffold(
      title: isArabic ? 'ملاحظات' : 'Feedback',
      isArabic: isArabic,
      actions: [
        IconButton(onPressed: _openForm, icon: const Icon(Icons.add_rounded)),
      ],
      children: [
        ProfileInfoCard(
          icon: Icons.feedback_rounded,
          title: isArabic ? 'ساعدنا نحسن SrOOd' : 'Help improve SrOOd',
          body: isArabic
              ? 'أرسل مشكلة، اقتراح، أو شكوى وسيتم مراجعتها من الإدارة.'
              : 'Send bugs, suggestions, or complaints for admin review.',
          isArabic: isArabic,
          action: FilledButton.icon(
            onPressed: _openForm,
            icon: const Icon(Icons.edit_rounded),
            label: Text(isArabic ? 'ملاحظات جديدة' : 'New feedback'),
          ),
        ),
        FutureBuilder<List<FeedbackTicket>>(
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
                    snapshot.error?.toString() ?? 'Failed to load feedback.',
                onRetry: _retry,
                isArabic: isArabic,
              );
            }
            final tickets = snapshot.data!;
            if (tickets.isEmpty) {
              return ProfileEmptyState(
                icon: Icons.inbox_rounded,
                title: isArabic ? 'لا توجد ملاحظات' : 'No feedback yet',
                description: isArabic
                    ? 'ستظهر رسائلك هنا.'
                    : 'Your feedback tickets will appear here.',
                isArabic: isArabic,
              );
            }
            return Column(
              children: tickets
                  .map(
                    (ticket) => TicketCard(
                      title: ticket.title,
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
