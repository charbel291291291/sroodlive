import '../../../core/supabase/supabase_service.dart';
import '../models/profile_hub_models.dart';

class AgencyService {
  const AgencyService();

  Future<AgencyMembership?> getMyMembership() async {
    final userId = SupabaseService.requiredClient.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No logged-in user found.');
    }

    final data = await SupabaseService.requiredClient
        .from('agency_members')
        .select(
          'role, status, agencies(name, country, commission_rate, monthly_target_coins, monthly_target_hours)',
        )
        .eq('user_id', userId)
        .order('joined_at', ascending: false)
        .limit(1);

    final rows = data as List<dynamic>;
    if (rows.isEmpty) {
      return null;
    }

    return AgencyMembership.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<List<AgencyApplication>> getMyApplications() async {
    final data = await SupabaseService.requiredClient
        .from('agency_applications')
        .select()
        .order('created_at', ascending: false)
        .limit(20);

    return (data as List<dynamic>)
        .map((item) => AgencyApplication.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Submits an application through the server-side SECURITY DEFINER RPCs.
  /// Direct table inserts are revoked; the server forces user_id = auth.uid()
  /// and status = pending, and (for join) resolves the agency from the code.
  Future<void> submitApplication({
    required String applicationType,
    required String message,
    String? phone,
    String? country,
    String? experience,
    String? agencyCode,
  }) async {
    final client = SupabaseService.requiredClient;
    switch (applicationType) {
      case 'become_host':
        await client.rpc('apply_to_become_host', params: {
          'p_message': message,
          'p_phone': phone,
          'p_country': country,
          'p_experience': experience,
        });
      case 'create_agency':
        await client.rpc('apply_to_create_agency', params: {
          'p_message': message,
          'p_phone': phone,
          'p_country': country,
          'p_experience': experience,
        });
      case 'join_agency':
        await client.rpc('apply_to_join_agency', params: {
          'p_agency_code': agencyCode,
          'p_message': message,
          'p_phone': phone,
          'p_country': country,
          'p_experience': experience,
        });
      default:
        throw ArgumentError('Unknown application type: $applicationType');
    }
  }
}
