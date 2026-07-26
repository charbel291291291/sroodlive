/// Frame Management v2 — artwork upload field.
///
/// Presentational only: the dialog owns the pick/upload lifecycle (it is the
/// thing that knows the frame code and category the storage path needs, and it
/// is the thing that must delete an orphan if the catalog write later fails).
/// This widget renders the current state of that lifecycle and exposes the two
/// buttons that drive it.
library;

import 'package:flutter/material.dart';

import '../services/frame_artwork_upload_service.dart';
import '../theme/frame_admin_theme.dart';

class FrameArtworkField extends StatelessWidget {
  const FrameArtworkField({
    required this.assetUrl,
    required this.isAnimated,
    required this.isUploading,
    required this.onUpload,
    required this.onClear,
    this.candidate,
    this.uploadError,
    this.enabled = true,
    this.disabledReason,
    super.key,
  });

  /// The artwork currently attached to the frame, if any.
  final String? assetUrl;

  final bool isAnimated;
  final bool isUploading;

  /// The most recent successfully uploaded file, for its size/dimension
  /// summary and any non-blocking warnings. Null when the frame's artwork was
  /// set in an earlier session.
  final FrameArtworkCandidate? candidate;

  /// A human-readable failure from the last pick or upload attempt.
  final String? uploadError;

  final VoidCallback onUpload;
  final VoidCallback onClear;

  /// False while the frame code is not yet derivable — the storage path needs
  /// it, so uploading before then would land the object in the wrong folder.
  final bool enabled;
  final String? disabledReason;

  bool get _hasArtwork => (assetUrl ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final warnings = candidate?.validation.warnings ?? const <String>[];

    return Container(
      decoration: BoxDecoration(
        color: FrameAdminTheme.raisedCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FrameAdminTheme.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('ARTWORK', style: FrameAdminTheme.sectionTitle),
              ),
              if (_hasArtwork)
                _Chip(
                  label: isAnimated ? 'Animated' : 'Static',
                  color: isAnimated
                      ? FrameAdminTheme.accent
                      : FrameAdminTheme.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '.webp (static or animated) or .png · '
            '$kFrameArtworkRecommendedCanvas×$kFrameArtworkRecommendedCanvas '
            'square recommended · under '
            '${formatFrameArtworkBytes(kFrameArtworkStaticTargetBytes)} static, '
            '${formatFrameArtworkBytes(kFrameArtworkAnimatedMaxBytes)} max '
            'animated.',
            style: FrameAdminTheme.metaStyle,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (enabled && !isUploading) ? onUpload : null,
                  icon: isUploading
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _hasArtwork
                              ? Icons.autorenew_rounded
                              : Icons.upload_rounded,
                          size: 18,
                        ),
                  label: Text(
                    isUploading
                        ? 'Uploading…'
                        : _hasArtwork
                        ? 'Replace artwork'
                        : 'Upload artwork',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: FrameAdminTheme.accent,
                    foregroundColor: const Color(0xFF1A0B2E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (_hasArtwork && !isUploading) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onClear,
                  tooltip: 'Remove artwork',
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: FrameAdminTheme.danger,
                ),
              ],
            ],
          ),
          if (!enabled && disabledReason != null) ...[
            const SizedBox(height: 8),
            _Note(
              icon: Icons.info_outline_rounded,
              color: FrameAdminTheme.textMuted,
              text: disabledReason!,
            ),
          ],
          if (candidate != null) ...[
            const SizedBox(height: 10),
            _Note(
              icon: Icons.check_circle_outline_rounded,
              color: FrameAdminTheme.success,
              text: candidate!.summary,
            ),
          ] else if (_hasArtwork) ...[
            const SizedBox(height: 10),
            _Note(
              icon: Icons.link_rounded,
              color: FrameAdminTheme.textMuted,
              text: assetUrl!.split('/').last,
            ),
          ],
          for (final warning in warnings) ...[
            const SizedBox(height: 8),
            _Note(
              icon: Icons.warning_amber_rounded,
              color: FrameAdminTheme.warning,
              text: warning,
            ),
          ],
          if (uploadError != null) ...[
            const SizedBox(height: 8),
            _Note(
              icon: Icons.error_outline_rounded,
              color: FrameAdminTheme.danger,
              text: uploadError!,
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
