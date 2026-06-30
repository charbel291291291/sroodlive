import 'package:flutter/material.dart';
import 'package:srood_live/shared/utils/error_utils.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

import '../../../core/constants/coin_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class WithdrawalScreen extends StatefulWidget {
  const WithdrawalScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends State<WithdrawalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _notesController = TextEditingController();
  String _method = 'bank';
  int _diamondsToWithdraw = 500;
  bool _isLoading = false;
  bool _isSubmitted = false;
  int _availableDiamonds = 0;

  static const List<Map<String, dynamic>> _methods = [
    {
      'key': 'bank',
      'en': 'Bank Transfer',
      'ar': 'تحويل بنكي',
      'icon': Icons.account_balance_rounded,
    },
    {
      'key': 'paypal',
      'en': 'PayPal',
      'ar': 'باي بال',
      'icon': Icons.payment_rounded,
    },
    {
      'key': 'wise',
      'en': 'Wise',
      'ar': 'وايز',
      'icon': Icons.swap_horiz_rounded,
    },
  ];

  static const int _minDiamonds = CoinConstants.minimumWithdrawalDiamonds;
  static const int _diamondsPerUsd = CoinConstants.diamondsPerUsd;

  bool _hasAgency = false;

  double get _grossUsd => _diamondsToWithdraw / _diamondsPerUsd;

  double get _hostShareRate => _hasAgency
      ? CoinConstants.hostShareWithAgency
      : CoinConstants.hostShareNoAgency;

  double get _estimatedUsd => _grossUsd * _hostShareRate;

  double get _agencyShareUsd =>
      _hasAgency ? _grossUsd * CoinConstants.agencyShare : 0;

  double get _platformShareUsd => _grossUsd - _estimatedUsd - _agencyShareUsd;

  @override
  void initState() {
    super.initState();
    _loadDiamonds();
    _loadAgencyStatus();
  }

  Future<void> _loadAgencyStatus() async {
    try {
      final data = await SupabaseService.requiredClient.rpc(
        'preview_withdrawal_split',
        params: {'p_diamonds': _minDiamonds},
      );
      final rows = data as List<dynamic>;
      if (rows.isEmpty || !mounted) return;
      final row = rows.first as Map<String, dynamic>;
      setState(() => _hasAgency = row['has_agency'] == true);
    } catch (e, st) {
      debugError('WithdrawalScreen._checkAgency', e, st);
    }
  }

  @override
  void dispose() {
    _accountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDiamonds() async {
    try {
      final user = SupabaseService.requiredClient.auth.currentUser;
      if (user == null) return;
      final data = await SupabaseService.requiredClient
          .from('wallets')
          .select('diamonds_balance')
          .eq('user_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _availableDiamonds = (data?['diamonds_balance'] as int?) ?? 0;
        _diamondsToWithdraw = _availableDiamonds < _minDiamonds
            ? _minDiamonds
            : _availableDiamonds;
      });
    } catch (e, st) {
      debugError('WithdrawalScreen._loadDiamonds', e, st);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      final user = SupabaseService.requiredClient.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      // Split + balance hold computed and enforced SQL-side
      await SupabaseService.requiredClient.rpc('request_withdrawal', params: {
        'p_diamonds': _diamondsToWithdraw,
        'p_method': _method,
        'p_account_details': _accountController.text.trim(),
        'p_notes': _notesController.text.trim(),
      });

      if (!mounted) return;
      setState(() => _isSubmitted = true);
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
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;

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
          child: _isSubmitted
              ? _buildSuccess(isArabic)
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    child: Column(
                      crossAxisAlignment: crossAxis,
                      children: [
                        _buildHeader(isArabic),
                        const SizedBox(height: 16),
                        _buildBalanceCard(isArabic),
                        const SizedBox(height: 20),
                        _buildSectionLabel(
                          isArabic
                              ? 'عدد الألماس للسحب'
                              : 'Diamonds to withdraw',
                          isArabic,
                        ),
                        const SizedBox(height: 10),
                        _buildDiamondsSlider(isArabic),
                        const SizedBox(height: 12),
                        _buildSplitBreakdown(isArabic),
                        const SizedBox(height: 20),
                        _buildSectionLabel(
                          isArabic ? 'طريقة السحب' : 'Withdrawal method',
                          isArabic,
                        ),
                        const SizedBox(height: 10),
                        ..._methods.map(
                          (m) => _buildMethodTile(m, isArabic, dir),
                        ),
                        const SizedBox(height: 20),
                        _buildSectionLabel(
                          isArabic ? 'تفاصيل الحساب' : 'Account details',
                          isArabic,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _accountController,
                          textDirection: dir,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? (isArabic ? 'مطلوب' : 'Required')
                              : null,
                          decoration: _inputDecoration(
                            isArabic
                                ? 'رقم الحساب / البريد الإلكتروني'
                                : 'Account number / email address',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesController,
                          textDirection: dir,
                          maxLines: 2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          decoration: _inputDecoration(
                            isArabic ? 'ملاحظات (اختياري)' : 'Notes (optional)',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B102B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(
                                0xFFF0C15A,
                              ).withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            textDirection: dir,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFFF0C15A),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isArabic
                                      ? 'تتم مراجعة طلبات السحب خلال 3-5 أيام عمل.'
                                      : 'Withdrawal requests are reviewed within 3-5 business days.',
                                  textAlign: textAlign,
                                  style: const TextStyle(
                                    color: Color(0xFFD8CFEA),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            onPressed:
                                _isLoading || _availableDiamonds < _minDiamonds
                                ? null
                                : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF0C15A),
                              foregroundColor: const Color(0xFF140820),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF140820),
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    isArabic
                                        ? 'إرسال طلب السحب'
                                        : 'Submit withdrawal request',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
          Column(
            crossAxisAlignment: isArabic
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                isArabic ? 'طلب سحب' : 'Withdraw',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                isArabic
                    ? 'حوّل الألماس إلى أموال'
                    : 'Convert diamonds to cash',
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(bool isArabic) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A0E3A), Color(0xFF0E0818), Color(0xFF1A1200)],
        ),
        border: Border.all(
          color: const Color(0xFFF0C15A).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF0C15A).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.diamond_rounded,
              color: Color(0xFFF0C15A),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: isArabic
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                isArabic ? 'الألماس المتاح' : 'Available diamonds',
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$_availableDiamonds',
                style: const TextStyle(
                  color: Color(0xFFF0C15A),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isArabic ? 'الحد الأدنى' : 'Minimum',
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$_minDiamonds 💎',
                style: const TextStyle(
                  color: Color(0xFFBCAED6),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiamondsSlider(bool isArabic) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              const Icon(
                Icons.diamond_rounded,
                color: Color(0xFFF0C15A),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '$_diamondsToWithdraw',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '≈ \$${_estimatedUsd.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFF63E6A1),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFF0C15A),
              inactiveTrackColor: const Color(0xFF2A1840),
              thumbColor: const Color(0xFFF0C15A),
              overlayColor: const Color(0xFFF0C15A).withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: _diamondsToWithdraw
                  .clamp(
                    _minDiamonds,
                    _availableDiamonds > _minDiamonds
                        ? _availableDiamonds
                        : _minDiamonds,
                  )
                  .toDouble(),
              min: _minDiamonds.toDouble(),
              max:
                  (_availableDiamonds > _minDiamonds
                          ? _availableDiamonds
                          : _minDiamonds)
                      .toDouble(),
              divisions: (_availableDiamonds > _minDiamonds
                  ? ((_availableDiamonds - _minDiamonds) ~/ 100).clamp(1, 100)
                  : 1),
              onChanged: _availableDiamonds >= _minDiamonds
                  ? (v) => setState(() => _diamondsToWithdraw = v.round())
                  : null,
            ),
          ),
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_minDiamonds',
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$_availableDiamonds',
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSplitBreakdown(bool isArabic) {
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final hostPct = (_hostShareRate * 100).round();

    Widget row(String label, String value, {Color? color, bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          textDirection: dir,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color ?? const Color(0xFF9E91B8),
                fontSize: bold ? 14 : 12.5,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color ?? const Color(0xFFD8CFEA),
                fontSize: bold ? 16 : 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF120A1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF63E6A1).withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        children: [
          row(
            isArabic ? 'القيمة الإجمالية' : 'Gross value',
            '\$${_grossUsd.toStringAsFixed(2)}',
          ),
          row(
            isArabic
                ? 'حصتك ($hostPct٪)'
                : 'Your share ($hostPct%)',
            '\$${_estimatedUsd.toStringAsFixed(2)}',
            color: const Color(0xFF63E6A1),
            bold: true,
          ),
          if (_hasAgency)
            row(
              isArabic ? 'حصة الوكالة (5٪)' : 'Agency share (5%)',
              '\$${_agencyShareUsd.toStringAsFixed(2)}',
            ),
          row(
            isArabic
                ? 'رسوم المنصة (${(100 - hostPct - (_hasAgency ? 5 : 0))}٪)'
                : 'Platform fee (${100 - hostPct - (_hasAgency ? 5 : 0)}%)',
            '\$${_platformShareUsd.toStringAsFixed(2)}',
          ),
        ],
      ),
    );
  }

  Widget _buildMethodTile(
    Map<String, dynamic> method,
    bool isArabic,
    TextDirection dir,
  ) {
    final key = method['key'] as String;
    final label = isArabic ? method['ar'] as String : method['en'] as String;
    final icon = method['icon'] as IconData;
    final selected = _method == key;

    return GestureDetector(
      onTap: () => setState(() => _method = key),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3A174F) : const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF8B26D9) : const Color(0xFF4A3470),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          textDirection: dir,
          children: [
            Icon(
              icon,
              color: selected
                  ? const Color(0xFFF0C15A)
                  : const Color(0xFF9E91B8),
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFBCAED6),
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF8B26D9),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, bool isArabic) {
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
              isArabic ? 'تم إرسال الطلب' : 'Request submitted',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'سيتم مراجعة طلبك خلال 3-5 أيام عمل. ستتلقى إشعاراً عند الموافقة.'
                  : 'Your request will be reviewed within 3-5 business days. You\'ll receive a notification when approved.',
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

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF6E5A8A), fontSize: 14),
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
