import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/profile_hub_models.dart';

class AgencyService {
  const AgencyService();

  Future<AgencyMembership?> getMyMembership() async {
    try {
      final data = await SupabaseService.requiredClient.rpc(
        'get_my_agency_membership',
      );
      if (data == null || data is! Map) return null;
      return AgencyMembership.fromJson(Map<String, dynamic>.from(data));
    } catch (error, stackTrace) {
      if (_isMissingRpc(error, 'get_my_agency_membership')) {
        debugPrint(
          '[AgencyService] get_my_agency_membership unavailable; '
          'continuing without active membership.',
        );
        return null;
      }
      debugPrint('[AgencyService.getMyMembership] ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getMyHostStatus() async {
    try {
      final data = await SupabaseService.requiredClient.rpc(
        'get_my_host_status',
      );
      if (data is! Map) {
        return const {'is_approved_host': false, 'status': 'not_approved'};
      }
      return Map<String, dynamic>.from(data);
    } catch (error, stackTrace) {
      if (_isMissingRpc(error, 'get_my_host_status')) {
        debugPrint(
          '[AgencyService] get_my_host_status unavailable; '
          'using not_approved fallback.',
        );
        return const {'is_approved_host': false, 'status': 'not_approved'};
      }
      debugPrint('[AgencyService.getMyHostStatus] ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  bool _isMissingRpc(Object error, String rpcName) {
    final value = error.toString();
    return value.contains('PGRST202') ||
        value.contains('Could not find the function public.$rpcName') ||
        value.contains('function public.$rpcName');
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
    String? agencyName,
  }) async {
    final client = SupabaseService.requiredClient;
    switch (applicationType) {
      case 'become_host':
        await client.rpc(
          'apply_to_become_host',
          params: {
            'p_message': message,
            'p_phone': phone,
            'p_country': country,
            'p_experience': experience,
            'p_agency_name': agencyName,
          },
        );
      case 'create_agency':
        await client.rpc(
          'apply_to_create_agency',
          params: {
            'p_message': message,
            'p_phone': phone,
            'p_country': country,
            'p_experience': experience,
          },
        );
      case 'join_agency':
        await client.rpc(
          'apply_to_join_agency',
          params: {
            'p_agency_code': agencyCode,
            'p_message': message,
            'p_phone': phone,
            'p_country': country,
            'p_experience': experience,
          },
        );
      default:
        throw ArgumentError('Unknown application type: $applicationType');
    }
  }

  // ── Agency owner ───────────────────────────────────────────────────────────

  /// The host agency the current user owns (if any), for the owner entry point
  /// and to surface the join code. Host agencies only — never recharge agencies.
  Future<Map<String, dynamic>?> getMyOwnedAgency() async {
    final userId = SupabaseService.requiredClient.auth.currentUser?.id;
    if (userId == null) return null;
    final data = await SupabaseService.requiredClient
        .from('agencies')
        .select('id, name, agency_code, status, country')
        .eq('owner_user_id', userId)
        .eq('status', 'active')
        .limit(1);
    final rows = data as List<dynamic>;
    return rows.isEmpty ? null : rows.first as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> ownerListHosts() async {
    final data = await SupabaseService.requiredClient.rpc(
      'agency_owner_list_hosts',
    );
    return _rows(data);
  }

  Future<List<Map<String, dynamic>>> ownerListPendingApplications() async {
    final data = await SupabaseService.requiredClient.rpc(
      'agency_owner_list_pending_applications',
    );
    return _rows(data);
  }

  Future<void> ownerReviewApplication({
    required String applicationId,
    required bool approve,
    String? reply,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'agency_owner_review_application',
      params: {
        'p_application_id': applicationId,
        'p_approve': approve,
        'p_reply': reply,
      },
    );
  }

  // ── Admin (host agencies only) ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> adminListHostAgencyApplications({
    String? status,
    int limit = 50,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_host_agency_applications',
      params: {'p_status': status, 'p_limit': limit},
    );
    return _rows(data);
  }

  Future<void> adminReviewApplication({
    required String applicationId,
    required bool approve,
    String? reply,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_review_agency_application',
      params: {
        'p_application_id': applicationId,
        'p_approve': approve,
        'p_reply': reply,
      },
    );
  }

  Future<void> adminAssignHost({
    required String agencyId,
    required String hostUserId,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_assign_host_to_agency',
      params: {'p_agency_id': agencyId, 'p_host_user_id': hostUserId},
    );
  }

  Future<void> adminRemoveHost({
    required String hostUserId,
    String? reason,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_remove_host_from_agency',
      params: {'p_host_user_id': hostUserId, 'p_reason': reason},
    );
  }

  List<Map<String, dynamic>> _rows(dynamic data) => (data as List<dynamic>)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}
