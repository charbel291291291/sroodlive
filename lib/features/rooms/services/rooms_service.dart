import '../../../core/supabase/supabase_service.dart';
import '../models/room.dart';
import '../models/room_member.dart';

class RoomsService {
  const RoomsService();

  DateTime get _activeSince =>
      DateTime.now().toUtc().subtract(const Duration(seconds: 45));

  Future<List<Room>> getRooms() async {
    final data = await SupabaseService.requiredClient
        .from('rooms')
        .select()
        .order('created_at', ascending: false);

    return (data as List<dynamic>)
        .map((item) => Room.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, int>> getActiveMemberCounts() async {
    final data = await SupabaseService.requiredClient
        .from('room_members')
        .select('room_id')
        .filter('left_at', 'is', null)
        .gte('last_seen_at', _activeSince.toIso8601String());

    final counts = <String, int>{};

    for (final item in data as List<dynamic>) {
      final map = item as Map<String, dynamic>;
      final roomId = map['room_id'] as String;

      counts[roomId] = (counts[roomId] ?? 0) + 1;
    }

    return counts;
  }

  Future<List<RoomMember>> getActiveRoomMembers(String roomId) async {
    final client = SupabaseService.requiredClient;

    try {
      final data = await client
          .from('room_members')
          .select('*, profiles(display_name, full_name, username, name)')
          .eq('room_id', roomId)
          .filter('left_at', 'is', null)
          .gte('last_seen_at', _activeSince.toIso8601String())
          .order('joined_at', ascending: true);

      return (data as List<dynamic>)
          .map((item) => RoomMember.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      final data = await client
          .from('room_members')
          .select()
          .eq('room_id', roomId)
          .filter('left_at', 'is', null)
          .gte('last_seen_at', _activeSince.toIso8601String())
          .order('joined_at', ascending: true);

      return (data as List<dynamic>)
          .map((item) => RoomMember.fromJson(item as Map<String, dynamic>))
          .toList();
    }
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

    final roomName =
        'srood_${DateTime.now().millisecondsSinceEpoch}_${user.id.substring(0, 8)}';

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

  Future<String> getMyRoleForRoom(String roomId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    final room = await client
        .from('rooms')
        .select('owner_id')
        .eq('id', roomId)
        .single();

    final ownerId = room['owner_id']?.toString();

    if (ownerId == user.id) {
      return 'host';
    }

    return 'listener';
  }

  Future<void> joinRoom(String roomId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    final role = await getMyRoleForRoom(roomId);
    final now = DateTime.now().toUtc().toIso8601String();

    await client.from('room_members').upsert(
      {
        'room_id': roomId,
        'user_id': user.id,
        'role': role,
        'is_muted': true,
        'left_at': null,
        'last_seen_at': now,
      },
      onConflict: 'room_id,user_id',
    );
  }

  Future<void> heartbeatRoomMember(String roomId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      return;
    }

    await client
        .from('room_members')
        .update({'last_seen_at': DateTime.now().toUtc().toIso8601String()})
        .eq('room_id', roomId)
        .eq('user_id', user.id)
        .filter('left_at', 'is', null);
  }

  Future<void> setRoomLocked({
    required String roomId,
    required bool isLocked,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    final room = await client
        .from('rooms')
        .select('owner_id')
        .eq('id', roomId)
        .single();

    final ownerId = room['owner_id']?.toString();

    if (ownerId != user.id) {
      throw StateError('Only the host can lock this room.');
    }

    await client
        .from('rooms')
        .update({'is_locked': isLocked})
        .eq('id', roomId);
  }
  Future<void> updateMemberRole({
    required String roomId,
    required String userId,
    required String role,
  }) async {
    if (role != 'speaker' && role != 'listener') {
      throw ArgumentError('Invalid role.');
    }

    await SupabaseService.requiredClient
        .from('room_members')
        .update({'role': role})
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .filter('left_at', 'is', null);
  }

  Future<void> setMyMuteStatus({
    required String roomId,
    required bool isMuted,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    await client
        .from('room_members')
        .update({'is_muted': isMuted})
        .eq('room_id', roomId)
        .eq('user_id', user.id)
        .filter('left_at', 'is', null);
  }

  Future<void> leaveRoom(String roomId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    final now = DateTime.now().toUtc().toIso8601String();

    await client
        .from('room_members')
        .update({
          'is_muted': true,
          'left_at': now,
          'last_seen_at': now,
        })
        .eq('room_id', roomId)
        .eq('user_id', user.id);
  }
}
