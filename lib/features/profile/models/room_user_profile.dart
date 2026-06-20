import '../../rooms/utils/vip_room_features.dart';

class RoomUserProfile {
  const RoomUserProfile({
    required this.userId,
    required this.nickname,
    required this.publicUserId,
    this.avatarUrl,
    this.selectedAvatarFrame,
    this.bio,
    this.dateOfBirth,
    this.country,
    this.gender,
    this.vipLevel = 0,
    this.vipStartedAt,
    this.vipExpiresAt,
    this.isGoldenId = false,
    this.goldenIdExpiresAt,
    this.goldenIdStyle = 'gold',
    this.goldenIdFrame = 'classic',
    this.followersCount = 0,
    this.followingCount = 0,
    this.friendsCount = 0,
    this.giftReceivedCount = 0,
    this.charmScore = 0,
    this.nobleLevel = 0,
    this.wealthLevel = 1,
    this.wealthTierNumber = 1,
    this.isFollowedByMe = false,
    this.isBlockedByMe = false,
  });

  final String userId;
  final String nickname;
  final String publicUserId;
  final String? avatarUrl;
  final String? selectedAvatarFrame;
  final String? bio;
  final String? dateOfBirth;
  final String? country;
  final String? gender;
  final int vipLevel;
  final DateTime? vipStartedAt;
  final DateTime? vipExpiresAt;
  final bool isGoldenId;
  final DateTime? goldenIdExpiresAt;
  final String goldenIdStyle;
  final String goldenIdFrame;
  final int followersCount;
  final int followingCount;
  final int friendsCount;
  final int giftReceivedCount;
  final int charmScore;
  final int nobleLevel;
  final int wealthLevel;
  final int wealthTierNumber;
  final bool isFollowedByMe;
  final bool isBlockedByMe;

  int get effectiveVipLevel {
    return VipFeatures.effectiveVipLevel(
      vipLevel: vipLevel,
      vipExpiresAt: vipExpiresAt,
    );
  }

  bool get hasActiveVip => effectiveVipLevel > 0;

  int? get age {
    final value = dateOfBirth;
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final birthDate = DateTime.tryParse(value);
    if (birthDate == null) {
      return null;
    }

    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }

    return age < 0 ? null : age;
  }

  RoomUserProfile copyWith({bool? isFollowedByMe, int? followersCount}) {
    return RoomUserProfile(
      userId: userId,
      nickname: nickname,
      publicUserId: publicUserId,
      avatarUrl: avatarUrl,
      selectedAvatarFrame: selectedAvatarFrame,
      bio: bio,
      dateOfBirth: dateOfBirth,
      country: country,
      gender: gender,
      vipLevel: vipLevel,
      vipStartedAt: vipStartedAt,
      vipExpiresAt: vipExpiresAt,
      isGoldenId: isGoldenId,
      goldenIdExpiresAt: goldenIdExpiresAt,
      goldenIdStyle: goldenIdStyle,
      goldenIdFrame: goldenIdFrame,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount,
      friendsCount: friendsCount,
      giftReceivedCount: giftReceivedCount,
      charmScore: charmScore,
      nobleLevel: nobleLevel,
      wealthLevel: wealthLevel,
      wealthTierNumber: wealthTierNumber,
      isFollowedByMe: isFollowedByMe ?? this.isFollowedByMe,
      isBlockedByMe: isBlockedByMe,
    );
  }
}

class GiftWallItem {
  const GiftWallItem({
    required this.giftName,
    required this.giftCode,
    required this.count,
    this.imageUrl,
  });

  final String giftName;
  final String giftCode;
  final int count;
  final String? imageUrl;
}
