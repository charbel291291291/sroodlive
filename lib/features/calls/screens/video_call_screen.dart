import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({
    required this.callId,
    required this.peerName,
    required this.peerAvatarUrl,
    required this.isOutgoing,
    required this.isArabic,
    super.key,
  });

  final String callId;
  final String peerName;
  final String? peerAvatarUrl;
  final bool isOutgoing;
  final bool isArabic;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isConnected = false;
  bool _isEnding = false;
  bool _controlsVisible = true;
  Duration _duration = Duration.zero;
  Timer? _durationTimer;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _connectCall();
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _controlsTimer?.cancel();
    super.dispose();
  }

  Future<void> _connectCall() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _isConnected = true);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _duration += const Duration(seconds: 1));
    });
  }

  void _scheduleHideControls() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  Future<void> _endCall() async {
    if (_isEnding) return;
    setState(() => _isEnding = true);
    _durationTimer?.cancel();

    try {
      await SupabaseService.requiredClient
          .from('calls')
          .update({
            'ended_at': DateTime.now().toIso8601String(),
            'duration_seconds': _duration.inSeconds,
          })
          .eq('id', widget.callId);
    } catch (_) {}

    if (mounted) Navigator.of(context).pop();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Remote video background (placeholder)
            Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFF0D0815),
              child: _isConnected && !_isCameraOff
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 64,
                            backgroundColor: const Color(0xFF241638),
                            backgroundImage: widget.peerAvatarUrl != null
                                ? NetworkImage(widget.peerAvatarUrl!)
                                : null,
                            child: widget.peerAvatarUrl == null
                                ? Text(
                                    widget.peerName.isNotEmpty
                                        ? widget.peerName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 52,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            widget.peerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (!_isConnected) ...[
                            const SizedBox(height: 8),
                            Text(
                              isArabic ? 'جارٍ الاتصال...' : 'Calling...',
                              style: const TextStyle(
                                color: Color(0xFF9E91B8),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B102B),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF4A3470),
                              ),
                            ),
                            child: const Icon(
                              Icons.videocam_off_rounded,
                              color: Color(0xFF9E91B8),
                              size: 46,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            isArabic ? 'الكاميرا مغلقة' : 'Camera off',
                            style: const TextStyle(
                              color: Color(0xFF9E91B8),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // Self preview (bottom-right)
            Positioned(
              right: 16,
              bottom: 140,
              child: Container(
                width: 90,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF241638),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF8B26D9),
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Center(
                    child: Icon(
                      _isCameraOff
                          ? Icons.videocam_off_rounded
                          : Icons.person_rounded,
                      color: const Color(0xFF9E91B8),
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),

            // Top status bar
            AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xBB000000), Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: Row(
                      textDirection: isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      children: [
                        IconButton(
                          onPressed: _endCall,
                          icon: Icon(
                            isArabic
                                ? Icons.arrow_forward_rounded
                                : Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _isConnected
                              ? _formatDuration(_duration)
                              : (isArabic ? 'جارٍ الاتصال...' : 'Calling...'),
                          style: TextStyle(
                            color: _isConnected
                                ? const Color(0xFF63E6A1)
                                : const Color(0xFFBCAED6),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _VideoCallButton(
                            icon: _isMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            active: _isMuted,
                            onTap: () => setState(() => _isMuted = !_isMuted),
                          ),
                          GestureDetector(
                            onTap: _endCall,
                            child: Container(
                              width: 66,
                              height: 66,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF4D6D),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFF4D6D,
                                    ).withValues(alpha: 0.45),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.call_end_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                          _VideoCallButton(
                            icon: _isCameraOff
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_rounded,
                            active: _isCameraOff,
                            onTap: () =>
                                setState(() => _isCameraOff = !_isCameraOff),
                          ),
                          _VideoCallButton(
                            icon: Icons.cameraswitch_rounded,
                            active: false,
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoCallButton extends StatelessWidget {
  const _VideoCallButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF3A174F)
              : Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? const Color(0xFF8B26D9)
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Icon(
          icon,
          color: active ? const Color(0xFFF0C15A) : Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
