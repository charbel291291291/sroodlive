
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class ClosedRoomException implements Exception {
  const ClosedRoomException();

  @override
  String toString() => 'closed_room';
}

class RoomsService {
  const RoomsService();

  static const RestrictionsService _restrictions = RestrictionsService();

  DateTime get _activeSince =>
      DateTime.now().toUtc().subtract(const Duration(seconds: 45));

  Future<List<Room>> getRooms({String? countryCode}) async {
    // Normalize: null or blank = "all countries" (no filter).
    final code = (countryCode?.trim().toUpperCase().isEmpty ?? true)
        ? null
        : countryCode!.trim().toUpperCase();

    var query = SupabaseService.requiredClient
        .from('rooms')
        .select('*, profiles!owner_id(country)')
        .eq('is_closed', false);

    // Apply server-side country filter only when a specific country is selected.
    if (code != null) {
      query = query.eq('country_code', code);
    }

    final data = await query.order('created_at', ascending: false);

    return (data as List<dynamic>)
        .map((item) => Room.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, int>> getActiveMemberCounts(List<String> roomIds) async {
    if (roomIds.isEmpty) return {};

    final data = await SupabaseService.requiredClient.rpc(
      'get_active_member_counts',
      params: {'p_room_ids': roomIds},
    );

    final counts = <String, int>{};
    for (final item in data as List<dynamic>) {
      final map = item as Map<String, dynamic>;
      final roomId = map['room_id'] as String;
      final count = map['active_count'];
      counts[roomId] = count is int ? count : (count as num).toInt();
    }
    return counts;
  }

  /// Returns all current members (not left) without the 45-second freshness
  /// window. Used in the owner management screen where members may not be
  /// actively sending heartbeats.
  Future<List<RoomMember>> getAllRoomMembers(String roomId) async {
    final client = SupabaseService.requiredClient;
    try {
      final data = await client
          .from('room_members')
          .select(
            '*, profiles(display_name, username, public_user_id, avatar_url, selected_avatar_frame_key, vip_level, vip_started_at, vip_expires_at)',
          )
          .eq('room_id', roomId)
          .filter('left_at', 'is', null)
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
          .order('joined_at', ascending: true);
      return (data as List<dynamic>)
          .map((item) => RoomMember.fromJson(item as Map<String, dynamic>))
          .toList();
    }
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

  /// Returns the caller's existing open room (if any), or creates a new one.
  /// Uses the backend RPC which enforces the one-active-room-per-owner rule
  /// via a partial unique index.  Pass [existingRoomFound] to learn whether
  /// the returned room already existed (so the caller can show a toast).
  Future<({Room room, bool alreadyExisted})> getOrCreateRoom({
    required String name,
    String? description,
    String language = 'ar',
    int maxSeats = 12,
    String? countryCode,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('No logged-in user found.');

    // First check whether the user already has an open room.
    final existing = await client
        .from('rooms')
        .select()
        .eq('owner_id', user.id)
        .eq('is_closed', false)
        .maybeSingle();

    if (existing != null) {
      return (room: Room.fromJson(existing), alreadyExisted: true);
    }

    final lkName =
        'srood_${DateTime.now().millisecondsSinceEpoch}_${user.id.substring(0, 8)}';

    // Normalize country_code to uppercase; fall back to owner profile value.
    final normalizedCode = countryCode?.trim().toUpperCase().isEmpty == true
        ? null
        : countryCode?.trim().toUpperCase();

    // If not supplied by caller, read from the owner's profile so the room
    // is discoverable under the correct country filter immediately.
    String? resolvedCode = normalizedCode;
    if (resolvedCode == null) {
      try {
        final profile = await client
            .from('profiles')
            .select('country_code')
            .eq('id', user.id)
            .maybeSingle();
        final raw = profile?['country_code']?.toString().trim().toUpperCase();
        if (raw != null && raw.isNotEmpty) resolvedCode = raw;
      } catch (_) {}
    }

    final inserted = await client.from('rooms').insert({
      'owner_id': user.id,
      'name': name,
      'description': ?description,
      'language': language,
      'max_seats': maxSeats,
      'livekit_room_name': lkName,
      'country_code': resolvedCode,
    }).select().single();

    return (room: Room.fromJson(inserted), alreadyExisted: false);
  }

  /// Legacy direct-insert path kept for internal use; prefer [getOrCreateRoom].
  Future<Room> createRoom({
    required String name,
    String? description,
    String language = 'ar',
    int maxSeats = 12,
    String? countryCode,
  }) async {
    final result = await getOrCreateRoom(
      name: name,
      description: description,
      language: language,
      maxSeats: maxSeats,
      countryCode: countryCode,
    );
    return result.room;
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
    if (roomId.isEmpty) throw StateError('Room ID is missing.');

    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    // Kick off the room lookup in parallel with the restriction checks so the
    // two independent round-trips overlap instead of running back-to-back.
    // Restriction precedence is preserved: account_ban then room_ban are still
    // awaited (and thrown) before the room row is consumed below.
    final roomFuture = client
        .from('rooms')
        .select('owner_id,is_locked,is_closed')
        .eq('id', roomId)
        .single();
    // Always observe the future so an early restriction throw can't surface it
    // as an unhandled async error.
    unawaited(roomFuture.then((_) {}, onError: (_) {}));

    await _restrictions.throwIfRestricted('account_ban');
    await _restrictions.throwIfRestricted('room_ban');

    final room = await roomFuture;

    final ownerId = room['owner_id']?.toString();
    final role = ownerId == user.id ? 'host' : 'listener';
    final isLocked = room['is_locked'] == true;
    final isClosed = room['is_closed'] == true;

    if (isClosed) {
      throw const ClosedRoomException();
    }

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

      if (message.contains('closed_room')) {
        throw const ClosedRoomException();
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

    await _restrictions.throwIfRestricted('account_ban');
    await _restrictions.throwIfRestricted('room_ban');

    // Use safe RPC function that verifies room ownership
    await SupabaseService.requiredClient.rpc(
      'update_room_member_role',
      params: {
        'p_room_id': roomId,
        'p_user_id': userId,
        'p_role': role,
        'p_seat_number': role == 'speaker' ? seatNumber : null,
      },
    );
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

    // Use the same claim_speaker_seat RPC used by non-hosts so the seat
    // uniqueness constraint is enforced atomically server-side, preventing
    // race conditions that surface as 23505 duplicate-key errors.
    try {
      await client.rpc(
        'claim_speaker_seat',
        params: {'p_room_id': roomId, 'p_seat_number': seatNumber},
      );
    } on PostgrestException catch (e) {
      final code = e.message;
      if (code.contains('seat_taken') || (e.code == '23505')) {
        throw Exception('This seat is already taken.');
      }
      rethrow;
    }
  }

  Future<void> moveMeToSpeakerSeat({
    required String roomId,
    required int seatNumber,
  }) async {
    if (SupabaseService.requiredClient.auth.currentUser == null) {
      throw StateError('No logged-in user found.');
    }

    // Client-side restriction check (fast path before hitting the network).
    await _restrictions.throwIfRestricted('account_ban');
    await _restrictions.throwIfRestricted('room_ban');

    // All remaining checks (membership, ban, force-mute, seat availability,
    // capacity, atomic uniqueness) are enforced server-side by the RPC.
    try {
      await SupabaseService.requiredClient.rpc(
        'claim_speaker_seat',
        params: {'p_room_id': roomId, 'p_seat_number': seatNumber},
      );
    } on PostgrestException catch (e) {
      final code = e.message;
      if (code.contains('seat_taken')) {
        throw Exception('This seat is already taken.');
      } else if (code.contains('force_muted')) {
        throw Exception('You have been muted from speaking by the host.');
      } else if (code.contains('banned_from_room')) {
        throw Exception('You are banned from this room.');
      } else if (code.contains('invalid_seat_number')) {
        throw Exception('Invalid seat number.');
      } else if (code.contains('not_in_room')) {
        throw Exception('You are not an active member of this room.');
      } else if (code.contains('room_closed')) {
        throw Exception('This room is closed.');
      } else if (e.code == '23505') {
        throw Exception('This seat is already taken.');
      } else {
        rethrow;
      }
    }
  }

  Future<void> updateMemberSeatNumber({
    required String roomId,
    required String userId,
    required int seatNumber,
  }) async {
    // Use safe RPC function that verifies room ownership
    await SupabaseService.requiredClient.rpc(
      'update_room_member_seat',
      params: {
        'p_room_id': roomId,
        'p_user_id': userId,
        'p_seat_number': seatNumber,
      },
    );
  }

  Future<void> removeMemberFromRoom({
    required String roomId,
    required String userId,
  }) async {
    // Use safe RPC function that verifies room ownership
    await SupabaseService.requiredClient.rpc(
      'remove_room_member',
      params: {'p_room_id': roomId, 'p_user_id': userId},
    );
  }

  Future<void> setMyMuteStatus({
    required String roomId,
    required bool isMuted,
  }) async {
    debugPrint('[RT-MEMBERS] setMyMuteStatus roomId=$roomId isMuted=$isMuted');
    await SupabaseService.requiredClient.rpc(
      'set_my_room_mute_status',
      params: {'p_room_id': roomId, 'p_is_muted': isMuted},
    );
  }

  Future<void> setRoomMuted({
    required String roomId,
    required bool isMuted,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'set_room_muted',
      params: {'p_room_id': roomId, 'p_is_muted': isMuted},
    );
  }

  Future<void> leaveRoom(String roomId) async {
    final client = SupabaseService.requiredClient;
    if (client.auth.currentUser == null) throw StateError('No logged-in user.');

    try {
      // RPC soft-removes the member and closes the room if the owner left
      // and no other members remain.
      await client.rpc('leave_room_and_maybe_close', params: {
        'p_room_id': roomId,
      });
    } catch (_) {
      // Fallback to direct update if the RPC isn't deployed yet.
      final now = DateTime.now().toUtc().toIso8601String();
      await client
          .from('room_members')
          .update({'left_at': now, 'last_seen_at': now})
          .eq('room_id', roomId)
          .eq('user_id', client.auth.currentUser!.id);
    }
  }

  /// Force-closes the room for all participants. Owner-only.
  /// Calls the owner_close_room RPC which marks all members as left and
  /// sets is_closed = true regardless of remaining member count.
  Future<void> closeRoom(String roomId) async {
    final client = SupabaseService.requiredClient;
    if (client.auth.currentUser == null) throw StateError('No logged-in user.');
    await client.rpc('owner_close_room', params: {'p_room_id': roomId});
  }

  /// Close room with optional PIN verification (backend validates the PIN).
  Future<void> closeRoomWithPin(String roomId, {String? pin}) async {
    final client = SupabaseService.requiredClient;
    if (client.auth.currentUser == null) throw StateError('No logged-in user.');
    await client.rpc('owner_close_room_with_pin', params: {
      'p_room_id': roomId,
      'p_pin': pin,
    });
  }

  /// Returns true if the PIN is correct (or room has no PIN set).
  Future<bool> verifyRoomPin(String roomId, String pin) async {
    final result = await SupabaseService.requiredClient
        .rpc('verify_room_pin', params: {'p_room_id': roomId, 'p_pin': pin});
    return result as bool? ?? false;
  }

  /// Closes any active rooms with zero remaining members.
  /// Call this on room-list load and after leaving a room.
  Future<void> closeEmptyRooms() async {
    try {
      await SupabaseService.requiredClient.rpc('close_empty_rooms');
    } catch (_) {}
  }

  // ── Room appearance (cover + avatar images) ─────────────────────────────

  /// Picks an image from the gallery and uploads it to [bucket].
  /// Returns the public URL on success, throws on failure.
  Future<String> pickAndUploadRoomImage({
    required String roomId,
    required String bucket,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('No logged-in user.');

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (picked == null) throw const RoomImagePickerCancelled();

    final bytes = await picked.readAsBytes();
    final ext = picked.path.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'png'  => 'image/png',
      'webp' => 'image/webp',
      _      => 'image/jpeg',
    };

    final path = '$roomId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await client.storage.from(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: true),
    );

    return client.storage.from(bucket).getPublicUrl(path);
  }

  /// Saves cover_url and/or room_avatar_url for the given room.
  /// Only the room owner can call this (Supabase RLS on rooms table enforces it).
  Future<void> updateRoomAppearance({
    required String roomId,
    String? coverUrl,
    String? avatarUrl,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('No logged-in user.');

    final updates = <String, dynamic>{};
    if (coverUrl != null) updates['cover_url'] = coverUrl;
    if (avatarUrl != null) updates['room_avatar_url'] = avatarUrl;
    if (updates.isEmpty) return;

    await client
        .from('rooms')
        .update(updates)
        .eq('id', roomId)
        .eq('owner_id', user.id);
  }

  /// Clears cover_url or room_avatar_url for the given room.
  Future<void> clearRoomImage({
    required String roomId,
    required bool clearCover,
    required bool clearAvatar,
  }) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('No logged-in user.');

    final updates = <String, dynamic>{};
    if (clearCover) updates['cover_url'] = null;
    if (clearAvatar) updates['room_avatar_url'] = null;
    if (updates.isEmpty) return;

    await client
        .from('rooms')
        .update(updates)
        .eq('id', roomId)
        .eq('owner_id', user.id);
  }

  /// Returns the user's personal room, creating it on first call.
  /// The room may be closed — caller must check [Room.isClosed] and call
  /// [reopenMyRoom] if needed before navigating into it.
  Future<Room> getOrCreateMyRoom() async {
    final data = await SupabaseService.requiredClient.rpc('get_or_create_my_room');
    return Room.fromJson(_singleRow(data));
  }

  /// Toggles a mic seat closed/open. Returns the updated closed_seats list.
  Future<List<int>> toggleSeatClosed(String roomId, int seatNumber) async {
    final data = await SupabaseService.requiredClient.rpc(
      'toggle_room_seat_closed',
      params: {'p_room_id': roomId, 'p_seat_number': seatNumber},
    );
    if (data is List) return data.map((e) => (e as num).toInt()).toList();
    return const [];
  }

  /// Un-closes the user's personal room and returns it with [isClosed] = false.
  Future<Room> reopenMyRoom() async {
    final data = await SupabaseService.requiredClient.rpc('reopen_my_room');
    return Room.fromJson(_singleRow(data));
  }

  /// PostgREST may return a single composite-type RPC result as either a Map
  /// or a one-element List depending on the function signature. This handles both.
  static Map<String, dynamic> _singleRow(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty) {
      return Map<String, dynamic>.from(data.first as Map);
    }
    throw StateError('RPC returned unexpected data: $data');
  }
}

class RoomImagePickerCancelled implements Exception {
  const RoomImagePickerCancelled();
}
