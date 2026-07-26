/// Frame Management v2 — artwork picking, validation, and upload.
///
/// The admin never types an asset URL during the normal flow: they press
/// "Upload artwork", the file is validated locally, uploaded to the
/// `avatar-frames` bucket under an immutable versioned path, and the resulting
/// public URL is written into `frame_catalog.asset_url` by the catalog RPC.
///
/// Deliberate choices:
///  * `file_picker` with `withData: true`, not `image_picker` — ImagePicker's
///    `imageQuality` / `maxWidth` re-encode the file, which destroys alpha and
///    animation. Frames need the bytes exactly as the artist exported them.
///  * Format is confirmed from the file's magic bytes, not just its extension,
///    so a renamed `.jpg` cannot slip through as `image/webp`.
///  * Dimensions and animation are read with a small pure-Dart header parser
///    rather than `dart:ui`, so validation is deterministic and testable
///    without a Flutter binding.
///  * All storage I/O goes through injected closures ([FrameStorageWriter],
///    [FrameStorageRemover], [FrameArtworkFilePicker]) following the seam in
///    `features/backpack_v2/repositories/supabase_backpack_v2_repository.dart`.
///    Nothing here holds a privileged key; writes are authorized by the
///    `avatar_frames_insert` storage policy (has_admin_access()).
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/utils/error_utils.dart';
import '../exceptions/frame_admin_exception.dart';

/// Storage bucket created by
/// `supabase/migrations/20261133000000_frame_artwork_storage_and_create_rpc.sql`.
const String kFrameArtworkBucket = 'avatar-frames';

/// Extensions the pipeline accepts. Lottie (`.json`) is intentionally absent:
/// the app has no `lottie`/`rive` package and no vector frame renderer, so a
/// Lottie upload could be stored but never drawn.
const List<String> kFrameArtworkExtensions = ['webp', 'png'];

/// Soft target for static artwork; over this the admin sees a warning but can
/// still save.
const int kFrameArtworkStaticTargetBytes = 400 * 1024;

/// Hard cap for static artwork.
const int kFrameArtworkStaticMaxBytes = 1024 * 1024;

/// Hard cap for animated artwork (also the bucket's `file_size_limit`).
const int kFrameArtworkAnimatedMaxBytes = 2 * 1024 * 1024;

/// Recommended square canvas for new frame artwork.
const int kFrameArtworkRecommendedCanvas = 1024;

/// Below this the frame looks soft at profile size.
const int kFrameArtworkMinCanvas = 256;

/// Above this the file is larger than any render size needs.
const int kFrameArtworkMaxCanvas = 2048;

/// One year, immutable — safe because every upload lands on a fresh
/// `v{timestamp}` path and existing objects are never rewritten in place.
const String kFrameArtworkCacheControl = '31536000';

typedef FrameStorageWriter =
    Future<String> Function({
      required String path,
      required Uint8List bytes,
      required String contentType,
    });

typedef FrameStorageRemover = Future<void> Function(String path);

/// Returns the picked file, or null when the admin cancelled the dialog.
typedef FrameArtworkFilePicker = Future<FrameArtworkFile?> Function();

/// A file handed to the service, decoupled from `file_picker`'s types so the
/// validation path is testable with plain byte lists.
class FrameArtworkFile {
  const FrameArtworkFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// What the header parser could work out about the artwork.
class FrameArtworkMetrics {
  const FrameArtworkMetrics({
    required this.format,
    this.width,
    this.height,
    this.isAnimated = false,
  });

  /// `'webp'`, `'png'`, or null when the magic bytes matched nothing known.
  final String? format;
  final int? width;
  final int? height;
  final bool isAnimated;

  bool get hasDimensions => width != null && height != null;
  bool get isSquare => hasDimensions && width == height;
}

/// Blocking errors and non-blocking warnings for one candidate file.
class FrameArtworkValidation {
  const FrameArtworkValidation({
    this.errors = const [],
    this.warnings = const [],
  });

  final List<String> errors;
  final List<String> warnings;

