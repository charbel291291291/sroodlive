import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// =============================================================================
// Srood Live - legal screens (Terms of Service & Privacy Policy) and the
// reusable legal footer shown under the login / register actions.
//
// Content is UI-only. It contains no auth, wallet, VIP, room, or Rocket Crash
// logic. Placeholders marked TODO must be filled with the real company legal
// name, support email, and governing law before public launch.
//
// NOTE: Copy is intentionally English-only for now (both languages) to avoid
// any text-encoding issues. RTL layout is still honoured when isArabic is true.
// Localised Arabic copy can be reintroduced later once written in valid UTF-8.
// =============================================================================

const Color _kGold = Color(0xFFF0C15A);
const Color _kMutedText = Color(0xFFB8AECF);
const Color _kBodyText = Color(0xFFD8CFEA);

// Update this whenever the legal copy changes.
const String _kLastUpdated = 'Last updated: TODO: Add last updated date';

/// One titled block of legal copy.
class _LegalSection {
  const _LegalSection(this.heading, this.paragraphs);
  final String heading;
  final List<String> paragraphs;
}

// -----------------------------------------------------------------------------
// Legal footer - "By continuing, you agree to our Terms of Service and
// Privacy Policy." with Terms and Privacy independently tappable.
// -----------------------------------------------------------------------------

class LegalFooter extends StatefulWidget {
  const LegalFooter({super.key, required this.isArabic});

  final bool isArabic;

  @override
  State<LegalFooter> createState() => _LegalFooterState();
}

