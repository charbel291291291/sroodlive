/// Immutable per-frame layout metrics for the profile page.
///
/// Computed exactly once per screen build from MediaQuery, then passed down
/// so section widgets never run their own LayoutBuilder/MediaQuery width
/// probes. Every value here is derived from the page's fixed content
/// contract: gutters of 16 and a 520px max content width.
library;

import 'package:flutter/material.dart';

import 'srood_profile_theme.dart';

@immutable
class SroodProfileMetrics {
  const SroodProfileMetrics({
    required this.screenWidth,
    required this.contentWidth,
    required this.horizontalPadding,
    required this.avatarShell,
    required this.sectionGap,
    required this.compact,
    required this.bottomPadding,
  });

  /// Raw screen width.
  final double screenWidth;

  /// Inner content width available to section cards (after gutters + the
  /// 520px cap).
  final double contentWidth;

  /// Page gutter.
  final double horizontalPadding;

  /// Fixed avatar shell diameter for the header.
  final double avatarShell;

  /// Vertical gap between major sections.
  final double sectionGap;

  /// Narrow-phone mode (≤330px of content) — tiles compress padding.
  final bool compact;

  /// Scroll bottom padding that clears the floating bottom navigation.
  final double bottomPadding;

  factory SroodProfileMetrics.of(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    const gutter = SroodProfileDims.gutter;
    final contentWidth = (screenWidth.clamp(0.0, 520.0)) - gutter * 2;

    return SroodProfileMetrics(
      screenWidth: screenWidth,
      contentWidth: contentWidth,
      horizontalPadding: gutter,
      avatarShell: SroodProfileDims.avatarShell(contentWidth),
      sectionGap: SroodProfileDims.sectionGap,
      compact: contentWidth <= 330,
      bottomPadding: media.padding.bottom + 32 + 80,
    );
  }
}
