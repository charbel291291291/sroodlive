import '../../../core/supabase/supabase_service.dart';

class LiveKitTokenResponse {
  const LiveKitTokenResponse({
    required this.token,
    required this.url,
    required this.roomName,
  });

  final String token;
  final String url;
  final String roomName;

  factory LiveKitTokenResponse.fromJson(Map<String, dynamic> json) {
    return LiveKitTokenResponse(
      token: json['token'] as String,
      url: json['url'] as String,
      roomName: json['roomName'] as String,
    );
  }
}

class _CachedToken {
  _CachedToken(this.response) : _fetchedAt = DateTime.now();
  final LiveKitTokenResponse response;
  final DateTime _fetchedAt;
  // LiveKit tokens are typically valid for 6 hours; we cache for 3 min so
  // quick re-entries (minimize → return) skip the edge-function round-trip.
  bool get isExpired =>
      DateTime.now().difference(_fetchedAt) > const Duration(minutes: 3);
}

class LiveKitTokenService {
  const LiveKitTokenService();

  // Shared across all service instances — one cache entry per room.
  static final Map<String, _CachedToken> _cache = {};

  Future<LiveKitTokenResponse> getToken({required String roomId}) async {
    final cached = _cache[roomId];
    if (cached != null && !cached.isExpired) {
      return cached.response;
    }

    final client = SupabaseService.requiredClient;
    final response = await client.functions.invoke(
      'livekit-token',
      body: {'room_id': roomId},
    );

    final data = response.data;
    if (data is! Map) throw StateError('Invalid LiveKit token response.');
    if (data['error'] != null) throw StateError(data['error'].toString());

    final tokenResponse =
        LiveKitTokenResponse.fromJson(Map<String, dynamic>.from(data));
    _cache[roomId] = _CachedToken(tokenResponse);
    return tokenResponse;
  }

  /// Remove any cached token for [roomId] (call after explicit disconnect so
  /// the next join always gets a fresh token).
  static void invalidate(String roomId) => _cache.remove(roomId);
}