  bool get isValid => errors.isEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
}

/// A validated (or rejected) candidate, before upload.
class FrameArtworkCandidate {
  const FrameArtworkCandidate({
    required this.file,
    required this.extension,
    required this.contentType,
    required this.metrics,
    required this.validation,
  });

  final FrameArtworkFile file;
  final String extension;
  final String contentType;
  final FrameArtworkMetrics metrics;
  final FrameArtworkValidation validation;

  int get sizeBytes => file.bytes.length;
  bool get isAnimated => metrics.isAnimated;

  /// `"celestial.webp · 312 KB · 1024×1024 · animated"`
  String get summary {
    final parts = <String>[file.name, formatFrameArtworkBytes(sizeBytes)];
    if (metrics.hasDimensions) {
      parts.add('${metrics.width}×${metrics.height}');
    }
    parts.add(isAnimated ? 'animated' : 'static');
    return parts.join(' · ');
  }
}

/// Where an uploaded object landed. [path] is kept so a failed catalog write
/// can delete the orphan.
class FrameArtworkUpload {
  const FrameArtworkUpload({required this.url, required this.path});

  final String url;
  final String path;
}

class FrameArtworkUploadService {
  FrameArtworkUploadService({
    FrameStorageWriter? writer,
    FrameStorageRemover? remover,
    FrameArtworkFilePicker? filePicker,
  }) : _writer = writer ?? _defaultWriter,
       _remover = remover ?? _defaultRemover,
       _filePicker = filePicker ?? _defaultFilePicker;

  final FrameStorageWriter _writer;
  final FrameStorageRemover _remover;
  final FrameArtworkFilePicker _filePicker;

  /// Opens the system file dialog and validates the result.
  /// Returns null when the admin cancelled.
  Future<FrameArtworkCandidate?> pick() async {
    final file = await _filePicker();
    if (file == null) return null;
    return inspect(file);
  }

  /// Pure validation — no I/O. Exposed so the editor can re-validate and tests
  /// can drive the whole matrix from byte lists.
  FrameArtworkCandidate inspect(FrameArtworkFile file) {
    final extension = _extensionOf(file.name);
    final metrics = readFrameArtworkMetrics(file.bytes);
    final contentType =
        _contentTypeFor(extension) ?? 'application/octet-stream';

    final errors = <String>[];
    final warnings = <String>[];

    if (!kFrameArtworkExtensions.contains(extension)) {
      errors.add(
        'Unsupported file type "${extension.isEmpty ? file.name : '.$extension'}". '
        'Frame artwork must be .webp (static or animated) or .png.',
      );
    }

    if (file.bytes.isEmpty) {
      errors.add('That file is empty (0 bytes). Export the artwork again.');
    } else if (metrics.format == null) {
      errors.add(
        'The file contents are not a valid WebP or PNG image, whatever the '
        'file name says.',
      );
    } else if (kFrameArtworkExtensions.contains(extension) &&
        metrics.format != extension) {
      errors.add(
        'The file is named .$extension but its contents are '
        '${metrics.format!.toUpperCase()}. Re-export it in the right format.',
      );
    }

    final maxBytes = metrics.isAnimated
        ? kFrameArtworkAnimatedMaxBytes
        : kFrameArtworkStaticMaxBytes;
    if (file.bytes.length > maxBytes) {
      errors.add(
        '${formatFrameArtworkBytes(file.bytes.length)} is over the '
        '${formatFrameArtworkBytes(maxBytes)} limit for '
        '${metrics.isAnimated ? 'animated' : 'static'} artwork. '
        'Compress it and try again.',
      );
    } else if (!metrics.isAnimated &&
        file.bytes.length > kFrameArtworkStaticTargetBytes) {
      warnings.add(
        'This is ${formatFrameArtworkBytes(file.bytes.length)}. Static frames '
        'should aim for under '
        '${formatFrameArtworkBytes(kFrameArtworkStaticTargetBytes)} so lists '
        'stay fast.',
      );
    }

    if (metrics.hasDimensions) {
      final width = metrics.width!;
      final height = metrics.height!;
      if (width != height) {
        warnings.add(
          'Artwork is $width×$height, not square. Frames render inside a '
          'square box, so it may look off-centre.',
        );
      }
      final longest = width > height ? width : height;
      if (longest < kFrameArtworkMinCanvas) {
        warnings.add(
          'Only $width×$height — this will look soft at profile size. '
          '$kFrameArtworkRecommendedCanvas×$kFrameArtworkRecommendedCanvas '
          'is recommended.',
        );
      } else if (longest > kFrameArtworkMaxCanvas) {
        warnings.add(
          '$width×$height is larger than any render size needs. '
          '$kFrameArtworkRecommendedCanvas×$kFrameArtworkRecommendedCanvas '
          'is recommended.',
        );
      }
    }

    return FrameArtworkCandidate(
      file: file,
      extension: extension,
      contentType: contentType,
      metrics: metrics,
      validation: FrameArtworkValidation(errors: errors, warnings: warnings),
    );
  }

