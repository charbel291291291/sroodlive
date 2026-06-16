import re, sys

path = r'C:\Users\user\Documents\Dev\srood_live\lib\features\rooms\screens\room_details_screen.dart'

with open(path, 'r', encoding='utf-8') as f:
    src = f.read()

changes = []

# ── 1. Gift callback: refresh PK scores after gift events ──────────────────
old1 = (
    '            Future.delayed(const Duration(milliseconds: 400), () {\n'
    '              if (!mounted) return;\n'
    '              unawaited(\n'
    '                _loadRoomGifts(showLoading: false, showNewestBanner: true),\n'
    '              );\n'
    '            });'
)
new1 = (
    '            Future.delayed(const Duration(milliseconds: 400), () {\n'
    '              if (!mounted) return;\n'
    '              unawaited(\n'
    '                _loadRoomGifts(showLoading: false, showNewestBanner: true),\n'
    '              );\n'
    '              // When PK is active, refresh team scores after every gift.\n'
    '              if (_activePk?.isActive == true) unawaited(_loadActivePk());\n'
    '            });'
)
changes.append((old1, new1, 'gift callback PK refresh'))

# ── 2. _SeatGrid._buildRow: pkTeamColor → pkTeam ──────────────────────────
old2 = (
    '                pkTeamColor: pkSeatTeamColor(\n'
    "                    row[c].member?.userId ?? '', activePk),"
)
new2 = (
    '                pkTeam: pkSeatTeam(\n'
    "                    row[c].member?.userId ?? '', activePk),"
)
changes.append((old2, new2, '_SeatGrid pkTeam'))

# ── 3. _LiveSeatBubble constructor + field: pkTeamColor → pkTeam ──────────
old3 = (
    '    this.pkTeamColor,\n'
    '  });\n'
    '\n'
    '  final _StageSeat seat;\n'
    '  final bool isArabic;\n'
    '  final bool isHost;\n'
    '  final bool isSpeaking;\n'
    '  final ValueChanged<int> onEmptySeatTap;\n'
    '  final void Function(RoomMember member, int seatNumber) onOccupiedSeatTap;\n'
    '  final void Function(RoomMember member, int seatNumber)\n'
    '  onOccupiedSeatLongPress;\n'
    '  final ValueChanged<String> onProfileTap;\n'
    '  final bool selectedForMove;\n'
    '  // Non-null when a PK is active and this seat belongs to a team.\n'
    '  final Color? pkTeamColor;'
)
new3 = (
    '    this.pkTeam,\n'
    '  });\n'
    '\n'
    '  final _StageSeat seat;\n'
    '  final bool isArabic;\n'
    '  final bool isHost;\n'
    '  final bool isSpeaking;\n'
    '  final ValueChanged<int> onEmptySeatTap;\n'
    '  final void Function(RoomMember member, int seatNumber) onOccupiedSeatTap;\n'
    '  final void Function(RoomMember member, int seatNumber)\n'
    '  onOccupiedSeatLongPress;\n'
    '  final ValueChanged<String> onProfileTap;\n'
    '  final bool selectedForMove;\n'
    "  // 'a', 'b', or null — non-null only when PK is active and seat is assigned.\n"
    '  final String? pkTeam;'
)
changes.append((old3, new3, '_LiveSeatBubble field'))

# ── 4. Badge computation + pkColor declaration ─────────────────────────────
# File stores Arabic as Dart \uXXXX escapes (literal backslash sequences).
# The badge block in the file (from repr output):
#   final badge = selectedForMove
#       ? (isArabic ? 'نقل' : 'Move')
#       : seat.isEmpty
#           ? ''   // No badge on empty seats — seat number in circle is enough
#           : occupiedByHost
#               ? (isArabic ? 'مضيف' : 'Host')
#               : '';
old4 = (
    "    // Only show badge for important states; suppress \"Tap\" to reduce noise.\n"
    "    final badge = selectedForMove\n"
    "        ? (isArabic ? '\\u0646\\u0642\\u0644' : 'Move')\n"
    "        : seat.isEmpty\n"
    "            ? ''   // No badge on empty seats \\u2014 seat number in circle is enough\n"
    "            : occupiedByHost\n"
    "                ? (isArabic ? '\\u0645\\u0636\\u064a\\u0641' : 'Host')\n"
    "                : '';"
)
new4 = (
    "    // Team color derived from pkTeam ('a'=red, 'b'=blue, null=no PK).\n"
    "    final Color? pkColor = pkTeam == 'a'\n"
    "        ? kPkRed\n"
    "        : pkTeam == 'b'\n"
    "            ? kPkBlue\n"
    "            : null;\n"
    "\n"
    "    // Only show badge for important states; suppress \"Tap\" to reduce noise.\n"
    "    final badge = selectedForMove\n"
    "        ? (isArabic ? '\\u0646\\u0642\\u0644' : 'Move')\n"
    "        : seat.isEmpty\n"
    "            ? ''   // No badge on empty seats \\u2014 seat number in circle is enough\n"
    "            : occupiedByHost\n"
    "                ? (isArabic ? '\\u0645\\u0636\\u064a\\u0641' : 'Host')\n"
    "                : pkTeam == 'a'\n"
    "                    ? 'A'\n"
    "                    : pkTeam == 'b'\n"
    "                        ? 'B'\n"
    "                        : '';"
)
changes.append((old4, new4, 'pkColor + badge team labels'))

