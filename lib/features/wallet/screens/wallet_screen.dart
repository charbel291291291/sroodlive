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
  final GlobalKey _transactionsKey = GlobalKey();

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

  void _scrollToTransactions() {
    final context = _transactionsKey.currentContext;
    if (context == null) return;

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _showHelp() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isArabic
              ? '\u062f\u0639\u0645 \u0627\u0644\u0634\u062d\u0646 \u0642\u0631\u064a\u0628\u0627\u064b'
              : 'Recharge support coming soon',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final mediaQuery = MediaQuery.of(context);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
        ),
      ),
      child: MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: mediaQuery.textScaler.clamp(
            minScaleFactor: 1,
            maxScaleFactor: 1.08,
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  child: Directionality(
                    textDirection: isArabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WalletHeader(
                          isArabic: isArabic,
                          onRefresh: _loadWallet,
                        ),
                        const SizedBox(height: 14),
                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 80),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_error != null)
                          _WalletErrorState(
                            message: _error!,
                            onRetry: _loadWallet,
                          )
                        else ...[
                          _WalletBalanceCard(
                            wallet: _wallet,
                            isArabic: isArabic,
                            onRecharge: _isSubmitting
                                ? null
                                : _openRechargeSheet,
                          ),
                          const SizedBox(height: 12),
                          _WalletStatsRow(wallet: _wallet, isArabic: isArabic),
                          const SizedBox(height: 12),
                          _WalletActionsRow(
                            isArabic: isArabic,
                            onRecharge: _isSubmitting
                                ? null
                                : _openRechargeSheet,
                            onHistory: _scrollToTransactions,
                            onHelp: _showHelp,
                          ),
                          const SizedBox(height: 14),
                          _WalletSection(
                            title: isArabic
                                ? '\u0637\u0644\u0628\u0627\u062a \u0627\u0644\u0634\u062d\u0646'
                                : 'Recharge Requests',
                            child: _rechargeRequests.isEmpty
                                ? _WalletEmptyState(
                                    icon: Icons.add_card_rounded,
                                    title: isArabic
                                        ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0637\u0644\u0628\u0627\u062a \u0634\u062d\u0646'
                                        : 'No recharge requests yet',
                                    subtitle: isArabic
                                        ? '\u0627\u0636\u063a\u0637 \u0634\u062d\u0646 \u0644\u0625\u0646\u0634\u0627\u0621 \u0637\u0644\u0628'
                                        : 'Tap Recharge to create one',
                                    compact: true,
                                  )
                                : Column(
                                    children: _rechargeRequests
                                        .take(6)
                                        .map(_RechargeRequestTile.new)
                                        .toList(),
                                  ),
                          ),
                          const SizedBox(height: 14),
                          _WalletSection(
                            key: _transactionsKey,
                            title: isArabic
                                ? '\u0633\u062c\u0644 \u0627\u0644\u0645\u062d\u0641\u0638\u0629'
                                : 'Transactions',
                            child: _transactions.isEmpty
                                ? _WalletEmptyState(
                                    icon: Icons.receipt_long_rounded,
                                    title: isArabic
                                        ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0633\u062c\u0644 \u0628\u0639\u062f'
                                        : 'No transactions yet',
                                    subtitle: isArabic
                                        ? '\u0633\u064a\u0638\u0647\u0631 \u0646\u0634\u0627\u0637 \u0645\u062d\u0641\u0638\u062a\u0643 \u0647\u0646\u0627'
                                        : 'Your wallet activity will appear here',
                                  )
                                : Column(
                                    children: _transactions
                                        .take(8)
                                        .map(_TransactionTile.new)
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
        ),
      ),
    );
  }
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({required this.isArabic, required this.onRefresh});

  final bool isArabic;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            }
          },
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic
                    ? '\u0627\u0644\u0645\u062d\u0641\u0638\u0629'
                    : 'Wallet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                isArabic
                    ? '\u0627\u0644\u0631\u0635\u064a\u062f\u060c \u0627\u0644\u0634\u062d\u0646\u060c \u0648\u0627\u0644\u0633\u062c\u0644'
                    : 'Balance, recharge, and history',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFBCAED6),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFFF4C95D)),
        ),
      ],
    );
  }
}

