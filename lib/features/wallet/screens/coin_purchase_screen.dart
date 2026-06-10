import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';

class CoinPurchaseScreen extends StatefulWidget {
  const CoinPurchaseScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<CoinPurchaseScreen> createState() => _CoinPurchaseScreenState();
}

class _CoinPackage {
  final int coins;
  final double priceUsd;
  final bool popular;
  final bool bestValue;

  const _CoinPackage({
    required this.coins,
    required this.priceUsd,
    this.popular = false,
    this.bestValue = false,
  });
}

const _packages = [
  _CoinPackage(coins: 100,   priceUsd: 1.00),
  _CoinPackage(coins: 500,   priceUsd: 4.50,  popular: true),
  _CoinPackage(coins: 1000,  priceUsd: 8.00),
  _CoinPackage(coins: 2500,  priceUsd: 18.00, bestValue: true),
  _CoinPackage(coins: 5000,  priceUsd: 35.00),
  _CoinPackage(coins: 10000, priceUsd: 65.00),
];

const _methods = ['Bank Transfer', 'PayPal', 'Wise', 'Agent Code'];

class _CoinPurchaseScreenState extends State<CoinPurchaseScreen> {
  int _selectedPackage = 1;
  int _selectedMethod = 0;
  final _refController = TextEditingController();
  final _agentController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _refController.dispose();
    _agentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pkg = _packages[_selectedPackage];
    setState(() => _submitting = true);
    try {
      final userId = SupabaseService.requiredClient.auth.currentUser?.id;
      if (userId == null) return;
      final method = _methods[_selectedMethod].toLowerCase().replaceAll(' ', '_');
      await SupabaseService.requiredClient.from('recharge_requests').insert({
        'user_id': userId,
        'requested_coins': pkg.coins,
        'amount_usd': pkg.priceUsd,
        'method': method,
        'reference_code': _selectedMethod < 3 ? _refController.text.trim() : null,
        'agent_code': _selectedMethod == 3 ? _agentController.text.trim() : null,
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
    final isArabic = widget.isArabic;

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
            const SizedBox(height: 6),
            _buildBalanceBanner(isArabic),
            const SizedBox(height: 20),
            _sectionLabel(isArabic ? 'اختر الباقة' : 'Choose a package', isArabic),
            const SizedBox(height: 10),
            _buildPackageGrid(isArabic),
            const SizedBox(height: 20),
            _sectionLabel(isArabic ? 'طريقة الدفع' : 'Payment method', isArabic),
            const SizedBox(height: 10),
            _buildMethodChips(isArabic),
            const SizedBox(height: 16),
            _buildReferenceField(isArabic),
            const SizedBox(height: 24),
            _buildOrderSummary(isArabic),
            const SizedBox(height: 20),
            _buildSubmitButton(isArabic),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Row(
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
                isArabic ? 'شراء عملات' : 'Buy Coins',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isArabic ? 'اختر الباقة المناسبة لك' : 'Pick the right package for you',
                style: const TextStyle(color: Color(0xFFBCAED6), fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const Icon(Icons.monetization_on_rounded, color: Color(0xFFF0C15A), size: 30),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildBalanceBanner(bool isArabic) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF6E3AA8).withValues(alpha: 0.45)),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFF0C15A), size: 22),
          const SizedBox(width: 10),
          Text(
            isArabic ? 'رصيدك الحالي' : 'Current balance',
            style: const TextStyle(color: Color(0xFFBCAED6), fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          const Text(
            '—  coins',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, bool isArabic) {
    return Text(
      text,
      textAlign: isArabic ? TextAlign.right : TextAlign.left,
      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
    );
  }

  Widget _buildPackageGrid(bool isArabic) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.88,
      ),
      itemCount: _packages.length,
      itemBuilder: (_, i) {
        final pkg = _packages[i];
        final selected = _selectedPackage == i;
        return GestureDetector(
          onTap: () => setState(() => _selectedPackage = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF2A1040) : const Color(0xFF160B24),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? const Color(0xFFF0C15A) : const Color(0xFF6E3AA8).withValues(alpha: 0.4),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (pkg.popular || pkg.bestValue)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: pkg.bestValue ? const Color(0xFFF0C15A).withValues(alpha: 0.2) : const Color(0xFF8B26D9).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: pkg.bestValue ? const Color(0xFFF0C15A) : const Color(0xFF8B26D9),
                      ),
                    ),
                    child: Text(
                      pkg.bestValue
                          ? (isArabic ? 'أفضل قيمة' : 'Best value')
                          : (isArabic ? 'شائع' : 'Popular'),
                      style: TextStyle(
                        color: pkg.bestValue ? const Color(0xFFF0C15A) : const Color(0xFFCCA0FF),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                const Icon(Icons.monetization_on_rounded, color: Color(0xFFF0C15A), size: 26),
                const SizedBox(height: 6),
                Text(
                  _formatCoins(pkg.coins),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, height: 1.0),
                ),
                const SizedBox(height: 3),
                Text(
                  isArabic ? 'عملة' : 'coins',
                  style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 10, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '\$${pkg.priceUsd.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: selected ? const Color(0xFFF0C15A) : const Color(0xFFBCAED6),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMethodChips(bool isArabic) {
    final labels = isArabic
        ? ['حوالة بنكية', 'PayPal', 'Wise', 'كود وكيل']
        : _methods;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(_methods.length, (i) {
        final selected = _selectedMethod == i;
        return GestureDetector(
          onTap: () => setState(() => _selectedMethod = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF2A1040) : const Color(0xFF160B24),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? const Color(0xFF8B26D9) : const Color(0xFF4A3470),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                color: selected ? const Color(0xFFCCA0FF) : const Color(0xFF9E91B8),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildReferenceField(bool isArabic) {
    final isAgent = _selectedMethod == 3;
    return Column(
      crossAxisAlignment: isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          isAgent
              ? (isArabic ? 'كود الوكيل' : 'Agent code')
              : (isArabic ? 'كود المرجع / رقم التحويل' : 'Reference code / transfer ID'),
          style: const TextStyle(color: Color(0xFFBCAED6), fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: isAgent ? _agentController : _refController,
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: isAgent
                ? (isArabic ? 'أدخل كود الوكيل' : 'Enter agent code')
                : (isArabic ? 'أدخل رقم التحويل أو كود المرجع' : 'Enter transfer ID or reference'),
            hintStyle: const TextStyle(color: Color(0xFF6E5A8A), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF160B24),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          ),
        ),
      ],
    );
  }

  Widget _buildOrderSummary(bool isArabic) {
    final pkg = _packages[_selectedPackage];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF6E3AA8).withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: isArabic ? 'الباقة المختارة' : 'Selected package',
            value: '${_formatCoins(pkg.coins)} ${isArabic ? "عملة" : "coins"}',
            isArabic: isArabic,
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: isArabic ? 'المبلغ' : 'Amount',
            value: '\$${pkg.priceUsd.toStringAsFixed(2)} USD',
            isArabic: isArabic,
            highlight: true,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: Color(0xFF2A1840), height: 1),
          ),
          Text(
            isArabic
                ? 'سيتم مراجعة طلبك وتفعيل العملات خلال 24 ساعة بعد التحقق من الدفع.'
                : 'Your request will be reviewed and coins activated within 24 hours after payment verification.',
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 11, fontWeight: FontWeight.w600, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(bool isArabic) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: _submitting ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFF0C15A),
          foregroundColor: const Color(0xFF140820),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        icon: _submitting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF140820)))
            : const Icon(Icons.send_rounded, size: 20),
        label: Text(
          isArabic ? 'إرسال الطلب' : 'Submit request',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
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
              child: const Icon(Icons.check_rounded, color: Color(0xFF63E6A1), size: 46),
            ),
            const SizedBox(height: 24),
            Text(
              isArabic ? 'تم إرسال الطلب!' : 'Request submitted!',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Text(
              isArabic
                  ? 'سيتم مراجعة طلبك وإضافة العملات خلال 24 ساعة.'
                  : 'Your request will be reviewed and coins added within 24 hours.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFBCAED6), fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  String _formatCoins(int coins) {
    if (coins >= 1000) return '${(coins / 1000).toStringAsFixed(coins % 1000 == 0 ? 0 : 1)}K';
    return '$coins';
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.isArabic,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool isArabic;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 13, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: highlight ? const Color(0xFFF0C15A) : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
