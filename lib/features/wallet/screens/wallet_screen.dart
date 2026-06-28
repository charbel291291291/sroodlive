import 'package:flutter/material.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

import '../models/recharge_package.dart';
import '../models/wallet.dart';
import '../models/wallet_transaction.dart';
import '../services/wallet_service.dart';
import '../../../shared/widgets/premium_ui.dart';
import '../widgets/recharge_request_sheet.dart';
import 'recharge_help_screen.dart';
import 'transaction_history_screen.dart';
import 'withdrawal_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final WalletService _walletService = const WalletService();

  UserWallet? _wallet;
  List<WalletTransaction> _recentActivity = const [];
  int _pendingRequestCount = 0;
  List<RechargePackage> _rechargePackages = const [];

  bool _walletLoading = true;
  bool _activityLoading = true;
  bool _pendingLoading = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    debugPrint('[PerfWallet] screen opened ts=${DateTime.now().millisecondsSinceEpoch}');
    _loadAll();
  }

  Future<void> _loadAll() async {
    await _loadWallet();
    await Future.wait([_loadRecentActivity(), _loadPendingRequests()]);
  }

  Future<void> _refresh() async {
    setState(() {
      _walletLoading = true;
      _activityLoading = true;
      _pendingLoading = true;
      _error = null;
    });
    await _loadAll();
  }

  Future<void> _loadWallet() async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      final results = await Future.wait([
        _walletService.ensureWallet(),
        _walletService.fetchRechargePackages(),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = results[0] as UserWallet;
        _rechargePackages = results[1] as List<RechargePackage>;
        _walletLoading = false;
        _error = null;
      });
      debugPrint('[PerfWallet] balances loaded in ${DateTime.now().millisecondsSinceEpoch - t0}ms');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _walletLoading = false;
      });
    }
  }

  Future<void> _loadRecentActivity() async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      final txs = await _walletService.fetchTransactions(limit: 3);
      if (!mounted) return;
      setState(() {
        _recentActivity = txs;
        _activityLoading = false;
      });
      debugPrint('[PerfWallet] recent activity loaded in ${DateTime.now().millisecondsSinceEpoch - t0}ms count=${txs.length}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _activityLoading = false);
    }
  }

  Future<void> _loadPendingRequests() async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      final pending = await _walletService.fetchPendingRechargeRequests(limit: 10);
      if (!mounted) return;
      setState(() {
        _pendingRequestCount = pending.length;
        _pendingLoading = false;
      });
      debugPrint('[PerfWallet] pending requests loaded in ${DateTime.now().millisecondsSinceEpoch - t0}ms count=${pending.length}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _pendingLoading = false);
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
      builder: (_) => RechargeRequestSheet(
        isArabic: context.isArabic,
        packages: _rechargePackages,
      ),
    );

    if (input == null || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      await _walletService.createRechargeRequest(
        coins: input.coins,
        method: input.method,
        amountUsd: input.amountUsd,
        packageId: input.packageId,
        referenceCode: input.referenceCode,
        agentCode: input.agentCode,
      );

      if (!mounted) return;

      SroodToast.show(context, context.isArabic ? 'تم إرسال طلب الشحن' : 'Recharge request submitted', type: SroodToastType.success);

      await _refresh();
    } catch (error) {
      if (!mounted) return;
      SroodToast.show(context, 'Recharge failed: $error', type: SroodToastType.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showWithdraw() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => WithdrawalScreen(isArabic: context.isArabic),
      ),
    ).then((_) => _refresh());
  }

  void _showHistory() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TransactionHistoryScreen(isArabic: context.isArabic),
      ),
    );
  }

  void _showHelp() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RechargeHelpScreen(isArabic: context.isArabic),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    final mq = MediaQuery.of(context);
    final bottomPad = (mq.padding.bottom + 80 + 60).clamp(140.0, 300.0);

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
        child: MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 1,
              maxScaleFactor: 1.08,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: RefreshIndicator(
                  color: const Color(0xFFF4C95D),
                  backgroundColor: const Color(0xFF1A0E2C),
                  onRefresh: _refresh,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad),
                    child: Directionality(
                      textDirection:
                          isArabic ? TextDirection.rtl : TextDirection.ltr,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _WalletHeader(
                            isArabic: isArabic,
                            onRefresh: _refresh,
                          ),
                          const SizedBox(height: 24),
                          if (_walletLoading)
                            const _LoadingShell()
                          else if (_error != null)
                            _ErrorCard(
                              message: _error!,
                              onRetry: _refresh,
                            )
                          else ...[
                            _BalanceCard(
                              wallet: _wallet,
                              isArabic: isArabic,
                            ),
                            const SizedBox(height: 20),
                            _PrimaryActions(
                              isArabic: isArabic,
                              isSubmitting: _isSubmitting,
                              onRecharge: _openRechargeSheet,
                              onWithdraw: _showWithdraw,
                              onHistory: _showHistory,
                              onHelp: _showHelp,
                            ),
                            if (!_pendingLoading && _pendingRequestCount > 0) ...[
                              const SizedBox(height: 16),
                              _PendingAlert(
                                count: _pendingRequestCount,
                                isArabic: isArabic,
                                onView: _showHistory,
                              ),
                            ],
                            const SizedBox(height: 24),
                            _RecentActivitySection(
                              transactions: _recentActivity,
                              isLoading: _activityLoading,
                              isArabic: isArabic,
                              onViewAll: _showHistory,
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

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
            final nav = Navigator.of(context);
            if (nav.canPop()) nav.pop();
          },
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic ? 'المحفظة' : 'Wallet',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isArabic ? 'الرصيد والمدفوعات' : 'Balance and payments',
                style: const TextStyle(
                  color: Color(0xFFBCAED6),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
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

// ---------------------------------------------------------------------------
// Loading shell (skeleton-style placeholders)
// ---------------------------------------------------------------------------

class _LoadingShell extends StatelessWidget {
  const _LoadingShell();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: const Color(0xFF1E1130),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF1E1130),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF1E1130),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Balance card
// ---------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet, required this.isArabic});

  final UserWallet? wallet;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    // Two premium glossy cards, keeping each currency's identity:
    // coins = gold, diamonds = purple/pink.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isArabic ? 'رصيدك' : 'Your Balance',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _WalletCard(
                  label: isArabic ? 'عملات' : 'Coins',
                  value: wallet?.coinsBalance ?? 0,
                  icon: Icons.monetization_on_rounded,
                  base: const Color(0xFFC79A3A), // gold identity
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _WalletCard(
                  label: isArabic ? 'ألماس' : 'Diamonds',
                  value: wallet?.diamondsBalance ?? 0,
                  icon: Icons.diamond_rounded,
                  base: const Color(0xFF8B2FB7), // purple/pink diamond identity
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.base,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color base;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: premiumCardDecoration(base: base),
        child: Stack(
          children: [
            const Positioned.fill(child: GlossSheen()),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.40),
                          ),
                        ),
                        child: Icon(icon, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _fmt(value),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        shadows: [
                          Shadow(
                            color: Colors.black38,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Primary actions
// ---------------------------------------------------------------------------

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({
    required this.isArabic,
    required this.isSubmitting,
    required this.onRecharge,
    required this.onWithdraw,
    required this.onHistory,
    required this.onHelp,
  });

  final bool isArabic;
  final bool isSubmitting;
  final VoidCallback onRecharge;
  final VoidCallback onWithdraw;
  final VoidCallback onHistory;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _GoldButton(
                icon: Icons.add_rounded,
                label: isArabic ? 'شحن' : 'Recharge',
                onTap: isSubmitting ? null : onRecharge,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DarkButton(
                icon: Icons.arrow_circle_up_rounded,
                label: isArabic ? 'سحب' : 'Withdraw',
                onTap: onWithdraw,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TextLink(
              label: isArabic ? 'السجل' : 'View history',
              onTap: onHistory,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '·',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 16,
                ),
              ),
            ),
            _TextLink(
              label: isArabic ? 'المساعدة' : 'Help',
              onTap: onHelp,
            ),
          ],
        ),
      ],
    );
  }
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFF4C95D),
          disabledBackgroundColor: const Color(0xFFF4C95D).withValues(alpha: 0.4),
          foregroundColor: const Color(0xFF140820),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _DarkButton extends StatelessWidget {
  const _DarkButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(
            color: const Color(0xFF6E3AA8).withValues(alpha: 0.7),
          ),
          backgroundColor: const Color(0xFF1A0B2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFBCAED6),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFFBCAED6),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending recharge alert