  /// Uploads a validated candidate to
  /// `avatar-frames/{category}/{frame_code}/v{timestamp}.{ext}`.
  ///
  /// Throws a [FrameAdminException] if the candidate is invalid or storage
  /// refuses the write. Never deletes anything.
  Future<FrameArtworkUpload> upload({
    required FrameArtworkCandidate candidate,
    required String category,
    required String frameCode,
    DateTime? now,
  }) async {
    if (!candidate.validation.isValid) {
      throw frameAdminError(
        FrameAdminErrorCategory.unsupportedFormat,
        'artwork_invalid',
        candidate.validation.errors.first,
      );
    }

    final path = buildFrameArtworkPath(
      category: category,
      frameCode: frameCode,
      extension: candidate.extension,
      now: now,
    );

    try {
      final url = await _writer(
        path: path,
        bytes: candidate.file.bytes,
        contentType: candidate.contentType,
      );
      return FrameArtworkUpload(url: url, path: path);
    } catch (error, stack) {
      debugError('FrameArtworkUploadService.upload', error, stack);
      throw mapFrameAdminError(error);
    }
  }

  /// Best-effort orphan cleanup after a failed catalog write. Returns whether
  /// the object was removed; never throws, because the caller is already
  /// reporting the original failure.
  Future<bool> deleteObject(String path) async {
    try {
      await _remover(path);
      return true;
    } catch (error, stack) {
      debugError('FrameArtworkUploadService.deleteObject', error, stack);
      return false;
    }
  }

  // ── Defaults (real Supabase Storage) ──────────────────────────────────────

  static Future<String> _defaultWriter({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final storage = SupabaseService.requiredClient.storage.from(
      kFrameArtworkBucket,
    );
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: contentType,
        cacheControl: kFrameArtworkCacheControl,
        upsert: false,
      ),
    );
    return storage.getPublicUrl(path);
  }

  static Future<void> _defaultRemover(String path) async {
    await SupabaseService.requiredClient.storage
        .from(kFrameArtworkBucket)
        .remove([path]);
  }

  static Future<FrameArtworkFile?> _defaultFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kFrameArtworkExtensions,
      // Required for web, and avoids a second disk read on mobile/desktop.
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null) {
      throw frameAdminError(
        FrameAdminErrorCategory.storageFailure,
        'artwork_bytes_unavailable',
        'Could not read that file from disk. Copy it somewhere local and try '
            'again.',
      );
    }
    return FrameArtworkFile(name: picked.name, bytes: bytes);
  }
}

/// `{category}/{frame_code}/v{timestamp}.{ext}`, with both path segments
/// reduced to the `[a-z0-9_]` alphabet the frame code constraint already uses.
String buildFrameArtworkPath({
  required String category,
  required String frameCode,
  required String extension,
  DateTime? now,
}) {
  final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final safeCategory = _pathSegment(category, fallback: 'custom');
  final safeCode = _pathSegment(frameCode, fallback: 'frame');
  return '$safeCategory/$safeCode/v$stamp.$extension';
}

String _pathSegment(String value, {required String fallback}) {
  final cleaned = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return cleaned.isEmpty ? fallback : cleaned;
}

String _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return '';
  return filename.substring(dot + 1).toLowerCase();
}

