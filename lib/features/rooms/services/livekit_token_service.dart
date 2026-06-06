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

class LiveKitTokenService {
  const LiveKitTokenService();

  Future<LiveKitTokenResponse> getToken({required String roomId}) async {
    final client = SupabaseService.requiredClient;

    final response = await client.functions.invoke(
      'livekit-token',
      body: {'room_id': roomId},
    );

    final data = response.data;

    if (data is! Map) {
      throw StateError('Invalid LiveKit token response.');
    }

    if (data['error'] != null) {
      throw StateError(data['error'].toString());
    }

    return LiveKitTokenResponse.fromJson(Map<String, dynamic>.from(data));
  }
}
