/// Frame Management v2 — artwork validation and upload.
///
/// Validation is pure and driven here from synthesised PNG/WebP headers, so the
/// whole accept/warn/reject matrix is covered without a file picker, a Flutter
/// binding, or a network. Upload/delete go through the injected storage
/// closures, which also proves the ordering guarantee in requirement 9: upload
/// never removes anything.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/admin/exceptions/frame_admin_exception.dart';
import 'package:srood_live/features/admin/services/frame_artwork_upload_service.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────
// Real container headers, because the service confirms the format from magic
// bytes rather than trusting the file name.

void _uint32BE(BytesBuilder out, int value) => out.add([
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
]);

void _pngChunk(BytesBuilder out, String type, List<int> data) {
  _uint32BE(out, data.length);
  out.add(type.codeUnits);
  out.add(data);
  out.add(const [0, 0, 0, 0]); // CRC — never read by the header parser.
}

/// A PNG (or APNG when [animated]) with a real IHDR, padded to [sizeBytes].
Uint8List pngBytes({
  int width = 1024,
  int height = 1024,
  bool animated = false,
  int sizeBytes = 0,
}) {
  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final ihdr = BytesBuilder();
  _uint32BE(ihdr, width);
  _uint32BE(ihdr, height);
  ihdr.add(const [8, 6, 0, 0, 0]); // bit depth, colour type, …
  _pngChunk(out, 'IHDR', ihdr.takeBytes());

  // APNG advertises itself with acTL ahead of the first IDAT.
  if (animated) _pngChunk(out, 'acTL', const [0, 0, 0, 2, 0, 0, 0, 0]);

  _pngChunk(out, 'IDAT', const [0x78, 0x9C, 0x00]);
  _pngChunk(out, 'IEND', const []);

  return _pad(out.takeBytes(), sizeBytes);
}

/// An extended-format (VP8X) WebP, padded to [sizeBytes].
Uint8List webpBytes({
  int width = 1024,
  int height = 1024,
  bool animated = false,
  int sizeBytes = 0,
}) {
  final out = BytesBuilder();
  out.add('RIFF'.codeUnits);
  out.add(const [0, 0, 0, 0]); // RIFF size — not read.
  out.add('WEBP'.codeUnits);
  out.add('VP8X'.codeUnits);
  out.add(const [10, 0, 0, 0]); // VP8X payload length, LE.
  out.add([animated ? 0x02 : 0x00, 0, 0, 0]); // flags + reserved
  final w = width - 1;
  final h = height - 1;
  out.add([w & 0xFF, (w >> 8) & 0xFF, (w >> 16) & 0xFF]);
  out.add([h & 0xFF, (h >> 8) & 0xFF, (h >> 16) & 0xFF]);

  return _pad(out.takeBytes(), sizeBytes);
}

Uint8List _pad(Uint8List bytes, int sizeBytes) {
  if (sizeBytes <= bytes.length) return bytes;
  final padded = Uint8List(sizeBytes);
  padded.setRange(0, bytes.length, bytes);
  return padded;
}

FrameArtworkFile file(String name, Uint8List bytes) =>
    FrameArtworkFile(name: name, bytes: bytes);

