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
                children: [
                  Text(
                    widget.isArabic
                        ? 'ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨ Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'
                        : 'Agency application',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    decoration: InputDecoration(
                      labelText: widget.isArabic
                          ? 'ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚Â'
                          : 'Phone',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: countryController,
                    decoration: InputDecoration(
                      labelText: widget.isArabic
                          ? 'ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'
                          : 'Country',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: experienceController,
                    decoration: InputDecoration(
                      labelText: widget.isArabic
                          ? 'ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â®ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â©'
                          : 'Experience',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: messageController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: widget.isArabic
                          ? 'ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚ÂªÃƒâ„¢Ã†â€™'
                          : 'Message',
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(
                        widget.isArabic
                            ? 'ÃƒËœÃ‚Â¥ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾'
                            : 'Submit',
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
            ? _agencyApplicationDefaultMessage(type)
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

  String _agencyApplicationTitle(String type) {
    return switch (type) {
      'join_agency' =>
        widget.isArabic
            ? 'Ã˜Â§Ã™â€ Ã˜Â¶Ã™â€¦Ã˜Â§Ã™â€¦ Ã˜Â¥Ã™â€žÃ™â€° Ã™Ë†Ã™Æ’Ã˜Â§Ã™â€žÃ˜Â©'
            : 'Join Agency',
      'create_agency' =>
        widget.isArabic
            ? 'Ã˜Â¥Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â¡ Ã™Ë†Ã™Æ’Ã˜Â§Ã™â€žÃ˜Â©'
            : 'Create Agency',
      'become_host' =>
        widget.isArabic ? 'Ã˜Â·Ã™â€žÃ˜Â¨ Ã™â€¦Ã˜Â¶Ã™Å Ã™Â' : 'Become Host',
      _ => type,
    };
  }

  String _agencyApplicationDefaultMessage(String type) {
    return switch (type) {
      'join_agency' =>
        widget.isArabic
            ? 'Ã˜Â£Ã˜Â±Ã™Å Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â§Ã™â€ Ã˜Â¶Ã™â€¦Ã˜Â§Ã™â€¦ Ã˜Â¥Ã™â€žÃ™â€° Ã™Ë†Ã™Æ’Ã˜Â§Ã™â€žÃ˜Â© Ã™â€¦Ã™Ë†Ã˜Â¬Ã™Ë†Ã˜Â¯Ã˜Â©.'
            : 'I want to join an existing agency.',
      'create_agency' =>
        widget.isArabic
            ? 'Ã˜Â£Ã˜Â±Ã™Å Ã˜Â¯ Ã˜Â¥Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â¡ Ã™Ë†Ã™Æ’Ã˜Â§Ã™â€žÃ˜Â© Ã˜Â¬Ã˜Â¯Ã™Å Ã˜Â¯Ã˜Â© Ã™Ë†Ã˜Â¥Ã˜Â¯Ã˜Â§Ã˜Â±Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â¶Ã™Å Ã™ÂÃ™Å Ã™â€ .'
            : 'I want to create a new agency and manage hosts.',
      'become_host' =>
        widget.isArabic
            ? 'Ã˜Â£Ã˜Â±Ã™Å Ã˜Â¯ Ã˜Â£Ã™â€  Ã˜Â£Ã˜ÂµÃ˜Â¨Ã˜Â­ Ã™â€¦Ã˜Â¶Ã™Å Ã™Â Ã˜ÂºÃ˜Â±Ã™Â Ã˜ÂµÃ™Ë†Ã˜ÂªÃ™Å Ã˜Â©.'
            : 'I want to become a live room host.',
      _ =>
        widget.isArabic
            ? 'Ã˜Â·Ã™â€žÃ˜Â¨ Ã™Ë†Ã™Æ’Ã˜Â§Ã™â€žÃ˜Â©'
            : 'Agency application',
    };
  }

  @override
  Widget build(BuildContext context) {
    return ProfileHubScaffold(
      title: widget.isArabic
          ? 'Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚ÂªÃƒâ„¢Ã…Â '
          : 'My agency',
      isArabic: widget.isArabic,
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
                isArabic: widget.isArabic,
              );
            }

            final membership = snapshot.data!.membership;
            final applications = snapshot.data!.apps;

            return Column(
              children: [
                if (membership == null)
                  ProfileEmptyState(
                    icon: Icons.groups_rounded,
                    title: widget.isArabic
                        ? 'Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â© ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¯'
                        : 'No agency yet',
                    description: widget.isArabic
                        ? 'Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã†â€™Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã†â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¶Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¥Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â° Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©ÃƒËœÃ…â€™ ÃƒËœÃ‚Â¥Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â´ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¡ Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©ÃƒËœÃ…â€™ ÃƒËœÃ‚Â£Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã…Â Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã†â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¶Ãƒâ„¢Ã…Â Ãƒâ„¢Ã‚Â.'
                        : 'Apply to join an agency, create one, or become a host.',
                    isArabic: widget.isArabic,
                  )
                else
                  ProfileInfoCard(
                    icon: Icons.apartment_rounded,
                    title: membership.agencyName,
                    body:
                        '${widget.isArabic ? 'ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±' : 'Role'}: ${membership.role}\n'
                        '${widget.isArabic ? 'ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©' : 'Status'}: ${membership.status}\n'
                        '${widget.isArabic ? 'ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©' : 'Commission'}: ${(membership.commissionRate * 100).toStringAsFixed(1)}%\n'
                        '${widget.isArabic ? 'Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª' : 'Coin target'}: ${membership.monthlyTargetCoins}\n'
                        '${widget.isArabic ? 'Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª' : 'Hour target'}: ${membership.monthlyTargetHours}',
                    isArabic: widget.isArabic,
                  ),
                if (membership == null) ...[
                  ProfileMenuItem(
                    icon: Icons.group_add_rounded,
                    title: widget.isArabic
                        ? 'ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¶Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¥Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â° Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'
                        : 'Join Agency',
                    isArabic: widget.isArabic,
                    onTap: () => _openApplication('join_agency'),
                  ),
                  ProfileMenuItem(
                    icon: Icons.add_business_rounded,
                    title: widget.isArabic
                        ? 'ÃƒËœÃ‚Â£Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¦ Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã†â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â©'
                        : 'Create Agency',
                    isArabic: widget.isArabic,
                    onTap: () => _openApplication('create_agency'),
                  ),
                  ProfileMenuItem(
                    icon: Icons.mic_external_on_rounded,
                    title: widget.isArabic
                        ? 'Ãƒâ„¢Ã†â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¶Ãƒâ„¢Ã…Â Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¹'
                        : 'Become Host',
                    isArabic: widget.isArabic,
                    onTap: () => _openApplication('become_host'),
                  ),
                ],
                ProfileSectionTitle(
                  title: widget.isArabic
                      ? 'ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª'
                      : 'Applications',
                  isArabic: widget.isArabic,
                ),
                if (applications.isEmpty)
                  ProfileEmptyState(
                    icon: Icons.inbox_rounded,
                    title: widget.isArabic
                        ? 'Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª'
                        : 'No applications',
                    description: widget.isArabic
                        ? 'ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¸Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒâ„¢Ã†â€™ Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â¥ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾.'
                        : 'Your applications will appear here after submission.',
                    isArabic: widget.isArabic,
                  )
                else
                  ...applications.map(
                    (app) => TicketCard(
                      title: _agencyApplicationTitle(app.applicationType),
                      status: app.status,
                      message: app.message ?? '',
                      date: app.createdAt,
                      isArabic: widget.isArabic,
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
