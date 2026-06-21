import 'package:flutter/material.dart';

// =============================================================================
// Shared premium "3D glossy" UI helpers — reusable so decoration code is not
// duplicated across buttons and cards. Colors are passed in by callers, so each
// surface keeps the app's existing identity (gold for coins, purple/pink for
// diamonds, gold for primary buttons, etc.). This file defines NO fixed brand
// colors of its own.
// =============================================================================

/// A glossy, beveled, 3D-raised capsule button.
///
/// - [filled] true  → solid gradient (primary). [accent] is the fill base.
/// - [filled] false → translucent tinted glass with an [accent] outline.
/// Keeps standard button behavior: [onPressed] null disables it; [loading]
/// shows a spinner. Tap feedback via InkWell ripple.
class GlossyButton extends StatelessWidget {
  const GlossyButton({
    required this.label,
    required this.onPressed,
    required this.accent,
    this.icon,
    this.leading,
    this.filled = true,
    this.loading = false,
    this.height = 54,
    this.foreground,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color accent;
  final IconData? icon;
  final Widget? leading;
  final bool filled;
  final bool loading;
  final double height;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(height / 2); // full pill

    // Foreground (label/icon) color.
    final fg = foreground ??
        (filled ? const Color(0xFF1A1208) : accent);

    final gradient = filled
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(accent, Colors.white, 0.45)!, // top sheen
              accent,
              Color.lerp(accent, Colors.black, 0.28)!, // bottom bevel
            ],
            stops: const [0.0, 0.55, 1.0],
          )
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0.18),
              accent.withValues(alpha: 0.06),
            ],
          );

    final opacity = enabled ? 1.0 : 0.45;

    return Opacity(
      opacity: opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: gradient,
          border: Border.all(
            color: filled
                ? Colors.white.withValues(alpha: 0.55)
                : accent.withValues(alpha: 0.65),
            width: filled ? 1.0 : 1.4,
          ),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.40),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: radius,
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  // Top inner highlight — the "gloss".
                  Positioned(
                    top: 1.5,
                    left: 10,
                    right: 10,
                    child: Container(
                      height: height * 0.34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(height),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: filled ? 0.40 : 0.14),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: loading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: fg,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (leading != null) ...[
                                leading!,
                                const SizedBox(width: 10),
                              ] else if (icon != null) ...[
                                Icon(icon, size: 20, color: fg),
                                const SizedBox(width: 9),
                              ],
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
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

/// Premium "3D glossy" card decoration. [base] drives the identity colour
/// (gold for coins, purple/pink for diamonds). Returns a BoxDecoration with a
/// vertical sheen→base→bevel gradient, a soft tinted shadow and a light rim.
BoxDecoration premiumCardDecoration({
  required Color base,
  double radius = 22,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(base, Colors.white, 0.32)!,
        base,
        Color.lerp(base, Colors.black, 0.42)!,
      ],
      stops: const [0.0, 0.5, 1.0],
    ),
    border: Border.all(color: Colors.white.withValues(alpha: 0.30), width: 1),
    boxShadow: [
      BoxShadow(
        color: base.withValues(alpha: 0.40),
        blurRadius: 22,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

/// A soft top sheen overlay to lay over a premium card (inside a ClipRRect).
class GlossSheen extends StatelessWidget {
  const GlossSheen({this.opacity = 0.22, super.key});
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FractionallySizedBox(
        widthFactor: 1,
        heightFactor: 0.5,
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: opacity),
                Colors.white.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
