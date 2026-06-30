import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';

class RoomReadService {
  RoomReadService._();

  static final RoomReadService instance = RoomReadService._();

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _readsChannel;
  Timer? _refreshDebounce;
  String? _userId;
  String? _activeRoomId;
  bool _initializing = false;

  Future<void> initialize() async {
    final userId = SupabaseService.client?.auth.currentUser?.id;
    if (userId == null) {
      unreadCount.value = 0;
      return;
    }
    if (_initializing) return;
    if (_userId == userId &&
        _messagesChannel != null &&
        _readsChannel != null) {
      await refreshUnreadCount();
      return;
    }

    _initializing = true;
    try {
      await _unsubscribe();
      _userId = userId;
      _subscribe(userId);
      await refreshUnreadCount();
    } catch (e, st) {
      _log('initialize failed', e, st);
    } finally {
      _initializing = false;
    }
  }

  Future<void> markRoomRead(String roomId) async {
    if (roomId.isEmpty) return;
    final client = SupabaseService.client;
    if (client?.auth.currentUser == null) return;
    try {
      await client!.rpc('mark_room_read', params: {'p_room_id': roomId});
      await refreshUnreadCount();
    } catch (e, st) {
      _log('markRoomRead failed roomId=$roomId', e, st);
    }
  }

  Future<void> setActiveRoom(String roomId) async {
    _activeRoomId = roomId;
    await initialize();
    await markRoomRead(roomId);
  }

  void clearActiveRoom(String roomId) {
    if (_activeRoomId == roomId) _activeRoomId = null;
  }

  Future<void> refreshUnreadCount() async {
    final client = SupabaseService.client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) {
      unreadCount.value = 0;
      return;
    }

    try {
      final readRows = await client
          .from('room_reads')
          .select('room_id, last_read_at')
          .eq('user_id', userId);
      final reads = <String, DateTime>{};
      for (final raw in readRows as List<dynamic>) {
        final row = raw as Map<String, dynamic>;
        final roomId = row['room_id']?.toString();
        final lastRead = DateTime.tryParse(
          row['last_read_at']?.toString() ?? '',
        );
        if (roomId != null && roomId.isNotEmpty && lastRead != null) {
          reads[roomId] = lastRead.toUtc();
        }
      }

      if (reads.isEmpty) {
        _setUnreadCount(0);
        return;
      }

      final earliestRead = reads.values.reduce((a, b) => a.isBefore(b) ? a : b);
      final messageRows = await client
          .from('room_messages')
          .select('room_id, sender_id, created_at')
          .inFilter('room_id', reads.keys.toList())
          .neq('sender_id', userId)
          .gt('created_at', earliestRead.toIso8601String());

      final unreadRooms = <String>{};
      for (final raw in messageRows as List<dynamic>) {
        final row = raw as Map<String, dynamic>;
        final roomId = row['room_id']?.toString();
        final createdAt = DateTime.tryParse(
          row['created_at']?.toString() ?? '',
        );
        if (roomId == null || createdAt == null) continue;
        final lastRead = reads[roomId];
        if (lastRead != null && createdAt.toUtc().isAfter(lastRead)) {
          unreadRooms.add(roomId);
        }
      }
      _setUnreadCount(unreadRooms.length);
    } catch (e, st) {
      _log('refreshUnreadCount failed', e, st);
    }
  }

  void _subscribe(String userId) {
    final client = SupabaseService.requiredClient;
    _messagesChannel = client
        .channel('room_unread_messages_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'room_messages',
          callback: (payload) {
            final row = payload.newRecord;
            if (row['sender_id']?.toString() == userId) return;
            final roomId = row['room_id']?.toString();
            if (roomId != null && roomId == _activeRoomId) {
              unawaited(markRoomRead(roomId));
            } else {
              _scheduleRefresh();
            }
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.timedOut) {
            _log('room message subscription unhealthy: $status', error);
          }
        });

    _readsChannel = client
        .channel('room_unread_reads_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_reads',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.timedOut) {
            _log('room read subscription unhealthy: $status', error);
          }
        });
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(refreshUnreadCount()),
    );
  }

  void _setUnreadCount(int value) {
    if (unreadCount.value != value) unreadCount.value = value;
  }

  Future<void> _unsubscribe() async {
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    final messages = _messagesChannel;
    final reads = _readsChannel;
    _messagesChannel = null;
    _readsChannel = null;
    if (messages != null) await messages.unsubscribe();
    if (reads != null) await reads.unsubscribe();
  }

  void _log(String message, [Object? error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    debugPrint('[RoomReadService] $message${error == null ? '' : ': $error'}');
    if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
  }
}
