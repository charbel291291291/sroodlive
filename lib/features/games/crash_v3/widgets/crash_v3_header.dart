import 'package:flutter/material.dart';

class CrashV3Header extends StatelessWidget {
  const CrashV3Header({
    required this.balance,
    required this.connected,
    required this.soundEnabled,
    required this.onSound,
    required this.onFairness,
    super.key,
  });
  final int balance;
  final bool connected, soundEnabled;
  final VoidCallback onSound, onFairness;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
      ),
      const Expanded(
        child: Text(
          'Crash Rocket V3',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      const Icon(
        Icons.monetization_on_rounded,
        color: Color(0xFFFFC857),
        size: 19,
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          '$balance',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      IconButton(
        tooltip: 'Provably fair',
        onPressed: onFairness,
        icon: const Icon(
          Icons.verified_user_outlined,
          color: Color(0xFFFFC857),
        ),
      ),
      IconButton(
        onPressed: onSound,
        icon: Icon(
          soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          color: Colors.white,
        ),
      ),
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? const Color(0xFF35E59A) : const Color(0xFFFF557D),
        ),
      ),
    ],
  );
}
