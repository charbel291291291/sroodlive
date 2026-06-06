import '../../../core/supabase/supabase_service.dart';
import '../models/profile_hub_models.dart';

class SupportService {
  const SupportService();

  Future<List<SupportTicket>> getMyTickets() async {
    final data = await SupabaseService.requiredClient
        .from('support_tickets')
        .select()
        .order('created_at', ascending: false)
        .limit(30);

    return (data as List<dynamic>)
        .map((item) => SupportTicket.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createTicket({
    required String category,
    required String subject,
    required String message,
    String? paymentReference,
    String? roomId,
    String? reportedUserId,
  }) async {
    final userId = SupabaseService.requiredClient.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No logged-in user found.');
    }

    await SupabaseService.requiredClient.from('support_tickets').insert({
      'user_id': userId,
      'category': category,
      'subject': subject,
      'message': message,
      'payment_reference': paymentReference,
      'room_id': roomId,
      'reported_user_id': reportedUserId,
      'status': 'open',
      'priority': category == 'recharge_support' ? 'high' : 'normal',
    });
  }
}
