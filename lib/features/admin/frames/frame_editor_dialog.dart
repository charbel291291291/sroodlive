/// Frame Management v2 — the frame editor dialog.
///
/// Replaces the old `_FrameEditorSheet`: a flat list of 16 bare `TextField`s
/// inside a bottom sheet whose Save button scrolled off the end and which
/// silently dropped four database columns on every save.
///
/// Layout contract (requirement 2): a width-capped [Dialog] at most 90% of the
/// viewport tall, with a sticky header, a single scrolling body, and a sticky
/// footer holding Cancel and Save. Save is never off screen and never hidden,
/// at any of the sizes the layout test exercises.
///
/// Everything an admin *must* decide is visible; everything derivable is
/// derived and tucked into Advanced, which still reaches every `frame_catalog`
/// column so nothing became unreachable.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/frames/srood_frame.dart';
import '../../../shared/utils/error_utils.dart';
import '../exceptions/frame_admin_exception.dart';
import '../services/frame_admin_service.dart';
import '../services/frame_artwork_upload_service.dart';
import '../theme/frame_admin_theme.dart';
import 'frame_artwork_field.dart';
import 'frame_editor_form.dart';
import 'frame_live_preview.dart';

/// Opens the editor. Resolves to the saved frame, or null if the admin
/// cancelled — nothing is written to the catalog until Save succeeds, which is
/// what makes Duplicate safe (requirement 8).
Future<SroodFrame?> showFrameEditorDialog(
  BuildContext context, {
  required FrameEditorState state,
  required List<SroodFrame> catalog,
  FrameAdminService? adminService,
  FrameArtworkUploadService? uploadService,
}) {
  return showDialog<SroodFrame>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (context) => FrameEditorDialog(
      state: state,
      catalog: catalog,
      adminService: adminService,
      uploadService: uploadService,
    ),
  );
}

class FrameEditorDialog extends StatefulWidget {
  const FrameEditorDialog({
    required this.state,
    required this.catalog,
    this.adminService,
    this.uploadService,
    super.key,
  });

  final FrameEditorState state;
  final List<SroodFrame> catalog;

  /// Injected in tests; production uses the defaults.
  final FrameAdminService? adminService;
  final FrameArtworkUploadService? uploadService;

  @override
  State<FrameEditorDialog> createState() => _FrameEditorDialogState();
}

class _FrameEditorDialogState extends State<FrameEditorDialog> {
  late final FrameEditorState _state = widget.state;
  late final FrameAdminService _admin =
      widget.adminService ?? FrameAdminService();
  late final FrameArtworkUploadService _uploads =
      widget.uploadService ?? FrameArtworkUploadService();

  late final TextEditingController _name = TextEditingController(
    text: _state.name,
  );
  late final TextEditingController _code = TextEditingController(
    text: _state.code,
  );
  late final TextEditingController _arabicName = TextEditingController(
    text: _state.arabicName,
  );
  late final TextEditingController _assetUrl = TextEditingController(
    text: _state.assetUrl ?? '',
  );
  late final TextEditingController _thumbnailUrl = TextEditingController(
    text: _state.thumbnailUrl ?? '',
  );
  late final TextEditingController _animationUrl = TextEditingController(
    text: _state.animationUrl ?? '',
  );
  late final TextEditingController _unlockValue = TextEditingController(
    text: _state.unlockValue ?? '',
  );
  late final TextEditingController _requiredLevel = TextEditingController(
    text: _state.requiredLevel?.toString() ?? '',
  );
  late final TextEditingController _sortOrder = TextEditingController(
    text: _state.sortOrder.toString(),
  );

  final ScrollController _scroll = ScrollController();

  bool _saving = false;
  bool _uploading = false;
  bool _advancedOpen = false;

  /// Set once the admin edited a field, so Cancel can warn about losing work.
  bool _dirty = false;

  FrameArtworkCandidate? _candidate;
  String? _artworkError;

  /// Storage path of an object uploaded during *this* editing session. If the
  /// catalog write fails it is an orphan and gets removed; the frame's previous
  /// object is never touched before the database write succeeds (requirement 9).
  String? _pendingUploadPath;

  /// A previous session-local upload superseded by a newer one.
  final List<String> _supersededUploadPaths = <String>[];