# ── 5. Border color: use pkColor for PK seats ─────────────────────────────
old5 = (
    '    final Color borderColor = selectedForMove\n'
    '        ? const Color(0xFF67E8A5)\n'
    '        : occupiedByHost\n'
    '            ? const Color(0xFFF0C15A)\n'
    '            : seat.isEmpty\n'
    '                ? Colors.white.withValues(alpha: 0.26)\n'
    '                : const Color(0xFF8B26D9).withValues(alpha: 0.55);'
)
new5 = (
    '    final Color borderColor = selectedForMove\n'
    '        ? const Color(0xFF67E8A5)\n'
    '        : occupiedByHost\n'
    '            ? const Color(0xFFF0C15A)\n'
    '            : seat.isEmpty\n'
    '                ? Colors.white.withValues(alpha: 0.26)\n'
    '                : pkColor != null\n'
    '                    ? pkColor.withValues(alpha: 0.85)\n'
    '                    : const Color(0xFF8B26D9).withValues(alpha: 0.55);'
)
changes.append((old5, new5, 'border color pkColor'))

# ── 6. Glow shadows: use pkColor for PK seats ─────────────────────────────
old6 = (
    '      ] else if (!seat.isEmpty) ...[\n'
    '        BoxShadow(\n'
    '          color: const Color(0xFF8B26D9).withValues(alpha: 0.45),\n'
    '          blurRadius: 14,\n'
    '          spreadRadius: 0,\n'
    '        ),\n'
    '        BoxShadow(\n'
    '          color: const Color(0xFF8B26D9).withValues(alpha: 0.20),\n'
    '          blurRadius: 26,\n'
    '          spreadRadius: 3,\n'
    '        ),\n'
    '      ],\n'
    '    ];'
)
new6 = (
    '      ] else if (!seat.isEmpty) ...[\n'
    '        if (pkColor != null) ...[\n'
    '          BoxShadow(\n'
    '            color: pkColor.withValues(alpha: 0.55),\n'
    '            blurRadius: 18,\n'
    '            spreadRadius: 1,\n'
    '          ),\n'
    '          BoxShadow(\n'
    '            color: pkColor.withValues(alpha: 0.25),\n'
    '            blurRadius: 32,\n'
    '            spreadRadius: 3,\n'
    '          ),\n'
    '        ] else ...[\n'
    '          BoxShadow(\n'
    '            color: const Color(0xFF8B26D9).withValues(alpha: 0.45),\n'
    '            blurRadius: 14,\n'
    '            spreadRadius: 0,\n'
    '          ),\n'
    '          BoxShadow(\n'
    '            color: const Color(0xFF8B26D9).withValues(alpha: 0.20),\n'
    '            blurRadius: 26,\n'
    '            spreadRadius: 3,\n'
    '          ),\n'
    '        ],\n'
    '      ],\n'
    '    ];'
)
changes.append((old6, new6, 'glow shadows pkColor'))

# ── 7. Pulse ring: pkTeamColor → pkColor ─────────────────────────────────
old7 = (
    '                      // PK team pulse ring (shown behind avatar during active PK).\n'
    '                      if (pkTeamColor != null)\n'
    '                        IgnorePointer(\n'
    '                          child: PkPulseRing(\n'
    '                            color: pkTeamColor!,\n'
    '                            radius: outerSize / 2 + 4,\n'
    '                          ),\n'
    '                        ),'
)
new7 = (
    '                      // PK team pulse ring (shown behind avatar during active PK).\n'
    '                      if (pkColor != null)\n'
    '                        IgnorePointer(\n'
    '                          child: PkPulseRing(\n'
    '                            color: pkColor,\n'
    '                            radius: outerSize / 2 + 4,\n'
    '                          ),\n'
    '                        ),'
)
changes.append((old7, new7, 'pulse ring pkColor'))

