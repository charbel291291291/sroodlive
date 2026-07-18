/// Whether an owned or equipped item currently counts as usable.
enum BackpackV2ExpirationState {
  /// `expires_at` is null — never expires.
  permanent,

  /// `expires_at` is set and still in the future.
  active,

  /// `expires_at` has passed (or the server already flagged it as expired).
  expired,
}

/// Resolves [BackpackV2ExpirationState] from an ownership row's `expires_at`
/// and, where available, the server-computed `is_expired` flag.
///
/// `get_my_backpack_v2` computes `is_expired` server-side against `now()` at
/// query time, so it is authoritative and preferred over a client-side
/// `DateTime.now()` comparison (avoids device-clock skew). Callers that don't
/// have a server flag (e.g. equipped-item rows, which are already filtered to
/// non-expired by the RPC's own WHERE clause) pass `isExpiredFlag: false` and
/// rely on the `expiresAt` comparison purely as a defensive fallback.
BackpackV2ExpirationState resolveExpirationState({
  required DateTime? expiresAt,
  required bool isExpiredFlag,
  DateTime? now,
}) {
  if (expiresAt == null) return BackpackV2ExpirationState.permanent;
  if (isExpiredFlag) return BackpackV2ExpirationState.expired;
  final effectiveNow = now ?? DateTime.now().toUtc();
  if (!expiresAt.isAfter(effectiveNow)) {
    return BackpackV2ExpirationState.expired;
  }
  return BackpackV2ExpirationState.active;
}
