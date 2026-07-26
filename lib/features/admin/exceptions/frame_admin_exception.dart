/// Frame Management v2 — typed admin errors.
///
/// The frame admin surface previously interpolated raw `'$e'` into toasts, so
/// an admin saw `PostgrestException(message: ..., code: 23505)` instead of
/// "that frame code is already taken". Everything caught in the frame admin
/// layer goes through [mapFrameAdminError] first; the raw error stays in
/// `debugError` (debug builds only).
///
/// Mirrors the structure of `features/backpack_v2/exceptions/
/// backpack_v2_exception.dart`, and adds the `StorageException` handling that
/// exists nowhere else in the app.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/utils/error_utils.dart';

enum FrameAdminErrorCategory {
  /// The frame `code` is already used by another catalog row.
  duplicateCode,

  /// Authenticated but lacking `has_admin_access()` (app role admin /
  /// super_admin), or a storage policy refused the write.
  notAuthorized,

  /// No auth session, or the JWT expired mid-session.
  sessionExpired,

  /// A VIP tier / required-VIP-level / unlock-type combination the server
  /// refuses (`invalid_vip_config`) or the DB check constraint rejects.
  invalidVipConfig,

  /// `unlock_type = 'role'` with no role selected (`invalid_role_config`).
  invalidRoleConfig,

  /// Artwork extension or MIME type outside the allowlist.
  unsupportedFormat,

  /// Artwork exceeds the per-format byte cap, client-side or storage-side.
  fileTooLarge,

  /// Storage rejected the operation for a reason other than authorization —
  /// missing bucket, object already exists, etc.
  storageFailure,

  /// Socket/timeout/connectivity failure before a response arrived.
  network,

  /// A Postgres constraint (unique/FK/check/not-null) not covered above.
  constraintViolation,

  /// Anything unrecognised.
  unknown,
}

/// Typed frame-admin failure. [message] is safe to show an admin verbatim;
/// [code] is the short machine string for logs.
class FrameAdminException implements Exception {
  const FrameAdminException(
    this.category,
    this.code, {
    required this.message,
    this.cause,
  });

  final FrameAdminErrorCategory category;

  /// Short machine-readable code (e.g. `frame_code_exists`, `23514`).
  final String code;

  /// Admin-facing English sentence. Admin screens in this app are English-only.
  final String message;

  final Object? cause;

  @override
  String toString() => 'FrameAdminException($category, $code)';
}

/// Convenience constructor for failures the client detects itself (upload
/// validation, duplicate-code pre-check) so they flow through the same type.
FrameAdminException frameAdminError(
  FrameAdminErrorCategory category,
  String code,
  String message, {
  Object? cause,
}) => FrameAdminException(category, code, message: message, cause: cause);

/// Maps any caught error into a [FrameAdminException] with a readable message.
FrameAdminException mapFrameAdminError(Object error) {
  if (error is FrameAdminException) return error;

  if (error is AuthException) {
    return FrameAdminException(
      FrameAdminErrorCategory.sessionExpired,
      'auth_exception',
      message:
          'Your admin session expired. Sign in again and retry the change.',
      cause: error,
    );
  }

  if (error is StorageException) return _mapStorageError(error);

  if (error is PostgrestException) return _mapPostgresError(error);

  final raw = error.toString().toLowerCase();
  if (raw.contains('socketexception') ||
      raw.contains('timeout') ||
      raw.contains('timedout') ||
      raw.contains('clientexception') ||
      raw.contains('connection') ||
      raw.contains('handshake') ||
      raw.contains('unreachable')) {
    return FrameAdminException(
      FrameAdminErrorCategory.network,
      'network',
      message:
          'Could not reach the server. Check the connection and try again — '
          'nothing was saved.',
      cause: error,
    );
  }

  return FrameAdminException(
    FrameAdminErrorCategory.unknown,
    'unknown',
    // friendlyMessage() keeps the app's existing tone for the residual cases.
    message: friendlyMessage(error, fallback: 'Something went wrong.'),
    cause: error,
  );
}

