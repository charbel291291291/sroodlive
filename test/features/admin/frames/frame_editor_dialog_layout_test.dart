/// Frame Management v2 — editor dialog layout and save ordering.
///
/// The dialog this replaced was a bottom sheet whose Save button was the last
/// child of the scrolling column, so on desktop it sat below the fold and there
/// was no Cancel at all. These tests pin the replacement contract: at every
/// common viewport the dialog fits, does not overflow, scrolls its body, and
/// keeps Cancel and Save on screen.
///
/// The last group pins requirement 9: a replacement upload is written *before*
/// the catalog write and the old artwork is never removed on a failed save —
/// only the new, unreferenced object is cleaned up.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/core/frames/srood_frame.dart';
import 'package:srood_live/features/admin/frames/frame_editor_dialog.dart';
import 'package:srood_live/features/admin/frames/frame_editor_form.dart';
import 'package:srood_live/features/admin/services/frame_admin_service.dart';
import 'package:srood_live/features/admin/services/frame_artwork_upload_service.dart';
import 'package:srood_live/features/admin/theme/frame_admin_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// A minimal extended-format WebP header: `RIFF….WEBP` + `VP8X` with the canvas
/// size the metrics reader expects at bytes 24–29.
Uint8List _webp({int width = 1024, int height = 1024, bool animated = false}) {
  final out = BytesBuilder();
  out.add('RIFF'.codeUnits);
  out.add(const [0, 0, 0, 0]);
  out.add('WEBP'.codeUnits);
  out.add('VP8X'.codeUnits);
  out.add(const [10, 0, 0, 0]);
  out.add([animated ? 0x02 : 0x00, 0, 0, 0]);
  for (final value in [width - 1, height - 1]) {
    out.add([value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF]);
  }
  return out.toBytes();
}

/// Frames used as the catalog context. All `painter`/`bundled` with codes the
/// registry does not know, so the live preview resolves to the legacy painter
/// path and performs no network or asset I/O inside the test.
final List<SroodFrame> catalog = <SroodFrame>[
  const SroodFrame(
    id: 'f1',
    code: 'luxury_test_ring',
    name: 'Test Ring',
    category: SroodFrameCategory.luxury,
    sortOrder: 40,
  ),
  const SroodFrame(
    id: 'f2',
    code: 'luxury_test_halo',
    name: 'Test Halo',
    category: SroodFrameCategory.luxury,
    sortOrder: 60,
  ),
];

/// An existing row being edited: bundled artwork, so the preview stays offline.
const SroodFrame existingFrame = SroodFrame(
  id: 'f1',
  code: 'luxury_test_ring',
  name: 'Test Ring',
  category: SroodFrameCategory.luxury,
  assetType: SroodFrameAssetType.bundled,
  assetUrl: 'assets/images/frames/legacy_test_ring.webp',
  sortOrder: 40,
);

