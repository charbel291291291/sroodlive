/// M5 — Backpack V2 inventory screen.
///
/// Isolated, flag-gated UI on top of the M4 domain layer
/// (lib/features/backpack_v2/controllers/backpack_v2_controller.dart).
/// Reachable only from the single gated entry point added in
/// lib/features/profile_hub/screens/settings_screen.dart when
/// `backpack_v2_ui_enabled` resolves `true` — this screen does not itself
/// re-check the flag, does not read any legacy backpack table/RPC, does not
/// render anywhere else in the app, and does not connect to rooms, profiles,
/// messages, leaderboards, gifts, follow lists, admin user cards, or
/// existing avatar widgets. See docs/backpack_v2/M5_FLAG_GATED_UI_REPORT.md.
///
/// Localization: this app has no `.arb`/intl dictionary for feature screens
/// and no French runtime locale support at all (`MaterialApp.supportedLocales`
/// is `[en, ar]` only, in lib/main.dart) — a pre-existing, app-wide gap, not
/// something this screen introduces. Strings here follow the same
/// `context.isArabic` inline-ternary convention as every other feature
/// screen (see lib/features/gamification/screens/backpack_screen.dart).
library;

import 'package:flutter/material.dart';

import '../controllers/backpack_v2_controller.dart';
import '../controllers/backpack_v2_state.dart';
import '../exceptions/backpack_v2_exception.dart';
import '../models/backpack_v2_item_type.dart';
import '../models/backpack_v2_owned_item.dart';
import '../models/backpack_v2_slot_type.dart';
import 'backpack_v2_item_card.dart';

const _kBgTop = Color(0xFF12061F);
const _kBgMid = Color(0xFF07030D);
const _kBgBottom = Color(0xFF050208);
const _kGold = Color(0xFFF0C15A);
const _kCardBg = Color(0xFF1B102A);
const _kTextMuted = Color(0xFF7A6890);
const _kTextSubtle = Color(0xFFD8CFEA);
const _kDanger = Color(0xFFFF5C7A);
const _kBorderMuted = Color(0xFF4A3470);

/// `BackpackV2ItemType.value`s share their string representation with
/// `BackpackV2SlotType.value`s by construction (see backpack_v2_slot_type.dart
/// doc comment) — this converts an owned item's catalog type into the slot
/// key used to look up its equipped state, without a second RPC/lookup.
BackpackV2SlotType _slotForItemType(BackpackV2ItemType? type) =>
    BackpackV2SlotType.fromValue(type?.value);

enum _BackpackV2Tab { owned, equipped }

class BackpackV2Screen extends StatefulWidget {
  const BackpackV2Screen({required this.isArabic, this.controller, super.key});

  final bool isArabic;

  /// Injectable for tests. In production, left null so the screen creates
  /// and owns its own [BackpackV2Controller] instance — this controller is
  /// never registered globally (per the M5 spec's CONTROLLER INTEGRATION
  /// requirement).
  final BackpackV2Controller? controller;

  @override
  State<BackpackV2Screen> createState() => _BackpackV2ScreenState();
}

class _BackpackV2ScreenState extends State<BackpackV2Screen> {
  late final BackpackV2Controller _controller;
  late final bool _ownsController;
  _BackpackV2Tab _tab = _BackpackV2Tab.owned;
  BackpackV2SlotType? _slotFilter;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? BackpackV2Controller();
    _controller.addListener(_onControllerChanged);
    _controller.load();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  bool get isArabic => widget.isArabic;

