import '../../../core/supabase/supabase_service.dart';
import '../models/profile_hub_models.dart';

class SettingsService {
  const SettingsService();

  Future<UserSettings> getMySettings() async {
    final data = await SupabaseService.requiredClient.rpc(
      'ensure_user_settings',
    );
    return UserSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<UserSettings> updateSettings(Map<String, dynamic> values) async {
    final client = SupabaseService.requiredClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No logged-in user found.');
    }

    final data = await client
        .from('user_settings')
        .update({...values, 'updated_at': DateTime.now().toIso8601String()})
        .eq('user_id', userId)
        .select()
        .single();

    return UserSettings.fromJson(data);
  }
}
