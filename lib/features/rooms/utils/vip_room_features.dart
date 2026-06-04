bool hasInvisibleEntry(int vipLevel) {
  return vipLevel >= 4;
}

bool hasStrongInvisibleEntry(int vipLevel) {
  return vipLevel >= 5;
}

bool requiresKickConfirmation(int vipLevel) {
  return vipLevel == 4;
}

bool hasAntiKickProtection(int vipLevel) {
  return vipLevel >= 5;
}

bool canKickVip5User({required bool isRoomOwner, required bool isSuperAdmin}) {
  return isRoomOwner || isSuperAdmin;
}
