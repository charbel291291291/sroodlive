/// Srood profile page design tokens — deep dark purple base, soft violet
/// gradients, controlled gold accents, minimal glow. Gold is reserved for
/// premium/VIP/edit affordances; each stat category gets exactly one
/// desaturated accent.
library;

import 'package:flutter/material.dart';

abstract final class SroodProfileColors {
  // Background scale
  static const bgTop = Color(0xFF12061F);
  static const bgMid = Color(0xFF07030D);
  static const bgBottom = Color(0xFF050208);

  // Card surfaces
  static const card = Color(0xFF160B26);
  static const cardRaised = Color(0xFF1E0D36);
  static const cardBorder = Color(0x338B5CF6); // violet 20%
  static const glassFill = Color(0x12FFFFFF); // white 7%

  // Accents
  static const violet = Color(0xFF9C4DFF);
  static const violetSoft = Color(0xFF7C3AED);
  static const gold = Color(0xFFF0C15A);

  // Category accents — desaturated single hues
  static const charm = Color(0xFFD4699E);
  static const wealth = Color(0xFFC9A24B);
  static const genderMale = Color(0xFF5B9BE6);
  static const genderFemale = Color(0xFFE07A9E);

  // Text
  static const textPrimary = Color(0xFFF5F2FA);
  static const textSecondary = Color(0xFFBCAED6);
  static const textMuted = Color(0xFF8E82A6);

  /// Card gradient used by the hero and major cards.
  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF241040), Color(0xFF140A24), Color(0xFF190B2C)],
    stops: [0.0, 0.55, 1.0],
  );
}

abstract final class SroodProfileDims {
  static const double gutter = 16;
  static const double sectionGap = 14;
  static const double cardRadius = 22;
  static const double innerRadius = 14;
  static const double chipRadius = 999;
  static const double touchTarget = 44;

  /// Shared height for the header's country + VIP identity chips.
  static const double identityChipHeight = 44;

  /// Fixed avatar shell diameter for the centered identity header,
  /// responsive between phones but never driven by the frame art.
  static double avatarShell(double maxWidth) {
    if (maxWidth <= 340) return 108;
    if (maxWidth <= 400) return 116;
    return 124;
  }
}

abstract final class SroodProfileText {
  static const displayName = TextStyle(
    color: SroodProfileColors.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w900,
    height: 1.1,
  );

  static const sectionValue = TextStyle(
    color: SroodProfileColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w900,
    height: 1.1,
  );

  static const label = TextStyle(
    color: SroodProfileColors.textSecondary,
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const caption = TextStyle(
    color: SroodProfileColors.textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  static const body = TextStyle(
    color: SroodProfileColors.textSecondary,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );
}

/// Shared glass card decoration for profile sections.
BoxDecoration sroodProfileCard({bool raised = false, Color? borderColor}) {
  return BoxDecoration(
    gradient: raised ? SroodProfileColors.cardGradient : null,
    color: raised ? null : SroodProfileColors.card.withValues(alpha: 0.92),
    borderRadius: BorderRadius.circular(SroodProfileDims.cardRadius),
    border: Border.all(
      color: borderColor ?? SroodProfileColors.cardBorder,
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF8B26D9).withValues(alpha: raised ? 0.18 : 0.10),
        blurRadius: 10,
        offset: const Offset(0, 6),
      ),
    ],
  );
}