  Future<void> _handleRefresh() => _controller.refresh();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_kBgTop, _kBgMid, _kBgBottom],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _Header(isArabic: isArabic),
                _TabBar(
                  isArabic: isArabic,
                  tab: _tab,
                  onChanged: (t) => setState(() => _tab = t),
                ),
                if (_tab == _BackpackV2Tab.owned)
                  _SlotFilterBar(
                    isArabic: isArabic,
                    items: _controller.state.snapshot?.ownedItems ?? const [],
                    selected: _slotFilter,
                    onChanged: (s) => setState(() => _slotFilter = s),
                  ),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final state = _controller.state;
    final snapshot = state.snapshot;
    final mutationInFlight =
        state.status == BackpackV2Status.refreshing ||
        state.status == BackpackV2Status.equipping ||
        state.status == BackpackV2Status.unequipping;

    if (snapshot == null) {
      if (state.hasError) {
        return _ErrorState(
          isArabic: isArabic,
          category: state.errorCategory,
          onRetry: _handleRefresh,
        );
      }
      return Semantics(
        liveRegion: true,
        label: isArabic ? 'جارٍ تحميل الحقيبة' : 'Loading backpack',
        child: const Center(child: CircularProgressIndicator(color: _kGold)),
      );
    }

    final ownedItems = _tab == _BackpackV2Tab.owned
        ? (_slotFilter == null
              ? snapshot.ownedItems
              : snapshot.ownedItems
                    .where(
                      (i) =>
                          _slotForItemType(i.catalogItem.itemType) ==
                          _slotFilter,
                    )
                    .toList())
        : snapshot.ownedItems.where((i) {
            final slot = _slotForItemType(i.catalogItem.itemType);
            final equipped = snapshot.equippedItemFor(slot);
            return equipped != null && equipped.ownershipId == i.ownershipId;
          }).toList();

    Widget content;
    if (ownedItems.isEmpty) {
      content = _EmptyState(isArabic: isArabic, tab: _tab);
    } else {
      content = ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        itemCount: ownedItems.length,
        itemBuilder: (context, index) {
          final item = ownedItems[index];
          final slot = _slotForItemType(item.catalogItem.itemType);
          final equipped = snapshot.equippedItemFor(slot);
          final isEquipped =
              equipped != null && equipped.ownershipId == item.ownershipId;
          final isPending =
              state.pendingOwnershipIds.contains(item.ownershipId) ||
              state.pendingSlots.contains(slot.value);

          return BackpackV2ItemCard(
            item: item,
            isArabic: isArabic,
            isEquipped: isEquipped,
            isPending: isPending,
            onEquip: () => _controller.equip(item.ownershipId),
            onUnequip: () => _controller.unequip(slot),
          );
        },
      );
    }

    return Column(
      children: [
        if (mutationInFlight)
          const LinearProgressIndicator(
            color: _kGold,
            backgroundColor: _kCardBg,
            minHeight: 2,
          ),
        if (state.hasError)
          _ErrorBanner(
            isArabic: isArabic,
            category: state.errorCategory,
            onRetry: _handleRefresh,
          ),
        Expanded(
          child: RefreshIndicator(
            color: _kGold,
            backgroundColor: _kCardBg,
            onRefresh: _handleRefresh,
            child: content is ListView
                ? content
                : ListView(
                    padding: const EdgeInsets.only(top: 40),
                    children: [content],
                  ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(
              isArabic
                  ? Icons.arrow_forward_ios_rounded
                  : Icons.arrow_back_ios_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Text(
              isArabic ? 'الحقيبة (معاينة)' : 'Backpack (Preview)',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.isArabic,
    required this.tab,
    required this.onChanged,
  });

  final bool isArabic;
  final _BackpackV2Tab tab;
  final ValueChanged<_BackpackV2Tab> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (_BackpackV2Tab.owned, isArabic ? 'المملوكة' : 'Owned'),
      (_BackpackV2Tab.equipped, isArabic ? 'المفعّلة' : 'Equipped'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: tabs
            .map(
              (t) => Expanded(
                child: Semantics(
                  button: true,
                  selected: tab == t.$1,
                  label: t.$2,
                  child: GestureDetector(
                    onTap: () => onChanged(t.$1),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tab == t.$1 ? _kGold : _kCardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: tab == t.$1 ? _kGold : _kBorderMuted,
                        ),
                      ),
                      child: Text(
                        t.$2,
                        style: TextStyle(
                          color: tab == t.$1
                              ? const Color(0xFF160B26)
                              : _kTextSubtle,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SlotFilterBar extends StatelessWidget {
  const _SlotFilterBar({
    required this.isArabic,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final bool isArabic;
  final List<BackpackV2OwnedItem> items;
  final BackpackV2SlotType? selected;
  final ValueChanged<BackpackV2SlotType?> onChanged;

  String _label(BackpackV2SlotType? slot) {
    if (slot == null) return isArabic ? 'الكل' : 'All';
    return slot.value.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final present = <BackpackV2SlotType>{
      for (final item in items) _slotForItemType(item.catalogItem.itemType),
    }.toList()..sort((a, b) => a.value.compareTo(b.value));

    final options = <BackpackV2SlotType?>[null, ...present];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          reverse: isArabic,
          itemCount: options.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final option = options[index];
            final isSelected = option == selected;
            return Semantics(
              button: true,
              selected: isSelected,
              label: _label(option),
              child: GestureDetector(
                onTap: () => onChanged(option),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? _kGold : _kCardBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isSelected ? _kGold : _kBorderMuted,
                    ),
                  ),
                  child: Text(
                    _label(option),
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF160B26)
                          : _kTextSubtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isArabic, required this.tab});

  final bool isArabic;
  final _BackpackV2Tab tab;

  @override
  Widget build(BuildContext context) {
    final message = tab == _BackpackV2Tab.owned
        ? (isArabic
              ? 'لا توجد عناصر في الحقيبة بعد'
              : 'No items in your backpack yet')
        : (isArabic
              ? 'لا توجد عناصر مفعّلة حاليًا'
              : 'Nothing is equipped right now');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              color: _kBorderMuted,
              size: 56,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

String _errorMessage(bool isArabic, BackpackV2ErrorCategory? category) {
  switch (category) {
    case BackpackV2ErrorCategory.authentication:
      return isArabic
          ? 'يرجى تسجيل الدخول لعرض الحقيبة'
          : 'Please sign in to view your backpack';
    case BackpackV2ErrorCategory.permission:
      return isArabic
          ? 'ليست لديك صلاحية للوصول إلى هذا'
          : 'You do not have permission to access this';
    case BackpackV2ErrorCategory.network:
      return isArabic
          ? 'تعذر الاتصال بالشبكة. حاول مرة أخرى.'
          : 'Network connection issue. Please try again.';
    case BackpackV2ErrorCategory.expiredOwnership:
      return isArabic ? 'انتهت صلاحية هذا العنصر' : 'This item has expired';
    case BackpackV2ErrorCategory.missingOwnership:
      return isArabic
          ? 'العنصر لم يعد متاحًا'
          : 'This item is no longer available';
    case BackpackV2ErrorCategory.equipEligibility:
      return isArabic
          ? 'لا يمكن تفعيل هذا العنصر حاليًا'
          : 'This item cannot be equipped right now';
    case BackpackV2ErrorCategory.unsupportedItemType:
    case BackpackV2ErrorCategory.databaseConstraint:
    case BackpackV2ErrorCategory.invalidResponse:
    case BackpackV2ErrorCategory.unknown:
    case null:
      return isArabic
          ? 'حدث خطأ. حاول مرة أخرى.'
          : 'Something went wrong. Please try again.';
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.isArabic,
    required this.category,
    required this.onRetry,
  });

  final bool isArabic;
  final BackpackV2ErrorCategory? category;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _kDanger, size: 44),
            const SizedBox(height: 12),
            Text(
              _errorMessage(isArabic, category),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextSubtle, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: isArabic ? 'إعادة المحاولة' : 'Retry',
              child: TextButton(
                onPressed: onRetry,
                child: Text(
                  isArabic ? 'إعادة المحاولة' : 'Retry',
                  style: const TextStyle(color: _kGold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.isArabic,
    required this.category,
    required this.onRetry,
  });

  final bool isArabic;
  final BackpackV2ErrorCategory? category;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kDanger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kDanger.withValues(alpha: 0.5)),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kDanger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage(isArabic, category),
              style: const TextStyle(color: _kTextSubtle, fontSize: 12),
            ),
          ),
          Semantics(
            button: true,
            label: isArabic ? 'إعادة المحاولة' : 'Retry',
            child: TextButton(
              onPressed: onRetry,
              child: Text(
                isArabic ? 'إعادة المحاولة' : 'Retry',
                style: const TextStyle(
                  color: _kGold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
