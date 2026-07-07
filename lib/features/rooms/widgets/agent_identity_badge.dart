import 'package:flutter/material.dart';

class AgentBadge extends StatelessWidget {
  const AgentBadge({
    super.key,
    this.compact = true,
    this.label,
  });

  final bool compact;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label ?? (compact ? 'Agent' : 'Official Agent');
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF221226),
            Color(0xFF0B0712),
            Color(0xFF2A183A),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFE7B85C).withValues(alpha: 0.55),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.16),
            blurRadius: compact ? 6 : 10,
          ),
          BoxShadow(
            color: const Color(0xFFE7B85C).withValues(alpha: 0.12),
            blurRadius: compact ? 5 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_user_rounded,
            size: compact ? 9 : 12,
            color: const Color(0xFFE7B85C),
          ),
          SizedBox(width: compact ? 3 : 5),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFFFFE3A3),
              fontSize: compact ? 8.5 : 10,
              fontWeight: FontWeight.w900,
              letterSpacing: compact ? 0.2 : 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class AgentAvatarMarker extends StatelessWidget {
  const AgentAvatarMarker({
    super.key,
    this.size = 17,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE7B85C), Color(0xFF5F2B93)],
        ),
        border: Border.all(color: const Color(0xFF07030D), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE7B85C).withValues(alpha: 0.34),
            blurRadius: 6,
          ),
        ],
      ),
      child: Icon(
        Icons.shield_rounded,
        color: const Color(0xFF0B0712),
        size: size * 0.62,
      ),
    );
  }
}

class AgentIdentityCard extends StatelessWidget {
  const AgentIdentityCard({
    super.key,
    required this.isArabic,
    this.agencyName,
    this.country,
  });

  final bool isArabic;
  final String? agencyName;
  final String? country;

  @override
  Widget build(BuildContext context) {
    final agency = agencyName?.trim();
    final location = country?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B102A), Color(0xFF0B0712)],
        ),
        border: Border.all(
          color: const Color(0xFFE7B85C).withValues(alpha: 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE7B85C).withValues(alpha: 0.14),
              border: Border.all(
                color: const Color(0xFFE7B85C).withValues(alpha: 0.42),
              ),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Color(0xFFE7B85C),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'وكيل رسمي في سرود' : 'Official Srood Agent',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFE3A3),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if ((agency?.isNotEmpty ?? false) ||
                    (location?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (agency?.isNotEmpty ?? false) agency!,
                      if (location?.isNotEmpty ?? false) location!,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const AgentBadge(compact: true),
        ],
      ),
    );
  }
}
