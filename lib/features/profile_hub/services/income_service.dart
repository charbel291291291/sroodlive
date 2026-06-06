import '../../../core/supabase/supabase_service.dart';
import '../models/profile_hub_models.dart';

class IncomeService {
  const IncomeService();

  Future<IncomeAccount> getMyIncomeAccount() async {
    final data = await SupabaseService.requiredClient.rpc(
      'ensure_income_account',
    );
    return IncomeAccount.fromJson(data as Map<String, dynamic>);
  }

  Future<List<IncomeTransaction>> getMyIncomeTransactions() async {
    final data = await SupabaseService.requiredClient
        .from('income_transactions')
        .select()
        .order('created_at', ascending: false)
        .limit(30);

    return (data as List<dynamic>)
        .map((item) => IncomeTransaction.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> requestPayout({
    required double amountUsd,
    required String method,
    required String accountDetails,
  }) async {
    final userId = SupabaseService.requiredClient.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No logged-in user found.');
    }

    await SupabaseService.requiredClient.from('payout_requests').insert({
      'user_id': userId,
      'amount_usd': amountUsd,
      'method': method,
      'account_details': accountDetails,
      'status': 'pending',
    });
  }
}
