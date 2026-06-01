import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.isArabic,
    super.key,
  });

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment:
              isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'الملف الشخصي' : 'Profile',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'اسم المستخدم الصورة إطار VIP والشارات ستظهر هنا.'
                  : 'Username, avatar, VIP frame, and badges will appear here.',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFFB8B8C7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
