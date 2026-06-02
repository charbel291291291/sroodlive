import 'package:flutter/material.dart';

class AppViewport extends StatelessWidget {
  const AppViewport({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF08030F),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: child,
        ),
      ),
    );
  }
}
