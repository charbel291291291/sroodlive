import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared coin design system
//
// Use these widgets anywhere the app shows coins, balances, bet chips, badges,
// or amount labels so every coin treatment looks identical.
// ─────────────────────────────────────────────────────────────────────────────

// ── Palette ───────────────────────────────────────────────────────────────────

const kCoinGoldLight = Color(0xFFFFE566);
const kCoinGoldMid = Color(0xFFF5A820);
const kCoinGoldDark = Color(0xFFC07810);
const kCoinGoldDeep = Color(0xFF8B5E00);
const kCoinRimLight = Color(0xFFFFF0A0);
const kCoinRimDark = Color(0xFFB8760A);
const kCoinTextDark = Color(0xFF3D1F00);
const kCoinGlow = Color(0xFFF5A820);

// ── Format helper (shared) ────────────────────────────────────────────────────

/// Format a coin integer to a compact label: 1200 → "1.2K", 1500000 → "1.5M".
String formatCoinAmount(int v) {
  if (v >= 1000000) {
    final d = v / 1000000;
    return '${d % 1 == 0 ? d.toInt() : d.toStringAsFixed(1)}M';
  }
  if (v >= 1000) {
    final d = v / 1000;
    return '${d % 1 == 0 ? d.toInt() : d.toStringAsFixed(1)}K';
  }
  return '$v';
}

// ─────────────────────────────────────────────────────────────────────────────
// AppCoinIcon
//
// A small golden coin icon that replaces every stray 🪙 emoji and
// `Icons.monetization_on_rounded` usage so they all look identical.
//
// Usage:
//   AppCoinIcon()                   // default 18 px
//   AppCoinIcon(size: 14)           // compact (inside badges)
//   AppCoinIcon(size: 28)           // large (wallet balance card)
// ─────────────────────────────────────────────────────────────────────────────

