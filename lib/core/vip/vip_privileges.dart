import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VipPrivilegeKey — canonical identifiers for every VIP privilege
// ─────────────────────────────────────────────────────────────────────────────

enum VipPrivilegeKey {
  // ── Visual (automatic, not user-settable) ──────────────────────────────────
  profileGlow,
  vipBadge,
  vipFrame,
  micWave,
  entranceEffect,

  // ── Room behavior (automatic) ──────────────────────────────────────────────
  silentEntry,
  kickProtection,
  kickConfirmation,
  strongAntiKick,

  // ── User-settable privacy / protection ────────────────────────────────────
  notBeingFollowed,
  antiEnteringRoom,
  privateBrowsing,
  doNotDisturb,
  antiKick,
  invisibility,

  // ── VIP 7 — content creation ──────────────────────────────────────────────
  sendRoomChatImage,
}

// ─────────────────────────────────────────────────────────────────────────────
// VipPrivilegeSpec — metadata for one privilege
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class VipPrivilegeSpec {
  const VipPrivilegeSpec({
    required this.key,
    required this.label,
    required this.labelAr,
    required this.description,
    required this.descriptionAr,
    required this.minVipLevel,
    this.isUserSettable = false,
  });

  final VipPrivilegeKey key;
  final String label;
  final String labelAr;
  final String description;
  final String descriptionAr;

  /// Minimum VIP level required to access this privilege.
  final int minVipLevel;

  /// Whether the user can toggle this via the VIP settings screen.
  /// False = automatic (always active when level is met).
  final bool isUserSettable;
}

// ─────────────────────────────────────────────────────────────────────────────
// VipPrivileges — single source of truth for all VIP privilege rules
// ─────────────────────────────────────────────────────────────────────────────

class VipPrivileges {
  const VipPrivileges._();

  /// Whether [vipLevel] is high enough to use [key].
  static bool canUse(int vipLevel, VipPrivilegeKey key) =>
      vipLevel >= spec(key).minVipLevel;

  /// Spec for a privilege key.
  static VipPrivilegeSpec spec(VipPrivilegeKey key) => _specs[key]!;

  /// All privileges unlocked at [vipLevel] (level >= minVipLevel).
  static List<VipPrivilegeSpec> unlockedFor(int vipLevel) =>
      _all.where((s) => vipLevel >= s.minVipLevel).toList();

  /// All privileges not yet unlocked at [vipLevel].
  static List<VipPrivilegeSpec> lockedFor(int vipLevel) =>
      _all.where((s) => vipLevel < s.minVipLevel).toList();

  // ── Privilege table ────────────────────────────────────────────────────────

  static final List<VipPrivilegeSpec> _all = List.unmodifiable(_specs.values);

