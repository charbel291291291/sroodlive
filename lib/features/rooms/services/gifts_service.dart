import '../../../core/supabase/supabase_service.dart';
import '../../../shared/services/restrictions_service.dart';
import '../models/room_gift.dart';

class RoomGiftProfile {
  const RoomGiftProfile({
    required this.userId,
    this.displayName,
    this.publicUserId,
    this.avatarUrl,
    this.selectedAvatarFrameKey,
    this.vipLevel = 0,
    this.vipStartedAt,
    this.vipExpiresAt,
  });

  final String userId;
  final String? displayName;
  final String? publicUserId;
  final String? avatarUrl;
  final String? selectedAvatarFrameKey;
  final int vipLevel;
  final DateTime? vipStartedAt;
  final DateTime? vipExpiresAt;

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }

  factory RoomGiftProfile.fromJson(Map<String, dynamic> json) {
    return RoomGiftProfile(
      userId: json['id'].toString(),
      displayName: json['display_name']?.toString(),
      publicUserId: json['public_user_id']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      selectedAvatarFrameKey: json['selected_avatar_frame_key']?.toString(),
      vipLevel: (json['vip_level'] as num?)?.toInt() ?? 0,
      vipStartedAt: _parseDate(json['vip_started_at']),
      vipExpiresAt: _parseDate(json['vip_expires_at']),
    );
  }

  String get displayLabel {
    final name = displayName?.trim();

    if (name != null && name.isNotEmpty) {
      return name;
    }

    final code = publicUserId?.trim();

    if (code != null && code.isNotEmpty) {
      return code;
    }

    final shortId = userId.length >= 8 ? userId.substring(0, 8) : userId;
    return 'ID $shortId';
  }

  int get effectiveVipLevel {
    if (vipLevel <= 0) {
      return 0;
    }

    if (vipExpiresAt != null && !vipExpiresAt!.isAfter(DateTime.now())) {
      return 0;
    }

    return vipLevel.clamp(0, 10).toInt();
  }
}

class RoomGiftTransaction {
  const RoomGiftTransaction({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.receiverId,
    required this.giftCode,
    required this.giftName,
    required this.giftPriceCoins,
    required this.createdAt,
    this.sender,
    this.receiver,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String receiverId;
  final String giftCode;
  final String giftName;
  final int giftPriceCoins;
  final DateTime createdAt;
  final RoomGiftProfile? sender;
  final RoomGiftProfile? receiver;

  factory RoomGiftTransaction.fromJson(
    Map<String, dynamic> json, {
    RoomGiftProfile? sender,
    RoomGiftProfile? receiver,
  }) {
    return RoomGiftTransaction(
      id: json['id'].toString(),
      roomId: json['room_id'].toString(),
      senderId: json['sender_id'].toString(),
      receiverId: json['receiver_id'].toString(),
      giftCode: json['gift_code']?.toString() ?? '',
      giftName: json['gift_name']?.toString() ?? 'Gift',
      giftPriceCoins: (json['gift_price_coins'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'].toString()),
      sender: sender,
      receiver: receiver,
    );
  }

  String get senderLabel =>
      sender?.displayLabel ?? _fallbackUserLabel(senderId);

  String get receiverLabel =>
      receiver?.displayLabel ?? _fallbackUserLabel(receiverId);

  RoomGift get giftPreview {
    return RoomGift(
      id: 'transaction-$giftCode',
      code: giftCode,
      name: giftName,
      arabicName: giftName,
      priceCoins: giftPriceCoins,
      icon: '',
      sortOrder: 0,
    );
  }

  static String _fallbackUserLabel(String userId) {
    final shortId = userId.length >= 8 ? userId.substring(0, 8) : userId;
    return 'ID $shortId';
  }
}

class GiftsService {
  const GiftsService();

  static const RestrictionsService _restrictions = RestrictionsService();

  Future<List<RoomGift>> fetchActiveGifts() async {
    final data = await SupabaseService.requiredClient
        .from('gifts')
        .select('id, code, name, arabic_name, price_coins, icon, sort_order')
        .eq('is_active', true)
        .order('sort_order', ascending: true);

    return (data as List<dynamic>)
        .map((item) => RoomGift.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> sendGift({
    required String roomId,
    required String receiverId,
    required RoomGift gift,
  }) async {
    final client = SupabaseService.requiredClient;

    if (client.auth.currentUser == null) {
      throw StateError('No logged-in user found.');
    }

    await _restrictions.throwIfRestricted('account_ban');
    await _restrictions.throwIfRestricted('gift_block');

    if (!_looksLikeUuid(gift.id)) {
      throw StateError('gift_not_found');
    }

    await client.rpc(
      'send_gift_with_wallet',
      params: {
        'p_room_id': roomId,
        'p_receiver_id': receiverId,
        'p_gift_id': gift.id,
        'p_quantity': 1,
      },
    );
  }

  Future<List<RoomGiftTransaction>> getRoomGiftTransactions(
    String roomId,
  ) async {
    final client = SupabaseService.requiredClient;
    final data = await client
        .from('gift_transactions')
        .select(
          'id, room_id, sender_id, receiver_id, gift_code, gift_name, gift_price_coins, created_at',
        )
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(10);

    final rows = (data as List<dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .toList();
    final userIds = <String>{
      for (final row in rows) row['sender_id'].toString(),
      for (final row in rows) row['receiver_id'].toString(),
    }.toList();
    final profiles = <String, RoomGiftProfile>{};

    if (userIds.isNotEmpty) {
      final profileData = await client
          .from('profiles')
          .select(
            'id, display_name, public_user_id, avatar_url, selected_avatar_frame_key, vip_level, vip_started_at, vip_expires_at',
          )
          .inFilter('id', userIds);

      for (final item in profileData as List<dynamic>) {
        final profile = RoomGiftProfile.fromJson(item as Map<String, dynamic>);
        profiles[profile.userId] = profile;
      }
    }

    return rows
        .map(
          (row) => RoomGiftTransaction.fromJson(
            row,
            sender: profiles[row['sender_id'].toString()],
            receiver: profiles[row['receiver_id'].toString()],
          ),
        )
        .toList();
  }

  bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }
}
