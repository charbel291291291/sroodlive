import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class ReportUserScreen extends StatefulWidget {
  const ReportUserScreen({
    required this.targetUserId,
    required this.targetName,
    required this.isArabic,
    super.key,
  });

  final String targetUserId;
  final String targetName;
  final bool isArabic;

  @override
  State<ReportUserScreen> createState() => _ReportUserScreenState();
}

class _Reason {
  final String key;
  final String en;
  final String ar;
  final IconData icon;

  const _Reason({
    required this.key,
    required this.en,
    required this.ar,
    required this.icon,
  });
}

const _reasons = [
  _Reason(
    key: 'spam',
    en: 'Spam or scam',
    ar: 'رسائل مزعجة أو احتيال',
    icon: Icons.report_gmailerrorred_rounded,
  ),
  _Reason(
    key: 'harassment',
    en: 'Harassment or bullying',
    ar: 'مضايقة أو تنمر',
    icon: Icons.sentiment_very_dissatisfied_rounded,
  ),
  _Reason(
    key: 'inappropriate',
    en: 'Inappropriate content',
    ar: 'محتوى غير لائق',
    icon: Icons.no_adult_content_rounded,
  ),
  _Reason(
    key: 'fake',
    en: 'Fake account',
    ar: 'حساب مزيف',
    icon: Icons.person_off_rounded,
  ),
  _Reason(
    key: 'hate',
    en: 'Hate speech',
    ar: 'خطاب كراهية',
    icon: Icons.gpp_bad_rounded,
  ),
  _Reason(
    key: 'violence',
    en: 'Violence or threats',
    ar: 'عنف أو تهديد',
    icon: Icons.warning_amber_rounded,
  ),
  _Reason(
    key: 'underage',
    en: 'Minor / underage content',
    ar: 'محتوى للأطفال القاصرين',
    icon: Icons.child_care_rounded,
  ),
  _Reason(
    key: 'other',
    en: 'Other',
    ar: 'أخرى',
    icon: Icons.more_horiz_rounded,
  ),
];

class _ReportUserScreenState extends State<ReportUserScreen> {
  int? _selectedReason;
  final _detailsController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;
    setState(() => _submitting = true);
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null) return;
      await SupabaseService.requiredClient.from('reports').insert({
        'reporter_id': me,
        'reported_user_id': widget.targetUserId,
        'reason': _reasons[_selectedReason!].key,
        'details': _detailsController.text.trim().isEmpty
            ? null
            : _detailsController.text.trim(),
        'status': 'pending',
      });
      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

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
          child: _submitted ? _buildSuccess(isArabic) : _buildForm(isArabic),
        ),
      ),
    );
  }

  Widget _buildForm(bool isArabic) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(isArabic),
            const SizedBox(height: 16),
            _buildTarget(isArabic),
            const SizedBox(height: 20),
            Text(
              isArabic ? 'ما سبب البلاغ؟' : 'Why are you reporting?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            ..._reasons.asMap().entries.map(
              (entry) => _ReasonTile(
                reason: entry.value,
                selected: _selectedReason == entry.key,
                isArabic: isArabic,
                onTap: () => setState(() => _selectedReason = entry.key),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isArabic
                  ? 'تفاصيل إضافية (اختياري)'
                  : 'Additional details (optional)',
              style: const TextStyle(
                color: Color(0xFFBCAED6),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsController,
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              maxLines: 4,
              maxLength: 500,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: isArabic
                    ? 'أضف أي تفاصيل إضافية...'
                    : 'Add any additional details...',
                hintStyle: const TextStyle(
                  color: Color(0xFF6E5A8A),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: const Color(0xFF160B24),
                counterStyle: const TextStyle(
                  color: Color(0xFF6E5A8A),
                  fontSize: 11,
                ),
                contentPadding: const EdgeInsets.all(14),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF8B26D9),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'سيتم مراجعة البلاغ من قِبل فريق الإشراف خلال 48 ساعة.'
                  : 'Your report will be reviewed by the moderation team within 48 hours.',
              style: const TextStyle(
                color: Color(0xFF6E5A8A),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: (_selectedReason == null || _submitting)
                    ? null
                    : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4D6D),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF3A1422),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.flag_rounded, size: 20),
                label: Text(
                  isArabic ? 'إرسال البلاغ' : 'Submit report',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
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
    return Row(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic ? 'الإبلاغ عن مستخدم' : 'Report user',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                isArabic
                    ? 'ساعدنا في الحفاظ على بيئة آمنة'
                    : 'Help us keep the community safe',
                style: const TextStyle(
                  color: Color(0xFFBCAED6),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.flag_rounded, color: Color(0xFFFF4D6D), size: 26),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildTarget(bool isArabic) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6E3AA8).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          const Icon(Icons.person_rounded, color: Color(0xFF9E91B8), size: 20),
          const SizedBox(width: 10),
          Text(
            isArabic ? 'الإبلاغ عن: ' : 'Reporting: ',
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              widget.targetName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(bool isArabic) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF1A3A28),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF63E6A1), width: 2),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFF63E6A1),
                size: 46,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isArabic ? 'تم إرسال البلاغ' : 'Report submitted',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isArabic
                  ? 'شكراً على مساعدتك. سيتم مراجعة البلاغ خلال 48 ساعة.'
                  : 'Thank you for helping. Your report will be reviewed within 48 hours.',
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
              height: 50,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF4A3470)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  isArabic ? 'العودة' : 'Go back',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.reason,
    required this.selected,
    required this.isArabic,
    required this.onTap,
  });

  final _Reason reason;
  final bool selected;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A1040) : const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFFF4D6D) : const Color(0xFF4A3470),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Icon(
              reason.icon,
              color: selected
                  ? const Color(0xFFFF4D6D)
                  : const Color(0xFF9E91B8),
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              isArabic ? reason.ar : reason.en,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFBCAED6),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFFFF4D6D),
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
