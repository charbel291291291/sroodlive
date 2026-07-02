import 'package:flutter/material.dart';

import '../../../core/auth/safe_logout.dart';
import '../../../core/extensions/locale_extension.dart';
import '../../onboarding/onboarding_screen.dart';
import '../services/account_service.dart';
import 'package:srood_live/main.dart' show rootNavigatorKey;
import 'package:srood_live/shared/widgets/srood_toast.dart';

/// Store-required in-app account deletion (Google Play User Data policy /
/// Apple 5.1.1(v)). Explains exactly what happens, requires a typed
/// confirmation so it can't be triggered accidentally, calls the
/// `request_account_deletion` RPC (which anonymizes PII server-side), then
/// signs the user out.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const _service = AccountService();

  final _reasonController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;

  bool get _ar => widget.isArabic;

  // The word the user must type to confirm (localized).
  String get _confirmWord => _ar ? 'حذف' : 'DELETE';

  @override
  void dispose() {
    _reasonController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      _confirmController.text.trim().toUpperCase() ==
          _confirmWord.toUpperCase();

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      await _service.requestDeletion(
        reason: _reasonController.text.trim().isEmpty
            ? null
            : _reasonController.text.trim(),
      );
      // Deletion succeeded server-side; sign out and return to onboarding.
      await SafeLogout.run();
      if (!mounted) return;
      final nav = rootNavigatorKey.currentState;
      nav?.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      SroodToast.show(
        context,
        _ar ? 'تعذر حذف الحساب. حاول مجددًا.' : 'Could not delete account. Please try again.',
        type: SroodToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFF0C0E14),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0C0E14),
          elevation: 0,
          title: Text(
            isArabic ? 'حذف الحساب' : 'Delete Account',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const SizedBox(height: 8),
              const Center(
                child: Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFEF4444), size: 56),
              ),
              const SizedBox(height: 16),
              Text(
                isArabic
                    ? 'حذف حسابك نهائي ولا يمكن التراجع عنه.'
                    : 'Deleting your account is permanent and cannot be undone.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              _bullets(isArabic),
              const SizedBox(height: 24),
              Text(
                isArabic
                    ? 'سبب المغادرة (اختياري)'
                    : 'Reason for leaving (optional)',
                style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                maxLength: 500,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration(
                  isArabic ? 'أخبرنا لماذا...' : 'Tell us why...',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isArabic
                    ? 'اكتب "$_confirmWord" للتأكيد'
                    : 'Type "$_confirmWord" to confirm',
                style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1),
                decoration: _fieldDecoration(_confirmWord),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    disabledBackgroundColor: const Color(0xFF3A2226),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          isArabic ? 'حذف حسابي نهائيًا' : 'Delete my account',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).maybePop(),
                  child: Text(
                    isArabic ? 'إلغاء' : 'Cancel',
                    style: const TextStyle(color: Color(0xFF9E91B8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullets(bool isArabic) {
    final items = isArabic
        ? const [
            'سيتم حذف اسمك وصورتك وبياناتك الشخصية.',
            'لن تتمكن من الوصول إلى حسابك أو رصيدك.',
            'يتم الاحتفاظ بسجلات المعاملات المالية للأغراض القانونية والمحاسبية فقط.',
          ]
        : const [
            'Your name, photo and personal data will be removed.',
            'You will lose access to your account and coin balance.',
            'Financial transaction records are retained only for legal and accounting purposes.',
          ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141720),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2435)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map(
              (t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.circle, color: Color(0xFFEF4444), size: 7),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t,
                        style: const TextStyle(
                            color: Color(0xFFC9C0DE), fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF5A5470)),
        filled: true,
        fillColor: const Color(0xFF141720),
        counterStyle: const TextStyle(color: Color(0xFF5A5470)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1E2435)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
      );
}