  String? _saveError;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _arabicName.dispose();
    _assetUrl.dispose();
    _thumbnailUrl.dispose();
    _animationUrl.dispose();
    _unlockValue.dispose();
    _requiredLevel.dispose();
    _sortOrder.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _edit(VoidCallback mutate) {
    setState(() {
      mutate();
      _dirty = true;
      _saveError = null;
    });
  }

  List<FrameEditorIssue> get _issues => _state.validate();

  String? _issueFor(FrameEditorField field) {
    for (final issue in _issues) {
      if (issue.field == field) return issue.message;
    }
    return null;
  }

  // ---------------------------------------------------------------- name/code

  void _onNameChanged(String value) {
    _edit(() {
      _state.name = value;
      final before = _state.code;
      final after = _state.syncCodeFromName();
      if (after != before) _code.text = after;
    });
  }

  void _regenerateCode() {
    _edit(() {
      _state.codeIsManual = false;
      _code.text = _state.syncCodeFromName(force: true);
    });
  }

  // -------------------------------------------------------------- VIP / roles

  /// Switching unlock method or category can strip VIP or role values. When the
  /// value being stripped was deliberately chosen, confirm first (requirement 5)
  /// — the values are only cleared after the admin agrees.
  Future<bool> _confirmClearing(String what) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FrameAdminTheme.surface,
        title: Text(
          'Clear $what?',
          style: const TextStyle(color: FrameAdminTheme.textPrimary),
        ),
        content: Text(
          'This unlock method does not use $what, so the current value will be '
          'removed from the frame.',
          style: const TextStyle(color: FrameAdminTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: FrameAdminTheme.accent,
              foregroundColor: const Color(0xFF1A0B2E),
            ),
            child: Text('Clear $what'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _onUnlockTypeChanged(SroodFrameUnlock next) async {
    if (next == _state.unlockType) return;
    final previous = _state.unlockType;

    // Evaluate the *next* configuration before committing to it.
    _state.unlockType = next;
    final losesVip = !_state.usesVipLevel && _state.hasMeaningfulVipValue;
    final losesRole = !_state.usesRequiredRole && _state.hasMeaningfulRoleValue;
    _state.unlockType = previous;

    if (losesVip && !await _confirmClearing('the VIP level')) return;
    if (losesRole && !await _confirmClearing('the required role')) return;
    if (!mounted) return;

    _edit(() {
      _state.unlockType = next;
      if (!_state.usesVipLevel) _state.vipTier = null;
      if (!_state.usesRequiredRole) _state.requiredRole = null;
      if (!_state.codeIsManual) _code.text = _state.syncCodeFromName();
    });
  }

  Future<void> _onCategoryChanged(SroodFrameCategory next) async {
    if (next == _state.category) return;
    final previous = _state.category;

    _state.category = next;
    final losesVip = !_state.usesVipLevel && _state.hasMeaningfulVipValue;
    _state.category = previous;

    if (losesVip && !await _confirmClearing('the VIP level')) return;
    if (!mounted) return;

    _edit(() {
      _state.category = next;
      if (!_state.usesVipLevel) _state.vipTier = null;
      if (_state.isNew) {
        final order = nextSortOrder(widget.catalog, next);
        _state.sortOrder = order;
        _sortOrder.text = order.toString();
      }
      if (!_state.codeIsManual) _code.text = _state.syncCodeFromName();
    });
  }

  // ----------------------------------------------------------------- artwork

  Future<void> _pickAndUpload() async {
    final frameCode = _state.code.trim();
    if (frameCode.isEmpty) return;

    setState(() {
      _artworkError = null;
      _uploading = true;
    });

    try {
      final candidate = await _uploads.pick();
      if (candidate == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }
      if (!candidate.validation.isValid) {
        if (mounted) {
          setState(() {
            _uploading = false;
            _candidate = null;
            _artworkError = candidate.validation.errors.join('\n');
          });
        }
        return;
      }

      final upload = await _uploads.upload(
        candidate: candidate,
        category: _state.category.wire,
        frameCode: frameCode,
      );
      if (!mounted) return;

      // A prior upload in this same session is now unreferenced. It was never
      // written to the catalog, so removing it cannot orphan a live row.
      final previous = _pendingUploadPath;
      if (previous != null && previous != upload.path) {
        _supersededUploadPaths.add(previous);
      }

      setState(() {
        _uploading = false;
        _dirty = true;
        _candidate = candidate;
        _pendingUploadPath = upload.path;
        _state.applyArtwork(url: upload.url, animated: candidate.isAnimated);
        _assetUrl.text = upload.url;
        _animationUrl.text = _state.animationUrl ?? '';
        _saveError = null;
      });
    } catch (error, stack) {
      debugError('FrameEditorDialog.upload', error, stack);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _artworkError = mapFrameAdminError(error).message;
      });
    }
  }