void main() {
  final service = FrameArtworkUploadService(
    writer: ({required path, required bytes, required contentType}) async =>
        'https://example.test/$path',
    remover: (path) async {},
  );

  group('header parsing', () {
    test('reads PNG dimensions and staticness', () {
      final metrics = readFrameArtworkMetrics(
        pngBytes(width: 512, height: 512),
      );
      expect(metrics.format, 'png');
      expect(metrics.width, 512);
      expect(metrics.height, 512);
      expect(metrics.isAnimated, isFalse);
      expect(metrics.isSquare, isTrue);
    });

    test('detects APNG through the acTL chunk', () {
      final metrics = readFrameArtworkMetrics(pngBytes(animated: true));
      expect(metrics.format, 'png');
      expect(metrics.isAnimated, isTrue);
    });

    test('reads WebP canvas size and the animation flag', () {
      final still = readFrameArtworkMetrics(webpBytes(width: 800, height: 600));
      expect(still.format, 'webp');
      expect(still.width, 800);
      expect(still.height, 600);
      expect(still.isAnimated, isFalse);
      expect(still.isSquare, isFalse);

      final moving = readFrameArtworkMetrics(webpBytes(animated: true));
      expect(moving.format, 'webp');
      expect(moving.isAnimated, isTrue);
    });

    test('unknown bytes yield a null format rather than throwing', () {
      final metrics = readFrameArtworkMetrics(
        Uint8List.fromList(List<int>.filled(64, 0x41)),
      );
      expect(metrics.format, isNull);
      expect(metrics.hasDimensions, isFalse);
    });
  });

  group('inspect() rejects', () {
    test('an extension outside the allowlist', () {
      final result = service.inspect(file('art.jpg', pngBytes()));
      expect(result.validation.isValid, isFalse);
      expect(
        result.validation.errors.first,
        contains('Unsupported file type ".jpg"'),
      );
      expect(kFrameArtworkExtensions, const ['webp', 'png']);
    });

    test('a Lottie file, which has no renderer in this app', () {
      final result = service.inspect(
        file('crown.json', Uint8List.fromList('{"v":"5"}'.codeUnits)),
      );
      expect(result.validation.isValid, isFalse);
      expect(result.validation.errors.first, contains('.webp'));
    });

    test('a file with no extension at all', () {
      final result = service.inspect(file('artwork', pngBytes()));
      expect(result.validation.isValid, isFalse);
      expect(result.validation.errors.first, contains('artwork'));
    });

    test('an empty file', () {
      final result = service.inspect(file('art.webp', Uint8List(0)));
      expect(result.validation.isValid, isFalse);
      expect(
        result.validation.errors,
        contains('That file is empty (0 bytes). Export the artwork again.'),
      );
    });

    test('contents that are not an image at all', () {
      final result = service.inspect(
        file('art.webp', Uint8List.fromList('not an image'.codeUnits)),
      );
      expect(result.validation.isValid, isFalse);
      expect(
        result.validation.errors.first,
        contains('not a valid WebP or PNG image'),
      );
    });

    test('a WebP renamed to .png (extension/content mismatch)', () {
      final result = service.inspect(file('art.png', webpBytes()));
      expect(result.validation.isValid, isFalse);
      expect(
        result.validation.errors.first,
        'The file is named .png but its contents are WEBP. '
        'Re-export it in the right format.',
      );
    });

    test('a PNG renamed to .webp', () {
      final result = service.inspect(file('art.webp', pngBytes()));
      expect(result.validation.isValid, isFalse);
      expect(result.validation.errors.first, contains('contents are PNG'));
    });

    test('static artwork over the 1 MB hard cap', () {
      final result = service.inspect(
        file('art.png', pngBytes(sizeBytes: 1200 * 1024)),
      );
      expect(result.validation.isValid, isFalse);
      expect(result.validation.errors.first, contains('over the 1.0 MB limit'));
      expect(result.validation.errors.first, contains('static'));
      expect(kFrameArtworkStaticMaxBytes, 1024 * 1024);
    });

    test('animated artwork over the 2 MB hard cap', () {
      final bytes = webpBytes(
        animated: true,
        sizeBytes: (2.5 * 1024 * 1024).round(),
      );
      final result = service.inspect(file('art.webp', bytes));
      expect(result.validation.isValid, isFalse);
      expect(result.validation.errors.first, contains('over the 2.0 MB limit'));
      expect(result.validation.errors.first, contains('animated'));
      expect(kFrameArtworkAnimatedMaxBytes, 2 * 1024 * 1024);
    });
  });

  group('inspect() accepts', () {
    test('a 1024×1024 static WebP with no warnings', () {
      final result = service.inspect(
        file('celestial.webp', webpBytes(sizeBytes: 120 * 1024)),
      );
      expect(result.validation.isValid, isTrue);
      expect(result.validation.warnings, isEmpty);
      expect(result.contentType, 'image/webp');
      expect(result.extension, 'webp');
      expect(result.isAnimated, isFalse);
      expect(result.summary, 'celestial.webp · 120 KB · 1024×1024 · static');
    });

    test('a PNG, with the right content type', () {
      final result = service.inspect(file('crown.png', pngBytes()));
      expect(result.validation.isValid, isTrue);
      expect(result.contentType, 'image/png');
    });

    test('an animated WebP under 2 MB, flagged animated', () {
      final result = service.inspect(
        file('spin.webp', webpBytes(animated: true, sizeBytes: 1500 * 1024)),
      );
      expect(result.validation.isValid, isTrue);
      expect(result.isAnimated, isTrue);
      expect(result.summary, contains('animated'));
      // Animated files are judged against the 2 MB cap, not the 400 KB target.
      expect(result.validation.warnings, isEmpty);
    });

    test('a 900 KB static file, with a size warning', () {
      final result = service.inspect(
        file('heavy.webp', webpBytes(sizeBytes: 900 * 1024)),
      );
      expect(result.validation.isValid, isTrue);
      expect(result.validation.hasWarnings, isTrue);
      expect(result.validation.warnings.first, contains('900 KB'));
      expect(result.validation.warnings.first, contains('Static frames'));
      expect(kFrameArtworkStaticTargetBytes, 400 * 1024);
    });

    test('non-square artwork — warned, never blocked (legacy assets)', () {
      final result = service.inspect(
        file('wide.webp', webpBytes(width: 1024, height: 768)),
      );
      expect(result.validation.isValid, isTrue);
      expect(
        result.validation.warnings,
        contains(
          'Artwork is 1024×768, not square. Frames render inside a square '
          'box, so it may look off-centre.',
        ),
      );
    });

    test('a tiny canvas warns about softness', () {
      final result = service.inspect(
        file('small.webp', webpBytes(width: 128, height: 128)),
      );
      expect(result.validation.isValid, isTrue);
      expect(result.validation.warnings.single, contains('128×128'));
      expect(kFrameArtworkMinCanvas, 256);
    });

    test('an oversized canvas warns about waste', () {
      final result = service.inspect(
        file('huge.webp', webpBytes(width: 4096, height: 4096)),
      );
      expect(result.validation.isValid, isTrue);
      expect(result.validation.warnings.single, contains('4096×4096'));
      expect(kFrameArtworkMaxCanvas, 2048);
      expect(kFrameArtworkRecommendedCanvas, 1024);
    });
  });

  group('buildFrameArtworkPath', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

    test('is {category}/{code}/v{timestamp}.{ext}', () {
      expect(
        buildFrameArtworkPath(
          category: 'vip',
          frameCode: 'vip4_celestial_crown',
          extension: 'webp',
          now: now,
        ),
        'vip/vip4_celestial_crown/v1700000000000.webp',
      );
    });

    test('reduces both segments to the [a-z0-9_] alphabet', () {
      expect(
        buildFrameArtworkPath(
          category: 'Special Edition',
          frameCode: 'Celestial Crown!!',
          extension: 'png',
          now: now,
        ),
        'special_edition/celestial_crown/v1700000000000.png',
      );
    });

    test('empty segments fall back rather than producing //', () {
      expect(
        buildFrameArtworkPath(
          category: '  ',
          frameCode: '???',
          extension: 'webp',
          now: now,
        ),
        'custom/frame/v1700000000000.webp',
      );
    });

    test('a later upload lands on a fresh version path', () {
      final first = buildFrameArtworkPath(
        category: 'vip',
        frameCode: 'c',
        extension: 'webp',
        now: now,
      );
      final second = buildFrameArtworkPath(
        category: 'vip',
        frameCode: 'c',
        extension: 'webp',
        now: now.add(const Duration(seconds: 1)),
      );
      expect(first, isNot(second));
    });
  });

  group('upload()', () {
    test('writes the versioned path with the right content type', () async {
      final calls = <Map<String, Object?>>[];
      final removals = <String>[];
      final uploader = FrameArtworkUploadService(
        writer: ({required path, required bytes, required contentType}) async {
          calls.add({
            'path': path,
            'contentType': contentType,
            'bytes': bytes.length,
          });
          return 'https://cdn.test/$path';
        },
        remover: (path) async => removals.add(path),
      );

      final candidate = uploader.inspect(
        file('celestial.webp', webpBytes(sizeBytes: 120 * 1024)),
      );
      final upload = await uploader.upload(
        candidate: candidate,
        category: 'vip',
        frameCode: 'vip4_celestial_crown',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      expect(calls, hasLength(1));
      expect(
        calls.single['path'],
        'vip/vip4_celestial_crown/v1700000000000.webp',
      );
      expect(calls.single['contentType'], 'image/webp');
      expect(calls.single['bytes'], 120 * 1024);

      expect(
        upload.url,
        'https://cdn.test/vip/vip4_celestial_crown/v1700000000000.webp',
      );
      expect(upload.path, 'vip/vip4_celestial_crown/v1700000000000.webp');

      // Requirement 9: uploading never deletes anything.
      expect(removals, isEmpty);
    });

    test('refuses an invalid candidate without touching storage', () async {
      var wrote = false;
      var removed = false;
      final uploader = FrameArtworkUploadService(
        writer: ({required path, required bytes, required contentType}) async {
          wrote = true;
          return 'never';
        },
        remover: (path) async => removed = true,
      );

      final candidate = uploader.inspect(file('art.jpg', pngBytes()));
      await expectLater(
        uploader.upload(candidate: candidate, category: 'vip', frameCode: 'c'),
        throwsA(
          isA<FrameAdminException>().having(
            (e) => e.category,
            'category',
            FrameAdminErrorCategory.unsupportedFormat,
          ),
        ),
      );
      expect(wrote, isFalse);
      expect(removed, isFalse);
    });

    test('a storage failure surfaces as a readable typed error', () async {
      final uploader = FrameArtworkUploadService(
        writer: ({required path, required bytes, required contentType}) async {
          throw Exception('SocketException: connection failed');
        },
        remover: (path) async {},
      );

      final candidate = uploader.inspect(file('art.webp', webpBytes()));
      await expectLater(
        uploader.upload(candidate: candidate, category: 'vip', frameCode: 'c'),
        throwsA(
          isA<FrameAdminException>()
              .having(
                (e) => e.category,
                'category',
                FrameAdminErrorCategory.network,
              )
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('Could not reach the server'),
                  isNot(contains('SocketException')),
                ),
              ),
        ),
      );
    });
  });

  group('deleteObject()', () {
    test('reports success and passes the exact path', () async {
      final removals = <String>[];
      final uploader = FrameArtworkUploadService(
        writer: ({required path, required bytes, required contentType}) async =>
            '',
        remover: (path) async => removals.add(path),
      );

      expect(await uploader.deleteObject('vip/c/v1.webp'), isTrue);
      expect(removals, ['vip/c/v1.webp']);
    });

    test('never throws — a failed cleanup returns false', () async {
      final uploader = FrameArtworkUploadService(
        writer: ({required path, required bytes, required contentType}) async =>
            '',
        remover: (path) async => throw Exception('storage down'),
      );

      expect(await uploader.deleteObject('vip/c/v1.webp'), isFalse);
    });
  });

  group('pick()', () {
    test('returns null when the admin cancels', () async {
      final uploader = FrameArtworkUploadService(
        writer: ({required path, required bytes, required contentType}) async =>
            '',
        remover: (path) async {},
        filePicker: () async => null,
      );
      expect(await uploader.pick(), isNull);
    });

    test('validates whatever the picker returned', () async {
      final uploader = FrameArtworkUploadService(
        writer: ({required path, required bytes, required contentType}) async =>
            '',
        remover: (path) async {},
        filePicker: () async => file('art.jpg', pngBytes()),
      );
      final candidate = await uploader.pick();
      expect(candidate, isNotNull);
      expect(candidate!.validation.isValid, isFalse);
    });
  });

  group('constants', () {
    test('the bucket and cache-control match the storage migration', () {
      expect(kFrameArtworkBucket, 'avatar-frames');
      // One year, immutable — safe because every path is version-stamped.
      expect(kFrameArtworkCacheControl, '31536000');
    });

    test('formatFrameArtworkBytes reads the way an admin expects', () {
      expect(formatFrameArtworkBytes(512), '512 B');
      expect(formatFrameArtworkBytes(400 * 1024), '400 KB');
      expect(formatFrameArtworkBytes(1024 * 1024), '1.0 MB');
      expect(formatFrameArtworkBytes(2 * 1024 * 1024), '2.0 MB');
    });
  });
}
