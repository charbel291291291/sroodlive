/// Srood Room UI v2 — design system tokens.
///
/// Single source of truth for every visual constant in the room presentation
/// layer. No widget in `presentation/` may hardcode a color, radius, size,
/// duration, or opacity — it must come from here.
///
/// Palette: deep dark purple base, soft neon violet, electric blue, subtle
/// cyan highlights, premium glass surfaces. Minimal glow, high contrast text.
library;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colors
// ─────────────────────────────────────────────────────────────────────────────

abstract final class SroodRoomColors {
  // ── Background scale (deep dark purple) ────────────────────────────────────
  /// Deepest layer — behind everything.
  static const bgDeep = Color(0xFF0A0618);

  /// Primary room background.
  static const bg = Color(0xFF120A26);

  /// Raised background (stage scrim base).
  static const bgRaised = Color(0xFF1A1038);

  // ── Accents ────────────────────────────────────────────────────────────────
  /// Soft neon violet — primary accent (active states, focus, speaking).
  static const violet = Color(0xFFA855F7);

  /// Muted violet for borders and inactive accents.
  static const violetSoft = Color(0xFF7C3AED);

  /// Electric blue — secondary accent (info, links, seat numbers).
  static const electric = Color(0xFF3B82F6);

  /// Subtle cyan — tertiary highlight (live indicators, online count).
  static const cyan = Color(0xFF22D3EE);

  /// Brand gold — kept for host/VIP/coins continuity with the app shell.
  static const gold = Color(0xFFF0C15A);

  // ── Glass surfaces ─────────────────────────────────────────────────────────
  /// Glass fill: white at low alpha over the dark bg.
  static const glassFill = Color(0x14FFFFFF); // white 8%
  /// Stronger glass for sheets/cards.
  static const glassFillStrong = Color(0x1FFFFFFF); // white 12%
  /// Glass border hairline.
  static const glassBorder = Color(0x29FFFFFF); // white 16%
  /// Violet-tinted glass (active surfaces).
  static const glassViolet = Color(0x2EA855F7); // violet 18%

  // ── Text ───────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFF8F7FC);
  static const textSecondary = Color(0xFFC9C3DC);
  static const textMuted = Color(0xFF8E86A8);

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const danger = Color(0xFFF43F5E);
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
  static const live = Color(0xFF4ADE80);

  // ── Seat-specific ──────────────────────────────────────────────────────────
  /// Host seat ring.
  static const seatHost = gold;

  /// Occupied seat ring.
  static const seatOccupied = violetSoft;

  /// Empty seat ring.
  static const seatEmpty = Color(0x3DFFFFFF); // white 24%
  /// Locked seat fill.
  static const seatLocked = Color(0x0FFFFFFF); // white 6%
  /// Seat selected for move.
  static const seatMove = Color(0xFF67E8A5);

  /// Speaking ring (matches violet accent, not resizing the seat).
  static const speaking = cyan;

  /// Muted-mic badge.
  static const mutedMic = danger;

  // ── Scrims / gradients ─────────────────────────────────────────────────────
  static const scrimTop = Color(0xB30A0618); // bgDeep 70%
  static const scrimBottom = Color(0xE60A0618); // bgDeep 90%

  /// Full-room fallback gradient (no custom background image).
  static const bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1E1145), Color(0xFF120A26), Color(0xFF0A0618)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Bottom bar gradient (glass over deep bg).
  static const bottomBarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xCC140B2E), Color(0xF50A0618)],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dimensions
// ─────────────────────────────────────────────────────────────────────────────

abstract final class SroodRoomDims {
  // ── Spacing scale ──────────────────────────────────────────────────────────
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;

  /// Horizontal screen gutter.
  static const double gutter = 14;

  // ── Radius scale ───────────────────────────────────────────────────────────
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 22;

  /// Sheets' top corners.
  static const double radiusSheet = 24;

  /// Fully-rounded pill.
  static const double radiusPill = 999;

  // ── Icon sizes ─────────────────────────────────────────────────────────────
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconAction = 22;

  // ── Text sizes ─────────────────────────────────────────────────────────────
  static const double textXs = 10;
  static const double textSm = 11.5;
  static const double textMd = 13;
  static const double textLg = 15;
  static const double textXl = 17;

  // ── Touch targets ──────────────────────────────────────────────────────────
  /// Minimum interactive target (accessibility floor).
  static const double touchTarget = 44;

  /// Compact visible control size (hit area padded to [touchTarget]).
  static const double controlVisual = 38;

  // ── Borders / glow ─────────────────────────────────────────────────────────
  static const double borderThin = 1.0;
  static const double borderSeat = 1.8;
  static const double borderSeatHost = 2.4;

  /// Single soft glow blur — the only glow strength in the system.
  static const double glowBlur = 14;
  static const double glowSpread = -2;

  // ── Bottom bar / chat zones ────────────────────────────────────────────────
  static const double bottomBarHeight = 56;
  static const double composerHeight = 44;

  /// Chat feed height fraction of screen height, with clamps.
  static const double chatHeightFraction = 0.16;
  static const double chatHeightMin = 96;
  static const double chatHeightMax = 142;
}

