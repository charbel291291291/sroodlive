/// Error sanitisation utilities for Srood Live.
///
/// Never expose raw exceptions (SocketException, PostgrestException, etc.)
/// to the user. Run every caught error through [friendlyMessage] first.
library;

import 'package:flutter/foundation.dart';

/// Converts a raw exception into a user-friendly English/Arabic string pair.
///
/// Usage:
/// ```dart
/// } catch (e, st) {
///   debugError('myMethod', e, st);
///   _showSnack(friendlyMessage(e, isArabic: _isArabic));
/// }
/// ```
String friendlyMessage(
  Object error, {
  bool isArabic = false,
  String? fallback,
}) {
  final msg = error.toString().toLowerCase();

  // Network / connectivity
  if (_contains(msg, ['socketexception', 'network', 'connection', 'unreachable', 'timeout', 'timedout', 'handshake'])) {
    return isArabic ? 'خطأ في الاتصال بالإنترنت' : 'Connection error — check your internet';
  }

  // Auth / permission
  if (_contains(msg, ['not_authorized', 'unauthorized', 'forbidden', '401', '403', 'jwt', 'token', 'not authenticated'])) {
    return isArabic ? 'غير مصرح لك بهذا الإجراء' : 'Not authorized';
  }

  // Not found
  if (_contains(msg, ['not_found', '404', 'no rows', 'does not exist'])) {
    return isArabic ? 'البيانات غير موجودة' : 'Item not found';
  }

  // Unique constraint / duplicate
  if (_contains(msg, ['unique', 'duplicate', 'already exists', 'conflict', '409', 'taken'])) {
    return isArabic ? 'هذه القيمة مستخدمة مسبقاً' : 'Already in use — try a different value';
  }

  // Supabase / Postgres
  if (_contains(msg, ['postgrestexception', 'pgrst', 'supabase', '42', 'pg_'])) {
    return isArabic ? 'خطأ في الخادم' : 'Server error — please try again';
  }

  // Firebase
  if (_contains(msg, ['firebaseexception', 'firebase'])) {
    return isArabic ? 'خطأ في Firebase' : 'Service error — please try again';
  }

  // Platform
  if (_contains(msg, ['platformexception', 'platform'])) {
    return isArabic ? 'خطأ في الجهاز' : 'Device error — please try again';
  }

  // Rate limit
  if (_contains(msg, ['ratelimit', 'rate_limit', 'too many', '429'])) {
    return isArabic ? 'الطلبات كثيرة جداً، انتظر قليلاً' : 'Too many requests — please wait';
  }

  // Offline / no data
  if (_contains(msg, ['offline', 'no internet', 'no data'])) {
    return isArabic ? 'لا يوجد اتصال بالإنترنت' : 'You appear to be offline';
  }

  return fallback ?? (isArabic ? 'حدث خطأ، حاول مجدداً' : 'Something went wrong — please try again');
}

bool _contains(String msg, List<String> keywords) =>
    keywords.any(msg.contains);

/// Logs an error in debug mode — no-op in release.
void debugError(String context, Object error, [StackTrace? st]) {
  if (kDebugMode) {
    debugPrint('[$context] ERROR: $error');
    if (st != null) debugPrintStack(stackTrace: st, label: context);
  }
}
