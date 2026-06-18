import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/room_announcement.dart';
import '../models/room_ban.dart';
import '../models/room_moderator.dart';

class RoomManagementService {
  const RoomManagementService();

  // ── Access check ──────────────────────────────────────────────────────────

  bool canManageRoom(String ownerId) {
    final uid = SupabaseService.requiredClient.auth.currentUser?.id;
    return uid != null && uid == ownerId;
  }

  // ── Room stats ─────────────────────────────────────────────────────────────

  Future<Map<String, int>> getRoomStats(String roomId) async {
    final client = SupabaseService.requiredClient;

    final membersData = await client
        .from('room_members')
        .select('role')
        .eq('room_id', roomId)
        .filter('left_at', 'is', null);

    int listeners = 0;
    int speakers = 0;

    for (final item in membersData as List<dynamic>) {
      final role = (item as Map<String, dynamic>)['role'] as String?;
      if (role == 'speaker' || role == 'host') {
        speakers++;
      } else {
        listeners++;
      }
    }

    final giftsData = await client
        .from('gift_transactions')
        .select('gift_price_coins')
        .eq('room_id', roomId);

    int totalCoins = 0;
    for (final item in giftsData as List<dynamic>) {
      final v = (item as Map<String, dynamic>)['gift_price_coins'];
      if (v is int) totalCoins += v;
      if (v is double) totalCoins += v.toInt();
    }

    final bansData = await client
        .from('room_bans')
        .select('id')
        .eq('room_id', roomId);

    return {
      'listeners': listeners,
      'speakers': speakers,
      'total_members': listeners + speakers,
      'total_gift_coins': totalCoins,
      'ban_count': (bansData as List<dynamic>).length,
    };
  }

  // ── Room metadata ──────────────────────────────────────────────────────────