// ─────────────────────────────────────────────────────────────────────────────
// Mic seat sizing — fixed shells per layout mode
// ─────────────────────────────────────────────────────────────────────────────

/// Resolved seat metrics for one grid layout mode. Empty and occupied seats
/// always share the exact same shell: [seatSize] outer diameter, [tileWidth] ×
/// [tileHeight] reserved box, [labelAreaHeight] fixed label strip.
@immutable
class SroodSeatSpec {
  const SroodSeatSpec({
    required this.preferred,
    required this.min,
    required this.max,
    required this.columns,
    required this.labelAreaHeight,
  });

  /// Preferred outer seat diameter.
  final double preferred;

  /// Minimum allowed diameter for narrow screens.
  final double min;

  /// Maximum allowed diameter for wide screens.
  final double max;

  /// Grid columns for this seat count.
  final int columns;

  /// Fixed height reserved under the avatar for name/badges — identical for
  /// empty and occupied seats so rows never shift.
  final double labelAreaHeight;

  /// Spec for a given seat count. 6 → 3×2, 8 → 4×2, 9 → 3×3, 12 → 4×3.
  static SroodSeatSpec forSeatCount(int count) {
    if (count <= 6) {
      return const SroodSeatSpec(
        preferred: 80,
        min: 76,
        max: 84,
        columns: 3,
        labelAreaHeight: 42,
      );
    }
    if (count == 8) {
      return const SroodSeatSpec(
        preferred: 76,
        min: 72,
        max: 80,
        columns: 4,
        labelAreaHeight: 38,
      );
    }
    if (count <= 9) {
      return const SroodSeatSpec(
        preferred: 78,
        min: 72,
        max: 80,
        columns: 3,
        labelAreaHeight: 38,
      );
    }
    if (count <= 12) {
      return const SroodSeatSpec(
        preferred: 70,
        min: 68,
        max: 74,
        columns: 4,
        labelAreaHeight: 38,
      );
    }
    return const SroodSeatSpec(
      preferred: 64,
      min: 58,
      max: 68,
      columns: 4,
      labelAreaHeight: 36,
    );
  }

  /// Max reserved tile width (seat + horizontal breathing room).
  double get tileMaxWidth => max + 16;

  /// Max reserved tile height (seat + label strip).
  double get tileMaxHeight => max + labelAreaHeight;
}

// ─────────────────────────────────────────────────────────────────────────────
// Motion
// ─────────────────────────────────────────────────────────────────────────────

abstract final class SroodRoomMotion {
  /// Micro state change (button press, badge swap).
  static const fast = Duration(milliseconds: 140);

  /// Standard transition (banner swap, sheet content).
  static const normal = Duration(milliseconds: 220);

  /// Emphasized entrance (overlays).
  static const slow = Duration(milliseconds: 380);

  /// Looping ambient animation period (speaking ring pulse).
  static const pulse = Duration(milliseconds: 1200);

  static const curve = Curves.easeOutCubic;
  static const curveEmphasized = Curves.easeInOutCubic;
}

// ─────────────────────────────────────────────────────────────────────────────
// Text styles
// ─────────────────────────────────────────────────────────────────────────────

abstract final class SroodRoomText {
  static const title = TextStyle(
    color: SroodRoomColors.textPrimary,
    fontSize: SroodRoomDims.textLg,
    fontWeight: FontWeight.w800,
    height: 1.15,
  );

  static const subtitle = TextStyle(
    color: SroodRoomColors.textSecondary,
    fontSize: SroodRoomDims.textSm,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const body = TextStyle(
    color: SroodRoomColors.textPrimary,
    fontSize: SroodRoomDims.textMd,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static const caption = TextStyle(
    color: SroodRoomColors.textMuted,
    fontSize: SroodRoomDims.textXs,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const seatName = TextStyle(
    color: SroodRoomColors.textPrimary,
    fontSize: SroodRoomDims.textSm,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );

  static const badge = TextStyle(
    color: SroodRoomColors.textPrimary,
    fontSize: 9,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: 0.3,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable decorations
// ─────────────────────────────────────────────────────────────────────────────

abstract final class SroodRoomDecor {
  /// Standard glass panel.
  static BoxDecoration glass({
    double radius = SroodRoomDims.radiusLg,
    bool strong = false,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: strong
          ? SroodRoomColors.glassFillStrong
          : SroodRoomColors.glassFill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? SroodRoomColors.glassBorder,
        width: SroodRoomDims.borderThin,
      ),
    );
  }

  /// Violet-glow accent shadow — the single sanctioned glow.
  static List<BoxShadow> glow(Color color, {double opacity = 0.45}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: SroodRoomDims.glowBlur,
        spreadRadius: SroodRoomDims.glowSpread,
      ),
    ];
  }

  /// Sheet container decoration (top-rounded, deep glass).
  static BoxDecoration sheet(BuildContext context) {
    return const BoxDecoration(
      color: SroodRoomColors.bgRaised,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SroodRoomDims.radiusSheet),
      ),
      border: Border(
        top: BorderSide(color: SroodRoomColors.glassBorder, width: 1),
      ),
    );
  }
}