# ── 8. Zone 4 badge: use pkColor for team badge styling ───────────────────
old8 = (
    '        SizedBox(\n'
    '          height: 18,\n'
    '          child: badge.isEmpty\n'
    '              ? null\n'
    '              : Center(\n'
    '                  child: Container(\n'
    '                    padding: const EdgeInsets.symmetric(\n'
    '                      horizontal: _micSeatBadgeHorizontalPadding,\n'
    '                      vertical: 1,\n'
    '                    ),\n'
    '                    decoration: BoxDecoration(\n'
    '                      color: selectedForMove\n'
    '                          ? const Color(0xFF67E8A5).withValues(alpha: 0.20)\n'
    '                          : occupiedByHost\n'
    '                              ? const Color(0xFFF0C15A).withValues(alpha: 0.18)\n'
    '                              : const Color(0xFF8B26D9).withValues(alpha: 0.15),\n'
    '                      borderRadius: BorderRadius.circular(999),\n'
    '                      border: Border.all(\n'
    '                        color: selectedForMove\n'
    '                            ? const Color(0xFF67E8A5).withValues(alpha: 0.8)\n'
    '                            : occupiedByHost\n'
    '                                ? const Color(0xFFF0C15A).withValues(alpha: 0.7)\n'
    '                                : const Color(0xFF8B26D9).withValues(alpha: 0.4),\n'
    '                        width: 0.7,\n'
    '                      ),\n'
    '                    ),\n'
    '                    child: Text(\n'
    '                      badge,\n'
    '                      maxLines: 1,\n'
    '                      overflow: TextOverflow.ellipsis,\n'
    '                      textAlign: TextAlign.center,\n'
    '                      style: TextStyle(\n'
    '                        fontSize: 8,\n'
    '                        fontWeight: FontWeight.w900,\n'
    '                        color: selectedForMove\n'
    '                            ? const Color(0xFF67E8A5)\n'
    '                            : occupiedByHost\n'
    '                                ? const Color(0xFFF0C15A)\n'
    '                                : Colors.white.withValues(alpha: 0.75),\n'
    '                        shadows: const [\n'
    '                          Shadow(blurRadius: 4, color: Colors.black),\n'
    '                        ],\n'
    '                      ),\n'
    '                    ),\n'
    '                  ),\n'
    '                ),\n'
    '        ),'
)
new8 = (
    '        SizedBox(\n'
    '          height: 18,\n'
    '          child: badge.isEmpty\n'
    '              ? null\n'
    '              : Center(\n'
    '                  child: Container(\n'
    '                    padding: const EdgeInsets.symmetric(\n'
    '                      horizontal: _micSeatBadgeHorizontalPadding,\n'
    '                      vertical: 1,\n'
    '                    ),\n'
    '                    decoration: BoxDecoration(\n'
    '                      color: selectedForMove\n'
    '                          ? const Color(0xFF67E8A5).withValues(alpha: 0.20)\n'
    '                          : occupiedByHost\n'
    '                              ? const Color(0xFFF0C15A).withValues(alpha: 0.18)\n'
    '                              : pkColor != null\n'
    '                                  ? pkColor.withValues(alpha: 0.22)\n'
    '                                  : const Color(0xFF8B26D9).withValues(alpha: 0.15),\n'
    '                      borderRadius: BorderRadius.circular(999),\n'
    '                      border: Border.all(\n'
    '                        color: selectedForMove\n'
    '                            ? const Color(0xFF67E8A5).withValues(alpha: 0.8)\n'
    '                            : occupiedByHost\n'
    '                                ? const Color(0xFFF0C15A).withValues(alpha: 0.7)\n'
    '                                : pkColor != null\n'
    '                                    ? pkColor.withValues(alpha: 0.85)\n'
    '                                    : const Color(0xFF8B26D9).withValues(alpha: 0.4),\n'
    '                        width: pkColor != null ? 1.0 : 0.7,\n'
    '                      ),\n'
    '                    ),\n'
    '                    child: Text(\n'
    '                      badge,\n'
    '                      maxLines: 1,\n'
    '                      overflow: TextOverflow.ellipsis,\n'
    '                      textAlign: TextAlign.center,\n'
    '                      style: TextStyle(\n'
    '                        fontSize: 8,\n'
    '                        fontWeight: FontWeight.w900,\n'
    '                        color: selectedForMove\n'
    '                            ? const Color(0xFF67E8A5)\n'
    '                            : occupiedByHost\n'
    '                                ? const Color(0xFFF0C15A)\n'
    '                                : pkColor ?? Colors.white.withValues(alpha: 0.75),\n'
    '                        shadows: const [\n'
    '                          Shadow(blurRadius: 4, color: Colors.black),\n'
    '                        ],\n'
    '                      ),\n'
    '                    ),\n'
    '                  ),\n'
    '                ),\n'
    '        ),'
)
changes.append((old8, new8, 'zone 4 badge pkColor'))

