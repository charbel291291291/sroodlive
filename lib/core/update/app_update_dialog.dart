import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_service.dart';

/// Shows the Srood-style update dialog.
/// Returns true if the user tapped Download (so callers can decide to
/// repeat the nag on next launch for force_update builds).
Future<bool> showAppUpdateDialog(
  BuildContext context, {
  required AppVersionInfo info,
  required bool isArabic,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: !info.forceUpdate,
    builder: (_) => _UpdateDialog(info: info, isArabic: isArabic),
  );
  return result == true;
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.info, required this.isArabic});

  final AppVersionInfo info;
  final bool isArabic;

  Future<void> _download() async {
    // Append version code to bust any cached APK on the device's browser.
    final rawUrl = info.apkUrl.isEmpty
        ? 'https://example.com/srood-live-latest.apk'
        : info.apkUrl;
    final uri = Uri.parse(rawUrl).replace(
      queryParameters: {
        ...Uri.parse(rawUrl).queryParameters,
        'v': '${info.versionCode}',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasNotes = info.releaseNotes.trim().isNotEmpty;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2B1A45), Color(0xFF160B26)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFD4A017).withValues(alpha: 0.70),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF0C15A).withValues(alpha: 0.20),
                blurRadius: 32,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFD4A017)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF0C15A).withValues(alpha: 0.40),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: Color(0xFF160B26),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  isArabic ? 'تحديث متاح' : 'Update available',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),

                // Version name
                Text(
                  isArabic
                      ? 'الإصدار ${info.versionName}'
                      : 'Version ${info.versionName}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                // Release notes
                if (hasNotes) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFD4A017).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      info.releaseNotes,
                      textAlign: isArabic ? TextAlign.right : TextAlign.left,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 22),

                // Download button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _download();
                      Navigator.of(context).pop(true);
                    },
                    icon: const Icon(
                      Icons.download_rounded,
                      size: 20,
                      color: Color(0xFF160B26),
                    ),
                    label: Text(
                      isArabic ? 'تحميل التحديث' : 'Download update',
                      style: const TextStyle(
                        color: Color(0xFF160B26),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: const Color(0xFF160B26),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),

                // Later button (hidden when force_update)
                if (!info.forceUpdate) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      isArabic ? 'لاحقاً' : 'Later',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.52),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
