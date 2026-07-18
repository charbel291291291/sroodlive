import 'package:supabase_flutter/supabase_flutter.dart';

/// Failure categories the Backpack V2 repository/controller must
/// differentiate (per the M4 spec's "Differentiate" checklist).
enum BackpackV2ErrorCategory {
  /// No authenticated user (`auth.uid()` was null server-side, or the local
  /// Supabase auth session is missing/expired).
  authentication,

  /// Caller authenticated but not authorized (e.g. admin-only RPC).
  permission,

  /// Socket/timeout/connectivity failure before a response was received.
  network,

  /// The RPC returned a 2xx response whose shape could not be parsed
  /// (wrong type, missing required field) — not a Postgres error at all.
  invalidResponse,

  /// A Postgres constraint violation (unique/FK/check) not covered by a more
  /// specific category below.
  databaseConstraint,

  /// Item exists and is owned, but fails an equip business rule that isn't
  /// expiry or missing-ownership (`item_not_active`, `item_not_equippable`,
  /// `item_equip_disabled`, `vip_level_required`, `item_not_consumable`).
  equipEligibility,

  /// The ownership row's `expires_at` has passed.
  expiredOwnership,

  /// No matching ownership row for the caller (`backpack_item_not_found` —
  /// covers both "doesn't exist" and "belongs to another user" by design,
  /// see equip_backpack_item_v2) or the row is revoked (`item_revoked`,
  /// which is functionally "no longer owned").
  missingOwnership,

  /// A slot/item type value outside the known enum was sent to an RPC that
  /// validates it server-side (`invalid_slot_type`).
  unsupportedItemType,

  /// Anything that doesn't match a known Postgres error code or keyword.
  unknown,
}

/// Typed failure raised by the Backpack V2 repository. Always carries a
/// [category] for control flow and a machine-readable [code] (mirrors this
/// repo's existing `StateError('short_code')` convention, e.g.
/// FollowService's `'follow_blocked_by_vip'`) for logging/debugging.
class BackpackV2Exception implements Exception {
  const BackpackV2Exception(this.category, this.code, {this.cause});

  final BackpackV2ErrorCategory category;
  final String code;
  final Object? cause;

  @override
  String toString() => 'BackpackV2Exception($category, $code)';
}

/// Maps a raw caught error (PostgrestException, AuthException, network
/// error, malformed-response FormatException, or anything else) to a typed
/// [BackpackV2Exception]. Never logs or includes tokens/emails — only the
/// short machine code the server/client already produced.
BackpackV2Exception mapBackpackV2Error(Object error) {
  if (error is BackpackV2Exception) return error;

  if (error is FormatException) {
    return BackpackV2Exception(
      BackpackV2ErrorCategory.invalidResponse,
      error.message,
      cause: error,
    );
  }

  if (error is AuthException) {
    return BackpackV2Exception(
      BackpackV2ErrorCategory.authentication,
      'auth_exception',
      cause: error,
    );
  }

  if (error is PostgrestException) {
    switch (error.code) {
      case '28000':
        return BackpackV2Exception(
          BackpackV2ErrorCategory.authentication,
          error.message,
          cause: error,
        );
      case '42501':
        return BackpackV2Exception(
          BackpackV2ErrorCategory.permission,
          error.message,
          cause: error,
        );
      case 'P0002':
        return BackpackV2Exception(
          BackpackV2ErrorCategory.missingOwnership,
          error.message,
          cause: error,
        );
      case '22023':
        return _classifyBusinessRuleViolation(error);
      case '23505':
      case '23503':
      case '23514':
      case '23502':
        return BackpackV2Exception(
          BackpackV2ErrorCategory.databaseConstraint,
          error.message,
          cause: error,
        );
      default:
        return BackpackV2Exception(
          BackpackV2ErrorCategory.invalidResponse,
          error.message,
          cause: error,
        );
    }
  }

  final msg = error.toString().toLowerCase();
  if (msg.contains('socketexception') ||
      msg.contains('timeout') ||
      msg.contains('timedout') ||
      msg.contains('network') ||
      msg.contains('connection') ||
      msg.contains('handshake') ||
      msg.contains('unreachable')) {
    return BackpackV2Exception(
      BackpackV2ErrorCategory.network,
      error.toString(),
      cause: error,
    );
  }

  return BackpackV2Exception(
    BackpackV2ErrorCategory.unknown,
    error.toString(),
    cause: error,
  );
}

/// 22023 is raised by `equip_backpack_item_v2` / `unequip_backpack_slot_v2`
/// for several distinct business rules; the exception `message` (the literal
/// string passed to `raise exception`) is the only way to tell them apart.
BackpackV2Exception _classifyBusinessRuleViolation(PostgrestException error) {
  switch (error.message) {
    case 'item_expired':
      return BackpackV2Exception(
        BackpackV2ErrorCategory.expiredOwnership,
        error.message,
        cause: error,
      );
    case 'item_revoked':
      return BackpackV2Exception(
        BackpackV2ErrorCategory.missingOwnership,
        error.message,
        cause: error,
      );
    case 'item_not_active':
    case 'item_not_equippable':
    case 'item_equip_disabled':
    case 'vip_level_required':
    case 'item_not_consumable':
      return BackpackV2Exception(
        BackpackV2ErrorCategory.equipEligibility,
        error.message,
        cause: error,
      );
    case 'invalid_slot_type':
      return BackpackV2Exception(
        BackpackV2ErrorCategory.unsupportedItemType,
        error.message,
        cause: error,
      );
    default:
      return BackpackV2Exception(
        BackpackV2ErrorCategory.databaseConstraint,
        error.message,
        cause: error,
      );
  }
}