Future<void> openEditor(
  WidgetTester tester, {
  required FrameEditorState state,
  FrameAdminService? adminService,
  FrameArtworkUploadService? uploadService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: FrameAdminTheme.background,
          body: Center(
            child: ElevatedButton(
              onPressed: () => showFrameEditorDialog(
                context,
                state: state,
                catalog: catalog,
                adminService: adminService,
                uploadService: uploadService,
              ),
              child: const Text('open editor'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open editor'));
  await tester.pump();
  // Let the dialog's entrance transition finish without pumpAndSettle, which
  // would hang if any frame art were animating.
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // 1366×768 and 1920×1080 are the two sizes named in the requirement; the rest
  // cover a small laptop, the narrowest desktop window, and a phone.
  const sizes = <String, Size>{
    '1366x768': Size(1366, 768),
    '1920x1080': Size(1920, 1080),
    '1280x800': Size(1280, 800),
    '800x600': Size(800, 600),
    '390x844': Size(390, 844),
  };

  group('layout', () {
    for (final entry in sizes.entries) {
      final label = entry.key;
      final size = entry.value;

      testWidgets('does not overflow at $label', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await openEditor(
          tester,
          state: FrameEditorState.fromFrame(existingFrame, catalog: catalog),
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('keeps Cancel and Save on screen at $label', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await openEditor(
          tester,
          state: FrameEditorState.fromFrame(existingFrame, catalog: catalog),
        );

        final save = find.widgetWithText(FilledButton, 'Save changes');
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        expect(save, findsOneWidget);
        expect(cancel, findsOneWidget);

        // Hit-testable means it is not just in the tree — it is reachable by a
        // pointer without scrolling, which is what the old sheet failed.
        expect(save.hitTestable(), findsOneWidget);
        expect(cancel.hitTestable(), findsOneWidget);

        final rect = tester.getRect(save);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      });

      testWidgets('fits the viewport and scrolls its body at $label', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await openEditor(
          tester,
          state: FrameEditorState.fromFrame(existingFrame, catalog: catalog),
        );

        // The body spans the panel, so its width is the panel's width.
        final body = tester.getRect(find.byType(SingleChildScrollView));
        expect(body.width, lessThanOrEqualTo(FrameAdminTheme.dialogMaxWidth));
        expect(body.width, lessThanOrEqualTo(size.width));

        // Sticky header top to sticky footer bottom — the whole panel — inside
        // 90% of the viewport.
        final panelTop = tester.getRect(find.text('Edit frame')).top;
        final panelBottom = tester
            .getRect(find.widgetWithText(FilledButton, 'Save changes'))
            .bottom;
        expect(panelBottom - panelTop, lessThanOrEqualTo(size.height * 0.9));

        // Exactly one scrollable body: the fields scroll, the chrome does not.
        expect(
          find.descendant(
            of: find.byType(FrameEditorDialog),
            matching: find.byType(SingleChildScrollView),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the sticky header and footer stay outside the scroll view', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await openEditor(
        tester,
        state: FrameEditorState.fromFrame(existingFrame, catalog: catalog),
      );

      final scroller = find.byType(SingleChildScrollView);
      expect(
        find.descendant(of: scroller, matching: find.text('Edit frame')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: scroller,
          matching: find.widgetWithText(FilledButton, 'Save changes'),
        ),
        findsNothing,
      );
    });

    testWidgets('a new frame labels its action Create frame', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await openEditor(tester, state: FrameEditorState.blank(catalog: catalog));

      expect(find.text('New frame'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create frame'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save changes'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('save gating', () {
    testWidgets('an empty form disables Save and says why', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await openEditor(tester, state: FrameEditorState.blank(catalog: catalog));

      // The old sheet silently returned from _save; this one explains itself
      // twice: as the name field's error and as the footer note beside Save.
      expect(find.text('Enter a frame name.'), findsNWidgets(2));
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create frame'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('typing a name enables Save and derives the code', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = FrameEditorState.blank(catalog: catalog);
      await openEditor(tester, state: state);

      await tester.enterText(find.byType(TextField).first, 'Celestial Crown');
      await tester.pump();

      expect(state.code, 'celestial_crown');
      expect(find.text('celestial_crown'), findsWidgets);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create frame'),
      );
      expect(button.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('replace artwork ordering (requirement 9)', () {
    /// The stub writer returns a bundled-style URL rather than an https one so
    /// the live preview resolves through the painter path and the test performs
    /// no network I/O. Nothing under test here depends on the URL's scheme —
    /// only on the order of the storage and catalog calls.
    ({
      FrameArtworkUploadService uploads,
      List<String> events,
      List<String> written,
      List<String> removed,
    })
    stubUploads(List<String> events) {
      final written = <String>[];
      final removed = <String>[];
      final uploads = FrameArtworkUploadService(
        filePicker: () async =>
            FrameArtworkFile(name: 'celestial.webp', bytes: _webp()),
        writer: ({required path, required bytes, required contentType}) async {
          events.add('upload');
          written.add(path);
          return 'assets/uploaded/$path';
        },
        remover: (path) async {
          events.add('delete');
          removed.add(path);
        },
      );
      return (
        uploads: uploads,
        events: events,
        written: written,
        removed: removed,
      );
    }

    testWidgets('uploads first, then writes the catalog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final events = <String>[];
      final stub = stubUploads(events);
      final admin = FrameAdminService(
        reader: () async => <Map<String, dynamic>>[],
        rpcCaller: (fn, {params}) async {
          events.add('rpc:$fn');
          return null;
        },
      );

      await openEditor(
        tester,
        state: FrameEditorState.fromFrame(existingFrame, catalog: catalog),
        adminService: admin,
        uploadService: stub.uploads,
      );

      expect(find.text('Replace artwork'), findsOneWidget);
      await tester.tap(find.text('Replace artwork'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(events, ['upload', 'rpc:admin_upsert_frame_v2']);
      // A successful save deletes nothing: the object the row now points at is
      // live, and the previous artwork was never a session upload.
      expect(stub.removed, isEmpty);
      expect(stub.written.single, contains('luxury/luxury_test_ring/v'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed catalog write removes only the new object', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final events = <String>[];
      final stub = stubUploads(events);
      final admin = FrameAdminService(
        reader: () async => <Map<String, dynamic>>[],
        rpcCaller: (fn, {params}) async {
          events.add('rpc:$fn');
          throw const PostgrestException(message: 'not_authorized');
        },
      );

      await openEditor(
        tester,
        state: FrameEditorState.fromFrame(existingFrame, catalog: catalog),
        adminService: admin,
        uploadService: stub.uploads,
      );

      await tester.tap(find.text('Replace artwork'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The delete strictly follows the failed write — never before it.
      expect(events, ['upload', 'rpc:admin_upsert_frame_v2', 'delete']);
      expect(stub.removed, [stub.written.single]);
      // The frame's previous artwork is still the live one.
      expect(stub.removed.single, isNot(contains('legacy_test_ring')));
      // And the admin gets a readable reason, not a PostgrestException dump.
      expect(
        find.textContaining('admin or super_admin app role'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a colliding code is refused before any catalog write', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final events = <String>[];
      final admin = FrameAdminService(
        // The code the editor is about to create already exists.
        reader: () async => <Map<String, dynamic>>[
          {'code': 'celestial_crown', 'name': 'Celestial Crown'},
        ],
        rpcCaller: (fn, {params}) async {
          events.add('rpc:$fn');
          return null;
        },
      );

      final state = FrameEditorState.blank(catalog: catalog)
        ..name = 'Celestial Crown';
      state.syncCodeFromName();

      await openEditor(tester, state: state, adminService: admin);

      await tester.tap(find.text('Create frame'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(events, isEmpty, reason: 'no write may be attempted');
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
