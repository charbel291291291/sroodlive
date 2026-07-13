/// Compact login top bar (back + centered title) and the brand block
/// (wordmark + subtitle) — clearly separated, never overlapping, sized so
/// the form stays above the fold on short screens.
library;

import 'package:flutter/material.dart';

class SroodLoginHeader extends StatelessWidget {
  const SroodLoginHeader({required this.isArabic, super.key});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (canPop)
            PositionedDirectional(
              start: 4,
              child: Semantics(
                label: isArabic ? 'رجوع' : 'Back',
                button: true,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          Text(
            isArabic ? 'تسجيل الدخول' : 'Login',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }
}

class SroodLoginBrand extends StatelessWidget {
  const SroodLoginBrand({required this.isArabic, super.key});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Wordmark — compact, gold, never pushes the form down.
        Text(
          'Srood Live',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFF0C15A),
            fontSize: 34,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: 0.5,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          isArabic ? 'ادخل إلى عالم Srood Live' : 'Enter your Srood Live world',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFBCAED6).withValues(alpha: 0.88),
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.4,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
