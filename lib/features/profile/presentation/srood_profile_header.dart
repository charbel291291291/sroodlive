/// Premium profile header — centered identity layout.
///
/// Top row: "Srood Profile" label (start) and Edit pill (end). Below it the
/// fixed-shell avatar, display name (one line, ellipsis), copyable public ID
/// chip, and a compact country + VIP badge row. All data and callbacks come
/// from the screen state; the VIP frame never drives the layout size.
library;

import 'package:flutter/material.dart';

import '../../../shared/widgets/vip_badge.dart';
import '../../../shared/widgets/vip_username.dart';
import '../widgets/country_picker_sheet.dart';
import 'srood_profile_avatar.dart';
import 'srood_profile_theme.dart';

class SroodProfileHeader extends StatelessWidget {
  const SroodProfileHeader({
    required this.displayName,
    required this.publicUserId,
    required this.avatarUrl,
    required this.frameKey,
    required this.vipLevel,
    required this.isGoldenId,
    required this.country,
    required this.isUploadingAvatar,
    required this.isArabic,
    required this.onAvatarTap,
    required this.onEditTap,
    required this.onFrameTap,
    required this.onCopyId,
    this.goldenIdStyle = 'gold',
    this.goldenIdFrame = 'classic',
    this.animatedFrame = false,
    super.key,
  });

  final String displayName;
  final String publicUserId;
  final String? avatarUrl;
  final String? frameKey;
  final int vipLevel;
  final bool isGoldenId;
  final String goldenIdStyle;
  final String goldenIdFrame;
  final String country;
  final bool isUploadingAvatar;
  final bool isArabic;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditTap;
  final VoidCallback onFrameTap;
  final VoidCallback onCopyId;
  final bool animatedFrame;

  String get _countryLabel {
    if (country.trim().isEmpty) return '';
    final match = countryFromStored(country);
    if (match != null) return '${match.flag} ${match.name}';
    // Legacy free-text entries display as-is.
    return country;
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final shell = SroodProfileDims.avatarShell(maxW);
        final countryLabel = _countryLabel;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          decoration: sroodProfileCard(
            raised: true,
            borderColor: SroodProfileColors.gold.withValues(alpha: 0.22),
          ),
          child: Directionality(
            textDirection: textDirection,
            child: Column(
              children: [
                // ── Top row: label + edit ─────────────────────────────────
                Row(
                  children: [
                    Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.26),
                        borderRadius: BorderRadius.circular(
                          SroodProfileDims.chipRadius,
                        ),
                        border: Border.all(
                          color: SroodProfileColors.gold.withValues(
                            alpha: 0.26,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.workspace_premium_rounded,
                            color: SroodProfileColors.gold,
                            size: 12,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isArabic ? 'ملف سرود' : 'Srood Profile',
                            style: TextStyle(
                              color: SroodProfileColors.gold.withValues(
                                alpha: 0.88,
                              ),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      label: isArabic ? 'تعديل الملف الشخصي' : 'Edit profile',
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          SroodProfileDims.chipRadius,
                        ),
                        onTap: onEditTap,
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: 30,
                            minWidth: SroodProfileDims.touchTarget,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              SroodProfileDims.chipRadius,
                            ),
                            color: SroodProfileColors.gold.withValues(
                              alpha: 0.13,
                            ),
                            border: Border.all(
                              color: SroodProfileColors.gold.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.edit_rounded,
                                color: SroodProfileColors.gold,
                                size: 13,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isArabic ? 'تعديل' : 'Edit',
                                style: const TextStyle(
                                  color: SroodProfileColors.gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Centered fixed-shell avatar ───────────────────────────
                SroodProfileAvatar(
                  shellSize: shell,
                  avatarUrl: avatarUrl,
                  frameKey: frameKey,
                  vipLevel: vipLevel,
                  isUploadingAvatar: isUploadingAvatar,
                  isArabic: isArabic,
                  onAvatarTap: onAvatarTap,
                  onFrameTap: onFrameTap,
                  animatedFrame: animatedFrame,
                ),
                const SizedBox(height: 12),

                // ── Display name — one line, never clipped mid-glyph ──────
                VipUsername(
                  name: displayName,
                  vipLevel: vipLevel,
                  fontSize: 22,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // ── Public ID chip (golden style preserved) ───────────────
                if (isGoldenId)
                  GoldenIdBadge(
                    idText: 'ID:$publicUserId',
                    goldenIdStyle: goldenIdStyle,
                    goldenIdFrame: goldenIdFrame,
                    onTap: onCopyId,
                    compact: true,
                    showCopyIcon: true,
                  )
                else
                  Semantics(
                    label: isArabic ? 'نسخ المعرف' : 'Copy ID',
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(
                        SroodProfileDims.chipRadius,
                      ),
                      onTap: onCopyId,
                      child: Container(
                        height: 26,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(
                            SroodProfileDims.chipRadius,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'ID:$publicUserId',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SroodProfileColors.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Icon(
                              Icons.copy_rounded,
                              color: Colors.white.withValues(alpha: 0.5),
                              size: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── Country + VIP badges — one compact row ────────────────
                if (countryLabel.isNotEmpty || vipLevel > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (countryLabel.isNotEmpty)
                        Container(
                          height: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          decoration: BoxDecoration(
                            color: SroodProfileColors.glassFill,
                            borderRadius: BorderRadius.circular(
                              SroodProfileDims.chipRadius,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              countryLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: SroodProfileColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      if (vipLevel > 0) VipBadge(vipLevel: vipLevel),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