FrameAdminException _mapStorageError(StorageException error) {
  final status = error.statusCode;
  final lower = '${error.message} ${error.error ?? ''}'.toLowerCase();

  if (status == '413' || lower.contains('payload too large')) {
    return FrameAdminException(
      FrameAdminErrorCategory.fileTooLarge,
      'storage_payload_too_large',
      message:
          'The storage bucket rejected the file for being too large. Export '
          'the artwork smaller (1 MB static, 2 MB animated) and retry.',
      cause: error,
    );
  }
  if (status == '403' ||
      status == '401' ||
      lower.contains('row-level security') ||
      lower.contains('unauthorized')) {
    return FrameAdminException(
      FrameAdminErrorCategory.notAuthorized,
      'storage_not_authorized',
      message:
          'Storage refused the upload. Your account needs the admin or '
          'super_admin app role to write frame artwork.',
      cause: error,
    );
  }
  if (status == '404' || lower.contains('not found')) {
    return FrameAdminException(
      FrameAdminErrorCategory.storageFailure,
      'storage_bucket_missing',
      message:
          'The avatar-frames storage bucket is missing. Apply the frame '
          'artwork storage migration to this project, then retry.',
      cause: error,
    );
  }
  if (status == '409' || lower.contains('already exists')) {
    return FrameAdminException(
      FrameAdminErrorCategory.storageFailure,
      'storage_object_exists',
      message:
          'An artwork file already exists at that path. Retry to upload '
          'under a fresh version path.',
      cause: error,
    );
  }
  if (lower.contains('mime') || lower.contains('content type')) {
    return FrameAdminException(
      FrameAdminErrorCategory.unsupportedFormat,
      'storage_mime_rejected',
      message:
          'Storage rejected the file type. Frame artwork must be WebP or PNG.',
      cause: error,
    );
  }
  return FrameAdminException(
    FrameAdminErrorCategory.storageFailure,
    'storage_error',
    message: 'The artwork upload failed. Nothing was saved — retry the upload.',
    cause: error,
  );
}

FrameAdminException _mapPostgresError(PostgrestException error) {
  // SECURITY DEFINER RPCs raise bare strings, which arrive as the message on a
  // P0001 (raise_exception). Match those before the SQLSTATE table.
  switch (error.message) {
    case 'frame_code_exists':
      return FrameAdminException(
        FrameAdminErrorCategory.duplicateCode,
        'frame_code_exists',
        message:
            'That frame code is already used by another frame. Open Advanced '
            'and choose a different code.',
        cause: error,
      );
    case 'not_authorized':
      return FrameAdminException(
        FrameAdminErrorCategory.notAuthorized,
        'not_authorized',
        message:
            'You are not authorized to change the frame catalog. This needs '
            'the admin or super_admin app role.',
        cause: error,
      );
    case 'invalid_vip_config':
      return FrameAdminException(
        FrameAdminErrorCategory.invalidVipConfig,
        'invalid_vip_config',
        message:
            'The VIP configuration is contradictory. A VIP-unlocked frame '
            'needs one VIP level, and the tier and required level must match.',
        cause: error,
      );
    case 'invalid_role_config':
      return FrameAdminException(
        FrameAdminErrorCategory.invalidRoleConfig,
        'invalid_role_config',
        message: 'A role-unlocked frame needs a required role selected.',
        cause: error,
      );
    case 'frame_not_found':
      return FrameAdminException(
        FrameAdminErrorCategory.constraintViolation,
        'frame_not_found',
        message: 'That frame no longer exists. Reload the list and retry.',
        cause: error,
      );
  }

  switch (error.code) {
    case '23505':
      return FrameAdminException(
        FrameAdminErrorCategory.duplicateCode,
        '23505',
        message:
            'That frame code is already taken. Open Advanced and choose a '
            'different code.',
        cause: error,
      );
    case '23514':
      return FrameAdminException(
        FrameAdminErrorCategory.invalidVipConfig,
        '23514',
        message:
            'The database rejected one of the values. Check the category, '
            'rarity, asset type, unlock type, and that VIP level is 1–9.',
        cause: error,
      );
    case '23502':
    case '23503':
      return FrameAdminException(
        FrameAdminErrorCategory.constraintViolation,
        error.code ?? 'constraint',
        message:
            'The database rejected the change because a required related '
            'record is missing. Nothing was saved.',
        cause: error,
      );
    case '28000':
      return FrameAdminException(
        FrameAdminErrorCategory.sessionExpired,
        '28000',
        message: 'Your admin session expired. Sign in again and retry.',
        cause: error,
      );
    case '42501':
      return FrameAdminException(
        FrameAdminErrorCategory.notAuthorized,
        '42501',
        message:
            'Permission denied by row-level security. This needs the admin or '
            'super_admin app role.',
        cause: error,
      );
    case 'PGRST202':
      return FrameAdminException(
        FrameAdminErrorCategory.constraintViolation,
        'PGRST202',
        message:
            'A required database function is missing from this project. Apply '
            'the frames v2 migrations, then retry.',
        cause: error,
      );
  }

  return FrameAdminException(
    FrameAdminErrorCategory.unknown,
    error.code ?? 'postgrest',
    message: friendlyMessage(
      error,
      fallback: 'The database rejected the change. Nothing was saved.',
    ),
    cause: error,
  );
}
