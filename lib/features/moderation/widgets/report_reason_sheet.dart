import 'package:flutter/material.dart';

import '../services/moderation_service.dart';

class ReportReasonSheet extends StatefulWidget {
  const ReportReasonSheet({
    required this.reportedUserId,
    required this.roomId,
    required this.isArabic,
    super.key,
  });

  final String reportedUserId;
  final String? roomId;
  final bool isArabic;

  /// Show the sheet and return true if the report was submitted.
  static Future<bool?> show(
    BuildContext context, {
    required String reportedUserId,
    String? roomId,
    required bool isArabic,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReportReasonSheet(
        reportedUserId: reportedUserId,
        roomId: roomId,
        isArabic: isArabic,
      ),
    );
  }

  @override
  State<ReportReasonSheet> createState() => _ReportReasonSheetState();
}

class _ReportReasonSheetState extends State<ReportReasonSheet> {
  final _service = const ModerationService();
  final _descCtrl = TextEditingController();
  String? _selectedReason;
  bool _submitting = false;
  String? _error;

  static const _reasons = [
    ('harassment',    'Harassment / Bullying', 'مضايقة / تنمر'),
    ('hate_speech',   'Hate Speech',           'خطاب الكراهية'),
    ('threat',        'Threat / Violence',     'تهديد / عنف'),
    ('sexual_content','Sexual Content',        'محتوى جنسي'),
    ('scam_fraud',    'Scam / Fraud',          'احتيال / نصب'),
    ('spam',          'Spam',                  'سبام'),
    ('illegal_content','Illegal Content',      'محتوى مخالف للقانون'),
    ('other',         'Other',                 'أخرى'),
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_selectedReason == null) return;
    setState(() { _submitting = true; _error = null; });
    try {
      await _service.submitReport(
        reportedUserId: widget.reportedUserId,
        roomId: widget.roomId,
        reason: _selectedReason!,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().contains('rate_limited')
              ? (widget.isArabic
                  ? 'لقد تجاوزت الحد المسموح به من البلاغات (5 في الساعة).'
                  : 'You have reached the report limit (5 per hour).')
              : (widget.isArabic ? 'تعذّر إرسال البلاغ.' : 'Failed to submit report.');
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        margin: EdgeInsets.only(bottom: bottom),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1D2A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isArabic ? 'الإبلاغ عن مستخدم' : 'Report User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'إغلاق',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF9E91B8),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                isArabic
                    ? 'اختر سبب البلاغ. سيتم مراجعته من قِبَل فريق الإشراف.'
                    : 'Select a reason. The moderation team will review your report.',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),

            // Reason list
            ..._reasons.map((r) {
              final selected = _selectedReason == r.$1;
              return InkWell(
                onTap: () => setState(() => _selectedReason = r.$1),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF6366F1).withValues(alpha: 0.18)
                        : const Color(0xFF252836),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF6366F1)
                          : Colors.white.withValues(alpha: 0.07),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isArabic ? r.$3 : r.$2,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (selected)
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF6366F1), size: 18),
                    ],
                  ),
                ),
              );
            }),

            // Optional description
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _descCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 2,
                maxLength: 300,
                decoration: InputDecoration(
                  hintText: isArabic
                      ? 'تفاصيل إضافية (اختياري)'
                      : 'Additional details (optional)',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF252836),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF6366F1)),
                  ),
                  counterStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(_error!,
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
              ),

            // Submit button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selectedReason == null || _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    disabledBackgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                      : Text(
                          isArabic ? 'إرسال البلاغ' : 'Submit Report',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
