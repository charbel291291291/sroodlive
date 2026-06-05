import '../../core/supabase/supabase_service.dart';

class UserRestrictedException implements Exception {
  const UserRestrictedException(this.type);

  final String type;

  @override
  String toString() => 'user_restricted:$type';
}

class RestrictionsService {
  const RestrictionsService();

  Future<bool> hasRestriction(String type) async {
    final client = SupabaseService.requiredClient;
    if (client.auth.currentUser == null) {
      return false;
    }

    final data = await client.rpc(
      'user_has_active_restriction',
      params: {'p_restriction_type': type},
    );

    return data == true;
  }

  Future<void> throwIfRestricted(String type) async {
    if (await hasRestriction(type)) {
      throw UserRestrictedException(type);
    }
  }
}
