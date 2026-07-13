/// Presentation model for one mic seat slot — empty, locked, or occupied.
library;

import '../../../../models/room_member.dart';

class SroodStageSeat {
  const SroodStageSeat({
    required this.number,
    required this.name,
    required this.role,
    required this.isMuted,
    required this.isEmpty,
    required this.supportAmount,
    this.isLocked = false,
    this.member,
  });

  factory SroodStageSeat.empty(int number, {bool isLocked = false}) {
    return SroodStageSeat(
      number: number,
      name: '',
      role: 'empty',
      isMuted: true,
      isEmpty: true,
      supportAmount: 0,
      isLocked: isLocked,
    );
  }

  factory SroodStageSeat.fromMember({
    required int number,
    required RoomMember member,
    required bool isArabic,
    required int supportAmount,
    bool isLocked = false,
  }) {
    return SroodStageSeat(
      number: number,
      name: member.fallbackName(isArabic),
      role: member.role,
      isMuted: member.isMuted,
      isEmpty: false,
      supportAmount: supportAmount,
      isLocked: isLocked,
      member: member,
    );
  }

  final int number;
  final String name;
  final String role;
  final bool isMuted;
  final bool isEmpty;
  final bool isLocked;
  final int supportAmount;
  final RoomMember? member;

  bool get isHostSeat => role == 'host';
}
