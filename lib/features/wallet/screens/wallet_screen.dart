import 'package:flutter/material.dart';

import '../models/recharge_request.dart';
import '../models/wallet.dart';
import '../models/wallet_transaction.dart';
import '../services/wallet_service.dart';
import '../widgets/recharge_request_sheet.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final WalletService _walletService = const WalletService();

  UserWallet? _wallet;
  List<WalletTransaction> _transactions = const [];
  List<RechargeRequest> _rechargeRequests = const [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final wallet = await _walletService.ensureWallet();
      final transactions = await _walletService.fetchTransactions();
      final rechargeRequests = await _walletService.fetchRechargeRequests();

      if (!mounted) return;

      setState(() {
        _wallet = wallet;
        _transactions = transactions;
        _rechargeRequests = rechargeRequests;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openRechargeSheet() async {
    final input = await showModalBottomSheet<RechargeRequestInput>(
      context: context,
      backgroundColor: const Color(0xFF100718),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => RechargeRequestSheet(isArabic: widget.isArabic),
    );

    if (input == null || !mounted) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _walletService.createRechargeRequest(
        coins: input.coins,
        method: input.method,
        amountUsd: input.amountUsd,
        referenceCode: input.referenceCode,
        agentCode: input.agentCode,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic
                ? '\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0637\u0644\u0628 \u0627\u0644\u0634\u062d\u0646'
                : 'Recharge request submitted',
          ),
        ),
      );

      await _loadWallet();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Recharge failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: RefreshIndicator(
              onRefresh: _loadWallet,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 128),
                child: Column(
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    Text(
                      isArabic
                          ? '\u0627\u0644\u0645\u062d\u0641\u0638\u0629'
                          : 'Wallet',
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isArabic
                          ? '\u0627\u0644\u0634\u062d\u0646 \u0627\u0644\u064a\u062f\u0648\u064a\u060c \u0627\u0644\u0647\u062f\u0627\u064a\u0627\u060c \u0648\u0633\u062c\u0644 \u0627\u0644\u0645\u062d\u0641\u0638\u0629.'
                          : 'Manual recharge, gifts, and wallet history.',
                      textAlign: textAlign,
                      style: const TextStyle(
                        color: Color(0xFFD8CFEA),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (_error != null)
                      _WalletNotice(
                        message: _error!,
                        icon: Icons.error_outline_rounded,
                      )
                    else ...[
                      _WalletBalanceHero(
                        wallet: _wallet,
                        isArabic: isArabic,
                        onRecharge: _isSubmitting ? null : _openRechargeSheet,
                      ),
                      const SizedBox(height: 14),
                      _WalletLifetimeGrid(wallet: _wallet, isArabic: isArabic),
                      const SizedBox(height: 14),
                      _WalletSection(
                        title: isArabic
                            ? '\u0633\u062c\u0644 \u0627\u0644\u0639\u0645\u0644\u064a\u0627\u062a'
                            : 'Transactions',
                        child: _transactions.isEmpty
                            ? _WalletEmptyState(
                                text: isArabic
                                    ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0633\u062c\u0644 \u0628\u0639\u062f'
                                    : 'No transactions yet',
                              )
                            : Column(
                                children: _transactions
                                    .take(8)
                                    .map(_TransactionRow.new)
                                    .toList(),
                              ),
                      ),
                      const SizedBox(height: 14),
                      _WalletSection(
                        title: isArabic
                            ? '\u0637\u0644\u0628\u0627\u062a \u0627\u0644\u0634\u062d\u0646'
                            : 'Recharge History',
                        child: _rechargeRequests.isEmpty
                            ? _WalletEmptyState(
                                text: isArabic
                                    ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0637\u0644\u0628\u0627\u062a \u0634\u062d\u0646'
                                    : 'No recharge requests yet',
                              )
                            : Column(
                                children: _rechargeRequests
                                    .take(8)
                                    .map(_RechargeRow.new)
                                    .toList(),
                              ),
                      ),
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

class _WalletBalanceHero extends StatelessWidget {
  const _WalletBalanceHero({
    required this.wallet,
    required this.isArabic,
    required this.onRecharge,
  });

  final UserWallet? wallet;
  final bool isArabic;
  final VoidCallback? onRecharge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF4B168C), Color(0xFF241638), Color(0xFFE0A83A)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: Color(0xFFF0C15A),
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isArabic ? '\u0631\u0635\u064a\u062f\u0643' : 'Your Balance',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: onRecharge,
                icon: const Icon(Icons.add_rounded),
                label: Text(isArabic ? '\u0634\u062d\u0646' : 'Recharge'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Expanded(
                child: _BalanceAmount(
                  icon: Icons.monetization_on_rounded,
                  label: isArabic ? '\u0639\u0645\u0644\u0627\u062a' : 'Coins',
                  value: wallet?.coinsBalance ?? 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BalanceAmount(
                  icon: Icons.diamond_rounded,
                  label: isArabic
                      ? '\u0623\u0644\u0645\u0627\u0633'
                      : 'Diamonds',
                  value: wallet?.diamondsBalance ?? 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceAmount extends StatelessWidget {
  const _BalanceAmount({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFF0C15A), size: 22),
          const SizedBox(height: 10),
          Text(
            _formatWalletCount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletLifetimeGrid extends StatelessWidget {
  const _WalletLifetimeGrid({required this.wallet, required this.isArabic});

  final UserWallet? wallet;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Expanded(
          child: _MiniWalletStat(
            label: isArabic ? '\u0645\u0634\u062d\u0648\u0646' : 'Charged',
            value: wallet?.lifetimeCoinsCharged ?? 0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniWalletStat(
            label: isArabic ? '\u0645\u0635\u0631\u0648\u0641' : 'Spent',
            value: wallet?.lifetimeCoinsSpent ?? 0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniWalletStat(
            label: isArabic ? '\u0623\u0644\u0645\u0627\u0633' : 'Earned',
            value: wallet?.lifetimeDiamondsEarned ?? 0,
          ),
        ),
      ],
    );
  }
}

class _MiniWalletStat extends StatelessWidget {
  const _MiniWalletStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        children: [
          Text(
            _formatWalletCount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFB9A9D4),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletSection extends StatelessWidget {
  const _WalletSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow(this.transaction);

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.direction == WalletDirection.credit;
    final amount = transaction.coinsDelta != 0
        ? '${transaction.coinsDelta > 0 ? '+' : ''}${transaction.coinsDelta} coins'
        : '${transaction.diamondsDelta > 0 ? '+' : ''}${transaction.diamondsDelta} diamonds';

    return _HistoryRow(
      icon: isCredit ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
      title: transaction.label,
      subtitle: transaction.note ?? _dateLabel(transaction.createdAt),
      trailing: amount,
      positive: isCredit,
    );
  }
}

class _RechargeRow extends StatelessWidget {
  const _RechargeRow(this.request);

  final RechargeRequest request;

  @override
  Widget build(BuildContext context) {
    return _HistoryRow(
      icon: Icons.add_card_rounded,
      title: '${request.requestedCoins} coins',
      subtitle: '${request.methodLabel} • ${request.statusLabel}',
      trailing: _dateLabel(request.createdAt),
      positive: request.status == RechargeStatus.approved,
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.positive,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B102B),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: positive ? const Color(0xFF63E6A1) : const Color(0xFFF0C15A),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB9A9D4),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletEmptyState extends StatelessWidget {
  const _WalletEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _WalletNotice(message: text, icon: Icons.receipt_long_rounded);
  }
}

class _WalletNotice extends StatelessWidget {
  const _WalletNotice({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B102B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFF0C15A), size: 32),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatWalletCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }

  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }

  return value.toString();
}

String _dateLabel(DateTime? value) {
  if (value == null) {
    return '-';
  }

  return '${value.month}/${value.day}/${value.year}';
}
