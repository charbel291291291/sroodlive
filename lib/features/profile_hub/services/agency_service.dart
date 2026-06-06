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

  Future<void> submitApplication({
    required String applicationType,
    required String message,
    String? phone,
    String? country,
    String? experience,
  }) async {
    final userId = SupabaseService.requiredClient.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No logged-in user found.');
    }

    await SupabaseService.requiredClient.from('agency_applications').insert({
      'user_id': userId,
      'application_type': applicationType,
      'message': message,
      'phone': phone,
      'country': country,
      'experience': experience,
      'status': 'pending',
    });
  }
}
