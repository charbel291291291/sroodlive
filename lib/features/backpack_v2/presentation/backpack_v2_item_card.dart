/// Card for a single owned Backpack V2 item. Pure presentation — all data
/// comes from [item] plus the flags passed in by the screen; no repository
/// or controller access happens here.
///
/// Visual conventions (dark purple/gold palette, rounded card, pill badges)
/// mirror the legacy `BackpackScreen`'s `_FrameCard`/`_BadgeCard`
/// (lib/features/gamification/screens/backpack_screen.dart) without reusing
/// its private widgets directly, since this module must not import from the
/// legacy screen.
library;

import 'package:flutter/material.dart';

import '../models/backpack_v2_expiration_state.dart';
import '../models/backpack_v2_owned_item.dart';
import '../models/backpack_v2_ownership_source.dart';
import '../models/backpack_v2_rarity.dart';

const _kCardBg = Color(0xFF12091D);
const _kGold = Color(0xFFF0C15A);
const _kBorderMuted = Color(0xFF4A3470);
const _kTextMuted = Color(0xFF7A6890);
const _kTextSubtle = Color(0xFFD8CFEA);
const _kDanger = Color(0xFFFF5C7A);
const _kPurpleAccent = Color(0xFF6B2FD4);

Color _rarityColor(BackpackV2Rarity rarity) {
  switch (rarity) {
    case BackpackV2Rarity.mythic:
      return const Color(0xFFFF5C7A);
    case BackpackV2Rarity.legendary:
      return _kGold;
    case BackpackV2Rarity.epic:
      return const Color(0xFF9B4DFF);
    case BackpackV2Rarity.rare:
      return const Color(0xFF4DA6FF);
    case BackpackV2Rarity.common:
    case BackpackV2Rarity.unknown:
      return _kTextMuted;
  }
}

String _rarityLabel(BackpackV2Rarity rarity, bool isArabic) {
  switch (rarity) {
    case BackpackV2Rarity.mythic:
      return isArabic ? 'أسطوري خارق' : 'Mythic';
    case BackpackV2Rarity.legendary:
      return isArabic ? 'أسطوري' : 'Legendary';
    case BackpackV2Rarity.epic:
      return isArabic ? 'ملحمي' : 'Epic';
    case BackpackV2Rarity.rare:
      return isArabic ? 'نادر' : 'Rare';
    case BackpackV2Rarity.common:
      return isArabic ? 'عادي' : 'Common';
    case BackpackV2Rarity.unknown:
      return isArabic ? 'غير معروف' : 'Unknown';
  }
}

String _sourceLabel(BackpackV2OwnershipSource source, bool isArabic) {
  switch (source) {
    case BackpackV2OwnershipSource.purchase:
      return isArabic ? 'تم الشراء' : 'Purchased';
    case BackpackV2OwnershipSource.adminGrant:
      return isArabic ? 'منحة إدارية' : 'Admin grant';
    case BackpackV2OwnershipSource.eventReward:
      return isArabic ? 'جائزة فعالية' : 'Event reward';
    case BackpackV2OwnershipSource.vipReward:
      return isArabic ? 'مكافأة VIP' : 'VIP reward';
    case BackpackV2OwnershipSource.legacyMigration:
      return isArabic ? 'من النظام السابق' : 'Migrated item';
    case BackpackV2OwnershipSource.unknown:
      return isArabic ? 'غير معروف' : 'Unknown source';
  }
}

class BackpackV2ItemCard extends StatelessWidget {
  const BackpackV2ItemCard({
    required this.item,
    required this.isArabic,
    required this.isEquipped,
    required this.isPending,
    required this.onEquip,
    required this.onUnequip,
    super.key,
  });

  final BackpackV2OwnedItem item;
  final bool isArabic;
  final bool isEquipped;

  /// True while an equip/unequip request for this item's ownership id (or
  /// its slot, for unequip) is in flight — used to disable the action
  /// button without disabling the rest of the list.
  final bool isPending;

  final VoidCallback onEquip;
  final VoidCallback onUnequip;

  String get _name {
    if (isArabic) {
      final ar = item.catalogItem.nameAr;
      if (ar != null && ar.isNotEmpty) return ar;
    }
    return item.catalogItem.name.isNotEmpty
        ? item.catalogItem.name
        : item.catalogItem.code;
  }

  String get _typeLabel {
    final type = item.catalogItem.itemType?.value ?? 'unknown';
    return type.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final expired = item.expirationState == BackpackV2ExpirationState.expired;
    final unavailable = !item.isEquippable;

    return Semantics(
      label: isArabic
          ? '$_name، ${_rarityLabel(item.catalogItem.rarity, isArabic)}'
          : '$_name, ${_rarityLabel(item.catalogItem.rarity, isArabic)}',
      child: Container(
        key: ValueKey('backpack_v2_item_${item.ownershipId}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEquipped ? _kGold.withValues(alpha: 0.7) : _kBorderMuted,
            width: isEquipped ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: isArabic
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _typeLabel,
                        style: const TextStyle(
                          color: _kTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isEquipped)
                  Semantics(
                    label: isArabic ? 'مُفعّل حاليًا' : 'Currently equipped',
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: _kGold,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Badge(
                  label: _rarityLabel(item.catalogItem.rarity, isArabic),
                  color: _rarityColor(item.catalogItem.rarity),
                ),
                _Badge(
                  label: _sourceLabel(item.sourceType, isArabic),
                  color: _kTextSubtle,
                ),
                if (expired)
                  _Badge(
                    label: isArabic ? 'منتهي الصلاحية' : 'Expired',
                    color: _kDanger,
                  )
                else if (item.expiresAt != null)
                  _Badge(
                    label: isArabic ? 'مؤقت' : 'Time-limited',
                    color: _kPurpleAccent,
                  )
                else
                  _Badge(
                    label: isArabic ? 'دائم' : 'Permanent',
                    color: _kTextMuted,
                  ),
                if (unavailable)
                  _Badge(
                    label: isArabic ? 'غير متاح للتفعيل' : 'Unavailable',
                    color: _kTextMuted,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _ActionButton(
                isArabic: isArabic,
                isEquipped: isEquipped,
                isPending: isPending,
                canAct: item.canEquip || isEquipped,
                onPressed: isEquipped ? onUnequip : onEquip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.isArabic,
    required this.isEquipped,
    required this.isPending,
    required this.canAct,
    required this.onPressed,
  });

  final bool isArabic;
  final bool isEquipped;
  final bool isPending;
  final bool canAct;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = canAct && !isPending;
    final label = isEquipped
        ? (isArabic ? 'إلغاء التفعيل' : 'Unequip')
        : (isArabic ? 'تفعيل' : 'Equip');

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEquipped
              ? const Color(0xFF3A2850)
              : const Color(0xFF4B168C),
          disabledBackgroundColor: const Color(0xFF241636),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isPending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
