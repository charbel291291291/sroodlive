import '../../../core/supabase/supabase_service.dart';
import '../models/profile_hub_models.dart';

class FeedbackService {
  const FeedbackService();

  Future<List<FeedbackTicket>> getMyTickets() async {
    final data = await SupabaseService.requiredClient
        .from('feedback_tickets')
        .select()
        .order('created_at', ascending: false)
        .limit(30);

    return (data as List<dynamic>)
        .map((item) => FeedbackTicket.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createTicket({
    required String category,
    required String title,
    required String message,
  }) async {
    final userId = SupabaseService.requiredClient.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No logged-in user found.');
    }

    await SupabaseService.requiredClient.from('feedback_tickets').insert({
      'user_id': userId,
      'category': category,
      'title': title,
      'message': message,
      'status': 'open',
      'priority': 'normal',
    });
  }
}
