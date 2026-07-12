import 'package:flutter/material.dart';

class RoomParticipantsChip extends StatelessWidget {
  const RoomParticipantsChip({
    required this.count,
    required this.isArabic,
    required this.onTap,
    super.key,
  });

  final int count;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF241638).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF5A3A86)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            const Icon(
              Icons.people_alt_rounded,
              size: 14,
              color: Color(0xFFF0C15A),
            ),
            const SizedBox(width: 5),
            Text(
              count.toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF4EBD8),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RoomMiniStatusPill extends StatelessWidget {
  const RoomMiniStatusPill({required this.label, this.gold = false, super.key});

  final String label;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: gold
            ? const Color(0xFFF0C15A).withValues(alpha: 0.18)
            : const Color(0xFF2A1A3D),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: gold ? const Color(0xFFF0C15A) : const Color(0xFF5A3A86),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: gold ? const Color(0xFFF0C15A) : const Color(0xFFD8CFEA),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class RoomTinyIconButton extends StatelessWidget {
  const RoomTinyIconButton({
    required this.icon,
    required this.busy,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final bool busy;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF5C7A) : const Color(0xFFF0C15A);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: busy ? null : onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.72)),
        ),
        child: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(icon, size: 16, color: color),
      ),
    );
  }
}
