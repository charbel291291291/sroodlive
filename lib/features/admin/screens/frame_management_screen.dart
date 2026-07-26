/// Frame System v2 — admin management screen.
///
/// Browse / search / filter the catalog, create, edit, duplicate, activate,
/// preview, and assign or revoke frames per user, plus migration status and
/// ownership history. Authorization is the existing admin model: every write
/// goes through a `has_admin_access()`-gated RPC. The client-side
/// [kPermFramesManage] check here is an extra guard on top of that, never a
/// replacement for it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/frames/frame_catalog_sync_service.dart';
import '../../../core/frames/srood_frame.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/widgets/srood_avatar_frame.dart';
import '../../../shared/widgets/srood_toast.dart';
import '../exceptions/frame_admin_exception.dart';
import '../frames/frame_editor_dialog.dart';
import '../frames/frame_editor_form.dart';
import '../frames/frame_live_preview.dart';
import '../services/admin_access_service.dart';
import '../services/frame_admin_service.dart';
import '../theme/frame_admin_theme.dart';

// ── Filters ──────────────────────────────────────────────────────────────────

/// What a chip filters on. Deliberately three kinds: "Mythic" is a `rarity`
/// value and "Role-based" is an `unlock_type` — neither is a category, and
/// inventing one would violate `frame_catalog`'s category CHECK.
enum _FilterKind { all, category, rarity, unlockType, active, inactive }

class _FrameFilter {
  const _FrameFilter(
    this.label,
    this.kind, {
    this.category,
    this.rarity,
    this.unlockType,
  });

  final String label;
  final _FilterKind kind;
  final SroodFrameCategory? category;
  final SroodFrameRarity? rarity;
  final SroodFrameUnlock? unlockType;

  bool matches(SroodFrame frame) => switch (kind) {
    _FilterKind.all => true,
    _FilterKind.category => frame.category == category,
    _FilterKind.rarity => frame.rarity == rarity,
    _FilterKind.unlockType => frame.unlockType == unlockType,
    _FilterKind.active => frame.isActive,
    _FilterKind.inactive => !frame.isActive,
  };
}

const _kFrameFilters = <_FrameFilter>[
  _FrameFilter('All', _FilterKind.all),
  _FrameFilter('VIP', _FilterKind.category, category: SroodFrameCategory.vip),
  _FrameFilter(
    'Luxury',
    _FilterKind.category,
    category: SroodFrameCategory.luxury,
  ),
  _FrameFilter('Mythic', _FilterKind.rarity, rarity: SroodFrameRarity.mythic),
  _FrameFilter(
    'Event',
    _FilterKind.category,
    category: SroodFrameCategory.event,
  ),
  _FrameFilter(
    'Achievement',
    _FilterKind.category,
    category: SroodFrameCategory.achievement,
  ),
  _FrameFilter(
    'Role-based',
    _FilterKind.unlockType,
    unlockType: SroodFrameUnlock.role,
  ),
  _FrameFilter('Active', _FilterKind.active),
  _FrameFilter('Inactive', _FilterKind.inactive),
];

// ── Screen ───────────────────────────────────────────────────────────────────

class FrameManagementScreen extends StatefulWidget {
  const FrameManagementScreen({super.key});

  @override
  State<FrameManagementScreen> createState() => _FrameManagementScreenState();
}

class _FrameManagementScreenState extends State<FrameManagementScreen> {
  final _service = FrameAdminService();
  final _access = const AdminAccessService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;

  /// Client-side mirror of the server gate. Resolved once on entry; false puts
  /// the screen in read-only mode rather than showing a blank page.
  bool _canManage = true;

  List<SroodFrame> _frames = const [];
  Map<String, dynamic> _report = const {};
  List<FrameOwnershipAuditEntry> _history = const [];

  _FrameFilter _filter = _kFrameFilters.first;
  String _search = '';

