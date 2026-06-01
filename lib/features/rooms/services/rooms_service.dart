import '../../../core/supabase/supabase_service.dart';
import '../models/room.dart';

class RoomsService {
  const RoomsService();

  Future<List<Room>> getRooms() async {
    final data = await SupabaseService.requiredClient
        .from('rooms')
        .select()
        .order('created_at', ascending: false);

    return (data as List<dynamic>)
        .map((item) => Room.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Room> createRoom({
    required String name,
    String? description,
    String language = 'ar',
    int maxSeats = 12,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    final roomName = 'srood_${DateTime.now().millisecondsSinceEpoch}_${user.id.substring(0, 8)}';

    final data = await client
        .from('rooms')
        .insert({
          'owner_id': user.id,
          'name': name,
          'description': description,
          'language': language,
          'max_seats': maxSeats,
          'livekit_room_name': roomName,
        })
        .select()
        .single();

    return Room.fromJson(data);
  }

  Future<void> joinRoom(String roomId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    await client.from('room_members').upsert(
      {
        'room_id': roomId,
        'user_id': user.id,
        'role': 'listener',
        'left_at': null,
      },
      onConflict: 'room_id,user_id',
    );
  }

  Future<void> leaveRoom(String roomId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    await client
        .from('room_members')
        .update({
          'left_at': DateTime.now().toIso8601String(),
        })
        .eq('room_id', roomId)
        .eq('user_id', user.id);
  }
}

