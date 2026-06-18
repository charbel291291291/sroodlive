import 'package:flutter/material.dart';

/// App-wide 3-D button — gradient fill, colored glow, shine highlight.
///
/// Usage:
///   SroodButton(label: 'Join Room', onPressed: ...)           // gold (default)
///   SroodButton.purple(label: 'Send Gift', onPressed: ...)
///   SroodButton.green(label: 'Confirm',   onPressed: ...)
///   SroodButton.red(label: 'Delete',      onPressed: ...)
///   SroodButton.outlined(label: 'Cancel', onPressed: ...)
class SroodButton extends StatefulWidget {
  const SroodButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradTop = const Color(0xFFF0C15A),
    this.gradBot = const Color(0xFF92400E),
    this.glow = const Color(0xFFF0C15A),
    this.labelColor = const Color(0xFF12061F),
    this.width,
    this.height = 52.0,
    this.fontSize = 15.0,
    this.isLoading = false,
    this.outlined = false,
    super.key,
  });

  // ── Named variants ─────────────────────────────────────────────────────────

  factory SroodButton.purple({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    double? width,
    double height = 52,
    double fontSize = 15,
    bool isLoading = false,
    Key? key,
  }) => SroodButton(
    label: label,
    onPressed: onPressed,
    icon: icon,
    gradTop: const Color(0xFF9B59F5),
    gradBot: const Color(0xFF3B0764),
    glow: const Color(0xFF8B5CF6),
    labelColor: Colors.white,
    width: width,
    height: height,
    fontSize: fontSize,
    isLoading: isLoading,
    key: key,
  );

  factory SroodButton.green({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    double? width,
    double height = 52,
    double fontSize = 15,
    bool isLoading = false,
    Key? key,
  }) => SroodButton(
    label: label,
    onPressed: onPressed,
    icon: icon,
    gradTop: const Color(0xFF10B981),
    gradBot: const Color(0xFF064E3B),
    glow: const Color(0xFF34D399),
    labelColor: Colors.white,
    width: width,
    height: height,
    fontSize: fontSize,
    isLoading: isLoading,
    key: key,
  );

  factory SroodButton.red({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    double? width,
    double height = 52,
    double fontSize = 15,
    bool isLoading = false,
    Key? key,
  }) => SroodButton(
    label: label,
    onPressed: onPressed,
    icon: icon,
    gradTop: const Color(0xFFEF4444),
    gradBot: const Color(0xFF7F1D1D),
    glow: const Color(0xFFF87171),
    labelColor: Colors.white,
    width: width,
    height: height,
    fontSize: fontSize,
    isLoading: isLoading,
    key: key,
  );

  factory SroodButton.blue({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    double? width,
    double height = 52,
    double fontSize = 15,
    bool isLoading = false,
    Key? key,
  }) => SroodButton(
    label: label,
    onPressed: onPressed,
    icon: icon,
    gradTop: const Color(0xFF3B82F6),
    gradBot: const Color(0xFF1E3A8A),
    glow: const Color(0xFF60A5FA),
    labelColor: Colors.white,
    width: width,
    height: height,
    fontSize: fontSize,
    isLoading: isLoading,
    key: key,
  );

  factory SroodButton.outlined({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    double? width,
    double height = 52,
    double fontSize = 15,
    Key? key,
  }) => SroodButton(
    label: label,
    onPressed: onPressed,
    icon: icon,
    gradTop: const Color(0xFFF0C15A).withValues(alpha: 0.12),
    gradBot: const Color(0xFF92400E).withValues(alpha: 0.06),
    glow: Colors.transparent,
    labelColor: const Color(0xFFF0C15A),
    outlined: true,
    width: width,
    height: height,
    fontSize: fontSize,
    key: key,
  );

  // ── Properties ──────────────────────────────────────────────────────────────

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color gradTop;
  final Color gradBot;
  final Color glow;
  final Color labelColor;
  final double? width;
  final double height;
  final double fontSize;
  final bool isLoading;
  final bool outlined;

  @override
  State<SroodButton> createState() => _SroodButtonState();
}

class _SroodButtonState extends State<SroodButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.isLoading;

    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: disabled
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: disabled ? 0.48 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [widget.gradTop, widget.gradBot],
              ),
              boxShadow: disabled || _pressed
                  ? []
                  : [
                      BoxShadow(
                        color: widget.glow.withValues(alpha: 0.55),
                        blurRadius: 14,
                        spreadRadius: 0,
                        offset: const Offset(0, 5),
                      ),
                      BoxShadow(
                        color: widget.glow.withValues(alpha: 0.20),
                        blurRadius: 6,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
              border: Border.all(
                color: widget.outlined
                    ? const Color(0xFFF0C15A).withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.22),
                width: widget.outlined ? 1.4 : 0.8,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 3D shine highlight — top-left
                if (!disabled && !widget.outlined)
                  Positioned(
                    top: 5,
                    left: 14,
                    child: Container(
                      width: 50,
                      height: 9,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.32),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Bottom-right depth shadow
                if (!disabled && !widget.outlined)
                  Positioned(
                    bottom: 5,
                    right: 14,
                    child: Container(
                      width: 40,
                      height: 7,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.0),
                            Colors.black.withValues(alpha: 0.18),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Content
                if (widget.isLoading)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.labelColor,
                      ),
                    ),
                  )
                else if (widget.icon != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 19, color: widget.labelColor),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.labelColor,
                            fontSize: widget.fontSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.labelColor,
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