  void _clearArtwork() {
    _edit(() {
      _state.clearArtwork();
      _candidate = null;
      _artworkError = null;
      _assetUrl.text = '';
      _animationUrl.text = '';
      _thumbnailUrl.text = '';
    });
  }

  // -------------------------------------------------------------------- save

  Future<void> _save() async {
    if (_saving || _uploading) return;
    if (_issues.isNotEmpty) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });

    final frame = _state.toFrame();
    try {
      if (_state.isNew) {
        // Fast, readable duplicate error before the round trip. The RPC's own
        // `frame_code_exists` remains the authority — this only saves a
        // failed write.
        if (await _admin.frameCodeExists(frame.code)) {
          throw frameAdminError(
            FrameAdminErrorCategory.duplicateCode,
            'frame_code_exists',
            'A frame with the code "${frame.code}" already exists. '
                'Choose a different code in Advanced.',
          );
        }
        await _admin.createFrame(frame);
      } else {
        await _admin.upsertFrame(frame);
      }

      // The catalog row now points at the new object, so anything it replaced
      // within this session can go.
      await _discardOrphans(_supersededUploadPaths);
      if (!mounted) return;
      Navigator.of(context).pop(frame);
    } catch (error, stack) {
      debugError('FrameEditorDialog.save', error, stack);
      final mapped = mapFrameAdminError(error);

      // The database was not updated, so the frame's previous artwork is still
      // the live one. Only this session's new upload is an orphan.
      final orphans = <String>[..._supersededUploadPaths, ?_pendingUploadPath];
      final removed = await _discardOrphans(orphans);

      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = removed
            ? mapped.message
            : '${mapped.message}\n'
                  'The uploaded artwork could not be cleaned up automatically; '
                  'it is unreferenced and safe to leave.';
        if (mapped.category == FrameAdminErrorCategory.duplicateCode) {
          _advancedOpen = true;
        }
      });
    }
  }

  /// Best-effort removal. Returns false if any delete failed.
  Future<bool> _discardOrphans(List<String> paths) async {
    if (paths.isEmpty) return true;
    var allRemoved = true;
    for (final path in List<String>.of(paths)) {
      final removed = await _uploads.deleteObject(path);
      if (removed) {
        paths.remove(path);
      } else {
        allRemoved = false;
      }
    }
    return allRemoved;
  }

  Future<void> _cancel() async {
    if (_saving) return;
    if (_dirty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: FrameAdminTheme.surface,
          title: const Text(
            'Discard changes?',
            style: TextStyle(color: FrameAdminTheme.textPrimary),
          ),
          content: const Text(
            'Nothing has been saved to the catalog yet.',
            style: TextStyle(color: FrameAdminTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: FrameAdminTheme.danger,
              ),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (leave != true) return;
      // Uploads made but never saved are unreferenced.
      await _discardOrphans([..._supersededUploadPaths, ?_pendingUploadPath]);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final issues = _issues;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: FrameAdminTheme.dialogMaxWidth,
          maxHeight: media.height * 0.9,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: FrameAdminTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FrameAdminTheme.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              Expanded(
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _body(),
                    ),
                  ),
                ),
              ),
              _footer(issues),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FrameAdminTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _state.isNew ? 'New frame' : 'Edit frame',
                  style: const TextStyle(
                    color: FrameAdminTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _state.code.isEmpty
                      ? 'Code generated from name'
                      : _state.code,
                  style: FrameAdminTheme.metaStyle,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _saving ? null : _cancel,
            icon: const Icon(Icons.close_rounded),
            color: FrameAdminTheme.textMuted,
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  List<Widget> _body() {
    return [
      const SizedBox(height: 12),
      TextField(
        controller: _name,
        style: FrameAdminTheme.fieldTextStyle,
        textCapitalization: TextCapitalization.words,
        decoration: FrameAdminTheme.inputDecoration(
          label: 'Frame name',
          hint: 'Celestial Crown',
          helper: _state.codeIsManual
              ? null
              : 'The frame code is generated from this name.',
          error: _issueFor(FrameEditorField.name),
        ),
        onChanged: _onNameChanged,
      ),
      const SizedBox(height: 12),
      FrameFieldPair(
        first: _dropdown<SroodFrameCategory>(
          label: 'Category',
          value: _state.category,
          options: SroodFrameCategory.values,
          format: _categoryLabel,
          onChanged: (v) => _onCategoryChanged(v),
          error: _issueFor(FrameEditorField.category),
        ),
        second: _dropdown<SroodFrameUnlock>(
          label: 'Unlock method',
          value: _state.unlockType,
          options: SroodFrameUnlock.values,
          format: _unlockLabel,
          onChanged: (v) => _onUnlockTypeChanged(v),
          error: _issueFor(FrameEditorField.unlockType),
        ),
      ),
      if (_state.usesVipLevel) ...[
        const SizedBox(height: 12),
        _dropdown<int?>(
          label: 'VIP level',
          value: _state.vipTier,
          options: <int?>[
            null,
            for (var i = kFrameMinVipLevel; i <= kFrameMaxVipLevel; i++) i,
          ],
          format: (v) => v == null ? 'Select a VIP level…' : 'VIP $v',
          onChanged: (v) => _edit(() {
            _state.vipTier = v;
            if (!_state.codeIsManual) _code.text = _state.syncCodeFromName();
          }),
          error: _issueFor(FrameEditorField.vipLevel),
          helper:
              'Sets both vip_level and required_vip_level — one value, so they '
              'cannot disagree.',
        ),
      ],
      if (_state.usesRequiredRole) ...[
        const SizedBox(height: 12),
        _dropdown<String?>(
          label: 'Required role',
          value: kFrameRequiredRoles.contains(_state.requiredRole)
              ? _state.requiredRole
              : null,
          options: <String?>[null, ...kFrameRequiredRoles],
          format: (v) => v ?? 'Select a role…',
          onChanged: (v) => _edit(() => _state.requiredRole = v),
          error: _issueFor(FrameEditorField.requiredRole),
          helper:
              'Matched against app_user_roles. An admin recorded only in '
              'admin_users will not unlock this frame.',
        ),
      ],
      const SizedBox(height: 14),
      FrameArtworkField(
        assetUrl: _state.assetUrl,
        isAnimated: _state.isAnimated,
        isUploading: _uploading,
        candidate: _candidate,
        uploadError: _artworkError ?? _issueFor(FrameEditorField.artwork),
        enabled: _state.code.trim().isNotEmpty,
        disabledReason:
            'Enter a frame name first — the storage path is built from the '
            'frame code.',
        onUpload: _pickAndUpload,
        onClear: _clearArtwork,
      ),
      const SizedBox(height: 14),
      FrameLivePreview(frame: _state.toFrame(), isUploading: _uploading),
      const SizedBox(height: 14),
      _switchTile(
        title: 'Active',
        subtitle:
            'Inactive frames stay in the catalog but nobody can equip '
            'them.',
        value: _state.isActive,
        onChanged: (v) => _edit(() => _state.isActive = v),
      ),
      const SizedBox(height: 8),
      _advanced(),
    ];
  }

  Widget _advanced() {
    // A Material, not a DecoratedBox: ExpansionTile's header is a ListTile,
    // which paints its background and ink on the nearest Material ancestor.
    // A coloured box in between hides both, and asserts in debug builds.
    return Material(
      color: FrameAdminTheme.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: FrameAdminTheme.border),
      ),
      child: Theme(
        // Strips the divider lines ExpansionTile draws by default, which read
        // as stray hairlines on this palette.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('advanced-$_advancedOpen'),
          initiallyExpanded: _advancedOpen,
          onExpansionChanged: (open) => _advancedOpen = open,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: FrameAdminTheme.accent,
          collapsedIconColor: FrameAdminTheme.textMuted,
          title: const Text('Advanced', style: FrameAdminTheme.sectionTitle),
          subtitle: const Text(
            'Code, asset wiring, scheduling, sort order',
            style: FrameAdminTheme.metaStyle,
          ),
          children: [
            TextField(
              controller: _code,
              style: FrameAdminTheme.fieldTextStyle,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
              ],
              decoration: FrameAdminTheme.inputDecoration(
                label: 'Frame code',
                helper:
                    'Lowercase letters, numbers and underscores. '
                    'Must be unique.',
                error: _issueFor(FrameEditorField.code),
                suffix: IconButton(
                  onPressed: _regenerateCode,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  color: FrameAdminTheme.accent,
                  tooltip: 'Regenerate from name',
                ),
              ),
              onChanged: (value) => _edit(() {
                _state.code = value;
                _state.codeIsManual = true;
              }),
            ),
            const SizedBox(height: 12),
            FrameFieldPair(
              first: _dropdown<SroodFrameRarity>(
                label: 'Rarity',
                value: _state.rarity,
                options: SroodFrameRarity.values,
                format: (v) => _titleCase(v.wire),
                onChanged: (v) => _edit(() => _state.rarity = v),
              ),
              second: _dropdown<SroodFrameAssetType>(
                label: 'Asset type',
                value: _state.assetType,
                options: SroodFrameAssetType.values,
                format: (v) => _titleCase(v.wire),
                onChanged: (v) => _edit(() => _state.assetType = v),
                helper: 'Derived from the artwork you upload.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _assetUrl,
              style: FrameAdminTheme.fieldTextStyle,
              decoration: FrameAdminTheme.inputDecoration(
                label: 'Asset URL',
                helper:
                    'Filled in by the upload. Edit only to point at an '
                    'existing bundled asset.',
              ),
              onChanged: (value) => _edit(() {
                _state.assetUrl = value;
                _state.assetType = assetTypeForUrl(value);
              }),
            ),
            const SizedBox(height: 12),
            FrameFieldPair(
              first: TextField(
                controller: _thumbnailUrl,
                style: FrameAdminTheme.fieldTextStyle,
                decoration: FrameAdminTheme.inputDecoration(
                  label: 'Thumbnail URL',
                ),
                onChanged: (v) => _edit(() => _state.thumbnailUrl = v),
              ),
              second: TextField(
                controller: _animationUrl,
                style: FrameAdminTheme.fieldTextStyle,
                decoration: FrameAdminTheme.inputDecoration(
                  label: 'Animation URL',
                ),
                onChanged: (v) => _edit(() => _state.animationUrl = v),
              ),
            ),
            const SizedBox(height: 12),
            FrameFieldPair(
              first: TextField(
                controller: _unlockValue,
                style: FrameAdminTheme.fieldTextStyle,
                decoration: FrameAdminTheme.inputDecoration(
                  label: 'Unlock value',
                  helper: 'Free-form: SKU, event id, reward key.',
                ),
                onChanged: (v) => _edit(() => _state.unlockValue = v),
              ),
              second: TextField(
                controller: _requiredLevel,
                style: FrameAdminTheme.fieldTextStyle,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: FrameAdminTheme.inputDecoration(
                  label: 'Required user level',
                ),
                onChanged: (v) =>
                    _edit(() => _state.requiredLevel = int.tryParse(v)),
              ),
            ),
            const SizedBox(height: 12),
            FrameFieldPair(
              first: TextField(
                controller: _sortOrder,
                style: FrameAdminTheme.fieldTextStyle,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: FrameAdminTheme.inputDecoration(
                  label: 'Sort order',
                  error: _issueFor(FrameEditorField.sortOrder),
                ),
                onChanged: (v) =>
                    _edit(() => _state.sortOrder = int.tryParse(v) ?? 0),
              ),
              second: TextField(
                controller: _arabicName,
                style: FrameAdminTheme.fieldTextStyle,
                decoration: FrameAdminTheme.inputDecoration(
                  label: 'Arabic name',
                  helper: 'Stored in localized_names.ar.',
                ),
                onChanged: (v) => _edit(() => _state.arabicName = v),
              ),
            ),
            const SizedBox(height: 12),
            FrameFieldPair(
              first: _dateField(
                label: 'Starts at',
                value: _state.startsAt,
                onChanged: (v) => _edit(() => _state.startsAt = v),
              ),
              second: _dateField(
                label: 'Expires at',
                value: _state.expiresAt,
                onChanged: (v) => _edit(() => _state.expiresAt = v),
                error: _issueFor(FrameEditorField.schedule),
              ),
            ),
            const SizedBox(height: 4),
            _switchTile(
              title: 'Animated',
              subtitle: 'Set automatically from the uploaded file.',
              value: _state.isAnimated,
              onChanged: (v) => _edit(() => _state.isAnimated = v),
            ),
            const SizedBox(height: 6),
            _readOnlyRow(
              'Legacy frame key',
              _state.legacyFrameKey ?? '—',
              'Maps this frame to a pre-v2 frame_key. Read-only: the catalog '
                  'RPCs have no parameter for it.',
            ),
            if (!_state.isNew)
              _readOnlyRow('Frame id', _state.original?.id ?? '—', null),
          ],
        ),
      ),
    );
  }

  Widget _footer(List<FrameEditorIssue> issues) {
    final blocked = issues.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: const BoxDecoration(
        color: FrameAdminTheme.surface,
        border: Border(top: BorderSide(color: FrameAdminTheme.border)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_saveError != null) ...[
            _FooterNote(
              icon: Icons.error_outline_rounded,
              color: FrameAdminTheme.danger,
              text: _saveError!,
            ),
            const SizedBox(height: 10),
          ] else if (blocked) ...[
            _FooterNote(
              icon: Icons.info_outline_rounded,
              color: FrameAdminTheme.warning,
              text: issues.first.message,
            ),
            const SizedBox(height: 10),
          ],
          // Wrap, not Row: on a narrow phone (or with a long label at a large
          // text scale) the two buttons stack instead of overflowing, so Save
          // is always reachable.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: _saving ? null : _cancel,
                style: TextButton.styleFrom(
                  foregroundColor: FrameAdminTheme.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: (blocked || _saving || _uploading) ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: FrameAdminTheme.accent,
                  foregroundColor: const Color(0xFF1A0B2E),
                  disabledBackgroundColor: const Color(0xFF2A1C3F),
                  disabledForegroundColor: FrameAdminTheme.textMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: FrameAdminTheme.textMuted,
                        ),
                      )
                    : Text(_state.isNew ? 'Create frame' : 'Save changes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- field parts

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> options,
    required String Function(T) format,
    required ValueChanged<T> onChanged,
    String? helper,
    String? error,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: FrameAdminTheme.raisedCard,
      style: FrameAdminTheme.fieldTextStyle,
      iconEnabledColor: FrameAdminTheme.textMuted,
      decoration: FrameAdminTheme.inputDecoration(
        label: label,
        helper: helper,
        error: error,
      ),
      items: [
        for (final option in options)
          DropdownMenuItem<T>(
            value: option,
            child: Text(format(option), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (selected) {
        if (selected != null || null is T) onChanged(selected as T);
      },
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
    String? error,
  }) {
    return InputDecorator(
      decoration: FrameAdminTheme.inputDecoration(label: label, error: error),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value == null
                  ? 'Not set'
                  : value.toLocal().toIso8601String().split('T').first,
              style: TextStyle(
                color: value == null
                    ? FrameAdminTheme.textMuted
                    : FrameAdminTheme.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 5),
              );
              if (picked != null) onChanged(picked);
            },
            icon: const Icon(Icons.event_rounded, size: 18),
            color: FrameAdminTheme.accent,
            tooltip: 'Pick a date',
          ),
          if (value != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.clear_rounded, size: 16),
              color: FrameAdminTheme.textMuted,
              tooltip: 'Clear',
            ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: FrameAdminTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FrameAdminTheme.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: FrameAdminTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: FrameAdminTheme.metaStyle),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: FrameAdminTheme.accent,
          ),
        ],
      ),
    );
  }

  Widget _readOnlyRow(String label, String value, String? helper) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: FrameAdminTheme.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FrameAdminTheme.textPrimary,
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          if (helper != null) ...[
            const SizedBox(height: 3),
            Text(helper, style: FrameAdminTheme.metaStyle),
          ],
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }
}

String _titleCase(String wire) {
  return wire
      .split('_')
      .map(
        (part) =>
            part.isEmpty ? part : part[0].toUpperCase() + part.substring(1),
      )
      .join(' ');
}

String _categoryLabel(SroodFrameCategory category) => switch (category) {
  SroodFrameCategory.vip => 'VIP',
  SroodFrameCategory.superAdmin => 'Super admin',
  SroodFrameCategory.specialEdition => 'Special edition',
  _ => _titleCase(category.wire),
};

String _unlockLabel(SroodFrameUnlock unlock) => switch (unlock) {
  SroodFrameUnlock.free => 'Free — everyone',
  SroodFrameUnlock.vipLevel => 'VIP level',
  SroodFrameUnlock.role => 'Role',
  SroodFrameUnlock.level => 'User level',
  SroodFrameUnlock.purchase => 'Purchase',
  SroodFrameUnlock.reward => 'Reward',
  SroodFrameUnlock.adminGrant => 'Admin grant only',
  SroodFrameUnlock.event => 'Event',
};