# ── 9. _LiveRoomStage: wrap SeatGrid with PK stage background ─────────────
old9 = (
    '          _SeatGrid(\n'
    '            seats: seats,\n'
    '            cols: _colsForSeatCount(seats.length),\n'
    '            isArabic: isArabic,\n'
    '            isHost: isHost,\n'
    '            onEmptySeatTap: onEmptySeatTap,\n'
    '            onOccupiedSeatTap: onOccupiedSeatTap,\n'
    '            onOccupiedSeatLongPress: onOccupiedSeatLongPress,\n'
    '            onProfileTap: onProfileTap,\n'
    '            selectedMoveUserId: selectedMoveUserId,\n'
    '            speakingUserIds: speakingUserIds,\n'
    '            activePk: activePk,\n'
    '          ),'
)
new9 = (
    '          // When PK active, a subtle red-left/blue-right background split\n'
    '          // signals the team sides without breaking the seat grid layout.\n'
    '          Stack(\n'
    '            children: [\n'
    '              if (activePk != null)\n'
    '                Positioned.fill(\n'
    '                  child: ClipRRect(\n'
    '                    borderRadius: BorderRadius.circular(14),\n'
    '                    child: Row(\n'
    '                      children: [\n'
    '                        Expanded(\n'
    '                          child: Container(\n'
    '                            decoration: BoxDecoration(\n'
    '                              gradient: LinearGradient(\n'
    '                                begin: Alignment.centerLeft,\n'
    '                                end: Alignment.centerRight,\n'
    '                                colors: [\n'
    '                                  kPkRed.withValues(alpha: 0.09),\n'
    '                                  Colors.transparent,\n'
    '                                ],\n'
    '                              ),\n'
    '                            ),\n'
    '                          ),\n'
    '                        ),\n'
    '                        Expanded(\n'
    '                          child: Container(\n'
    '                            decoration: BoxDecoration(\n'
    '                              gradient: LinearGradient(\n'
    '                                begin: Alignment.centerLeft,\n'
    '                                end: Alignment.centerRight,\n'
    '                                colors: [\n'
    '                                  Colors.transparent,\n'
    '                                  kPkBlue.withValues(alpha: 0.09),\n'
    '                                ],\n'
    '                              ),\n'
    '                            ),\n'
    '                          ),\n'
    '                        ),\n'
    '                      ],\n'
    '                    ),\n'
    '                  ),\n'
    '                ),\n'
    '              _SeatGrid(\n'
    '                seats: seats,\n'
    '                cols: _colsForSeatCount(seats.length),\n'
    '                isArabic: isArabic,\n'
    '                isHost: isHost,\n'
    '                onEmptySeatTap: onEmptySeatTap,\n'
    '                onOccupiedSeatTap: onOccupiedSeatTap,\n'
    '                onOccupiedSeatLongPress: onOccupiedSeatLongPress,\n'
    '                onProfileTap: onProfileTap,\n'
    '                selectedMoveUserId: selectedMoveUserId,\n'
    '                speakingUserIds: speakingUserIds,\n'
    '                activePk: activePk,\n'
    '              ),\n'
    '            ],\n'
    '          ),'
)
changes.append((old9, new9, '_LiveRoomStage PK background'))

# Apply all changes
failed = []
for old, new, name in changes:
    if old in src:
        src = src.replace(old, new, 1)
        print(f'OK: {name}')
    else:
        # Debug: show context around expected location
        key = old[:60].replace('\n', '|')
        idx = src.find(old[:40])
        print(f'FAIL: {name}  (key={repr(key[:40])}, found={idx})')
        failed.append(name)

if not failed:
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print('\nAll changes written successfully.')
else:
    print(f'\nNOT WRITTEN — {len(failed)} failed.')
