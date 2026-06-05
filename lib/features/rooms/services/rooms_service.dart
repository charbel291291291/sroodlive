import '../../../core/supabase/supabase_service.dart';
import '../../../shared/services/restrictions_service.dart';
import '../models/room.dart';
import '../models/room_member.dart';

class LockedRoomException implements Exception {
  const LockedRoomException();

  @override
  String toString() => 'locked_room';
}

class WrongRoomPasswordException implements Exception {
  const WrongRoomPasswordException();

  @override
  String toString() => 'wrong_room_password';
}

class RoomPasswordRequiredException implements Exception {
  const RoomPasswordRequiredException();

  @override
  String toString() => 'room_password_required';
}

class RoomsService {
  const RoomsService();

  static const RestrictionsService _restrictions = RestrictionsService();

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
          .select(
            '*, profiles(display_name, username, public_user_id, avatar_url, selected_avatar_frame_key, vip_level, vip_started_at, vip_expires_at)',
          )
          .eq('room_id', roomId)
          .filter('left_at', 'is', null)
          .gte('last_seen_at', _activeSince.toIso8601String())
          .order('joined_at', ascending: true);

      return (data as List<dynamic>)
          .map((item) => RoomMember.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      try {
        final data = await client
            .from('room_members')
            .select(
              '*, profiles(display_name, username, avatar_url, selected_avatar_frame_key, vip_level, vip_started_at, vip_expires_at)',
            )
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

    await _restrictions.throwIfRestricted('account_ban');
    await _restrictions.throwIfRestricted('room_ban');

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

  Future<void> joinRoom(String roomId, {String? password}) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    await _restrictions.throwIfRestricted('account_ban');
    await _restrictions.throwIfRestricted('room_ban');

    final room = await client
        .from('rooms')
        .select('owner_id,is_locked')
        .eq('id', roomId)
        .single();

    final ownerId = room['owner_id']?.toString();
    final role = ownerId == user.id ? 'host' : 'listener';
    final isLocked = room['is_locked'] == true;

    if (isLocked &&
        role == 'listener' &&
        (password == null || password.trim().isEmpty)) {
      throw const LockedRoomException();
    }

    try {
      await client.rpc(
        'join_room_with_password',
        params: {'p_room_id': roomId, 'p_password': password},
      );
    } catch (error) {
      final message = error.toString();

      if (message.contains('wrong_room_password')) {
        throw const WrongRoomPasswordException();
      }

      if (message.contains('locked_room')) {
        throw const LockedRoomException();
      }

      rethrow;
    }
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
    String? password,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    await _restrictions.throwIfRestricted('account_ban');
    await _restrictions.throwIfRestricted('room_ban');

    try {
      await client.rpc(
        'set_room_lock',
        params: {
          'p_room_id': roomId,
          'p_is_locked': isLocked,
          'p_password': password,
        },
      );
    } catch (error) {
      final message = error.toString();

      if (message.contains('room_password_required')) {
        throw const RoomPasswordRequiredException();
      }

      rethrow;
    }
  }

  Future<void> updateMemberRole({
    required String roomId,
    required String userId,
    required String role,
    int? seatNumber,
  }) async {
    if (role != 'speaker' && role != 'listener') {
      throw ArgumentError('Invalid role.');
    }

    final values = {
      'role': role,
      'seat_number': role == 'speaker' ? seatNumber : null,
    };

    await SupabaseService.requiredClient
        .from('room_members')
        .update(values)
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .filter('left_at', 'is', null);
  }

  Future<void> updateMySeatNumber({
    required String roomId,
    required int seatNumber,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    await _restrictions.throwIfRestricted('account_ban');
    await _restrictions.throwIfRestricted('room_ban');

    await client
        .from('room_members')
        .update({'seat_number': seatNumber})
        .eq('room_id', roomId)
        .eq('user_id', user.id)
        .filter('left_at', 'is', null);
  }

  Future<void> moveMeToSpeakerSeat({
    required String roomId,
    required int seatNumber,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    await _restrictions.throwIfRestricted('account_ban');
    await _restrictions.throwIfRestricted('room_ban');

    await client
        .from('room_members')
        .update({'role': 'speaker', 'seat_number': seatNumber})
        .eq('room_id', roomId)
        .eq('user_id', user.id)
        .filter('left_at', 'is', null);
  }

  Future<void> updateMemberSeatNumber({
    required String roomId,
    required String userId,
    required int seatNumber,
  }) async {
    await SupabaseService.requiredClient
        .from('room_members')
        .update({'seat_number': seatNumber})
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .filter('left_at', 'is', null);
  }

  Future<void> removeMemberFromRoom({
    required String roomId,
    required String userId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await SupabaseService.requiredClient
        .from('room_members')
        .update({
          'is_muted': true,
          'seat_number': null,
          'left_at': now,
          'last_seen_at': now,
        })
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
        .update({'is_muted': true, 'left_at': now, 'last_seen_at': now})
        .eq('room_id', roomId)
        .eq('user_id', user.id);
  }
}
