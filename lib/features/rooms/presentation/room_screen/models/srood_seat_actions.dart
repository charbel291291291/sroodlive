/// Result models for the seat action sheets (empty-seat assignment and
/// occupied-seat management) shown by the room screen.
library;

import '../../../models/room_member.dart';

class SroodEmptySeatAction {
  const SroodEmptySeatAction.moveSelf() : member = null, moveSelf = true;

  const SroodEmptySeatAction.moveMember(this.member) : moveSelf = false;

  final RoomMember? member;
  final bool moveSelf;
}

class SroodOccupiedSeatAction {
  const SroodOccupiedSeatAction.selectForMove()
    : seatNumber = null,
      selectForMove = true;

  const SroodOccupiedSeatAction.moveToListener()
    : seatNumber = null,
      selectForMove = false;

  const SroodOccupiedSeatAction.moveToSeat(this.seatNumber)
    : selectForMove = false;

  final int? seatNumber;
  final bool selectForMove;
}
