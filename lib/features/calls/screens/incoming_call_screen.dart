import 'dart:async';
import 'package:flutter/material.dart';
import 'audio_call_screen.dart';
import 'video_call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    required this.callId,
    required this.callerName,
    required this.callerAvatarUrl,
    required this.isVideo,
    required this.isArabic,
    super.key,
  });

  final String callId;
  final String callerName;
  final String? callerAvatarUrl;
  final bool isVideo;
  final bool isArabic;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  Timer? _autoDeclineTimer;
  int _countdown = 30;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _autoDeclineTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _decline();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _autoDeclineTimer?.cancel();
    super.dispose();
  }

  void _accept() {
    _autoDeclineTimer?.cancel();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => widget.isVideo
            ? VideoCallScreen(
                callId: widget.callId,
                peerName: widget.callerName,
                peerAvatarUrl: widget.callerAvatarUrl,
                isOutgoing: false,
                isArabic: widget.isArabic,
              )
            : AudioCallScreen(
                callId: widget.callId,
                peerName: widget.callerName,
                peerAvatarUrl: widget.callerAvatarUrl,
                isOutgoing: false,
                isArabic: widget.isArabic,
              ),
      ),
    );
  }

  void _decline() {
    _autoDeclineTimer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.4,
            colors: [Color(0xFF2A0F4A), Color(0xFF08060F), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 48),
              Text(
                isArabic
                    ? (widget.isVideo
                          ? 'مكالمة مرئية واردة'
                          : 'مكالمة صوتية واردة')
                    : (widget.isVideo
                          ? 'Incoming video call'
                          : 'Incoming voice call'),
                style: const TextStyle(
                  color: Color(0xFFBCAED6),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 40),
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF8B26D9),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B26D9).withValues(alpha: 0.4),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: widget.callerAvatarUrl != null
                        ? Image.network(
                            widget.callerAvatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _avatarFallback(),
                          )
                        : _avatarFallback(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.callerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isVideo
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    color: const Color(0xFF9E91B8),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isArabic
                        ? 'ينتهي خلال $_countdown ثانية'
                        : 'Ends in $_countdown seconds',
                    style: const TextStyle(
                      color: Color(0xFF9E91B8),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 48, 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: Icons.call_end_rounded,
                      color: const Color(0xFFFF4D6D),
                      label: isArabic ? 'رفض' : 'Decline',
                      onTap: _decline,
                    ),
                    _CallActionButton(
                      icon: widget.isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: const Color(0xFF2ECC71),
                      label: isArabic ? 'قبول' : 'Accept',
                      onTap: _accept,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: const Color(0xFF241638),
      child: Center(
        child: Text(
          widget.callerName.isNotEmpty
              ? widget.callerName[0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFBCAED6),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
