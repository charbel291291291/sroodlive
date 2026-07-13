/// Full-width bio card: up to three lines collapsed with ellipsis, tap to
/// expand/collapse (presentation-only state), owner-only edit icon, RTL
/// aligned for Arabic. Shows a friendly placeholder when the bio is empty.
library;

import 'package:flutter/material.dart';

import 'srood_profile_theme.dart';

class SroodProfileBioCard extends StatefulWidget {
  const SroodProfileBioCard({
    required this.bio,
    required this.isArabic,
    this.onEditTap,
    super.key,
  });

  final String bio;
  final bool isArabic;

  /// Non-null only for the profile owner.
  final VoidCallback? onEditTap;

  @override
  State<SroodProfileBioCard> createState() => _SroodProfileBioCardState();
}

class _SroodProfileBioCardState extends State<SroodProfileBioCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final hasBio = widget.bio.trim().isNotEmpty;
    final text = hasBio
        ? widget.bio.trim()
        : (isArabic ? 'أضف نبذة عنك...' : 'Add something about yourself...');

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Semantics(
        label: isArabic ? 'النبذة الشخصية' : 'Profile bio',
        child: InkWell(
          borderRadius: BorderRadius.circular(SroodProfileDims.cardRadius),
          onTap: hasBio
              ? () => setState(() => _expanded = !_expanded)
              : widget.onEditTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: sroodProfileCard(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.format_quote_rounded,
                    color: SroodProfileColors.violet,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                // Plain swap on expand — AnimatedSize would re-measure the
                // text on every layout pass, which shows up in first-entry
                // frame times.
                Expanded(
                  child: Text(
                    text,
                    maxLines: _expanded ? null : 3,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: SroodProfileText.body.copyWith(
                      color: hasBio
                          ? SroodProfileColors.textSecondary
                          : SroodProfileColors.textMuted,
                      fontStyle: hasBio ? null : FontStyle.italic,
                    ),
                  ),
                ),
                if (widget.onEditTap != null) ...[
                  const SizedBox(width: 6),
                  Semantics(
                    label: isArabic ? 'تعديل النبذة' : 'Edit bio',
                    button: true,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.onEditTap,
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.edit_rounded,
                          color: SroodProfileColors.gold.withValues(
                            alpha: 0.75,
                          ),
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
