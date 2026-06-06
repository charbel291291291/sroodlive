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
                      isArabic ? 'Ø·Ù„Ø¨ Ø³Ø­Ø¨' : 'Payout request',
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
                        labelText: isArabic ? 'Ø§Ù„Ù…Ø¨Ù„Øº USD' : 'Amount USD',
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
                        labelText: isArabic ? 'Ø§Ù„Ø·Ø±ÙŠÙ‚Ø©' : 'Method',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: detailsController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: isArabic
                            ? 'ØªÙØ§ØµÙŠÙ„ Ø§Ù„Ø­Ø³Ø§Ø¨'
                            : 'Account details',
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(isArabic ? 'Ø¥Ø±Ø³Ø§Ù„' : 'Submit'),
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
      title: isArabic ? 'Ø¯Ø®Ù„ÙŠ' : 'My income',
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
                      ? 'Ø§Ù„Ø±ØµÙŠØ¯ Ø§Ù„Ù…ØªØ§Ø­'
                      : 'Available income',
                  body:
                      '\$${account.availableBalanceUsd.toStringAsFixed(2)}\n'
                      '${isArabic ? 'Ù‚ÙŠØ¯ Ø§Ù„Ù…Ø±Ø§Ø¬Ø¹Ø©' : 'Pending'}: \$${account.pendingBalanceUsd.toStringAsFixed(2)}\n'
                      '${isArabic ? 'Ù…Ø¯Ù‰ Ø§Ù„Ø­ÙŠØ§Ø©' : 'Lifetime'}: \$${account.lifetimeIncomeUsd.toStringAsFixed(2)}\n'
                      '${isArabic ? 'Ù…ÙƒØ§ÙØ¢Øª Ø§Ù„Ø¹Ù…Ù„Ø§Øª' : 'Coin rewards'}: ${account.availableCoinsReward}',
                  isArabic: isArabic,
                  action: FilledButton.icon(
                    onPressed: account.availableBalanceUsd > 0
                        ? () => _requestPayout(account.availableBalanceUsd)
                        : null,
                    icon: const Icon(Icons.payments_rounded),
                    label: Text(isArabic ? 'Ø·Ù„Ø¨ Ø³Ø­Ø¨' : 'Request payout'),
                  ),
                ),
                ProfileSectionTitle(
                  title: isArabic ? 'Ø³Ø¬Ù„ Ø§Ù„Ø¯Ø®Ù„' : 'Income history',
                  isArabic: isArabic,
                ),
                if (transactions.isEmpty)
                  ProfileEmptyState(
                    icon: Icons.savings_rounded,
                    title: isArabic
                        ? 'Ù„Ø§ ÙŠÙˆØ¬Ø¯ Ø¯Ø®Ù„ Ø¨Ø¹Ø¯'
                        : 'No income yet',
                    description: isArabic
                        ? 'Ø³ØªØ¸Ù‡Ø± Ù…ÙƒØ§ÙØ¢Øª Ø§Ù„Ù…Ø¶ÙŠÙ ÙˆØ§Ù„ÙˆÙƒØ§Ù„Ø© Ù‡Ù†Ø§ Ø¨Ø¹Ø¯ Ø§Ù„Ø§Ø¹ØªÙ…Ø§Ø¯.'
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