  static final Map<VipPrivilegeKey, VipPrivilegeSpec> _specs = {
    // ── VIP 1 — basic visual perks ─────────────────────────────────────────
    VipPrivilegeKey.profileGlow: const VipPrivilegeSpec(
      key: VipPrivilegeKey.profileGlow,
      label: 'Profile Glow',
      labelAr: 'توهج الملف الشخصي',
      description: 'Your avatar glows with a colored ring in rooms.',
      descriptionAr: 'يضيء أفاتارك بحلقة ملونة داخل الغرف.',
      minVipLevel: 1,
    ),
    VipPrivilegeKey.vipBadge: const VipPrivilegeSpec(
      key: VipPrivilegeKey.vipBadge,
      label: 'VIP Badge',
      labelAr: 'شارة VIP',
      description: 'A VIP badge is shown next to your name.',
      descriptionAr: 'تظهر شارة VIP بجانب اسمك.',
      minVipLevel: 1,
    ),
    VipPrivilegeKey.vipFrame: const VipPrivilegeSpec(
      key: VipPrivilegeKey.vipFrame,
      label: 'VIP Frame',
      labelAr: 'إطار VIP',
      description: 'Unlocks an exclusive VIP avatar frame.',
      descriptionAr: 'يفتح إطار أفاتار VIP حصري.',
      minVipLevel: 1,
    ),
    VipPrivilegeKey.micWave: const VipPrivilegeSpec(
      key: VipPrivilegeKey.micWave,
      label: 'Mic Wave Ring',
      labelAr: 'حلقة موجة الميكروفون',
      description: 'Animated sound wave ring when you speak on mic.',
      descriptionAr: 'حلقة موجة صوت متحركة عند التحدث على الميكروفون.',
      minVipLevel: 1,
    ),
    VipPrivilegeKey.entranceEffect: const VipPrivilegeSpec(
      key: VipPrivilegeKey.entranceEffect,
      label: 'Entrance Effect',
      labelAr: 'تأثير الدخول',
      description: 'A banner announces your entry into a room.',
      descriptionAr: 'لافتة تُعلن عن دخولك للغرفة.',
      minVipLevel: 1,
    ),

    // ── VIP 3 — basic kick protection ─────────────────────────────────────
    VipPrivilegeKey.kickProtection: const VipPrivilegeSpec(
      key: VipPrivilegeKey.kickProtection,
      label: 'Kick Protection',
      labelAr: 'الحماية من الطرد',
      description: 'Moderators cannot kick you without extra steps.',
      descriptionAr: 'لا يمكن للمشرفين طردك دون خطوات إضافية.',
      minVipLevel: 3,
    ),

    // ── VIP 4 — kick confirmation ─────────────────────────────────────────
    VipPrivilegeKey.kickConfirmation: const VipPrivilegeSpec(
      key: VipPrivilegeKey.kickConfirmation,
      label: 'Kick Confirmation',
      labelAr: 'تأكيد الطرد',
      description: 'Moderators must confirm a dialog before kicking you.',
      descriptionAr: 'يجب على المشرفين تأكيد حوار قبل طردك.',
      minVipLevel: 4,
    ),

    // ── VIP 5 — strong protection + anti-follow ───────────────────────────
    VipPrivilegeKey.strongAntiKick: const VipPrivilegeSpec(
      key: VipPrivilegeKey.strongAntiKick,
      label: 'Strong Anti-Kick',
      labelAr: 'حماية قوية من الطرد',
      description: 'Only the room owner can kick you.',
      descriptionAr: 'يمكن فقط لصاحب الغرفة طردك.',
      minVipLevel: 5,
    ),
    VipPrivilegeKey.notBeingFollowed: const VipPrivilegeSpec(
      key: VipPrivilegeKey.notBeingFollowed,
      label: 'Not being Followed',
      labelAr: 'منع المتابعة',
      description: 'Prevent other users from following you.',
      descriptionAr: 'امنع المستخدمين الآخرين من متابعتك.',
      minVipLevel: 5,
      isUserSettable: true,
    ),

    // ── VIP 6 — silent entry + privacy ───────────────────────────────────
    VipPrivilegeKey.silentEntry: const VipPrivilegeSpec(
      key: VipPrivilegeKey.silentEntry,
      label: 'Silent Entry',
      labelAr: 'دخول صامت',
      description: 'Enter rooms without triggering an entrance banner.',
      descriptionAr: 'ادخل الغرف دون إظهار لافتة الدخول.',
      minVipLevel: 6,
    ),
    VipPrivilegeKey.antiEnteringRoom: const VipPrivilegeSpec(
      key: VipPrivilegeKey.antiEnteringRoom,
      label: 'Anti-Entering Room',
      labelAr: 'منع دخول الغرفة',
      description: 'Prevent others from following you into rooms.',
      descriptionAr: 'امنع الآخرين من متابعتك عند دخول الغرف.',
      minVipLevel: 6,
      isUserSettable: true,
    ),
    VipPrivilegeKey.privateBrowsing: const VipPrivilegeSpec(
      key: VipPrivilegeKey.privateBrowsing,
      label: 'Private Browsing',
      labelAr: 'التصفح الخاص',
      description: 'Browse rooms without appearing in visitor lists.',
      descriptionAr: 'تصفح الغرف دون الظهور في قوائم الزوار.',
      minVipLevel: 6,
      isUserSettable: true,
    ),

    // ── VIP 7 — do not disturb ────────────────────────────────────────────
    VipPrivilegeKey.doNotDisturb: const VipPrivilegeSpec(
      key: VipPrivilegeKey.doNotDisturb,
      label: 'Do Not Disturb',
      labelAr: 'عدم الإزعاج',
      description: 'Suppress notifications from other users.',
      descriptionAr: 'تعطيل الإشعارات من المستخدمين الآخرين.',
      minVipLevel: 7,
      isUserSettable: true,
    ),

    // ── VIP 7 — image sharing in room chat ───────────────────────────────────
    VipPrivilegeKey.sendRoomChatImage: const VipPrivilegeSpec(
      key: VipPrivilegeKey.sendRoomChatImage,
      label: 'Send Images in Chat',
      labelAr: 'إرسال صور في الدردشة',
      description: 'Send image messages directly in live room chat.',
      descriptionAr: 'أرسل صور مباشرةً في دردشة الغرفة المباشرة.',
      minVipLevel: 7,
    ),

    // ── VIP 8 — premium protection + invisibility ─────────────────────────
    VipPrivilegeKey.antiKick: const VipPrivilegeSpec(
      key: VipPrivilegeKey.antiKick,
      label: 'Anti-Kick',
      labelAr: 'منع الطرد',
      description: 'Enable to block moderators from kicking you.',
      descriptionAr: 'فعّل لمنع المشرفين من طردك.',
      minVipLevel: 8,
      isUserSettable: true,
    ),
    VipPrivilegeKey.invisibility: const VipPrivilegeSpec(
      key: VipPrivilegeKey.invisibility,
      label: 'Invisibility',
      labelAr: 'التخفي',
      description: 'Hide your online status and room presence.',
      descriptionAr: 'أخفِ حالتك الآن وتواجدك في الغرف.',
      minVipLevel: 8,
      isUserSettable: true,
    ),
  };
}
