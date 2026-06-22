import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../utils/vip_assets.dart';

/// Pure-Flutter avatar crop/adjust screen (no native crop package, so it can't
/// break the Android build). The user pans/zooms the image inside a square
/// viewport; on Save the visible square is captured to PNG bytes and returned.
///
/// Returns the cropped [Uint8List] on Save, or null on Cancel. The grid and
/// circle/frame guides are overlays OUTSIDE the captured boundary, so only the
/// photo is exported (the avatar is shown circular on the profile anyway).
class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({
    required this.imageFile,
    required this.isArabic,
    this.vipLevel = 0,
    super.key,
  });

  final File imageFile;
  final bool isArabic;
  final int vipLevel;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  static const _gold = Color(0xFFF0C15A);
  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _controller = TransformationController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(double cropSize) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      // Export ~512px square regardless of on-screen size.
      final pixelRatio = (512.0 / cropSize).clamp(1.0, 4.0);
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw StateError('encode_failed');
      final bytes = byteData.buffer.asUint8List();
      if (!mounted) return;
      Navigator.of(context).pop<Uint8List>(bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isArabic
              ? 'تعذّر قص الصورة. حاول مرة أخرى.'
              : 'Could not crop the image. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final media = MediaQuery.of(context);
    final cropSize =
        (media.size.width - 48).clamp(220.0, 360.0).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFF0C0518),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          isArabic ? 'تعديل الصورة' : 'Adjust profile photo',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A0E45), Color(0xFF12061F), Color(0xFF07030D)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: cropSize,
                height: cropSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Captured layer: ONLY the pan/zoomable photo.
                    ClipRect(
                      child: RepaintBoundary(
                        key: _boundaryKey,
                        child: Container(
                          color: Colors.black,
                          child: InteractiveViewer(
                            transformationController: _controller,
                            clipBehavior: Clip.hardEdge,
                            minScale: 1.0,
                            maxScale: 4.0,
                            boundaryMargin: EdgeInsets.all(cropSize),
                            child: Image.file(
                              widget.imageFile,
                              width: cropSize,
                              height: cropSize,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Overlays (NOT captured): circular mask, grid, VIP frame.
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size(cropSize, cropSize),
                        painter: _CropGuidePainter(),
                      ),
                    ),
                    if (VipAssets.hasVip(widget.vipLevel))
                      IgnorePointer(
                        child: Image.asset(
                          VipAssets.frame(widget.vipLevel),
                          width: cropSize,
                          height: cropSize,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  isArabic
                      ? 'حرّك الصورة وكبّرها لتناسب الدائرة.'
                      : 'Move and zoom your photo to fit the circle.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFCBBEE6),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + media.padding.bottom),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(isArabic ? 'إلغاء' : 'Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : () => _save(cropSize),
                        style: FilledButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: const Color(0xFF0A0612),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Color(0xFF0A0612),
                                ),
                              )
                            : Text(
                                isArabic ? 'حفظ' : 'Save',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Darkens the area outside the circle and draws rule-of-thirds grid lines +
/// the circular avatar guide.
class _CropGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.width / 2;
    final center = rect.center;

    // Dim outside the circle.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));

    // Circle guide.
    canvas.drawCircle(
      center,
      radius - 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // Rule-of-thirds grid.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.28);
    for (var i = 1; i < 3; i++) {
      final dx = size.width * i / 3;
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), grid);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
