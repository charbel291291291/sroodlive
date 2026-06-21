import '../../../core/supabase/supabase_service.dart';

/// Authenticated user's charm progress, sourced from the official
/// `get_my_charm_level` RPC (charm XP accrues from gifts RECEIVED). Separate
/// from VIP, Wealth, and the activity user-level systems.
class UserCharm {
  const UserCharm({
    required this.charmLevel,
    required this.charmXp,
    required this.tierNumber,
    required this.tierName,
    required this.colorHex,
    this.nextLevel,
    this.xpToNextLevel,
    this.levelProgress,
  });

  final int charmLevel;
  final int charmXp;
  final int tierNumber;
  final String tierName;
  final String colorHex;
  final int? nextLevel;
  final int? xpToNextLevel;
  final double? levelProgress;

  bool get isMaxLevel => nextLevel == null;

  factory UserCharm.fromJson(Map<String, dynamic> json) => UserCharm(
    charmLevel: _int(json['charm_level'], 1),
    charmXp: _int(json['charm_xp']),
    tierNumber: _int(json['tier_number'], 1),
    tierName: json['tier_name']?.toString() ?? 'Bronze',
    colorHex: json['color_hex']?.toString() ?? '#8B5E3C',
    nextLevel: _nullInt(json['next_level']),
    xpToNextLevel: _nullInt(json['xp_to_next_level']),
    levelProgress: _nullDouble(json['level_progress']),
  );
}

class CharmService {
  const CharmService();

  Future<UserCharm> getMyCharm() async {
    final data =
        await SupabaseService.requiredClient.rpc('get_my_charm_level');
    return UserCharm.fromJson(data as Map<String, dynamic>);
  }
}

int _int(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? _nullInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _nullDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
