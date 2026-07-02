import '../../../core/supabase/supabase_service.dart';

/// Account lifecycle operations (deletion, push-token registration) backed by
/// SECURITY DEFINER RPCs. No client-side table writes.
class AccountService {
  const AccountService();

  /// Requests self-service account deletion for the signed-in user. The
  /// backend anonymizes personal data, records an audit row, and removes push
  /// tokens; financial ledger rows are preserved (anonymized) for retention.
  ///
  /// Returns the RPC result map (e.g. `status: 'anonymized' | 'already_requested'`).
  Future<Map<String, dynamic>> requestDeletion({String? reason}) async {
    final res = await SupabaseService.requiredClient.rpc(
      'request_account_deletion',
      params: {'p_reason': reason},
    );
    return (res is Map)
        ? Map<String, dynamic>.from(res)
        : <String, dynamic>{'status': 'anonymized'};
  }
}
