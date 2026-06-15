class CharismaChallenge {
  const CharismaChallenge({
    required this.id,
    required this.title,
    required this.scope,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.rewardCoins,
    required this.createdAt,
    this.titleAr,
    this.agencyId,
    this.rewardFrameId,
    this.winnerUserId,
    this.crownedAt,
    this.createdBy,
  });

  final String id;
  final String title;
  final String? titleAr;
  final String scope;         // 'official' | 'agency'
  final String? agencyId;
  final String status;        // 'scheduled' | 'active' | 'ended' | 'crowned' | 'cancelled'
  final DateTime startsAt;
  final DateTime endsAt;
  final int rewardCoins;
  final String? rewardFrameId;
  final String? winnerUserId;
  final DateTime? crownedAt;
  final DateTime createdAt;
  final String? createdBy;

  bool get isScheduled  => status == 'scheduled';
  bool get isActive     => status == 'active';
  bool get isEnded      => status == 'ended';
  bool get isCrowned    => status == 'crowned';
  bool get isCancelled  => status == 'cancelled';
  bool get isFinished   => isCrowned || isCancelled || isEnded;
  bool get isOfficial   => scope == 'official';

  Duration get timeRemaining => endsAt.toUtc().difference(DateTime.now().toUtc());
  bool get hasTimeLeft => !timeRemaining.isNegative;

  String localizedTitle(bool isArabic) =>
      isArabic ? (titleAr ?? title) : title;

  factory CharismaChallenge.fromJson(Map<String, dynamic> j) => CharismaChallenge(
    id:             j['id']              as String,
    title:          j['title']           as String,
    titleAr:        j['title_ar']        as String?,
    scope:          j['scope']           as String,
    agencyId:       j['agency_id']       as String?,
    status:         j['status']          as String,
    startsAt:       DateTime.parse(j['starts_at'] as String),
    endsAt:         DateTime.parse(j['ends_at']   as String),
    rewardCoins:    (j['reward_coins']   as num?)?.toInt() ?? 100000,
    rewardFrameId:  j['reward_frame_id'] as String?,
    winnerUserId:   j['winner_user_id']  as String?,
    crownedAt:      j['crowned_at'] != null
        ? DateTime.parse(j['crowned_at'] as String)
        : null,
    createdAt:      DateTime.parse(j['created_at'] as String),
    createdBy:      j['created_by']      as String?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class CharismaEntry {
  const CharismaEntry({
    required this.id,
    required this.challengeId,
    required this.userId,
    required this.status,
    required this.voteCount,
    required this.joinedAt,
    this.roomId,
    this.performedAt,
  });

  final String id;
  final String challengeId;
  final String userId;
  final String? roomId;
  final String status;     // 'joined' | 'performed' | 'disqualified' | 'winner'
  final int voteCount;
  final DateTime joinedAt;
  final DateTime? performedAt;

  bool get isWinner    => status == 'winner';
  bool get isPerformed => status == 'performed' || isWinner;

  factory CharismaEntry.fromJson(Map<String, dynamic> j) => CharismaEntry(
    id:           j['id']           as String,
    challengeId:  j['challenge_id'] as String,
    userId:       j['user_id']      as String,
    roomId:       j['room_id']      as String?,
    status:       j['status']       as String,
    voteCount:    (j['vote_count']  as num?)?.toInt() ?? 0,
    joinedAt:     DateTime.parse(j['joined_at'] as String),
    performedAt:  j['performed_at'] != null
        ? DateTime.parse(j['performed_at'] as String)
        : null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class CharismaProfile {
  const CharismaProfile({
    this.displayName,
    this.username,
    this.avatarUrl,
    this.selectedAvatarFrameKey,
    this.publicUserId,
    this.vipLevel,
  });

  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String? selectedAvatarFrameKey;
  final String? publicUserId;
  final int? vipLevel;

  String get effectiveName => displayName ?? username ?? '—';

  factory CharismaProfile.fromJson(Map<String, dynamic> j) => CharismaProfile(
    displayName:             j['display_name']              as String?,
    username:                j['username']                   as String?,
    avatarUrl:               j['avatar_url']                 as String?,
    selectedAvatarFrameKey:  j['selected_avatar_frame_key']  as String?,
    publicUserId:            j['public_user_id']             as String?,
    vipLevel:                (j['vip_level'] as num?)?.toInt(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class CharismaLeaderboardEntry {
  const CharismaLeaderboardEntry({
    required this.rank,
    required this.entryId,
    required this.userId,
    required this.status,
    required this.voteCount,
    required this.hasVoted,
    required this.isMe,
    required this.profile,
    required this.joinedAt,
    this.performedAt,
  });

  final int rank;
  final String entryId;
  final String userId;
  final String status;
  final int voteCount;
  final bool hasVoted;
  final bool isMe;
  final CharismaProfile profile;
  final DateTime joinedAt;
  final DateTime? performedAt;

  bool get isWinner => status == 'winner';

  factory CharismaLeaderboardEntry.fromJson(Map<String, dynamic> j) =>
      CharismaLeaderboardEntry(
        rank:         (j['rank']       as num).toInt(),
        entryId:      j['entry_id']    as String,
        userId:       j['user_id']     as String,
        status:       j['status']      as String,
        voteCount:    (j['vote_count'] as num?)?.toInt() ?? 0,
        hasVoted:     j['has_voted']   as bool? ?? false,
        isMe:         j['is_me']       as bool? ?? false,
        profile:      CharismaProfile.fromJson(
            j['profile'] as Map<String, dynamic>? ?? {}),
        joinedAt:     DateTime.parse(j['joined_at'] as String),
        performedAt:  j['performed_at'] != null
            ? DateTime.parse(j['performed_at'] as String)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class CharismaActiveChallenge {
  const CharismaActiveChallenge({
    required this.challenge,
    required this.participantCount,
    this.myEntry,
  });

  final CharismaChallenge challenge;
  final int participantCount;
  final CharismaEntry? myEntry;

  bool get hasJoined => myEntry != null;

  factory CharismaActiveChallenge.fromJson(Map<String, dynamic> j) =>
      CharismaActiveChallenge(
        challenge: CharismaChallenge.fromJson(
            j['challenge'] as Map<String, dynamic>),
        participantCount:
            (j['participant_count'] as num?)?.toInt() ?? 0,
        myEntry: j['my_entry'] != null
            ? CharismaEntry.fromJson(j['my_entry'] as Map<String, dynamic>)
            : null,
      );

  // Used when admin_charisma_get_challenges returns a flat challenge object
  factory CharismaActiveChallenge.fromFlatJson(Map<String, dynamic> j) =>
      CharismaActiveChallenge(
        challenge:        CharismaChallenge.fromJson(j),
        participantCount: (j['participant_count'] as num?)?.toInt() ?? 0,
        myEntry:          null,
      );
}
