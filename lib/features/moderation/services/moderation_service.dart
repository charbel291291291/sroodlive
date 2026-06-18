import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';

// ── Result of a local text check ─────────────────────────────────────────────

class ModerationResult {
  const ModerationResult({
    required this.passed,
    this.severity = 0,
    this.violationType = '',
    this.matchedRule = '',
    this.action = ModerationAction.allow,
  });

  final bool passed;
  final int severity;          // 0=clean 1=warn 2=mute 3=block+review 4=restrict
  final String violationType;
  final String matchedRule;
  final ModerationAction action;

  static const ModerationResult clean =
      ModerationResult(passed: true);
}

enum ModerationAction { allow, warn, blockAndLog, blockAndReview, blockAndRestrict }

// ── Active mute info returned from server ────────────────────────────────────

class ActiveMuteInfo {
  const ActiveMuteInfo({
    required this.type,
    this.expiresAt,
    this.reason,
  });

  final String type;            // 'chat_mute' | 'force_muted' | 'room_ban'
  final DateTime? expiresAt;
  final String? reason;
}

// ── Exception thrown when user is muted ──────────────────────────────────────

class UserMutedException implements Exception {
  const UserMutedException(this.info);
  final ActiveMuteInfo info;

  String get displayMessage {
    if (info.expiresAt != null) {
      final local = info.expiresAt!.toLocal();
      final time =
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      return 'You are muted until $time.';
    }
    return 'You are muted by the room owner.';
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class ModerationService {
  const ModerationService();

  SupabaseClient get _client => SupabaseService.requiredClient;

  // ── Text checking ──────────────────────────────────────────────────────────

  /// Client-side text safety check. Fast, deterministic, no network call.
  ModerationResult checkMessage(String text) {
    final normalized = _normalize(text);

    for (final entry in _rules) {
      final pattern = entry.$1;
      final severity = entry.$2;
      final type = entry.$3;
      if (_matches(normalized, pattern)) {
        final action = switch (severity) {
          1 => ModerationAction.warn,
          2 => ModerationAction.blockAndLog,
          3 => ModerationAction.blockAndReview,
          _ => ModerationAction.blockAndRestrict,
        };
        return ModerationResult(
          passed: false,
          severity: severity,
          violationType: type,
          matchedRule: pattern,
          action: action,
        );
      }
    }
    return ModerationResult.clean;
  }

  /// Log a detected violation to the server (non-blocking).
  Future<void> logEvent({
    required String? roomId,
    required String source,
    required String violationType,
    required int severity,
    required String originalText,
    required String normalizedText,
    required String matchedRule,
    required String actionTaken,
  }) async {
    try {
      await _client.rpc('log_moderation_event', params: {
        'p_room_id':         roomId,
        'p_source':          source,
        'p_violation_type':  violationType,
        'p_severity':        severity,
        'p_original_text':   originalText,
        'p_normalized_text': normalizedText,
        'p_matched_rule':    matchedRule,
        'p_action_taken':    actionTaken,
      });
    } catch (e) {
      debugPrint('[Moderation] logEvent error: $e');
    }
  }

  /// Server-side check for active mute/ban. Called before sending a message.
  Future<ActiveMuteInfo?> checkActiveMute(String? roomId) async {
    try {
      final result = await _client.rpc(
        'check_user_active_mute',
        params: {'p_room_id': roomId},
      ) as Map<String, dynamic>?;

      if (result == null) return null;
      if (result['muted'] != true) return null;

      return ActiveMuteInfo(
        type: result['type'] as String? ?? 'chat_mute',
        expiresAt: result['expires_at'] != null
            ? DateTime.tryParse(result['expires_at'].toString())
            : null,
        reason: result['reason'] as String?,
      );
    } catch (e) {
      debugPrint('[Moderation] checkActiveMute error: $e');
      return null;
    }
  }

  /// Submit a user report. Reuses existing `submit_user_report` RPC.
  Future<void> submitReport({
    required String reportedUserId,
    required String? roomId,
    required String reason,
    String? description,
  }) async {
    final details = [
      if (roomId != null) 'room:$roomId',
      if (description != null && description.isNotEmpty) description,
    ].join(' | ');

    await _client.rpc('submit_user_report', params: {
      'p_target_type': 'user',
      'p_target_id':   reportedUserId,
      'p_reason':      reason,
      'p_details':     details.isEmpty ? null : details,
    });
  }

  // ── Text normalizer ────────────────────────────────────────────────────────

  static String _normalize(String text) {
    var t = text.toLowerCase().trim();

    // Remove Arabic diacritics (tashkeel)
    t = t.replaceAll(RegExp(r'[ً-ٰٟ]'), '');

    // Normalize Arabic letters
    t = t.replaceAll(RegExp(r'[أإآٱ]'), 'ا');
    t = t.replaceAll('ة', 'ه');
    t = t.replaceAll(RegExp(r'[ىئ]'), 'ي');
    t = t.replaceAll('ؤ', 'و');

    // Arabizi digit replacements (common transliterations)
    t = t
        .replaceAll('3', 'ع')
        .replaceAll('7', 'ح')
        .replaceAll('5', 'خ')
        .replaceAll('9', 'ق')
        .replaceAll('6', 'ط')
        .replaceAll('2', 'ء');

    // Leet-speak substitutions
    t = t
        .replaceAll('@', 'a')
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('!', 'i')
        .replaceAll('\$', 's')
        .replaceAll('+', 't');

    // Collapse repeated characters (haaate → hate, يييي → ي)
    t = t.replaceAllMapped(
        RegExp(r'(.)\1{2,}'), (m) => m.group(1)!);

    // Remove punctuation separators between letters (k.l.b → klb)
    t = t.replaceAll(RegExp(r'(?<=[a-zأ-ي])[.\-_*](?=[a-zأ-ي])'), '');

    return t;
  }

  static bool _matches(String normalized, String pattern) {
    // Arabic patterns: no word boundaries needed (Arabic doesn't use spaces same way)
    if (RegExp(r'[؀-ۿ]').hasMatch(pattern)) {
      return normalized.contains(pattern);
    }
    // Latin patterns: word boundary check
    return RegExp('\\b${RegExp.escape(pattern)}\\b').hasMatch(normalized);
  }

  // ── Rules: (pattern, severity, violationType) ─────────────────────────────
  // Severity 1 = warn  |  2 = block+log  |  3 = block+review  |  4 = restrict

  static const List<(String, int, String)> _rules = [
    // ── Arabic insults / harassment ──────────────────────────────────────────
    ('كلب',          2, 'insult'),
    ('حمار',         2, 'insult'),
    ('غبي',          1, 'insult'),
    ('احمق',         1, 'insult'),
    ('تف',           1, 'insult'),
    ('يلعن',         2, 'insult'),
    ('ابن الحرام',   3, 'insult'),
    ('ابن الكلب',    3, 'insult'),
    ('شرموطه',       3, 'hate_speech'),
    ('شرموطة',       3, 'hate_speech'),
    ('عاهره',        3, 'hate_speech'),
    ('عاهرة',        3, 'hate_speech'),
    ('قحبه',         3, 'hate_speech'),
    ('قحبة',         3, 'hate_speech'),
    ('زبالة',        2, 'insult'),
    ('منافق',        1, 'insult'),
    ('خنزير',        2, 'insult'),
    ('روح تنيك',     4, 'sexual_content'),
    ('كس امك',       4, 'hate_speech'),
    ('كس اختك',      4, 'hate_speech'),
    ('نيك',          3, 'sexual_content'),
    ('اللعن ابوك',   3, 'insult'),
    ('اقتلك',        4, 'threat'),
    ('هقتلك',        4, 'threat'),
    ('سوي بيك',      3, 'threat'),
    ('ايدي عليك',    3, 'threat'),

    // ── English profanity & violations ───────────────────────────────────────
    ('fuck',         2, 'insult'),
    ('fucking',      2, 'insult'),
    ('bitch',        2, 'insult'),
    ('asshole',      2, 'insult'),
    ('bastard',      2, 'insult'),
    ('idiot',        1, 'insult'),
    ('stupid',       1, 'insult'),
    ('moron',        1, 'insult'),
    ('loser',        1, 'insult'),
    ('trash',        1, 'insult'),
    ('retard',       3, 'hate_speech'),
    ('nigger',       4, 'hate_speech'),
    ('faggot',       3, 'hate_speech'),
    ('whore',        3, 'sexual_content'),
    ('slut',         3, 'sexual_content'),
    ('kill yourself',4, 'threat'),
    ('i will kill',  4, 'threat'),
    ('ill kill you', 4, 'threat'),
    ('send nudes',   3, 'sexual_content'),
    ('rape',         4, 'sexual_content'),
    ('bomb',         3, 'illegal_content'),
    ('terrorist',    3, 'illegal_content'),
    ('scam',         2, 'scam_fraud'),
    ('give me money',2, 'scam_fraud'),
    ('western union',3, 'scam_fraud'),
    ('click this link',2,'scam_fraud'),

    // ── French profanity ──────────────────────────────────────────────────────
    ('putain',       1, 'insult'),
    ('merde',        1, 'insult'),
    ('connard',      2, 'insult'),
    ('salope',       3, 'hate_speech'),
    ('pute',         3, 'hate_speech'),
    ('va te faire',  2, 'insult'),
    ('je vais te tuer', 4, 'threat'),

    // ── Spam patterns ─────────────────────────────────────────────────────────
    ('whatsapp',     1, 'spam'),
    ('telegram',     1, 'spam'),
    ('instagram',    1, 'spam'),
  ];
}