class AppCoinIcon extends StatelessWidget {
  const AppCoinIcon({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [kCoinGoldLight, kCoinGoldMid, kCoinGoldDark],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: kCoinRimDark,
          width: size > 20 ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: kCoinGlow.withValues(alpha: 0.45),
            blurRadius: size * 0.5,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '₿',
          style: TextStyle(
            fontSize: size * 0.48,
            height: 1,
            color: kCoinTextDark,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CoinAmountText
//
// Shows a coin icon + formatted number in one row.
// Drop-in for any "🪙 1,200" or "1.2K 🪙" pattern.
//
// Usage:
//   CoinAmountText(amount: wallet.coinsBalance)
//   CoinAmountText(amount: betAmount, fontSize: 12, iconSize: 14)
//   CoinAmountText(amount: prize, color: Colors.white, bold: true)
// ─────────────────────────────────────────────────────────────────────────────

class CoinAmountText extends StatelessWidget {
  const CoinAmountText({
    super.key,
    required this.amount,
    this.fontSize = 14,
    this.iconSize,
    this.color = Colors.white,
    this.bold = true,
    this.gap = 4.0,
    this.prefix,
  });

  final int amount;
  final double fontSize;
  final double? iconSize;
  final Color color;
  final bool bold;
  final double gap;
  /// Optional prefix like "+" or "-" prepended to the number.
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final icon = iconSize ?? fontSize * 1.1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppCoinIcon(size: icon),
        SizedBox(width: gap),
        Text(
          '${prefix ?? ''}${formatCoinAmount(amount)}',
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CoinAmountBadge
//
// Pill-shaped badge used on leaderboards, gift prices, bet totals, etc.
//
// Usage:
//   CoinAmountBadge(amount: 2500)
//   CoinAmountBadge(amount: 500, compact: true)  // smaller padding
// ─────────────────────────────────────────────────────────────────────────────

class CoinAmountBadge extends StatelessWidget {
  const CoinAmountBadge({
    super.key,
    required this.amount,
    this.compact = false,
    this.glow = false,
  });

  final int amount;
  final bool compact;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final fs = compact ? 10.0 : 12.0;
    final icon = compact ? 11.0 : 14.0;
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1800), Color(0xFF1A0E00)],
        ),
        border: Border.all(
          color: kCoinGoldMid.withValues(alpha: glow ? 0.85 : 0.55),
          width: glow ? 1.5 : 1.0,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: kCoinGlow.withValues(alpha: 0.35),
                  blurRadius: 8,
                ),
              ]
            : [],
      ),
      child: CoinAmountText(
        amount: amount,
        fontSize: fs,
        iconSize: icon,
        gap: 3,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CoinBalancePill
//
// The standard top-bar balance chip: a rounded pill with the shared coin glyph
// and a compact, consistently-formatted amount. Use it anywhere a screen shows
// the user's coin balance in a header so every game's balance looks identical.
//
// Usage:
//   CoinBalancePill(amount: balance)
//   CoinBalancePill(amount: balance, loading: _loadingWallet)
// ─────────────────────────────────────────────────────────────────────────────

class CoinBalancePill extends StatelessWidget {
  const CoinBalancePill({
    super.key,
    required this.amount,
    this.loading = false,
    this.fontSize = 13,
    this.iconSize = 15,
  });

  final int amount;
  final bool loading;
  final double fontSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1800), Color(0xFF1A0E00)],
        ),
        border: Border.all(color: kCoinGoldMid.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppCoinIcon(size: iconSize),
          const SizedBox(width: 5),
          Text(
            loading ? '…' : formatCoinAmount(amount),
            style: TextStyle(
              color: kCoinGoldLight,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CoinChipButton
//
// The premium coin-chip for bet-amount selectors.
// Used in Hungry Cat, Magic Srood, and any future game with wager chips.
//
// Usage:
//   CoinChipButton(
//     amount: 1000,
//     selected: _betAmount == 1000,
//     disabled: _balance < 1000,
//     onTap: () => setState(() => _betAmount = 1000),
//   )
// ─────────────────────────────────────────────────────────────────────────────

class CoinChipButton extends StatelessWidget {
  const CoinChipButton({
    super.key,
    required this.amount,
    required this.selected,
    required this.disabled,
    required this.onTap,
    this.size = 58.0,
  });

  final int amount;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  /// Outer diameter of the coin chip. Defaults to 58 px.
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = formatCoinAmount(amount);

    final List<Color> gradColors;
    final Color borderColor;
    final double borderWidth;
    final List<BoxShadow> shadows;

    if (selected && !disabled) {
      gradColors = const [kCoinGoldLight, kCoinGoldMid, kCoinGoldDark];
      borderColor = kCoinRimLight;
      borderWidth = 2.5;
      shadows = [
        BoxShadow(
          color: kCoinGlow.withValues(alpha: 0.70),
          blurRadius: 14,
          spreadRadius: 2,
        ),
        BoxShadow(
          color: kCoinGlow.withValues(alpha: 0.30),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    } else if (disabled) {
      gradColors = const [Color(0xFF4A3A20), Color(0xFF2A2010)];
      borderColor = const Color(0xFF6B5030);
      borderWidth = 1.0;
      shadows = [];
    } else {
      gradColors = const [Color(0xFFD4900A), kCoinGoldMid, Color(0xFFA06808)];
      borderColor = kCoinRimDark;
      borderWidth = 1.5;
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.40),
          blurRadius: 6,
          offset: const Offset(0, 3),
        ),
      ];
    }

    return GestureDetector(
      onTap: disabled
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap?.call();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: gradColors,
            stops: const [0.0, 0.55, 1.0],
          ),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: shadows,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Inner rim ring (gives coin depth)
            Container(
              width: size * 0.80,
              height: size * 0.80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: (selected && !disabled)
                      ? kCoinRimLight.withValues(alpha: 0.50)
                      : Colors.black.withValues(alpha: 0.18),
                  width: 1.0,
                ),
              ),
            ),
            // Top-left shine
            Positioned(
              top: size * 0.10,
              left: size * 0.14,
              child: Container(
                width: size * 0.28,
                height: size * 0.14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.08),
                  color: (selected && !disabled)
                      ? Colors.white.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.28),
                ),
              ),
            ),
            // Amount label
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Unified coin glyph (was a raw 🪙 emoji) so every coin in the
                // app renders identically.
                AppCoinIcon(size: size * 0.26),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: size * 0.08),
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: (selected && !disabled)
                            ? kCoinTextDark
                            : disabled
                            ? Colors.white30
                            : Colors.white,
                        fontSize: size * 0.22,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CoinChipRow
//
// A self-contained horizontally-scrollable row of CoinChipButtons.
// Pass the list of amounts, the currently selected amount, the user's balance,
// and a callback — all chip state management lives in the parent.
//
// Usage:
//   CoinChipRow(
//     chips: kBetChips,
//     selected: _betAmount,
//     balance: _balance,
//     locked: !active,
//     chipSize: 54,
//     onSelect: (v) => setState(() => _betAmount = v),
//   )
// ─────────────────────────────────────────────────────────────────────────────

class CoinChipRow extends StatelessWidget {
  const CoinChipRow({
    super.key,
    required this.chips,
    required this.selected,
    required this.balance,
    required this.onSelect,
    this.locked = false,
    this.chipSize = 58.0,
    this.spacing = 6.0,
  });

  final List<int> chips;
  final int selected;
  final int balance;
  final ValueChanged<int> onSelect;
  final bool locked;
  final double chipSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: spacing),
      child: Row(
        children: chips.map((chip) {
          final sel = chip == selected;
          final disabled = locked || (balance < chip && !sel);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing / 2),
            child: CoinChipButton(
              amount: chip,
              selected: sel,
              disabled: disabled,
              size: chipSize,
              onTap: locked ? null : () => onSelect(chip),
            ),
          );
        }).toList(),
      ),
    );
  }
}
