import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/supabase/supabase_service.dart';

class CrashV3RealtimeService {
  RealtimeChannel? _channel;
  void subscribe({
    required void Function() onChange,
    required void Function(RealtimeSubscribeStatus) onStatus,
  }) {
    _channel = SupabaseService.requiredClient
        .channel('crash-v3-game')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'crash_v3_round_events',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'crash_v3_bets',
          callback: (_) => onChange(),
        )
        .subscribe((status, [_]) => onStatus(status));
  }

  Future<void> dispose() async {
    final channel = _channel;
    if (channel != null) {
      await SupabaseService.requiredClient.removeChannel(channel);
    }
    _channel = null;
  }
}
