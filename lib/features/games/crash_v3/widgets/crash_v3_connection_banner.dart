import 'package:flutter/material.dart';

class CrashV3ConnectionBanner extends StatelessWidget {
  const CrashV3ConnectionBanner({
    required this.connected,
    required this.onRetry,
    super.key,
  });
  final bool connected;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => connected
      ? const SizedBox.shrink()
      : Material(
          color: const Color(0xFF7F1D1D),
          child: InkWell(
            onTap: onRetry,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.white),
                  SizedBox(width: 7),
                  Text(
                    'Reconnecting — tap to retry',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
}
