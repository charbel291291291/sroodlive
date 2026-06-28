import 'package:flutter/material.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class HostRegistrationScreen extends StatefulWidget {
  const HostRegistrationScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<HostRegistrationScreen> createState() => _HostRegistrationScreenState();
}

class _HostRegistrationScreenState extends State<HostRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();
  final _socialController = TextEditingController();
  String _category = 'entertainment';
  bool _isLoading = false;
  bool _submitted = false;
  String? _existingStatus;

  static const List<Map<String, String>> _categories = [
    {'key': 'entertainment', 'en': 'Entertainment', 'ar': 'ترفيه'},
    {'key': 'music', 'en': 'Music', 'ar': 'موسيقى'},
    {'key': 'education', 'en': 'Education', 'ar': 'تعليم'},
    {'key': 'sports', 'en': 'Sports', 'ar': 'رياضة'},
    {'key': 'gaming', 'en': 'Gaming', 'ar': 'ألعاب'},
    {'key': 'lifestyle', 'en': 'Lifestyle', 'ar': 'أسلوب حياة'},
  ];

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _socialController.dispose();
    super.dispose();
  }

  Future<void> _checkExisting() async {
    try {
      final user = SupabaseService.requiredClient.auth.currentUser;
      if (user == null) return;
      final data = await SupabaseService.requiredClient
          .from('host_applications')
          .select('status')
          .eq('user_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (data != null) {
        setState(() => _existingStatus = data['status'] as String?);
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      final user = SupabaseService.requiredClient.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      await SupabaseService.requiredClient.from('host_applications').upsert({
        'user_id': user.id,
        'category': _category,
        'bio': _bioController.text.trim(),
        'social_links': _socialController.text.trim(),
        'status': 'pending',
        'applied_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (!mounted) return;
      SroodToast.show(context, 'Error: $e', type: SroodToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final crossAxis = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Scaffold(
      backgroundColor: const Color(0xFF08060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: _existingStatus != null
              ? _buildStatusView(isArabic)
              : (_submitted
                    ? _buildSuccess(isArabic)
                    : _buildForm(isArabic, dir, crossAxis)),
        ),
      ),
    );
  }

  Widget _buildForm(
    bool isArabic,
    TextDirection dir,
    CrossAxisAlignment crossAxis,
  ) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: Column(
          crossAxisAlignment: crossAxis,
          children: [
            _buildHeader(isArabic),
            const SizedBox(height: 16),
            _buildInfoCard(isArabic),
            const SizedBox(height: 22),
            _buildLabel(isArabic ? 'تخصصك' : 'Your category', isArabic),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((c) {
                final selected = _category == c['key'];
                return GestureDetector(
                  onTap: () => setState(() => _category = c['key']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF3A174F)
                          : const Color(0xFF160B24),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF8B26D9)
                            : const Color(0xFF4A3470),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      isArabic ? c['ar']! : c['en']!,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFFBCAED6),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _buildLabel(isArabic ? 'نبذة عن نفسك' : 'About yourself', isArabic),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bioController,
              maxLines: 4,
              maxLength: 300,
              textDirection: dir,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              validator: (v) => (v == null || v.trim().length < 20)
                  ? (isArabic ? 'على الأقل 20 حرف' : 'At least 20 characters')
                  : null,
              decoration: _inputDecoration(
                isArabic
                    ? 'أخبرنا لماذا تريد أن تصبح مضيفاً...'
                    : 'Tell us why you want to become a host...',
              ),
            ),
            const SizedBox(height: 14),
            _buildLabel(
              isArabic
                  ? 'روابط التواصل الاجتماعي (اختياري)'
                  : 'Social links (optional)',
              isArabic,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _socialController,
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDecoration(
                isArabic
                    ? 'Instagram، TikTok، YouTube...'
                    : 'Instagram, TikTok, YouTube...',
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _isLoading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B26D9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        isArabic ? 'إرسال الطلب' : 'Submit application',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'تسجيل كمضيف' : 'Become a host',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  isArabic
                      ? 'ابدأ البث وكسب الدخل'
                      : 'Start streaming and earn income',
                  style: const TextStyle(
                    color: Color(0xFF9E91B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isArabic) {
    final perks = isArabic
        ? [
            '💎 كسب الألماس من الهدايا',
            '📺 بث مباشر بلا حدود',
            '🏆 أوسمة خاصة بالمضيف',
          ]
        : [
            '💎 Earn diamonds from gifts',
            '📺 Unlimited live streaming',
            '🏆 Exclusive host badges',
          ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A0F4A), Color(0xFF150830), Color(0xFF1A1000)],
        ),
        border: Border.all(
          color: const Color(0xFFF0C15A).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: perks
            .map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    Text(
                      p,
                      style: const TextStyle(
                        color: Color(0xFFD8CFEA),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
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

  Widget _buildStatusView(bool isArabic) {
    final isPending = _existingStatus == 'pending';
    final isApproved = _existingStatus == 'approved';
    final color = isApproved
        ? const Color(0xFF63E6A1)
        : isPending
        ? const Color(0xFFF0C15A)
        : const Color(0xFFFF6B8A);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isApproved
                  ? Icons.verified_rounded
                  : isPending
                  ? Icons.hourglass_top_rounded
                  : Icons.cancel_rounded,
              color: color,
              size: 72,
            ),
            const SizedBox(height: 20),
            Text(
              isArabic
                  ? (isApproved
                        ? 'تم قبول طلبك!'
                        : isPending
                        ? 'طلبك قيد المراجعة'
                        : 'تم رفض الطلب')
                  : (isApproved
                        ? 'Application approved!'
                        : isPending
                        ? 'Application under review'
                        : 'Application rejected'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? (isApproved
                        ? 'يمكنك الآن البدء بالبث المباشر!'
                        : isPending
                        ? 'سيتم مراجعة طلبك قريباً.'
                        : 'يمكنك إعادة التقديم لاحقاً.')
                  : (isApproved
                        ? 'You can now start live streaming!'
                        : isPending
                        ? 'Your application will be reviewed soon.'
                        : 'You can reapply later.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFBCAED6),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF4A3470)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  isArabic ? 'رجوع' : 'Go back',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess(bool isArabic) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFF123A2A),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF63E6A1).withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFF63E6A1),
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isArabic ? 'تم إرسال الطلب!' : 'Application sent!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'سيراجع الفريق طلبك ويتواصل معك قريباً.'
                  : 'The team will review your application and get back to you soon.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFBCAED6),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B26D9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  isArabic ? 'رجوع' : 'Go back',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label, bool isArabic) {
    return Text(
      label,
      textAlign: isArabic ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        color: Color(0xFFD8CFEA),
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF6E5A8A), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF160B24),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF4A3470)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF4A3470)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF8B26D9), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF6B8A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF6B8A), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
