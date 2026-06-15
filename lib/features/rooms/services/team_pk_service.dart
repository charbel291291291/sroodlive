import 'dart:async';

import '../../../core/supabase/supabase_service.dart';
import '../models/pk_session.dart';

class TeamPkService {
  const TeamPkService();

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<PkSession?> getActivePk(String roomId) async {
    final result = await SupabaseService.requiredClient.rpc(
      'get_active_room_team_pk',
      params: {'p_room_id': roomId},
    );
    if (result == null) return null;
    final data = result as Map<String, dynamic>;
    return PkSession.fromJson(
      data['session'] as Map<String, dynamic>,
      (data['members'] as List<dynamic>?) ?? [],
    );
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  Stream<PkSession?> watchPk(String roomId) {
    final controller = StreamController<PkSession?>.broadcast();
    PkSession? current;

    final membersCache = <String, PkMember>{};

    void emitCurrent() {
      if (!controller.isClosed) controller.add(current);
    }

    final client = SupabaseService.requiredClient;

    final sessionSub = client
        .from('room_team_pk_sessions')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .listen((rows) {
          final active = rows
              .where((r) => r['status'] == 'active')
              .toList();

          if (active.isEmpty) {
            final finished = rows
                .where((r) => r['status'] == 'finished')
                .toList();
            if (finished.isNotEmpty && current?.isActive == true) {
              final s = finished.last;
              current = current!.copyWith(
                status: s['status']?.toString(),
                teamAScore: (s['team_a_score'] as num?)?.toInt(),
                teamBScore: (s['team_b_score'] as num?)?.toInt(),
                winnerTeam: s['winner_team']?.toString(),
                finishedAt: s['finished_at'] != null
                    ? DateTime.parse(s['finished_at'].toString())
                    : null,
                updatedAt: DateTime.parse(s['updated_at'].toString()),
              );
              emitCurrent();
              return;
            }
            if (current != null) {
              current = null;
              emitCurrent();
            }
            return;
          }

          final s = active.last;
          final sessionId = s['id'].toString();

          if (current == null || current!.id != sessionId) {
            current = PkSession.fromJson(
              s,
              membersCache.values
                  .where((m) => m.pkSessionId == sessionId)
                  .toList(),
            );
          } else {
            current = current!.copyWith(
              status: s['status']?.toString(),
              teamAScore: (s['team_a_score'] as num?)?.toInt(),
              teamBScore: (s['team_b_score'] as num?)?.toInt(),
              winnerTeam: s['winner_team']?.toString(),
              finishedAt: s['finished_at'] != null
                  ? DateTime.parse(s['finished_at'].toString())
                  : null,
              updatedAt: DateTime.parse(s['updated_at'].toString()),
            );
          }
          emitCurrent();
        });

    final memberSub = client
        .from('room_team_pk_members')
        .stream(primaryKey: ['id'])
        .listen((rows) {
          membersCache.clear();
          for (final r in rows) {
            final m = PkMember.fromJson(r);
            membersCache[m.userId] = m;
          }
          if (current != null) {
            final updated = membersCache.values
                .where((m) => m.pkSessionId == current!.id)
                .toList();
            if (updated.isNotEmpty) {
              current = current!.copyWith(members: updated);
              emitCurrent();
            }
          }
        });

    controller.onCancel = () {
      sessionSub.cancel();
      memberSub.cancel();
    };

    return controller.stream;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<String> startPk({
    required String roomId,
    required int durationSeconds,
    bool autoAssign = true,
  }) async {
    final result = await SupabaseService.requiredClient.rpc(
      'start_room_team_pk',
      params: {
        'p_room_id': roomId,
        'p_duration_seconds': durationSeconds,
        'p_auto_assign': autoAssign,
      },
    );
    final data = result as Map<String, dynamic>;
    return (data['session'] as Map<String, dynamic>)['id'].toString();
  }

  Future<void> finishPk(String sessionId) async {
    await SupabaseService.requiredClient.rpc(
      'finish_room_team_pk',
      params: {'p_pk_session_id': sessionId},
    );
  }

  Future<void> cancelPk(String sessionId) async {
    await SupabaseService.requiredClient.rpc(
      'cancel_room_team_pk',
      params: {'p_pk_session_id': sessionId},
    );
  }
}
