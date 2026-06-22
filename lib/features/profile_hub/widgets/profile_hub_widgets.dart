import 'package:flutter/material.dart';

const profileHubBg = Color(0xFF07030D);
const profileHubCard = Color(0xFF12091D);
const profileHubBorder = Color(0xFF3E285E);
const profileHubGold = Color(0xFFF0C15A);
const profileHubMuted = Color(0xFFBCAED6);

class ProfileHubScaffold extends StatelessWidget {
  const ProfileHubScaffold({
    required this.title,
    required this.isArabic,
    required this.children,
    this.actions,
    super.key,
  });

  final String title;
  final bool isArabic;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), profileHubBg, Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            children: children,
          ),
        ),
      ),
    );
  }
}

class ProfileMenuItem extends StatelessWidget {
  const ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.isArabic,
    this.subtitle,
    this.badge,
    this.trailing,
    this.isEnabled = true,
    this.gradientIcon = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final Widget? trailing;
  final bool isEnabled;
  final bool isArabic;
  final bool gradientIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final direction = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Opacity(
      opacity: isEnabled ? 1 : 0.48,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: isEnabled ? onTap : null,
            child: Container(
              constraints: BoxConstraints(
                minHeight: subtitle == null ? 58 : 68,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: profileHubCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: profileHubBorder),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                textDirection: direction,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: gradientIcon
                          ? const LinearGradient(
                              colors: [Color(0xFF7D2BFF), profileHubGold],
                            )
                          : null,
                      color: gradientIcon
                          ? null
                          : profileHubGold.withValues(alpha: 0.12),
                      border: Border.all(
                        color: profileHubGold.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: gradientIcon
                          ? const Color(0xFF160B26)
                          : profileHubGold,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: isArabic
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: profileHubMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    _BadgePill(label: badge!),
                  ],
                  trailing ??
                      Icon(
                        isArabic
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        color: const Color(0xFF9E91B8),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileSectionTitle extends StatelessWidget {
  const ProfileSectionTitle({
    required this.title,
    required this.isArabic,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final align = isArabic ? TextAlign.right : TextAlign.left;
    final cross = isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Column(
        crossAxisAlignment: cross,
        children: [
          Text(
            title,
            textAlign: align,
            style: const TextStyle(
              color: profileHubGold,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              textAlign: align,
              style: const TextStyle(
                color: profileHubMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ProfileInfoCard extends StatelessWidget {
  const ProfileInfoCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.isArabic,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool isArabic;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: profileHubCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: profileHubBorder),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Icon(icon, color: profileHubGold, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: profileHubMuted,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

class ProfileEmptyState extends StatelessWidget {
  const ProfileEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    required this.isArabic,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool isArabic;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ProfileInfoCard(
      icon: icon,
      title: title,
      body: description,
      isArabic: isArabic,
      action: action,
    );
  }
}

class ProfileErrorState extends StatelessWidget {
  const ProfileErrorState({
    required this.message,
    required this.onRetry,
    required this.isArabic,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return ProfileInfoCard(
      icon: Icons.error_outline_rounded,
      title: isArabic ? 'حدث خطأ' : 'Something went wrong',
      body: message,
      isArabic: isArabic,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(isArabic ? 'إعادة المحاولة' : 'Retry'),
      ),
    );
  }
}

class TicketCard extends StatelessWidget {
  const TicketCard({
    required this.title,
    required this.status,
    required this.message,
    required this.isArabic,
    this.date,
    super.key,
  });

  final String title;
  final String status;
  final String message;
  final DateTime? date;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return ProfileInfoCard(
      icon: Icons.confirmation_number_rounded,
      title: title,
      body: [
        status.toUpperCase(),
        if (date != null) date!.toLocal().toString().split('.').first,
        message,
      ].join('\n'),
      isArabic: isArabic,
    );
  }
}

class SettingsToggleTile extends StatelessWidget {
  const SettingsToggleTile({
    this.icon = Icons.tune_rounded,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.isArabic,
    this.subtitle,
    this.isEnabled = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isArabic;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return ProfileMenuItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      isArabic: isArabic,
      isEnabled: isEnabled,
      onTap: () => onChanged(!value),
      trailing: Switch(value: value, onChanged: isEnabled ? onChanged : null),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: profileHubGold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: profileHubGold.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: profileHubGold,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