// ---------------------------------------------------------------------------

class _PendingAlert extends StatelessWidget {
  const _PendingAlert({
    required this.count,
    required this.isArabic,
    required this.onView,
  });

  final int count;
  final bool isArabic;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF3E2C12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF4C95D).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.pending_actions_rounded,
              color: Color(0xFFF4C95D), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isArabic
                  ? 'لديك $count طلب شحن معلّق'
                  : 'You have $count pending recharge ${count == 1 ? 'request' : 'requests'}',
              style: const TextStyle(
                color: Color(0xFFF4C95D),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GestureDetector(
            onTap: onView,
            child: Text(
              isArabic ? 'عرض' : 'View',
              style: const TextStyle(
                color: Color(0xFFF4C95D),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.underline,
                decorationColor: Color(0xFFF4C95D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent activity
// ---------------------------------------------------------------------------

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({
    required this.transactions,
    required this.isLoading,
    required this.isArabic,
    required this.onViewAll,
  });

  final List<WalletTransaction> transactions;
  final bool isLoading;
  final bool isArabic;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isArabic ? 'النشاط الأخير' : 'Recent Activity',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (transactions.isNotEmpty)
              GestureDetector(
                onTap: onViewAll,
                child: Text(
                  isArabic ? 'عرض الكل' : 'See all',
                  style: const TextStyle(
                    color: Color(0xFFBCAED6),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFFBCAED6),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (isLoading)
          const _ActivityLoadingPlaceholder()
        else if (transactions.isEmpty)
          _EmptyActivity(isArabic: isArabic)
        else
          ...transactions.map((tx) => _ActivityTile(tx: tx)),
      ],
    );
  }
}

class _ActivityLoadingPlaceholder extends StatelessWidget {
  const _ActivityLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF1A0E2C),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: const Color(0xFF12081E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            color: Colors.white.withValues(alpha: 0.2),
            size: 36,
          ),
          const SizedBox(height: 10),
          Text(
            isArabic ? 'لا يوجد نشاط بعد' : 'No activity yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.tx});

  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final delta =
        tx.coinsDelta != 0 ? tx.coinsDelta : tx.diamondsDelta;
    final unit = tx.coinsDelta != 0 ? 'coins' : 'diamonds';
    final isPositive = delta > 0;
    final amountColor = isPositive
        ? const Color(0xFF63E6A1)
        : const Color(0xFFFF6B8A);
    final amountStr =
        '${isPositive ? '+' : ''}${_fmt(delta.abs())} $unit';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF12081E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF4C95D).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _icon(tx.type),
              color: const Color(0xFFF4C95D),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _dateLabel(tx.createdAt),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amountStr,
            style: TextStyle(
              color: amountColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon(WalletTransactionType type) {
    return switch (type) {
      WalletTransactionType.giftSent => Icons.card_giftcard_rounded,
      WalletTransactionType.giftReceived => Icons.redeem_rounded,
      WalletTransactionType.rechargeRequest => Icons.add_card_rounded,
      WalletTransactionType.agencyRecharge => Icons.groups_rounded,
      WalletTransactionType.adminAdjustment => Icons.tune_rounded,
      WalletTransactionType.refund => Icons.undo_rounded,
      WalletTransactionType.gameBet => Icons.casino_rounded,
      WalletTransactionType.gameReward => Icons.emoji_events_rounded,
      WalletTransactionType.gameRefund => Icons.replay_rounded,
      WalletTransactionType.withdrawal => Icons.arrow_circle_up_rounded,
      WalletTransactionType.withdrawalRefund => Icons.arrow_circle_down_rounded,
      WalletTransactionType.agencyCommission => Icons.account_balance_rounded,
      WalletTransactionType.system => Icons.receipt_long_rounded,
    };
  }
}

// ---------------------------------------------------------------------------
// Error card
// ---------------------------------------------------------------------------

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0B2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFFF6B8A).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFFF6B8A), size: 32),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _fmt(int value) {
  final abs = value.abs();
  if (abs >= 1000000) {
    return '${(abs / 1000000).toStringAsFixed(1)}M';
  }
  if (abs >= 1000) {
    return '${(abs / 1000).toStringAsFixed(1)}K';
  }
  return abs.toString();
}

String _dateLabel(DateTime? dt) {
  if (dt == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}
