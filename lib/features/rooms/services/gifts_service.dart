import '../../../core/supabase/supabase_service.dart';
import '../models/room_gift.dart';

class GiftsService {
  const GiftsService();

  Future<List<RoomGift>> fetchActiveGifts() async {
    final data = await SupabaseService.requiredClient
        .from('gifts')
        .select('id, code, name, arabic_name, price_coins, icon, sort_order')
        .eq('is_active', true)
        .order('sort_order', ascending: true);

    return (data as List<dynamic>)
        .map((item) => RoomGift.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> sendGift({
    required String roomId,
    required String receiverId,
    required RoomGift gift,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    await client.from('gift_transactions').insert({
      'room_id': roomId,
      'sender_id': user.id,
      'receiver_id': receiverId,
      'gift_id': gift.id,
      'gift_code': gift.code,
      'gift_name': gift.name,
      'gift_price_coins': gift.priceCoins,
    });
  }
}
