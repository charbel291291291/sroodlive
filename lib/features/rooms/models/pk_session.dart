class PkMember {
  const PkMember({
    required this.id,
    required this.pkSessionId,
    required this.userId,
    required this.seatNumber,
    required this.team,
    this.displayName,
    this.avatarUrl,
    required this.pkScore,
  });

  final String id;
  final String pkSessionId;
  final String userId;
  final int seatNumber;
  final String team; // 'a' or 'b'
  final String? displayName;
  final String? avatarUrl;
  final int pkScore;

  factory PkMember.fromJson(Map<String, dynamic> json) => PkMember(
        id: json['id'].toString(),
        pkSessionId: json['pk_session_id'].toString(),
        userId: json['user_id'].toString(),
        seatNumber: (json['seat_index'] as num?)?.toInt() ?? 0,
        team: json['team'].toString(),
        displayName: json['display_name']?.toString(),
        avatarUrl: json['avatar_url']?.toString(),
        pkScore: (json['pk_score'] as num?)?.toInt() ?? 0,
      );

  PkMember copyWith({int? pkScore}) => PkMember(
        id: id,
        pkSessionId: pkSessionId,
        userId: userId,
        seatNumber: seatNumber,
        team: team,
        displayName: displayName,
        avatarUrl: avatarUrl,
        pkScore: pkScore ?? this.pkScore,
      );
}

class PkSession {
  const PkSession({
    required this.id,
    required this.roomId,
    required this.createdBy,
    required this.status,
    required this.durationSeconds,
    required this.startedAt,
    required this.endsAt,
    this.finishedAt,
    required this.teamAScore,
    required this.teamBScore,
    this.winnerTeam,
    required this.updatedAt,
    required this.members,
  });

  final String id;
  final String roomId;
  final String createdBy;
  final String status; // 'active', 'finished', 'cancelled'
  final int durationSeconds;
  final DateTime startedAt;
  final DateTime endsAt;
  final DateTime? finishedAt;
  final int teamAScore;
  final int teamBScore;
  final String? winnerTeam; // 'a', 'b', 'draw'
  final DateTime updatedAt;
  final List<PkMember> members;

  bool get isActive => status == 'active';
  bool get isFinished => status == 'finished';

  int get totalScore => teamAScore + teamBScore;

  // 0.0 = all team A, 1.0 = all team B, 0.5 = tied.
  double get teamAFraction {
    final total = totalScore;
    if (total == 0) return 0.5;
    return teamAScore / total;
  }

  String? get leadingTeam {
    if (teamAScore == teamBScore) return null;
    return teamAScore > teamBScore ? 'a' : 'b';
  }

  factory PkSession.fromJson(
    Map<String, dynamic> sessionJson,
    List<dynamic> membersJson,
  ) =>
      PkSession(
        id: sessionJson['id'].toString(),
        roomId: sessionJson['room_id'].toString(),
        createdBy: sessionJson['created_by'].toString(),
        status: sessionJson['status'].toString(),
        durationSeconds: (sessionJson['duration_seconds'] as num).toInt(),
        startedAt: DateTime.parse(sessionJson['started_at'].toString()),
        endsAt: DateTime.parse(sessionJson['ends_at'].toString()),
        finishedAt: sessionJson['finished_at'] != null
            ? DateTime.parse(sessionJson['finished_at'].toString())
            : null,
        teamAScore: (sessionJson['team_a_score'] as num?)?.toInt() ?? 0,
        teamBScore: (sessionJson['team_b_score'] as num?)?.toInt() ?? 0,
        winnerTeam: sessionJson['winner_team']?.toString(),
        updatedAt: DateTime.parse(sessionJson['updated_at'].toString()),
        members: membersJson
            .map((e) => PkMember.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  PkSession copyWith({
    String? status,
    int? teamAScore,
    int? teamBScore,
    String? winnerTeam,
    DateTime? finishedAt,
    DateTime? updatedAt,
    List<PkMember>? members,
  }) =>
      PkSession(
        id: id,
        roomId: roomId,
        createdBy: createdBy,
        status: status ?? this.status,
        durationSeconds: durationSeconds,
        startedAt: startedAt,
        endsAt: endsAt,
        finishedAt: finishedAt ?? this.finishedAt,
        teamAScore: teamAScore ?? this.teamAScore,
        teamBScore: teamBScore ?? this.teamBScore,
        winnerTeam: winnerTeam ?? this.winnerTeam,
        updatedAt: updatedAt ?? this.updatedAt,
        members: members ?? this.members,
      );
}
