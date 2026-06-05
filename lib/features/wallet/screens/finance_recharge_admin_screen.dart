import 'package:flutter/material.dart';

import '../models/recharge_request.dart';
import '../services/wallet_service.dart';

class FinanceRechargeAdminScreen extends StatefulWidget {
  const FinanceRechargeAdminScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<FinanceRechargeAdminScreen> createState() =>
      _FinanceRechargeAdminScreenState();
}

class _FinanceRechargeAdminScreenState
    extends State<FinanceRechargeAdminScreen> {
  final WalletService _walletService = const WalletService();
  final TextEditingController _noteController = TextEditingController();
  List<RechargeRequest> _requests = const [];
  bool _isLoading = true;
  bool _hasAccess = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final hasAccess = await _walletService.hasFinanceAccess();
      final requests = hasAccess
          ? await _walletService.fetchPendingRechargeRequests()
          : <RechargeRequest>[];

      if (!mounted) return;

      setState(() {
        _hasAccess = hasAccess;
        _requests = requests;
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

  Future<void> _approve(RechargeRequest request) async {
    try {
      await _walletService.approveRechargeRequest(
        request.id,
        adminNote: _noteController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic
                ? '\u062a\u0645\u062a \u0627\u0644\u0645\u0648\u0627\u0641\u0642\u0629 \u0639\u0644\u0649 \u0637\u0644\u0628 \u0627\u0644\u0634\u062d\u0646'
                : 'Recharge request approved',
          ),
        ),
      );

      _noteController.clear();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Approval failed: $error')));
    }
  }

  Future<void> _reject(RechargeRequest request) async {
    final reason = _noteController.text.trim().isEmpty
        ? 'Rejected by finance'
        : _noteController.text.trim();

    try {
      await _walletService.rejectRechargeRequest(request.id, reason);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic
                ? '\u062a\u0645 \u0631\u0641\u0636 \u0637\u0644\u0628 \u0627\u0644\u0634\u062d\u0646'
                : 'Recharge request rejected',
          ),
        ),
      );

      _noteController.clear();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Rejection failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return Scaffold(
      backgroundColor: const Color(0xFF07030D),
      appBar: AppBar(
        title: Text(
          isArabic ? '\u0627\u0644\u0645\u0627\u0644\u064a\u0629' : 'Finance',
        ),
        backgroundColor: const Color(0xFF12091D),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    _FinanceNotice(message: _error!)
                  else if (!_hasAccess)
                    _FinanceNotice(
                      message: isArabic
                          ? '\u063a\u064a\u0631 \u0645\u0635\u0631\u062d'
                          : 'Not authorized',
                    )
                  else ...[
                    TextField(
                      controller: _noteController,
                      decoration: InputDecoration(
                        labelText: isArabic
                            ? '\u0645\u0644\u0627\u062d\u0638\u0629'
                            : 'Admin note / reject reason',
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_requests.isEmpty)
                      _FinanceNotice(
                        message: isArabic
                            ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0637\u0644\u0628\u0627\u062a \u0645\u0639\u0644\u0642\u0629'
                            : 'No pending recharge requests',
                      )
                    else
                      ..._requests.map(
                        (request) => _RechargeApprovalCard(
                          request: request,
                          onApprove: () => _approve(request),
                          onReject: () => _reject(request),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RechargeApprovalCard extends StatelessWidget {
  const _RechargeApprovalCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final RechargeRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.publicUserId ?? request.userId,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${request.requestedCoins} coins • ${request.methodLabel}',
            style: const TextStyle(
              color: Color(0xFFF0C15A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ref: ${request.referenceCode ?? '-'} • Agent: ${request.agentCode ?? '-'}',
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinanceNotice extends StatelessWidget {
  const _FinanceNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFD8CFEA),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