class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard({
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
      height: 172,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A1689), Color(0xFF231036), Color(0xFFC8952D)],
        ),
        border: Border.all(
          color: const Color(0xFFF4C95D).withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.25),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Color(0xFFF4C95D),
                  size: 22,
                ),
              ),
              const Spacer(),
              _GoldPillButton(
                label: isArabic ? '\u0634\u062d\u0646' : 'Recharge',
                icon: Icons.add_rounded,
                onTap: onRecharge,
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _BalanceTile(
                  icon: Icons.monetization_on_rounded,
                  label: isArabic ? '\u0639\u0645\u0644\u0627\u062a' : 'Coins',
                  value: wallet?.coinsBalance ?? 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BalanceTile(
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

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
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
      height: 86,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFF4C95D), size: 20),
          const Spacer(),
          Text(
            _formatWalletCount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFE3D9F4),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletStatsRow extends StatelessWidget {
  const _WalletStatsRow({required this.wallet, required this.isArabic});

  final UserWallet? wallet;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.south_west_rounded,
            label: isArabic ? '\u0645\u0634\u062d\u0648\u0646' : 'Charged',
            value: wallet?.lifetimeCoinsCharged ?? 0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            icon: Icons.north_east_rounded,
            label: isArabic ? '\u0645\u0635\u0631\u0648\u0641' : 'Spent',
            value: wallet?.lifetimeCoinsSpent ?? 0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            icon: Icons.auto_awesome_rounded,
            label: isArabic ? '\u0645\u0643\u062a\u0633\u0628' : 'Earned',
            value: wallet?.lifetimeDiamondsEarned ?? 0,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return _WalletGlassCard(
      height: 78,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFF4C95D), size: 17),
          const Spacer(),
          Text(
            _formatWalletCount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFBCAED6),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletActionsRow extends StatelessWidget {
  const _WalletActionsRow({
    required this.isArabic,
    required this.onRecharge,
    required this.onHistory,
    required this.onHelp,
  });

  final bool isArabic;
  final VoidCallback? onRecharge;
  final VoidCallback onHistory;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _WalletActionButton(
            icon: Icons.add_card_rounded,
            label: isArabic ? '\u0634\u062d\u0646' : 'Recharge',
            onTap: onRecharge,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _WalletActionButton(
            icon: Icons.history_rounded,
            label: isArabic ? '\u0627\u0644\u0633\u062c\u0644' : 'History',
            onTap: onHistory,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _WalletActionButton(
            icon: Icons.support_agent_rounded,
            label: isArabic ? '\u062f\u0639\u0645' : 'Help',
            onTap: onHelp,
          ),
        ),
      ],
    );
  }
}

class _WalletActionButton extends StatelessWidget {
  const _WalletActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: _WalletGlassCard(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFF4C95D), size: 21),
            const Spacer(),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletSection extends StatelessWidget {
  const _WalletSection({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _WalletGlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _RechargeRequestTile extends StatelessWidget {
  const _RechargeRequestTile(this.request);

  final RechargeRequest request;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _statusStyle(request.status);
    final detail = request.referenceCode?.trim().isNotEmpty == true
        ? 'Ref ${request.referenceCode}'
        : request.agentCode?.trim().isNotEmpty == true
        ? 'Agent ${request.agentCode}'
        : _dateLabel(request.createdAt);

    return _WalletListTile(
      icon: Icons.add_card_rounded,
      title: '${request.methodLabel} • ${request.requestedCoins} coins',
      subtitle: detail,
      trailing: _StatusPill(
        label: request.statusLabel,
        color: statusStyle.$1,
        background: statusStyle.$2,
      ),
    );
  }

  (Color, Color) _statusStyle(RechargeStatus status) {
    return switch (status) {
      RechargeStatus.approved => (
        const Color(0xFF63E6A1),
        const Color(0xFF123A2A),
      ),
      RechargeStatus.rejected => (
        const Color(0xFFFF6B8A),
        const Color(0xFF3A1422),
      ),
      RechargeStatus.cancelled => (
        const Color(0xFFBCAED6),
        const Color(0xFF241638),
      ),
      RechargeStatus.pending => (
        const Color(0xFFF4C95D),
        const Color(0xFF3E2C12),
      ),
    };
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile(this.transaction);

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final delta = transaction.coinsDelta != 0
        ? transaction.coinsDelta
        : transaction.diamondsDelta;
    final unit = transaction.coinsDelta != 0 ? 'coins' : 'diamonds';
    final isPositive = delta > 0;
    final isNegative = delta < 0;
    final color = isPositive
        ? const Color(0xFF63E6A1)
        : isNegative
        ? const Color(0xFFFF6B8A)
        : const Color(0xFFBCAED6);

    return _WalletListTile(
      icon: _transactionIcon(transaction.type),
      title: transaction.label,
      subtitle: transaction.note?.trim().isNotEmpty == true
          ? transaction.note!
          : _dateLabel(transaction.createdAt),
      trailing: Text(
        '${delta > 0 ? '+' : ''}$delta $unit',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  IconData _transactionIcon(WalletTransactionType type) {
    return switch (type) {
      WalletTransactionType.giftSent => Icons.card_giftcard_rounded,
      WalletTransactionType.giftReceived => Icons.redeem_rounded,
      WalletTransactionType.rechargeRequest => Icons.add_card_rounded,
      WalletTransactionType.agencyRecharge => Icons.groups_rounded,
      WalletTransactionType.adminAdjustment => Icons.tune_rounded,
      WalletTransactionType.refund => Icons.undo_rounded,
      WalletTransactionType.system => Icons.receipt_long_rounded,
    };
  }
}

class _WalletListTile extends StatelessWidget {
  const _WalletListTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF1B102B).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF6E3AA8).withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF4C95D).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFFF4C95D), size: 20),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFBCAED6),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Align(alignment: Alignment.centerRight, child: trailing),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _WalletEmptyState extends StatelessWidget {
  const _WalletEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 120 : 150,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B102B).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6E3AA8).withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFFF4C95D), size: compact ? 26 : 30),
          const SizedBox(height: 9),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFBCAED6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletErrorState extends StatelessWidget {
  const _WalletErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _WalletGlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF6B8A),
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _GoldPillButton extends StatelessWidget {
  const _GoldPillButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFF4C95D),
        foregroundColor: const Color(0xFF140820),
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _WalletGlassCard extends StatelessWidget {
  const _WalletGlassCard({
    required this.child,
    this.height,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF160B24).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF6E3AA8).withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6A28D9).withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
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
