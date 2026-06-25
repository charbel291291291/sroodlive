import 'package:flutter/foundation.dart';
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

    // Run all three independent queries in parallel.
    final results = await Future.wait([
      client
          .from('room_members')
          .select('role')
          .eq('room_id', roomId)
          .filter('left_at', 'is', null),
      client
          .from('gift_transactions')
          .select('gift_price_coins')
          .eq('room_id', roomId),
      client.from('room_bans').select('id').eq('room_id', roomId),
    ]);

    final membersData = results[0] as List<dynamic>;
    final giftsData = results[1] as List<dynamic>;
    final bansData = results[2] as List<dynamic>;

    int listeners = 0;
    int speakers = 0;
    for (final item in membersData) {
      final role = (item as Map<String, dynamic>)['role'] as String?;
      if (role == 'speaker' || role == 'host') {
        speakers++;
      } else {
        listeners++;
      }
    }

    int totalCoins = 0;
    for (final item in giftsData) {
      final v = (item as Map<String, dynamic>)['gift_price_coins'];
      if (v is int) totalCoins += v;
      if (v is double) totalCoins += v.toInt();
    }

    return {
      'listeners': listeners,
      'speakers': speakers,
      'total_members': listeners + speakers,
      'total_gift_coins': totalCoins,
      'ban_count': bansData.length,
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
    bool? allowImages,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (coverUrl != null) updates['cover_url'] = coverUrl;
    if (maxSeats != null) updates['max_seats'] = maxSeats;
    if (backgroundUrl != null) updates['background_url'] = backgroundUrl;
    if (clearBackground) updates['background_url'] = null;
    if (allowImages != null) updates['allow_images'] = allowImages;
    if (updates.isEmpty) return;

    final uid = SupabaseService.requiredClient.auth.currentUser?.id;
    if (uid == null) throw StateError('No logged-in user.');

    await SupabaseService.requiredClient
        .from('rooms')
        .update(updates)
        .eq('id', roomId)
        .eq('owner_id', uid);
  }

  /// Uploads a cover image to Supabase storage and returns the public URL.
  Future<String> uploadRoomCover(
    String roomId,
    Uint8List imageBytes,
    String mimeType,
  ) async {
    final client = SupabaseService.requiredClient;
    final path = 'covers/$roomId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await client.storage.from('room-backgrounds').uploadBinary(
          path,
          imageBytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
    return client.storage.from('room-backgrounds').getPublicUrl(path);
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

    // Step 1: load moderator rows (with profile join where allowed).
    List<RoomModerator> mods;
    try {
      final data = await client
          .from('room_moderators')
          .select('*, profiles(display_name, username, full_name, avatar_url)')
          .eq('room_id', roomId)
          .order('created_at', ascending: false);
      mods = (data as List<dynamic>)
          .map((e) => RoomModerator.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      final data = await client
          .from('room_moderators')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: false);
      mods = (data as List<dynamic>)
          .map((e) => RoomModerator.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // Step 2: for any moderator whose profile is still missing, fetch separately.
    final missingIds = mods
        .where((m) => m.displayName == null && m.username == null && m.fullName == null)
        .map((m) => m.userId)
        .toSet()
        .toList();

    if (missingIds.isNotEmpty) {
      try {
        final profiles = await client
            .from('profiles')
            .select('id, display_name, username, full_name, avatar_url')
            .inFilter('id', missingIds);
        final profileMap = <String, Map<String, dynamic>>{
          for (final p in profiles as List<dynamic>)
            (p as Map<String, dynamic>)['id'] as String: p,
        };
        mods = mods.map((m) {
          final p = profileMap[m.userId];
          if (p == null) return m;
          debugPrint('[RoomMods] resolved name=${p['display_name'] ?? p['username'] ?? p['full_name']} userId=${m.userId}');
          return m.withProfile(
            displayName: p['display_name'] as String?,
            username: p['username'] as String?,
            fullName: p['full_name'] as String?,
            avatarUrl: p['avatar_url'] as String? ?? m.avatarUrl,
          );
        }).toList();
      } catch (e) {
        debugPrint('[RoomMods] profile fetch fallback error: $e');
      }
    }

    for (final m in mods) {
      debugPrint('[RoomMods] moderator userId=${m.userId} resolved name=${m.resolvedName}');
    }
    return mods;
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
    debugPrint('[RoomMods] moderator added userId=$userId');
  }

  Future<void> removeModerator(String moderatorId) async {
    await SupabaseService.requiredClient
        .from('room_moderators')
        .delete()
        .eq('id', moderatorId);
    debugPrint('[RoomMods] moderator removed id=$moderatorId');
  }

  /// Sends an in-app notification to a user about moderator assignment/removal.
  Future<void> notifyModeratorAssignment({
    required String userId,
    required String roomName,
    required bool assigned,
  }) async {
    try {
      final type = assigned ? 'moderator_assigned' : 'moderator_removed';
      final title = assigned ? 'تمت ترقيتك إلى مشرف' : 'تمت إزالتك من المشرفين';
      final body = assigned
          ? 'أنت الآن مشرف في غرفة $roomName'
          : 'تمت إزالتك من مشرفي غرفة $roomName';
      await SupabaseService.requiredClient.from('notifications').insert({
        'user_id': userId,
        'type': type,
        'title': title,
        'body': body,
        'is_read': false,
      });
      debugPrint('[RoomMods] notification sent type=$type userId=$userId');
    } catch (e) {
      debugPrint('[RoomMods] notification failed (non-fatal): $e');
    }
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
    // Insert the new announcement first so it is never lost if the second
    // step fails.  Then deactivate all other active announcements for the
    // room, excluding the one just created.
    final inserted = await SupabaseService.requiredClient
        .from('room_announcements')
        .insert({
          'room_id': roomId,
          'created_by': uid,
          'message': message,
          'is_active': true,
        })
        .select('id')
        .single();
    final newId = inserted['id'] as String;
    await SupabaseService.requiredClient
        .from('room_announcements')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('room_id', roomId)
        .eq('is_active', true)
        .neq('id', newId);
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
