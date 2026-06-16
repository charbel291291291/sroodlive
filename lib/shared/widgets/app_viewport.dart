import 'package:flutter/material.dart';
import 'floating_room_bar.dart';

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
          child: Stack(
            children: [
              child,
              // Floating mini-bar appears when a room is minimized
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: FloatingRoomBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
