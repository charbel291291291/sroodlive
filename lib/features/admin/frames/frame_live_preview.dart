/// Frame Management v2 — live preview.
///
/// Renders the frame being edited through [SroodAvatarFrame], the exact widget
/// every user-facing avatar goes through, using its `frameOverride` hook. There
/// is deliberately no second renderer here: if the preview and a real profile
/// could disagree, the preview would be worthless as an approval step.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/frames/srood_frame.dart';
import '../../../shared/widgets/srood_avatar_frame.dart';
import '../theme/frame_admin_theme.dart';

enum _ArtworkProbe { notApplicable, loading, ready, failed }

class FrameLivePreview extends StatefulWidget {
  const FrameLivePreview({
    required this.frame,
    this.isUploading = false,
    super.key,
  });

  /// The frame as currently configured in the editor — including unsaved edits.
  final SroodFrame frame;

  /// True while an upload is in flight, so the preview shows progress instead
  /// of the previous artwork.
  final bool isUploading;

  @override
  State<FrameLivePreview> createState() => _FrameLivePreviewState();
}

class _FrameLivePreviewState extends State<FrameLivePreview> {
  bool _lightBackground = false;
  bool _animate = true;
  int _attempt = 0;
  _ArtworkProbe _probe = _ArtworkProbe.notApplicable;

  String? get _networkUrl {
    final frame = widget.frame;
    if (frame.assetType != SroodFrameAssetType.network) return null;
    final url = frame.assetUrl?.trim();
    return (url == null || url.isEmpty) ? null : url;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startProbe();
  }

  @override
  void didUpdateWidget(FrameLivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frame.assetUrl != widget.frame.assetUrl ||
        oldWidget.frame.assetType != widget.frame.assetType) {
      _startProbe();
    }
  }

  /// Resolves the artwork ahead of the renderer so a broken URL surfaces as an
  /// explicit error with a Retry button. [SroodAvatarFrame] falls back silently
  /// (correct for users, useless for an admin checking their upload).
  ///
  /// This shares `CachedNetworkImage`'s cache, so it is not a second download.
  void _startProbe() {
    final url = _networkUrl;
    if (url == null) {
      if (_probe != _ArtworkProbe.notApplicable) {
        setState(() => _probe = _ArtworkProbe.notApplicable);
      }
      return;
    }
    setState(() => _probe = _ArtworkProbe.loading);
    final attempt = _attempt;
    precacheImage(CachedNetworkImageProvider(url), context)
        .then((_) {
          if (!mounted || attempt != _attempt || _networkUrl != url) return;
          setState(() => _probe = _ArtworkProbe.ready);
        })
        .catchError((Object _) {
          if (!mounted || attempt != _attempt || _networkUrl != url) return;
          setState(() => _probe = _ArtworkProbe.failed);
        });
  }

  Future<void> _retry() async {
    final url = _networkUrl;
    if (url == null) return;
    await CachedNetworkImage.evictFromCache(url);
    if (!mounted) return;
    setState(() => _attempt++);
    _startProbe();
  }

  @override
  Widget build(BuildContext context) {
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
                child: Text(
                  'LIVE PREVIEW',
                  style: FrameAdminTheme.sectionTitle,
                ),
              ),
              _MiniToggle(
                label: 'Animate',
                value: _animate,
                onChanged: (v) => setState(() => _animate = v),
              ),
              const SizedBox(width: 4),
              _MiniToggle(
                label: 'Light bg',
                value: _lightBackground,
                onChanged: (v) => setState(() => _lightBackground = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.isUploading)
            const _PreviewNotice(
              icon: Icons.cloud_upload_rounded,
              color: FrameAdminTheme.accent,
              message: 'Uploading artwork…',
              busy: true,
            )
          else if (_probe == _ArtworkProbe.loading)
            const _PreviewNotice(
              icon: Icons.downloading_rounded,
              color: FrameAdminTheme.textMuted,
              message: 'Loading artwork…',
              busy: true,
            )
          else if (_probe == _ArtworkProbe.failed)
            _PreviewNotice(
              icon: Icons.broken_image_rounded,
              color: FrameAdminTheme.danger,
              message: 'The artwork URL could not be loaded.',
              action: TextButton(onPressed: _retry, child: const Text('Retry')),
            )
          else
            _previewSurface(),
          const SizedBox(height: 8),
          Text(
            widget.frame.assetType == SroodFrameAssetType.painter
                ? 'No artwork uploaded — users see the built-in placeholder ring '
                      'for this frame.'
                : 'Rendered through the same component user profiles use.',
            style: FrameAdminTheme.metaStyle,
          ),
        ],
      ),
    );
  }

  Widget _previewSurface() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: _lightBackground
            ? const LinearGradient(
                colors: [Color(0xFFF3EFF8), Color(0xFFE2DCEC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF120A1F), Color(0xFF07040D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 26,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _sample('Chat / lists', SroodAvatarFrameSize.small),
          _sample('Mic seat', SroodAvatarFrameSize.medium),
          _sample('Profile', SroodAvatarFrameSize.large),
        ],
      ),
    );
  }

  Widget _sample(String label, SroodAvatarFrameSize preset) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SroodAvatarFrame(
          // The attempt counter forces a fresh image element after a retry.
          key: ValueKey('${widget.frame.assetUrl}#$_attempt#${preset.name}'),
          // No sample photo: AvatarWithFrame draws its fallback avatar, which
          // keeps the frame itself the only thing under review.
          frameOverride: widget.frame,
          vipLevel: widget.frame.vipLevel ?? 0,
          sizePreset: preset,
          animate: _animate && widget.frame.isAnimated,
          preferV2TierArt: widget.frame.category == SroodFrameCategory.vip,
        ),
        const SizedBox(height: 6),
        Text(
          '$label · ${preset.avatarDiameter.round()}px',
          style: TextStyle(
            fontSize: 10,
            color: _lightBackground
                ? const Color(0xFF5C5170)
                : FrameAdminTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice({
    required this.icon,
    required this.color,
    required this.message,
    this.busy = false,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String message;
  final bool busy;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0718),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12.5),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 6), action!],
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          children: [
            Icon(
              value ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
              size: 22,
              color: value ? FrameAdminTheme.accent : FrameAdminTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: value
                    ? FrameAdminTheme.textPrimary
                    : FrameAdminTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