  Future<void> updateRoom(
    String roomId, {
    String? name,
    String? description,
    String? coverUrl,
    int? maxSeats,
    String? backgroundUrl,
    bool clearBackground = false,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (coverUrl != null) updates['cover_url'] = coverUrl;
    if (maxSeats != null) updates['max_seats'] = maxSeats;
    if (backgroundUrl != null) updates['background_url'] = backgroundUrl;
    if (clearBackground) updates['background_url'] = null;
    if (updates.isEmpty) return;

    await SupabaseService.requiredClient
        .from('rooms')
        .update(updates)
        .eq('id', roomId);
  }

  /// Uploads a background image to Supabase storage and returns the public URL.
  Future<String> uploadRoomBackground(
    String roomId,
    Uint8List imageBytes,
    String mimeType,
  ) async {
    final client = SupabaseService.requiredClient;
    final path = '$roomId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await client.storage.from('room-backgrounds').uploadBinary(
          path,
          imageBytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
    return client.storage.from('room-backgrounds').getPublicUrl(path);
  }

  // ── Moderators ─────────────────────────────────────────────────────────────

  Future<List<RoomModerator>> getModerators(String roomId) async {
    final client = SupabaseService.requiredClient;
    try {
      final data = await client
          .from('room_moderators')
          .select('*, profiles(display_name, avatar_url)')
          .eq('room_id', roomId)
          .order('created_at', ascending: false);
      return (data as List<dynamic>)
          .map((e) => RoomModerator.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Profiles join may fail if RLS is restrictive — fall back to bare query.
      final data = await client
          .from('room_moderators')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: false);
      return (data as List<dynamic>)
          .map((e) => RoomModerator.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> addModerator(String roomId, String userId) async {
    await SupabaseService.requiredClient.from('room_moderators').upsert(
      {
        'room_id': roomId,
        'user_id': userId,
        'created_by': SupabaseService.requiredClient.auth.currentUser!.id,
      },
      onConflict: 'room_id,user_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> removeModerator(String moderatorId) async {
    await SupabaseService.requiredClient
        .from('room_moderators')
        .delete()
        .eq('id', moderatorId);
  }

  Future<void> updateModeratorPermissions(
    String moderatorId, {
    required bool canManageMics,
    required bool canMute,
    required bool canKick,
    required bool canManageSchedule,
  }) async {
    await SupabaseService.requiredClient
        .from('room_moderators')
        .update({
          'can_manage_mics': canManageMics,
          'can_mute': canMute,
          'can_kick': canKick,
          'can_manage_schedule': canManageSchedule,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', moderatorId);
  }

  // ── Bans ───────────────────────────────────────────────────────────────────

  Future<List<RoomBan>> getBans(String roomId) async {
    final data = await SupabaseService.requiredClient
        .from('room_bans')
        .select('*, profiles(display_name, avatar_url)')
        .eq('room_id', roomId)
        .order('created_at', ascending: false);

    return (data as List<dynamic>)
        .map((e) => RoomBan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> banUser(
    String roomId,
    String userId, {
    String? reason,
    DateTime? expiresAt,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'ban_room_member',
      params: {
        'p_room_id': roomId,
        'p_user_id': userId,
        'p_reason': reason,
        'p_expires_at': expiresAt?.toIso8601String(),
      },
    );
  }

  Future<void> unbanUser(String roomId, String userId) async {
    await SupabaseService.requiredClient.rpc(
      'unban_room_member',
      params: {'p_room_id': roomId, 'p_user_id': userId},
    );
  }

  // ── Mute (owner-level) ─────────────────────────────────────────────────────

  Future<void> ownerMuteMember(
    String roomId,
    String userId, {
    required bool isMuted,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'owner_mute_member',
      params: {'p_room_id': roomId, 'p_user_id': userId, 'p_is_muted': isMuted},
    );
  }

  // ── Announcements ──────────────────────────────────────────────────────────

  Future<List<RoomAnnouncement>> getAnnouncements(String roomId) async {
    final data = await SupabaseService.requiredClient
        .from('room_announcements')
        .select()
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(20);

    return (data as List<dynamic>)
        .map((e) => RoomAnnouncement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RoomAnnouncement?> getActiveAnnouncement(String roomId) async {
    final data = await SupabaseService.requiredClient
        .from('room_announcements')
        .select()
        .eq('room_id', roomId)
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(1);

    final list = data as List<dynamic>;
    if (list.isEmpty) return null;
    return RoomAnnouncement.fromJson(list.first as Map<String, dynamic>);
  }

  Future<void> saveAnnouncement(String roomId, String message) async {
    final uid = SupabaseService.requiredClient.auth.currentUser!.id;
    await deactivateAnnouncements(roomId);
    await SupabaseService.requiredClient.from('room_announcements').insert({
      'room_id': roomId,
      'created_by': uid,
      'message': message,
      'is_active': true,
    });
  }

  Future<void> deactivateAnnouncements(String roomId) async {
    await SupabaseService.requiredClient
        .from('room_announcements')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('room_id', roomId)
        .eq('is_active', true);
  }

  // ── Gift analytics ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getGiftSummary(String roomId) async {
    final data = await SupabaseService.requiredClient
        .from('gift_transactions')
        .select('gift_name, gift_code, gift_price_coins, created_at')
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(50);

    final grouped = <String, Map<String, dynamic>>{};
    for (final item in data as List<dynamic>) {
      final map = item as Map<String, dynamic>;
      final code = map['gift_code'] as String? ?? 'unknown';
      if (!grouped.containsKey(code)) {
        grouped[code] = {
          'gift_name': map['gift_name'],
          'gift_code': code,
          'count': 0,
          'total_coins': 0,
        };
      }
      grouped[code]!['count'] = (grouped[code]!['count'] as int) + 1;
      final coins = map['gift_price_coins'];
      int c = 0;
      if (coins is int) c = coins;
      if (coins is double) c = coins.toInt();
      grouped[code]!['total_coins'] =
          (grouped[code]!['total_coins'] as int) + c;
    }

    final list = grouped.values.toList()
      ..sort(
        (a, b) => (b['total_coins'] as int).compareTo(a['total_coins'] as int),
      );
    return list;
  }

  // ── Schedules ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRoomSchedules(String roomId) async {
    final data = await SupabaseService.requiredClient
        .from('room_schedules')
        .select()
        .eq('room_id', roomId)
        .eq('is_active', true)
        .order('scheduled_at', ascending: true);

    return (data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> createRoomSchedule({
    required String roomId,
    required String title,
    required DateTime scheduledAt,
    String? description,
  }) async {
    final uid = SupabaseService.requiredClient.auth.currentUser!.id;
    await SupabaseService.requiredClient.from('room_schedules').insert({
      'host_id': uid,
      'room_id': roomId,
      'title': title,
      'description': description,
      'scheduled_at': scheduledAt.toIso8601String(),
    });
  }

  Future<void> deleteSchedule(String scheduleId) async {
    await SupabaseService.requiredClient
        .from('room_schedules')
        .delete()
        .eq('id', scheduleId);
  }
}
