import 'package:flutter/material.dart';

import '../models/recharge_request.dart';

class RechargeRequestInput {
  const RechargeRequestInput({
    required this.coins,
    required this.method,
    this.amountUsd,
    this.referenceCode,
    this.agentCode,
  });

  final int coins;
  final RechargeMethod method;
  final double? amountUsd;
  final String? referenceCode;
  final String? agentCode;
}

class RechargeRequestSheet extends StatefulWidget {
  const RechargeRequestSheet({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<RechargeRequestSheet> createState() => _RechargeRequestSheetState();
}

class _RechargeRequestSheetState extends State<RechargeRequestSheet> {
  final TextEditingController _coinsController = TextEditingController(
    text: '1000',
  );
  final TextEditingController _amountController = TextEditingController(
    text: '1',
  );
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _agentController = TextEditingController();
  RechargeMethod _method = RechargeMethod.omt;
  String? _error;

  @override
  void dispose() {
    _coinsController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _agentController.dispose();
    super.dispose();
  }

  void _setPackage(int coins) {
    setState(() {
      _coinsController.text = coins.toString();
      _amountController.text = (coins / 1000).toStringAsFixed(0);
    });
  }

  void _submit() {
    final coins = int.tryParse(_coinsController.text.trim()) ?? 0;
    final amount = double.tryParse(_amountController.text.trim());

    if (coins <= 0) {
      setState(() {
        _error = widget.isArabic
            ? '\u0623\u062f\u062e\u0644 \u0639\u062f\u062f \u0639\u0645\u0644\u0627\u062a \u0635\u062d\u064a\u062d.'
            : 'Enter a valid coin amount.';
      });
      return;
    }

    Navigator.of(context).pop(
      RechargeRequestInput(
        coins: coins,
        method: _method,
        amountUsd: amount,
        referenceCode: _blankToNull(_referenceController.text),
        agentCode: _blankToNull(_agentController.text),
      ),
    );
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final textDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Directionality(
            textDirection: textDirection,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isArabic
                      ? '\u0637\u0644\u0628 \u0634\u062d\u0646'
                      : 'Recharge Request',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isArabic
                      ? '\u0627\u062f\u0641\u0639 \u0639\u0628\u0631 \u0648\u0643\u064a\u0644 \u0634\u062d\u0646 \u0631\u0633\u0645\u064a \u062b\u0645 \u0623\u0631\u0633\u0644 \u0631\u0642\u0645 \u0627\u0644\u0639\u0645\u0644\u064a\u0629.'
                      : 'Send payment to an official SrOOd recharge agent, then submit the reference.',
                  style: const TextStyle(
                    color: Color(0xFFD8CFEA),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [1000, 5000, 10000, 50000]
                      .map(
                        (coins) => ActionChip(
                          label: Text('$coins'),
                          onPressed: () => _setPackage(coins),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),
                _WalletSheetField(
                  controller: _coinsController,
                  label: isArabic
                      ? '\u0627\u0644\u0639\u0645\u0644\u0627\u062a'
                      : 'Coins',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<RechargeMethod>(
                  initialValue: _method,
                  dropdownColor: const Color(0xFF1B102B),
                  decoration: InputDecoration(
                    labelText: isArabic
                        ? '\u0627\u0644\u0637\u0631\u064a\u0642\u0629'
                        : 'Method',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: RechargeMethod.omt,
                      child: Text('OMT'),
                    ),
                    DropdownMenuItem(
                      value: RechargeMethod.wish,
                      child: Text('Wish'),
                    ),
                    DropdownMenuItem(
                      value: RechargeMethod.usdt,
                      child: Text('USDT'),
                    ),
                    DropdownMenuItem(
                      value: RechargeMethod.agent,
                      child: Text('Recharge Agent'),
                    ),
                    DropdownMenuItem(
                      value: RechargeMethod.cash,
                      child: Text('Cash'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _method = value);
                  },
                ),
                const SizedBox(height: 10),
                _WalletSheetField(
                  controller: _amountController,
                  label: isArabic
                      ? '\u0627\u0644\u0645\u0628\u0644\u063a USD'
                      : 'Amount USD',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 10),
                _WalletSheetField(
                  controller: _referenceController,
                  label: isArabic
                      ? '\u0631\u0642\u0645 \u0627\u0644\u0645\u0631\u062c\u0639'
                      : 'Reference code',
                ),
                const SizedBox(height: 10),
                _WalletSheetField(
                  controller: _agentController,
                  label: isArabic
                      ? '\u0643\u0648\u062f \u0627\u0644\u0648\u0643\u064a\u0644'
                      : 'Agent code',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFFF5C7A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                    isArabic
                        ? '\u0625\u0631\u0633\u0627\u0644 \u0637\u0644\u0628 \u0627\u0644\u0634\u062d\u0646'
                        : 'Submit recharge request',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WalletSheetField extends StatelessWidget {
  const _WalletSheetField({
    required this.controller,
    required this.label,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
    );
  }
}
