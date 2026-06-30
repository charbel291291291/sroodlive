import 'package:srood_live/shared/utils/error_utils.dart';

import '../../../core/constants/coin_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../models/recharge_package.dart';
import '../models/recharge_request.dart';
import '../models/wallet.dart';
import '../models/wallet_transaction.dart';

class WalletService {
  const WalletService();

  Future<UserWallet> fetchWallet() async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    final data = await client
        .from('wallets')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();

    if (data == null) {
      return UserWallet.empty(user.id);
    }

    return UserWallet.fromJson(data);
  }

  Future<UserWallet> ensureWallet() async {
    final data = await SupabaseService.requiredClient.rpc('ensure_wallet');
    return UserWallet.fromJson(data as Map<String, dynamic>);
  }

  Future<List<WalletTransaction>> fetchTransactions({int limit = 50}) async {
    final data = await SupabaseService.requiredClient
        .from('wallet_transactions')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);

    return (data as List<dynamic>)
        .map((item) => WalletTransaction.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<RechargeRequest>> fetchRechargeRequests({int limit = 30}) async {
    final data = await SupabaseService.requiredClient
        .from('recharge_requests')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);

    return (data as List<dynamic>)
        .map((item) => RechargeRequest.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<RechargePackage>> fetchRechargePackages() async {
    try {
      final data = await SupabaseService.requiredClient
          .from('recharge_packages')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final packages = (data as List<dynamic>)
          .map((item) => RechargePackage.fromJson(item as Map<String, dynamic>))
          .where((package) => package.totalCoins > 0 && package.priceUsd > 0)
          .toList();

      if (packages.isNotEmpty) {
        return packages;
      }
    } catch (e, st) {
      debugError('WalletService.fetchRechargePackages', e, st);
      // The app can run before the latest economy migration is applied.
    }

    return RechargePackage.fallbackPackages();
  }

  Future<List<RechargeRequest>> fetchPendingRechargeRequests({
    int limit = 50,
  }) async {
    final data = await SupabaseService.requiredClient
        .from('recharge_requests')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: true)
        .limit(limit);

    return (data as List<dynamic>)
        .map((item) => RechargeRequest.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<String> createRechargeRequest({
    required int coins,
    required RechargeMethod method,
    double? amountUsd,
    String? referenceCode,
    String? agentCode,
    String? packageId,
  }) async {
    if (coins <= 0) {
      throw ArgumentError('invalid_requested_coins');
    }
    if (coins > CoinConstants.maximumRechargeCoins) {
      throw ArgumentError('coins_exceeds_maximum');
    }

    if (packageId != null && !packageId.startsWith('fallback_')) {
      try {
        final data = await SupabaseService.requiredClient.rpc(
          'create_recharge_transaction',
          params: {
            'p_package_id': packageId,
            'p_payment_method': _canonicalMethodKey(method),
            'p_payment_reference': referenceCode,
          },
        );

        return data.toString();
      } catch (e, st) {
        debugError('WalletService.createRechargeRequest', e, st);
        // Fall back to the legacy request RPC until the new RPC is deployed.
      }
    }

    final data = await SupabaseService.requiredClient.rpc(
      'request_recharge',
      params: {
        'p_requested_coins': coins,
        'p_method': _methodKey(method),
        'p_requested_amount_usd': amountUsd,
        'p_reference_code': referenceCode,
        'p_agent_code': agentCode,
      },
    );

    return data.toString();
  }

  Future<void> approveRechargeRequest(
    String requestId, {
    String? adminNote,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'approve_recharge_request',
      params: {'p_request_id': requestId, 'p_admin_note': adminNote},
    );
  }

  Future<void> rejectRechargeRequest(String requestId, String reason) async {
    await SupabaseService.requiredClient.rpc(
      'reject_recharge_request',
      params: {'p_request_id': requestId, 'p_reject_reason': reason},
    );
  }

  Future<bool> hasFinanceAccess() async {
    final data = await SupabaseService.requiredClient.rpc('has_finance_access');
    return data == true;
  }

  String _methodKey(RechargeMethod method) {
    return switch (method) {
      RechargeMethod.omt => 'omt',
      RechargeMethod.wish => 'wish',
      RechargeMethod.usdt => 'usdt',
      RechargeMethod.agent => 'agent',
      RechargeMethod.cash => 'cash',
      RechargeMethod.adminManual => 'admin_manual',
    };
  }

  String _canonicalMethodKey(RechargeMethod method) {
    return switch (method) {
      RechargeMethod.omt => 'omt',
      RechargeMethod.wish => 'wish',
      RechargeMethod.usdt => 'usdt',
      RechargeMethod.agent => 'cash',
      RechargeMethod.cash => 'cash',
      RechargeMethod.adminManual => 'manual_admin',
    };
  }
}
