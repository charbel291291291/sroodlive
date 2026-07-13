/// Chat image thumbnail with a tap-to-zoom full-screen preview.
library;

import 'package:flutter/material.dart';

import '../../../theme/srood_room_theme.dart';

class SroodChatImageThumbnail extends StatelessWidget {
  const SroodChatImageThumbnail({required this.imageUrl, super.key});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPreview(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusSm),
        child: Image.network(
          imageUrl,
          width: 160,
          height: 120,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : Container(
                  width: 160,
                  height: 120,
                  color: Colors.white.withValues(alpha: 0.08),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                          : null,
                      color: Colors.white54,
                    ),
                  ),
                ),
          errorBuilder: (ctx, err, stack) => Container(
            width: 160,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(SroodRoomDims.radiusSm),
            ),
            child: const Icon(
              Icons.broken_image_rounded,
              color: Colors.white38,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  void _showPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(SroodRoomDims.space16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, stack) => const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white38,
                    size: 64,
                  ),
                ),
              ),
            ),
            Positioned(
              top: SroodRoomDims.space8,
              right: SroodRoomDims.space8,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(SroodRoomDims.space6),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: SroodRoomDims.iconMd,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
