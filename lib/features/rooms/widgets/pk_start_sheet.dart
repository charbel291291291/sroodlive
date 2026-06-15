import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/room_member.dart';
import '../services/team_pk_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PkStartSheet — host configures and launches a Team PK battle.
// ─────────────────────────────────────────────────────────────────────────────

class PkStartSheet extends StatefulWidget {
  const PkStartSheet({
    required this.roomId,
    required this.micMembers,
    required this.isArabic,
    super.key,
  });

  final String roomId;
  // All members currently on a mic seat (host + speakers).
  final List<RoomMember> micMembers;
  final bool isArabic;

  @override
  State<PkStartSheet> createState() => _PkStartSheetState();
}

class _PkStartSheetState extends State<PkStartSheet> {
  static const _kRed = Color(0xFFE63946);
  static const _kBlue = Color(0xFF3D8EF0);
  static const _kBg = Color(0xFF160C2F);

  static const _durations = [
    (label: '5 min', seconds: 300),
    (label: '10 min', seconds: 600),
    (label: '30 min', seconds: 1800),
  ];

  final _service = const TeamPkService();
  int _selectedDuration = 300; // default 5 min
  // userId → team ('a' or 'b')
  final Map<String, String> _assignments = {};
  bool _loading = false;
  String? _error;

  String _t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _autoSplit();
  }

  void _autoSplit() {
    final members = widget.micMembers;
    _assignments.clear();
    for (var i = 0; i < members.length; i++) {
      _assignments[members[i].userId] = i < (members.length / 2).ceil() ? 'a' : 'b';
    }
  }

  void _toggleTeam(String userId) {
    setState(() {
      _assignments[userId] = _assignments[userId] == 'a' ? 'b' : 'a';
    });
  }

  List<RoomMember> get _teamA =>
      widget.micMembers.where((m) => _assignments[m.userId] == 'a').toList();
  List<RoomMember> get _teamB =>
      widget.micMembers.where((m) => _assignments[m.userId] == 'b').toList();

  bool get _canStart =>
      _teamA.isNotEmpty && _teamB.isNotEmpty && !_loading;

  Future<void> _startPk() async {
    if (!_canStart) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _service.startPk(
        roomId: widget.roomId,
        durationSeconds: _selectedDuration,
        autoAssign: true,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _t('فشل بدء المنافسة', 'Failed to start PK');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF231440), _kBg],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Title
          Text(
            _t('منافسة الفرق', 'Team PK'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 18),

          // Duration selector
          Text(
            _t('مدة المنافسة', 'Duration'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _durations.map((d) {
              final selected = d.seconds == _selectedDuration;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedDuration = d.seconds),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: selected
                          ? const Color(0xFF8B26D9)
                          : Colors.white.withValues(alpha: 0.07),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF8B26D9)
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      d.label,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Team assignment
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Team A
              Expanded(
                child: _TeamColumn(
                  label: _t('الفريق أ', 'Team A'),
                  color: _kRed,
                  members: _teamA,
                  onTap: _toggleTeam,
                  isArabic: widget.isArabic,
                ),
              ),
              // VS divider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                      child: Text(
                        'VS',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Team B
              Expanded(
                child: _TeamColumn(
                  label: _t('الفريق ب', 'Team B'),
                  color: _kBlue,
                  members: _teamB,
                  onTap: _toggleTeam,
                  isArabic: widget.isArabic,
                ),
              ),
            ],
          ),

          // Auto split button
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              setState(_autoSplit);
              HapticFeedback.selectionClick();
            },
            child: Text(
              _t('توزيع تلقائي', 'Auto Split'),
              style: TextStyle(
                color: const Color(0xFF8B26D9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: _kRed, fontSize: 12),
            ),
          ],

          const SizedBox(height: 20),

          // Start button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _canStart
                    ? const Color(0xFF8B26D9)
                    : Colors.white.withValues(alpha: 0.1),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _canStart ? _startPk : null,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _t('بدء المنافسة', 'Start PK'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.label,
    required this.color,
    required this.members,
    required this.onTap,
    required this.isArabic,
  });

  final String label;
  final Color color;
  final List<RoomMember> members;
  final void Function(String userId) onTap;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              isArabic ? 'لا أحد' : 'Nobody',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 11,
              ),
            ),
          )
        else
          for (final m in members)
            GestureDetector(
              onTap: () => onTap(m.userId),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          color.withValues(alpha: 0.2),
                      backgroundImage: m.avatarUrl != null
                          ? NetworkImage(m.avatarUrl!)
                          : null,
                      child: m.avatarUrl == null
                          ? Icon(Icons.person_rounded,
                              size: 14, color: color)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        m.displayName ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