  /// Codes with a row-level mutation in flight — the row shows progress
  /// instead of the whole screen dropping to a spinner.
  final Set<String> _busyCodes = <String>{};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final role = await _access.fetchCurrentAdminRole();
    if (!mounted) return;
    setState(() => _canManage = role.hasPermission(kPermFramesManage));
    await _reload();
  }

  /// A secondary panel must never take the catalog down with it.
  Future<T> _soft<T>(Future<T> future, T fallback, String label) async {
    try {
      return await future;
    } catch (error, stack) {
      debugError(label, error, stack);
      return fallback;
    }
  }

  Future<void> _reload({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    // Three independent RPCs — issued together rather than one after another.
    final framesFuture = _service.listFrames();
    final reportFuture = _soft<Map<String, dynamic>>(
      _service.migrationReport(),
      const {},
      'FrameManagement.migrationReport',
    );
    final historyFuture = _soft<List<FrameOwnershipAuditEntry>>(
      _service.ownershipHistory(limit: 50),
      const [],
      'FrameManagement.ownershipHistory',
    );
    try {
      final results = await Future.wait<Object?>([
        framesFuture,
        reportFuture,
        historyFuture,
      ]);
      if (!mounted) return;
      setState(() {
        _frames = results[0]! as List<SroodFrame>;
        _report = results[1]! as Map<String, dynamic>;
        _history = results[2]! as List<FrameOwnershipAuditEntry>;
        _loading = false;
        _error = null;
      });
    } catch (error, stack) {
      debugError('FrameManagement.reload', error, stack);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(error);
      });
    }
  }

  static String _friendly(Object error) => error is FrameAdminException
      ? error.message
      : mapFrameAdminError(error).message;

  void _toast(String message, {bool success = false}) {
    if (!mounted) return;
    SroodToast.show(
      context,
      message,
      type: success ? SroodToastType.success : SroodToastType.error,
    );
  }

  /// Pulls the live catalog into [FrameRegistry] so the frame the admin just
  /// wrote is renderable immediately. Fire-and-forget: it never throws, and a
  /// stale registry must not fail an otherwise successful save.
  void _refreshRegistry() {
    unawaited(FrameCatalogSyncService.instance.load(forceRefresh: true));
  }

  List<SroodFrame> get _visibleFrames {
    final query = _search.trim().toLowerCase();
    return _frames.where((frame) {
      if (!_filter.matches(frame)) return false;
      if (query.isEmpty) return true;
      return frame.name.toLowerCase().contains(query) ||
          frame.code.toLowerCase().contains(query) ||
          (frame.legacyFrameKey?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FrameAdminTheme.background,
      appBar: AppBar(
        title: const Text('Frame Management (v2)'),
        backgroundColor: FrameAdminTheme.surface,
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(null),
              backgroundColor: FrameAdminTheme.accent,
              foregroundColor: const Color(0xFF1B0F2B),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New frame'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _reload)
          : RefreshIndicator(
              onRefresh: () => _reload(showSpinner: false),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                children: [
                  if (!_canManage) const _ReadOnlyBanner(),
                  _MigrationStatusCard(
                    report: _report,
                    canManage: _canManage,
                    onToggleEnforcement: _toggleEnforcement,
                  ),
                  const SizedBox(height: 14),
                  _searchField(),
                  const SizedBox(height: 10),
                  _filters(),
                  const SizedBox(height: 10),
                  _countLine(),
                  const SizedBox(height: 6),
                  if (_visibleFrames.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        'No frames match this filter.',
                        textAlign: TextAlign.center,
                        style: FrameAdminTheme.metaStyle,
                      ),
                    )
                  else
                    ..._visibleFrames.map(
                      (frame) => _FrameRow(
                        key: ValueKey(frame.code),
                        frame: frame,
                        canManage: _canManage,
                        busy: _busyCodes.contains(frame.code),
                        onEdit: () => _openEditor(frame),
                        onDuplicate: () => _duplicate(frame),
                        onPreview: () => _openPreview(frame),
                        onAssign: () => _openAssign(frame),
                        onToggleActive: () => _toggleActive(frame),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _HistoryCard(history: _history),
                ],
              ),
            ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      style: FrameAdminTheme.fieldTextStyle,
      onChanged: (value) => setState(() => _search = value),
      decoration:
          FrameAdminTheme.inputDecoration(
            label: 'Search',
            hint: 'Name, code, or legacy frame key',
          ).copyWith(
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: FrameAdminTheme.textMuted,
            ),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                  ),
          ),
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in _kFrameFilters)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: identical(_filter, filter),
                showCheckmark: false,
                backgroundColor: FrameAdminTheme.field,
                selectedColor: FrameAdminTheme.accent,
                side: const BorderSide(color: FrameAdminTheme.border),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: identical(_filter, filter)
                      ? const Color(0xFF1B0F2B)
                      : FrameAdminTheme.textSecondary,
                ),
                onSelected: (_) => setState(() => _filter = filter),
              ),
            ),
        ],
      ),
    );
  }

  Widget _countLine() {
    final shown = _visibleFrames.length;
    return Text(
      shown == _frames.length
          ? '$shown frames'
          : '$shown of ${_frames.length} frames',
      style: FrameAdminTheme.metaStyle,
    );
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> _toggleActive(SroodFrame frame) async {
    if (!_canManage || _busyCodes.contains(frame.code)) return;
    final updated = frame.copyWith(isActive: !frame.isActive);
    // Optimistic: flip the one row now, revert it if the RPC refuses.
    setState(() {
      _frames = _replaceRow(updated);
      _busyCodes.add(frame.code);
    });
    try {
      await _service.upsertFrame(updated);
      _refreshRegistry();
      _toast(
        updated.isActive ? 'Frame activated' : 'Frame deactivated',
        success: true,
      );
    } catch (error, stack) {
      debugError('FrameManagement.toggleActive', error, stack);
      if (mounted) setState(() => _frames = _replaceRow(frame));
      _toast(_friendly(error));
    } finally {
      if (mounted) setState(() => _busyCodes.remove(frame.code));
    }
  }

  List<SroodFrame> _replaceRow(SroodFrame frame) => [
    for (final entry in _frames)
      if (entry.code == frame.code) frame else entry,
  ];

  Future<void> _toggleEnforcement() async {
    if (!_canManage) return;
    final current = _report['enforcement_enabled'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FrameAdminTheme.surface,
        title: Text(
          current ? 'Disable enforcement?' : 'Enable enforcement?',
          style: const TextStyle(color: FrameAdminTheme.textPrimary),
        ),
        content: Text(
          current
              ? 'Selection guard returns to log-only mode.'
              : 'Users will be BLOCKED from selecting frames they do not own. '
                    'Only enable after the violation log has been reviewed.',
          style: const TextStyle(color: FrameAdminTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.setEnforcement(!current);
      await _reload(showSpinner: false);
    } catch (error, stack) {
      debugError('FrameManagement.toggleEnforcement', error, stack);
      _toast(_friendly(error));
    }
  }

  void _openPreview(SroodFrame frame) {
    showDialog<void>(
      context: context,
      builder: (_) => _FramePreviewDialog(frame: frame),
    );
  }

  Future<void> _openAssign(SroodFrame frame) async {
    if (!_canManage) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FrameAdminTheme.surface,
      builder: (_) => _AssignSheet(frame: frame, service: _service),
    );
    if (changed == true) await _reload(showSpinner: false);
  }

  Future<void> _openEditor(SroodFrame? frame) async {
    if (!_canManage) return;
    final state = frame == null
        ? FrameEditorState.blank(catalog: _frames)
        : FrameEditorState.fromFrame(frame, catalog: _frames);
    final saved = await showFrameEditorDialog(
      context,
      state: state,
      catalog: _frames,
      adminService: _service,
    );
    if (saved == null) return;
    _refreshRegistry();
    await _reload(showSpinner: false);
    _toast(
      frame == null ? 'Frame "${saved.name}" created' : 'Frame saved',
      success: true,
    );
  }

  /// Opens a pre-filled copy. Nothing is written until the admin saves, and
  /// the source row is never touched.
  Future<void> _duplicate(SroodFrame frame) async {
    if (!_canManage) return;
    final saved = await showFrameEditorDialog(
      context,
      state: duplicateFrom(frame, catalog: _frames),
      catalog: _frames,
      adminService: _service,
    );
    if (saved == null) return;
    _refreshRegistry();
    await _reload(showSpinner: false);
    _toast('Frame "${saved.name}" created', success: true);
  }
}

// ── Small shared pieces ──────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: FrameAdminTheme.danger,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: FrameAdminTheme.danger),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FrameAdminTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: FrameAdminTheme.warning.withValues(alpha: 0.4),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.visibility_rounded,
            size: 16,
            color: FrameAdminTheme.warning,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Read-only: your admin role does not include "frames.manage". '
              'You can browse and preview frames but not change them.',
              style: TextStyle(color: FrameAdminTheme.warning, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Migration status ─────────────────────────────────────────────────────────

class _MigrationStatusCard extends StatelessWidget {
  const _MigrationStatusCard({
    required this.report,
    required this.canManage,
    required this.onToggleEnforcement,
  });

  final Map<String, dynamic> report;
  final bool canManage;
  final VoidCallback onToggleEnforcement;

  @override
  Widget build(BuildContext context) {
    final enforcement = report['enforcement_enabled'] == true;
    final unmappedLegacy = report['legacy_keys_unmapped'];
    final unmappedSelected = report['selected_keys_unmapped'];
    return Card(
      color: FrameAdminTheme.raisedCard,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Migration status',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: FrameAdminTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Legacy catalog rows: ${report['legacy_catalog_rows'] ?? '-'}\n'
              'v2 catalog rows: ${report['v2_catalog_rows'] ?? '-'}\n'
              'Legacy ownership rows: ${report['legacy_ownership_rows'] ?? '-'}\n'
              'v2 ownership rows: ${report['v2_ownership_rows'] ?? '-'}\n'
              'Unmapped legacy keys: ${unmappedLegacy is List && unmappedLegacy.isEmpty ? 'none' : unmappedLegacy}\n'
              'Unmapped selected keys: ${unmappedSelected is List && unmappedSelected.isEmpty ? 'none' : unmappedSelected}',
              style: const TextStyle(
                color: FrameAdminTheme.textSecondary,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  enforcement ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: 16,
                  color: enforcement
                      ? FrameAdminTheme.success
                      : FrameAdminTheme.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    enforcement
                        ? 'Selection enforcement: ON'
                        : 'Selection enforcement: LOG-ONLY',
                    style: const TextStyle(
                      color: FrameAdminTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: canManage ? onToggleEnforcement : null,
                  child: Text(enforcement ? 'Disable' : 'Enable'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Frame row ────────────────────────────────────────────────────────────────

String frameRequirementLabel(SroodFrame frame) => switch (frame.unlockType) {
  SroodFrameUnlock.free => 'Free',
  SroodFrameUnlock.vipLevel =>
    'VIP ${frame.requiredVipLevel ?? frame.vipLevel ?? '—'}',
  SroodFrameUnlock.role => 'Role: ${frame.requiredRole ?? '—'}',
  SroodFrameUnlock.level => 'Level ${frame.requiredLevel ?? '—'}',
  SroodFrameUnlock.purchase =>
    frame.unlockValue == null ? 'Purchase' : 'Purchase · ${frame.unlockValue}',
  SroodFrameUnlock.reward => 'Reward',
  SroodFrameUnlock.adminGrant => 'Admin grant',
  SroodFrameUnlock.event => 'Event',
};

class _FrameRow extends StatelessWidget {
  const _FrameRow({
    required this.frame,
    required this.canManage,
    required this.busy,
    required this.onEdit,
    required this.onDuplicate,
    required this.onPreview,
    required this.onAssign,
    required this.onToggleActive,
    super.key,
  });

  final SroodFrame frame;
  final bool canManage;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onPreview;
  final VoidCallback onAssign;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: FrameAdminTheme.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            SroodAvatarFrame(
              // `frameOverride` renders this exact catalog row, so uploaded
              // artwork shows in the list without a registry round-trip.
              frameOverride: frame,
              vipLevel: frame.vipLevel ?? 0,
              sizePreset: SroodAvatarFrameSize.small,
              preferV2TierArt: frame.category == SroodFrameCategory.vip,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    frame.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FrameAdminTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${frame.code} · ${frame.category.wire}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FrameAdminTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _Tag(frameRequirementLabel(frame)),
                      _Tag(
                        frame.isAnimated ? 'Animated' : 'Static',
                        color: frame.isAnimated
                            ? FrameAdminTheme.accent
                            : FrameAdminTheme.textMuted,
                      ),
                      _Tag(
                        frame.isActive ? 'Active' : 'Inactive',
                        color: frame.isActive
                            ? FrameAdminTheme.success
                            : FrameAdminTheme.danger,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Switch(
                value: frame.isActive,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: canManage ? (_) => onToggleActive() : null,
              ),
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              onPressed: canManage ? onEdit : null,
              icon: const Icon(Icons.edit_rounded, size: 18),
            ),
            IconButton(
              tooltip: 'Duplicate',
              visualDensity: VisualDensity.compact,
              onPressed: canManage ? onDuplicate : null,
              icon: const Icon(Icons.copy_all_rounded, size: 18),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              color: FrameAdminTheme.raisedCard,
              onSelected: (value) => switch (value) {
                'preview' => onPreview(),
                'assign' => onAssign(),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'preview', child: Text('Preview')),
                PopupMenuItem(
                  value: 'assign',
                  enabled: canManage,
                  child: const Text('Assign / Revoke'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? FrameAdminTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tint,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Preview dialog ───────────────────────────────────────────────────────────

/// Reuses [FrameLivePreview], the same component the editor shows, which in
/// turn renders through [SroodAvatarFrame]. Scrollable and height-capped: the
/// old fixed `Column` overflowed on short viewports.
class _FramePreviewDialog extends StatelessWidget {
  const _FramePreviewDialog({required this.frame});

  final SroodFrame frame;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    return AlertDialog(
      backgroundColor: FrameAdminTheme.surface,
      title: Text(
        frame.name,
        style: const TextStyle(color: FrameAdminTheme.textPrimary),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FrameLivePreview(frame: frame),
              const SizedBox(height: 10),
              Text(
                '${frame.code}\n'
                '${frame.category.wire} · ${frame.rarity.wire} · '
                '${frameRequirementLabel(frame)}'
                '${frame.legacyFrameKey != null ? '\nlegacy: ${frame.legacyFrameKey}' : ''}',
                style: FrameAdminTheme.metaStyle,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ── Assign / revoke sheet ────────────────────────────────────────────────────

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.frame, required this.service});

  final SroodFrame frame;
  final FrameAdminService service;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  final _userCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  DateTime? _expiresAt;
  bool _busy = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() op, String successMsg) async {
    if (_userCtrl.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await op();
      if (!mounted) return;
      SroodToast.show(context, successMsg, type: SroodToastType.success);
      Navigator.pop(context, true);
    } catch (error, stack) {
      debugError('FrameManagement.assignSheet', error, stack);
      if (mounted) {
        SroodToast.show(
          context,
          _FrameManagementScreenState._friendly(error),
          type: SroodToastType.error,
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Height-capped and scrollable so the keyboard cannot overflow it.
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            MediaQuery.viewInsetsOf(context).bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assign / revoke: ${widget.frame.code}',
                style: const TextStyle(
                  color: FrameAdminTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userCtrl,
                style: FrameAdminTheme.fieldTextStyle,
                decoration: FrameAdminTheme.inputDecoration(
                  label: 'User ID (uuid)',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _expiresAt == null
                          ? 'No expiration (permanent)'
                          : 'Expires: ${_expiresAt!.toLocal()}'
                                .split('.')
                                .first,
                      style: FrameAdminTheme.metaStyle,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(
                          const Duration(days: 30),
                        ),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (picked != null) setState(() => _expiresAt = picked);
                    },
                    child: const Text('Set expiry'),
                  ),
                  if (_expiresAt != null)
                    IconButton(
                      onPressed: () => setState(() => _expiresAt = null),
                      icon: const Icon(Icons.clear_rounded, size: 16),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _reasonCtrl,
                style: FrameAdminTheme.fieldTextStyle,
                decoration: FrameAdminTheme.inputDecoration(
                  label: 'Revoke reason (optional)',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => widget.service.assignFrame(
                                userId: _userCtrl.text.trim(),
                                code: widget.frame.code,
                                expiresAt: _expiresAt,
                              ),
                              'Frame assigned',
                            ),
                      child: const Text('Assign'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => widget.service.revokeFrame(
                                userId: _userCtrl.text.trim(),
                                code: widget.frame.code,
                                reason: _reasonCtrl.text.trim().isEmpty
                                    ? null
                                    : _reasonCtrl.text.trim(),
                              ),
                              'Frame revoked',
                            ),
                      child: const Text('Revoke'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── History ──────────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history});

  final List<FrameOwnershipAuditEntry> history;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: FrameAdminTheme.card,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ownership history (latest 50)',
              style: TextStyle(
                color: FrameAdminTheme.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const Text('No entries yet.', style: FrameAdminTheme.metaStyle)
            else
              for (final entry in history)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${entry.createdAt?.toLocal().toString().split('.').first ?? ''}'
                    '  ${entry.action.toUpperCase()}  ${entry.frameCode ?? ''}'
                    '  user:${entry.userId?.substring(0, 8) ?? '-'}',
                    style: TextStyle(
                      color: entry.action == 'violation'
                          ? FrameAdminTheme.danger
                          : FrameAdminTheme.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
