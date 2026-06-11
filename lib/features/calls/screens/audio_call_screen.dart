import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';

class AudioCallScreen extends StatefulWidget {
  const AudioCallScreen({
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
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen>
    with TickerProviderStateMixin {
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isConnected = false;
  bool _isEnding = false;
  Duration _duration = Duration.zero;
  Timer? _durationTimer;

  late final AnimationController _waveController;
  late final Animation<double> _waveAnim;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _waveAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.easeInOut),
    );

    _connectCall();
  }

  @override
  void dispose() {
    _waveController.dispose();
    _durationTimer?.cancel();
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
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0530), Color(0xFF08060F), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 32),
              Text(
                _isConnected
                    ? _formatDuration(_duration)
                    : (isArabic ? 'جارٍ الاتصال...' : 'Calling...'),
                style: TextStyle(
                  color: _isConnected
                      ? const Color(0xFF63E6A1)
                      : const Color(0xFF9E91B8),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 40),
              AnimatedBuilder(
                animation: _waveAnim,
                builder: (_, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!_isConnected) ...[
                        Container(
                          width: 160 * _waveAnim.value,
                          height: 160 * _waveAnim.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(
                                0xFF8B26D9,
                              ).withValues(alpha: 0.25),
                              width: 1.5,
                            ),
                          ),
                        ),
                        Container(
                          width: 140 * _waveAnim.value,
                          height: 140 * _waveAnim.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(
                                0xFF8B26D9,
                              ).withValues(alpha: 0.15),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ],
                      child!,
                    ],
                  );
                },
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isConnected
                          ? const Color(0xFF63E6A1)
                          : const Color(0xFF8B26D9),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isConnected
                                    ? const Color(0xFF63E6A1)
                                    : const Color(0xFF8B26D9))
                                .withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: widget.peerAvatarUrl != null
                        ? Image.network(
                            widget.peerAvatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _avatarFallback(),
                          )
                        : _avatarFallback(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.peerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isArabic ? 'مكالمة صوتية' : 'Voice call',
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SmallCallButton(
                      icon: _isMuted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      label: isArabic
                          ? (_isMuted ? 'إلغاء كتم' : 'كتم')
                          : (_isMuted ? 'Unmute' : 'Mute'),
                      active: _isMuted,
                      onTap: () => setState(() => _isMuted = !_isMuted),
                    ),
                    _SmallCallButton(
                      icon: _isSpeakerOn
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded,
                      label: isArabic
                          ? (_isSpeakerOn ? 'سماعة' : 'مكبر')
                          : (_isSpeakerOn ? 'Earpiece' : 'Speaker'),
                      active: _isSpeakerOn,
                      onTap: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 48, 56),
                child: GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4D6D),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFFF4D6D,
                          ).withValues(alpha: 0.45),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.call_end_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
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
          widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 44,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _SmallCallButton extends StatelessWidget {
  const _SmallCallButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF3A174F) : const Color(0xFF1B102B),
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? const Color(0xFF8B26D9)
                    : const Color(0xFF4A3470),
              ),
            ),
            child: Icon(
              icon,
              color: active ? const Color(0xFFF0C15A) : const Color(0xFFBCAED6),
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