String? _contentTypeFor(String extension) => switch (extension) {
  'webp' => 'image/webp',
  'png' => 'image/png',
  _ => null,
};

String formatFrameArtworkBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// ── Header parsing ─────────────────────────────────────────────────────────
// Enough of the PNG and WebP containers to read canvas size and whether the
// file animates. Pure Dart on purpose: validation must not need a Flutter
// binding, and `dart:ui` would decode the whole bitmap just to read a header.

/// Reads format, canvas size, and animation from raw image bytes. Unknown or
/// truncated input yields `format: null` rather than throwing.
FrameArtworkMetrics readFrameArtworkMetrics(Uint8List bytes) {
  if (_isPng(bytes)) return _readPng(bytes);
  if (_isWebp(bytes)) return _readWebp(bytes);
  return const FrameArtworkMetrics(format: null);
}

const List<int> _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

bool _isPng(Uint8List bytes) {
  if (bytes.length < 8) return false;
  for (var i = 0; i < _pngMagic.length; i++) {
    if (bytes[i] != _pngMagic[i]) return false;
  }
  return true;
}

bool _isWebp(Uint8List bytes) =>
    bytes.length >= 16 &&
    _fourCc(bytes, 0) == 'RIFF' &&
    _fourCc(bytes, 8) == 'WEBP';

FrameArtworkMetrics _readPng(Uint8List bytes) {
  // IHDR is always the first chunk: length(4) type(4) width(4) height(4).
  int? width;
  int? height;
  if (bytes.length >= 24 && _fourCc(bytes, 12) == 'IHDR') {
    width = _uint32BE(bytes, 16);
    height = _uint32BE(bytes, 20);
  }
  return FrameArtworkMetrics(
    format: 'png',
    width: width,
    height: height,
    // APNG advertises itself with an acTL chunk ahead of the first IDAT.
    isAnimated: _hasChunkBeforeIdat(bytes, 'acTL'),
  );
}

bool _hasChunkBeforeIdat(Uint8List bytes, String fourCc) {
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final length = _uint32BE(bytes, offset);
    final type = _fourCc(bytes, offset + 4);
    if (type == fourCc) return true;
    if (type == 'IDAT' || type == 'IEND') return false;
    // length + type + data + crc
    final next = offset + 12 + length;
    if (next <= offset) return false; // malformed / overflow guard
    offset = next;
  }
  return false;
}

FrameArtworkMetrics _readWebp(Uint8List bytes) {
  final chunk = _fourCc(bytes, 12);

  if (chunk == 'VP8X' && bytes.length >= 30) {
    // Extended format: flags byte, then 24-bit LE canvas width-1 / height-1.
    final animated = (bytes[20] & 0x02) != 0;
    final width = _uint24LE(bytes, 24) + 1;
    final height = _uint24LE(bytes, 27) + 1;
    return FrameArtworkMetrics(
      format: 'webp',
      width: width,
      height: height,
      isAnimated: animated,
    );
  }

  if (chunk == 'VP8 ' && bytes.length >= 30) {
    // Simple lossy: 3-byte frame tag, 3-byte start code, then 14-bit sizes.
    if (bytes[23] == 0x9D && bytes[24] == 0x01 && bytes[25] == 0x2A) {
      final width = _uint16LE(bytes, 26) & 0x3FFF;
      final height = _uint16LE(bytes, 28) & 0x3FFF;
      return FrameArtworkMetrics(format: 'webp', width: width, height: height);
    }
    return const FrameArtworkMetrics(format: 'webp');
  }

  if (chunk == 'VP8L' && bytes.length >= 25 && bytes[20] == 0x2F) {
    // Lossless: 14 bits width-1 then 14 bits height-1, LSB first.
    final packed =
        bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
    final width = (packed & 0x3FFF) + 1;
    final height = ((packed >> 14) & 0x3FFF) + 1;
    return FrameArtworkMetrics(format: 'webp', width: width, height: height);
  }

  return const FrameArtworkMetrics(format: 'webp');
}

String _fourCc(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length) return '';
  return String.fromCharCodes(bytes.sublist(offset, offset + 4));
}

int _uint32BE(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _uint24LE(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);

int _uint16LE(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
