import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// =============================================================================
// Srood Live - legal screens (Terms of Service & Privacy Policy) and the
// reusable legal footer shown under the login / register actions.
//
// Content is UI-only. It contains no auth, wallet, VIP, room, or Rocket Crash
// logic.
//
// NOTE: Copy is intentionally English-only for now (both languages) to avoid
// any text-encoding issues. RTL layout is still honoured when isArabic is true.
// Localised Arabic copy can be reintroduced later once written in valid UTF-8.
// =============================================================================

const Color _kGold = Color(0xFFF0C15A);
const Color _kMutedText = Color(0xFFB8AECF);
const Color _kBodyText = Color(0xFFD8CFEA);

const String _kSupportEmail = 'support@sroodlive.com';

// Update this whenever the legal copy changes.
const String _kLastUpdated = 'Last updated: June 2025';

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
              colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
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
          'of Service and our Privacy Policy. If you do not agree, please do '
          'not use the app.',
    ]),
    _LegalSection('2. Eligibility', [
      'Srood Live is intended for users who are 18 years of age or older. '
          'By registering, you confirm that you are at least 18 years old. '
          'If we learn that a user is under 18, we will suspend or close '
          'that account.',
    ]),
    _LegalSection('3. Account Responsibility', [
      'You are responsible for keeping your login credentials secure and for '
          'all activity that takes place under your account. Do not share your '
          'password with anyone.',
      'You agree to provide accurate, current information when registering '
          'and to keep it up to date.',
    ]),
    _LegalSection('4. User Profile and Public Content', [
      'Information you add to your profile and content you share in the app '
          'may be visible to other users. Do not post content you do not have '
          'the right to share.',
      'You are responsible for the content you publish. Content must not '
          'violate anyone\'s rights or these Terms.',
    ]),
    _LegalSection('5. Live Rooms and Voice Conduct', [
      'Srood Live includes live voice rooms where your voice is transmitted '
          'in real time to other participants. You must behave respectfully '
          'toward all other people in the room at all times.',
      'Live rooms are not end-to-end encrypted and are not guaranteed to be '
          'private. Do not share sensitive personal information in public '
          'voice rooms.',
      'Room hosts and moderators may mute, remove, or restrict participants '
          'at their discretion. Their decisions within a room are final.',
    ]),
    _LegalSection('6. Prohibited Behavior', [
      'You may not use Srood Live to:',
      '- Harass, threaten, bully, or harm other users.',
      '- Share illegal, hateful, defamatory, or sexually explicit content.',
      '- Impersonate any person or organization.',
      '- Solicit or distribute spam, scams, or unauthorized advertising.',
      '- Circumvent moderation, bans, or account restrictions.',
      '- Engage in any activity that violates applicable law.',
      'We may remove content and restrict, suspend, or permanently ban '
          'accounts that violate these rules.',
    ]),
    _LegalSection('7. Coins, Gifts, Wallet, and Virtual Items', [
      'Srood Coins, gifts, and other virtual items are digital goods licensed '
          'to you for use inside the app only. They have no real-world '
          'monetary value and are not redeemable for cash except where '
          'expressly permitted by official host-income or withdrawal features '
          'described in the app.',
      'Purchases of virtual items are generally final and non-refundable '
          'except where required by applicable law.',
      'We reserve the right to modify, adjust, or discontinue virtual items '
          'or coin balances where necessary to maintain the integrity of the '
          'platform.',
    ]),
    _LegalSection('8. VIP and Paid Features', [
      'Some features require payment or a VIP subscription. Benefits and '
          'duration are described at the point of purchase. Paid features and '
          'their pricing may change over time with reasonable notice.',
    ]),
    _LegalSection('9. Moderation, Reports, Suspensions, and Bans', [
      'To keep the community safe we review reports and may take action '
          'including muting, restricting, suspending, or permanently banning '
          'accounts, and removing or hiding content.',
      'Actions may be temporary or permanent depending on the severity and '
          'history of the violation. We are not required to provide advance '
          'notice before taking action.',
      'You can report users or content through the in-app reporting tools. '
          'False or abusive reports may themselves result in account action.',
    ]),
    _LegalSection('10. Safety and Community Standards', [
      'You are expected to treat all users with respect and to help keep '
          'Srood Live safe by using the report tools when you encounter '
          'behavior that breaks these Terms.',
    ]),
    _LegalSection('11. Service Availability', [
      'We aim to keep the app available at all times, but we cannot '
          'guarantee it will be uninterrupted or error-free. The service may '
          'be temporarily unavailable for maintenance or for reasons outside '
          'our control.',
    ]),
    _LegalSection('12. Changes to the Service and These Terms', [
      'We may add, change, or remove features and may update these Terms at '
          'any time. We will take reasonable steps to notify you of significant '
          'changes. Continued use of the app after changes are posted means '
          'you accept the updated Terms.',
    ]),
    _LegalSection('13. Limitation of Liability', [
      'To the extent permitted by applicable law, Srood Live is provided '
          '"as is" without warranties of any kind. We are not liable for '
          'indirect, incidental, or consequential damages arising from your '
          'use of, or inability to use, the app.',
    ]),
    _LegalSection('14. Contact Us', [
      'If you have questions about these Terms, please contact us:\n'
          'Email: $_kSupportEmail',
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
      'We collect the categories of information described below in order to '
          'provide, operate, and improve Srood Live. What we collect depends '
          'on how you use the app.',
    ]),
    _LegalSection('2. Account Data', [
      'When you register we collect your email address, chosen username, and '
          'display name so we can create and secure your account.',
    ]),
    _LegalSection('3. Profile Data', [
      'Information you add to your public profile — such as your display '
          'name, profile photo, bio, and VIP or frame selections — is stored '
          'so it can be shown to other users in the app.',
    ]),
    _LegalSection('4. Live Room Activity', [
      'We record information about rooms you join or host, your role (host, '
          'moderator, speaker, or listener), seat positions, and participation '
          'so rooms can function correctly and be moderated.',
    ]),
    _LegalSection('5. Voice and Audio Handling', [
      'When you speak in a live room, your voice is transmitted in real time '
          'to other participants using our voice infrastructure. Live audio is '
          'not end-to-end encrypted. This is a core part of how voice rooms '
          'work and is required for the service to function.',
    ]),
    _LegalSection('6. Chat Messages', [
      'Room chat messages you send are stored so they can be displayed to '
          'room participants and, where required for safety, reviewed by '
          'moderators. Private messages between users are stored to deliver '
          'them to recipients.',
    ]),
    _LegalSection('7. Reports and Moderation Evidence', [
      'When you submit a report about another user, or a report is submitted '
          'about you, we store the report details, reason, and a snapshot of '
          'recent room chat as moderation evidence. This data is used only by '
          'our moderation team to review safety issues.',
    ]),
    _LegalSection('8. Wallet, Coins, Gifts, and Recharge Records', [
      'We keep records of coin balances, gifts sent and received, recharge '
          'transactions, and payout requests so we can operate the wallet, '
          'prevent abuse, resolve disputes, and maintain accurate financial '
          'records.',
    ]),
    _LegalSection('9. Device and Diagnostic Data', [
      'We may collect technical data such as device type, operating system '
          'version, app version, and crash or error reports to keep the app '
          'working, fix problems, and improve performance.',
    ]),
    _LegalSection('10. How We Use Your Data', [
      'We use your data to:',
      '- Operate and deliver the features of Srood Live.',
      '- Personalize your experience (VIP benefits, room history, etc.).',
      '- Process recharge and payout transactions.',
      '- Communicate service updates and support responses.',
      '- Enforce our Terms of Service and community rules.',
      '- Detect and prevent fraud, abuse, and unauthorized access.',
      '- Improve app performance and fix technical issues.',
      '- Comply with applicable legal obligations.',
    ]),
    _LegalSection('11. Safety, Moderation, and Fraud Prevention', [
      'We use data — including chat snapshots, room activity, and report '
          'history — to review reported behavior, enforce our rules, and '
          'protect users from harm. This processing is necessary to maintain '
          'a safe community.',
    ]),
    _LegalSection('12. Data Sharing', [
      'We do not sell your personal data. We may share data with:',
      '- Trusted infrastructure and hosting providers who help us run the '
          'app (such as database and real-time voice services). They may only '
          'use data to provide their services to us.',
      '- Payment and recharge partners where required to process '
          'transactions.',
      '- Law enforcement or regulators where we are required to do so by '
          'applicable law, or where necessary to protect users from serious '
          'harm.',
    ]),
    _LegalSection('13. Data Retention', [
      'We keep account and profile data for as long as your account is '
          'active and for a reasonable period after account deletion.',
      'Moderation evidence and reports are kept as long as necessary to '
          'resolve the matter and protect against future harm.',
      'Transaction and wallet records are kept as required for financial '
          'record-keeping and legal compliance.',
      'You may request deletion of your account and associated data. Certain '
          'records required by law or for dispute resolution will be retained '
          'for the period required.',
    ]),
    _LegalSection('14. Your Rights', [
      'You can update most profile information directly in the app. You may '
          'contact us to request access to, correction of, or deletion of '
          'personal data we hold about you, subject to legal retention '
          'requirements.',
    ]),
    _LegalSection('15. Age Restriction', [
      'Srood Live is strictly for users aged 18 and over. We do not '
          'knowingly collect personal data from anyone under 18. If you '
          'believe a user under 18 is using the app, please report it '
          'through the in-app report tools or contact us directly.',
    ]),
    _LegalSection('16. Contact Us', [
      'If you have questions about this Privacy Policy or wish to exercise '
          'your data rights, please contact us:\n'
          'Email: $_kSupportEmail',
    ]),
  ];
}