class _LegalFooterState extends State<LegalFooter> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = _openTerms;
    _privacyTap = TapGestureRecognizer()..onTap = _openPrivacy;
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _openTerms() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TermsOfServiceScreen(isArabic: widget.isArabic),
      ),
    );
  }

  void _openPrivacy() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivacyPolicyScreen(isArabic: widget.isArabic),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    const baseStyle = TextStyle(
      color: _kMutedText,
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w500,
    );
    const linkStyle = TextStyle(
      color: _kGold,
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w800,
    );

    const termsLabel = 'Terms of Service';
    const privacyLabel = 'Privacy Policy';

    final content = TextSpan(
      style: baseStyle,
      children: [
        const TextSpan(text: 'By continuing, you agree to our '),
        TextSpan(text: termsLabel, style: linkStyle, recognizer: _termsTap),
        const TextSpan(text: ' and '),
        TextSpan(text: privacyLabel, style: linkStyle, recognizer: _privacyTap),
        const TextSpan(text: '.'),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(top: 18, bottom: 12 + bottomInset),
      child: Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Text.rich(content, textAlign: TextAlign.center),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared scaffold for both legal screens.
// -----------------------------------------------------------------------------

class _LegalScaffold extends StatelessWidget {
  const _LegalScaffold({
    required this.isArabic,
    required this.title,
    required this.lastUpdated,
    required this.intro,
    required this.sections,
  });

  final bool isArabic;
  final String title;
  final String lastUpdated;
  final String intro;
  final List<_LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final align = isArabic ? TextAlign.right : TextAlign.left;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Directionality(
      textDirection: dir,
      child: Scaffold(
        backgroundColor: const Color(0xFF08060F),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF12061F),
                Color(0xFF07030D),
                Color(0xFF050208),
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(22, 8, 22, 32 + bottomInset),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      lastUpdated,
                      textAlign: align,
                      style: const TextStyle(
                        color: _kMutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      intro,
                      textAlign: align,
                      style: const TextStyle(
                        color: _kBodyText,
                        fontSize: 14,
                        height: 1.6,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final section in sections) ...[
                      const SizedBox(height: 22),
                      Text(
                        section.heading,
                        textAlign: align,
                        style: const TextStyle(
                          color: _kGold,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final paragraph in section.paragraphs) ...[
                        Text(
                          paragraph,
                          textAlign: align,
                          style: const TextStyle(
                            color: _kBodyText,
                            fontSize: 14,
                            height: 1.6,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Terms of Service
// -----------------------------------------------------------------------------

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key, required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return _LegalScaffold(
      isArabic: isArabic,
      title: 'Terms of Service',
      lastUpdated: _kLastUpdated,
      intro:
          'These Terms govern your use of the Srood Live app. Please read them '
          'carefully. By using the app you agree to these Terms.',
      sections: _sections,
    );
  }

  static const List<_LegalSection> _sections = [
    _LegalSection('1. Acceptance of Terms', [
      'By creating an account or using Srood Live, you agree to these Terms '
          'of Service. If you do not agree, please do not use the app.',
    ]),
    _LegalSection('2. Eligibility and Account Responsibility', [
      'You must be old enough to use the app under the laws that apply to '
          'you. You are responsible for keeping your login details secure and '
          'for all activity that happens under your account.',
      'You agree to provide accurate information and to keep it up to date.',
    ]),
    _LegalSection('3. User Profile and Public Content', [
      'Information you add to your profile, and content you share in the app, '
          'may be visible to other users. Do not post content you do not have '
          'the right to share.',
    ]),
    _LegalSection('4. Live Rooms and Voice Behavior', [
      'Srood Live includes live voice rooms. When you speak in a room, your '
          'voice is transmitted to other participants so the room can '
          'function. Behave respectfully toward other people in the room.',
    ]),
    _LegalSection('5. Prohibited Behavior', [
      'You may not use Srood Live to harass, threaten, or harm others; to '
          'share illegal, hateful, or sexually exploitative content; to '
          'impersonate others; or to disrupt the service. We may remove '
          'content and restrict accounts that break these rules.',
    ]),
    _LegalSection('6. Coins, Gifts, Wallet, and Virtual Items', [
      'Coins, gifts, and other virtual items have no real-world monetary '
          'value, are not redeemable for cash, and are licensed to you for '
          'use inside the app only. Purchases of virtual items are generally '
          'final except where a refund is required by law.',
    ]),
    _LegalSection('7. VIP and Paid Features', [
      'Some features may require payment or a VIP subscription. The benefits '
          'and duration of paid features are described where they are offered. '
          'Paid features may change over time.',
    ]),
    _LegalSection('8. Moderation, Reports, Bans, Mutes, and Restrictions', [
      'To keep the community safe we may review reports and take action, '
          'including muting, restricting, suspending, or banning accounts, and '
          'removing content. Actions may be temporary or, for serious '
          'violations, longer-lasting.',
    ]),
    _LegalSection('9. Safety and Community Standards', [
      'You are expected to follow our community standards and to help keep '
          'Srood Live safe by reporting behavior that breaks these Terms.',
    ]),
    _LegalSection('10. Service Availability', [
      'We aim to keep the app available, but we cannot guarantee it will be '
          'uninterrupted or error-free. The service may be unavailable at '
          'times for maintenance or reasons outside our control.',
    ]),
    _LegalSection('11. Changes to the Service', [
      'We may add, change, or remove features, and we may update these Terms. '
          'If we make significant changes we will take reasonable steps to let '
          'you know. Continued use after changes means you accept them.',
    ]),
    _LegalSection('12. Limitation of Liability', [
      'To the extent permitted by law, Srood Live is provided "as is" and we '
          'are not liable for indirect or incidental damages arising from your '
          'use of the app.',
    ]),
    _LegalSection('13. Contact', [
      'Contact:\nTODO: Add support email for Srood Live\n'
          'TODO: Add company legal name\n'
          'TODO: Add governing law / jurisdiction',
    ]),
  ];
}

// -----------------------------------------------------------------------------
// Privacy Policy
// -----------------------------------------------------------------------------

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key, required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return _LegalScaffold(
      isArabic: isArabic,
      title: 'Privacy Policy',
      lastUpdated: _kLastUpdated,
      intro:
          'This Policy explains what data Srood Live collects, how it is used, '
          'and the choices you have.',
      sections: _sections,
    );
  }

  static const List<_LegalSection> _sections = [
    _LegalSection('1. Information We Collect', [
      'We collect the information described below to provide and improve the '
          'app. The exact data depends on how you use Srood Live.',
    ]),
    _LegalSection('2. Account Data', [
      'When you register we collect data such as your email, username, and '
          'display name so we can create and secure your account.',
    ]),
    _LegalSection('3. Profile Data', [
      'Information you add to your profile, such as your name, photo, and '
          'other details you choose to share, is stored so it can be shown in '
          'the app.',
    ]),
    _LegalSection('4. Live Room Activity', [
      'We process information about your activity in live rooms, such as the '
          'rooms you join and your participation, so rooms can function.',
    ]),
    _LegalSection('5. Voice and Audio Handling', [
      'When you speak in a live room, your live voice is transmitted in real '
          'time to other participants so the room can function. This is a core '
          'part of how voice rooms work.',
    ]),
    _LegalSection('6. Messages and Reports', [
      'We process messages you send within the app and any reports you submit '
          'or that are submitted about you, so we can deliver messages and '
          'review safety issues.',
    ]),
    _LegalSection('7. Wallet, Coins, Gifts, and Transaction Records', [
      'We keep records of coin balances, gifts, and related transactions so '
          'we can operate the wallet, prevent abuse, and maintain accurate '
          'records.',
    ]),
    _LegalSection('8. Device and Technical Data', [
      'We may collect technical information such as device type, app version, '
          'and basic diagnostic data to keep the app working and to fix '
          'problems.',
    ]),
    _LegalSection('9. How We Use Data', [
      'We use data to operate and improve the app, personalize your '
          'experience, communicate with you, keep the service secure, and '
          'comply with legal obligations.',
    ]),
    _LegalSection('10. Safety, Moderation, and Fraud Prevention', [
      'We use data to detect and respond to abuse, enforce our rules, review '
          'reports, and help prevent fraud and other harm.',
    ]),
    _LegalSection('11. Data Sharing with Service Providers', [
      'We may share data with trusted service providers who help us operate '
          'the app, such as hosting and real-time voice infrastructure. They '
          'may only use the data to provide their services to us.',
    ]),
    _LegalSection('12. Data Retention', [
      'We keep data for as long as needed to provide the app, meet legal '
          'requirements, resolve disputes, and enforce our agreements.',
    ]),
    _LegalSection('13. User Choices and Deletion Requests', [
      'You can update certain profile information in the app. You may request '
          'deletion of your account and associated data, subject to records '
          'we must keep by law.',
    ]),
    _LegalSection('14. Children / Minors', [
      'TODO: Add minimum age and children/minors policy for Srood Live. The '
          'app is not intended for users under the required minimum age.',
    ]),
    _LegalSection('15. Contact', [
      'Contact:\nTODO: Add support email for Srood Live\n'
          'TODO: Add company legal name\n'
          'TODO: Add governing law / jurisdiction',
    ]),
  ];
}
