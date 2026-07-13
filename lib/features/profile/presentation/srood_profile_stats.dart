/// Identity stat row — Charm / Wealth / Gender as three equal tiles in one
/// visual system: small icon, short label, main value, one desaturated
/// accent per category. Tiles whose data is missing are simply omitted.
library;

import 'package:flutter/material.dart';

import '../../../shared/widgets/gender_chip.dart';
import 'srood_profile_theme.dart';

class SroodProfileStats extends StatelessWidget {
  const SroodProfileStats({
    required this.isArabic,
    required this.gender,
    this.charmLevel,
    this.wealthLevel,
    this.compact = false,
    super.key,
  });

  final bool isArabic;
  final String gender;
  final int? charmLevel;
  final int? wealthLevel;

  /// Narrow-phone mode, decided once by the screen's metrics object.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = <_StatSpec>[];

    if (charmLevel != null) {
      items.add(
        _StatSpec(
          icon: Icons.favorite_rounded,
          label: isArabic ? 'سحر' : 'Charm',
          value: '$charmLevel',
          accent: SroodProfileColors.charm,
        ),
      );
    }
    if (wealthLevel != null) {
      items.add(
        _StatSpec(
          icon: Icons.diamond_rounded,
          label: isArabic ? 'ثروة' : 'Wealth',
          value: '$wealthLevel',
          accent: SroodProfileColors.wealth,
        ),
      );
    }
    if (ProfileGenderChip.isKnown(gender)) {
      final male = gender.trim().toLowerCase() == 'male';
      items.add(
        _StatSpec(
          icon: male ? Icons.male_rounded : Icons.female_rounded,
          label: isArabic ? 'الجنس' : 'Gender',
          value: male
              ? (isArabic ? 'ذكر' : 'Male')
              : (isArabic ? 'أنثى' : 'Female'),
          accent: male
              ? SroodProfileColors.genderMale
              : SroodProfileColors.genderFemale,
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    // One fixed-height row of equal tiles — no per-build width probing.
    return SizedBox(
      height: compact ? 54 : 62,
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _StatTile(spec: items[i], compact: compact),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatSpec {
  const _StatSpec({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.spec, required this.compact});

  final _StatSpec spec;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${spec.label}: ${spec.value}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: spec.accent.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(SroodProfileDims.innerRadius),
          border: Border.all(color: spec.accent.withValues(alpha: 0.24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(spec.icon, color: spec.accent, size: compact ? 12 : 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: spec.accent,
                      fontSize: compact ? 9.5 : 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              spec.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: SroodProfileColors.textPrimary,
                fontSize: compact ? 13 : 15,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
