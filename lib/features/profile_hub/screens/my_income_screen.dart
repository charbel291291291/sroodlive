import 'package:flutter/material.dart';

import '../models/profile_hub_models.dart';
import '../services/income_service.dart';
import '../widgets/profile_hub_widgets.dart';

class MyIncomeScreen extends StatefulWidget {
  const MyIncomeScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<MyIncomeScreen> createState() => _MyIncomeScreenState();
}

class _MyIncomeScreenState extends State<MyIncomeScreen> {
  final IncomeService _service = const IncomeService();
  late Future<({IncomeAccount account, List<IncomeTransaction> transactions})>
  _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({IncomeAccount account, List<IncomeTransaction> transactions})>
  _load() async {
    final account = await _service.getMyIncomeAccount();
    final transactions = await _service.getMyIncomeTransactions();
    return (account: account, transactions: transactions);
  }

  void _retry() => setState(() => _future = _load());

  Future<void> _requestPayout(double maxAmount) async {
    final amountController = TextEditingController();
    final detailsController = TextEditingController();
    var method = 'OMT';
    final isArabic = widget.isArabic;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: profileHubCard,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  MediaQuery.viewInsetsOf(context).bottom + 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isArabic ? 'طلب سحب' : 'Payout request',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: isArabic ? 'المبلغ USD' : 'Amount USD',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      items: const ['OMT', 'Wish', 'Cash', 'USDT', 'Bank later']
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setSheetState(() => method = value ?? 'OMT'),
                      decoration: InputDecoration(
                        labelText: isArabic ? 'الطريقة' : 'Method',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: detailsController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: isArabic
                            ? 'تفاصيل الحساب'
                            : 'Account details',
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
            );
          },
        );
      },
    );

    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    if (submitted == true && amount > 0 && amount <= maxAmount) {
      await _service.requestPayout(
        amountUsd: amount,
        method: method,
        accountDetails: detailsController.text.trim(),
      );
      _retry();
    }

    amountController.dispose();
    detailsController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return ProfileHubScaffold(
      title: isArabic ? 'دخلي' : 'My income',
      isArabic: isArabic,
      children: [
        FutureBuilder<
          ({IncomeAccount account, List<IncomeTransaction> transactions})
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
                message: snapshot.error?.toString() ?? 'Failed to load income.',
                onRetry: _retry,
                isArabic: isArabic,
              );
            }

            final account = snapshot.data!.account;
            final transactions = snapshot.data!.transactions;

            return Column(
              children: [
                ProfileInfoCard(
                  icon: Icons.account_balance_wallet_rounded,
                  title: isArabic
                      ? 'الرصيد المتاح'
                      : 'Available income',
                  body:
                      '\$${account.availableBalanceUsd.toStringAsFixed(2)}\n'
                      '${isArabic ? 'قيد المراجعة' : 'Pending'}: \$${account.pendingBalanceUsd.toStringAsFixed(2)}\n'
                      '${isArabic ? 'مدى الحياة' : 'Lifetime'}: \$${account.lifetimeIncomeUsd.toStringAsFixed(2)}\n'
                      '${isArabic ? 'مكافآت العملات' : 'Coin rewards'}: ${account.availableCoinsReward}',
                  isArabic: isArabic,
                  action: FilledButton.icon(
                    onPressed: account.availableBalanceUsd > 0
                        ? () => _requestPayout(account.availableBalanceUsd)
                        : null,
                    icon: const Icon(Icons.payments_rounded),
                    label: Text(isArabic ? 'طلب سحب' : 'Request payout'),
                  ),
                ),
                ProfileSectionTitle(
                  title: isArabic ? 'سجل الدخل' : 'Income history',
                  isArabic: isArabic,
                ),
                if (transactions.isEmpty)
                  ProfileEmptyState(
                    icon: Icons.savings_rounded,
                    title: isArabic
                        ? 'لا يوجد دخل بعد'
                        : 'No income yet',
                    description: isArabic
                        ? 'ستظهر مكافآت المضيف والوكالة هنا بعد الاعتماد.'
                        : 'Host and agency rewards will appear here after approval.',
                    isArabic: isArabic,
                  )
                else
                  ...transactions.map(
                    (tx) => TicketCard(
                      title: tx.sourceType,
                      status: tx.status,
                      message:
                          '\$${tx.amountUsd.toStringAsFixed(2)} - ${tx.coinsValue} coins\n${tx.description ?? ''}',
                      date: tx.createdAt,
                      isArabic: isArabic,
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
