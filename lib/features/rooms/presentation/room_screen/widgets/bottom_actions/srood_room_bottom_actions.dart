/// Pinned bottom control zone: keyboard-aware composer (with @mention
/// suggestions and VIP-gated image sending) plus the quick-action row —
/// mic, emoji reactions, private messages (unread badge), gift, and tools.
///
/// Music, games, and speaker routing remain reachable through the tools
/// sheet (`onMoreTap`), preserving the existing state paths. All callbacks
/// are owned by the screen state; this widget owns only text-editing state.
library;

import 'package:flutter/material.dart';

import '../../../../models/room_member.dart';
import '../../../theme/srood_room_theme.dart';

class SroodRoomBottomActions extends StatefulWidget {
  const SroodRoomBottomActions({
    required this.isArabic,
    required this.connectingAudio,
    required this.micEnabled,
    required this.isOnMic,
    required this.leaving,
    required this.isSendingMessage,
    required this.myVipLevel,
    required this.isUploadingImage,
    required this.onToggleMic,
    required this.onGiftTap,
    required this.onMoreTap,
    required this.onReactionTap,
    required this.onInboxTap,
    required this.inboxUnreadCount,
    required this.onSendMessage,
    required this.onSendImage,
    this.members = const [],
    this.bottomPad = 0,
    super.key,
  });

  final bool isArabic;
  final bool connectingAudio;
  final bool micEnabled;
  final bool isOnMic;
  final bool leaving;
  final bool isSendingMessage;
  final int myVipLevel;
  final bool isUploadingImage;
  final VoidCallback onToggleMic;
  final VoidCallback onGiftTap;
  final VoidCallback onMoreTap;
  final VoidCallback onReactionTap;
  final VoidCallback onInboxTap;
  final int inboxUnreadCount;
  final Future<void> Function(String) onSendMessage;
  final Future<void> Function() onSendImage;
  final List<RoomMember> members;
  final double bottomPad;

  @override
  State<SroodRoomBottomActions> createState() => _SroodRoomBottomActionsState();
}

class _SroodRoomBottomActionsState extends State<SroodRoomBottomActions> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _isTyping = false;
  bool _isFocused = false;
  List<RoomMember> _mentionSuggestions = const [];

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() => _isFocused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged(String v) {
    final isTyping = v.trim().isNotEmpty;
    // Detect @mention: find last @ before cursor, extract query after it.
    final cursor = _ctrl.selection.baseOffset;
    final text = cursor >= 0 ? v.substring(0, cursor) : v;
    final atIdx = text.lastIndexOf('@');
    List<RoomMember> suggestions = const [];
    if (atIdx >= 0) {
      final query = text.substring(atIdx + 1).toLowerCase();
      // Only suggest when there's no space after @.
      if (!query.contains(' ')) {
        suggestions = widget.members
            .where((m) {
              final name = (m.displayName ?? m.username ?? '').toLowerCase();
              return name.isNotEmpty && (query.isEmpty || name.contains(query));
            })
            .take(5)
            .toList();
      }
    }
    setState(() {
      _isTyping = isTyping;
      _mentionSuggestions = suggestions;
    });
  }

  void _insertMention(RoomMember member) {
    final name =
        member.displayName ?? member.username ?? member.userId.substring(0, 8);
    final text = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset >= 0
        ? _ctrl.selection.baseOffset
        : text.length;
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    final atIdx = before.lastIndexOf('@');
    final newText = atIdx >= 0
        ? '${before.substring(0, atIdx)}@$name $after'
        : '@$name $after';
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: atIdx >= 0 ? atIdx + name.length + 2 : name.length + 2,
      ),
    );
    setState(() {
      _isTyping = newText.trim().isNotEmpty;
      _mentionSuggestions = const [];
    });
    _focus.requestFocus();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || widget.isSendingMessage) return;

    FocusManager.instance.primaryFocus?.unfocus();
    _ctrl.clear();
    setState(() {
      _isTyping = false;
      _mentionSuggestions = const [];
    });
    _focus.requestFocus();
    try {
      await widget.onSendMessage(text);
    } catch (_) {
      // Restore the draft so the user can retry after a send failure.
      if (mounted) {
        _ctrl.text = text;
        _ctrl.selection = TextSelection.collapsed(offset: text.length);
        setState(() => _isTyping = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 50;

    final micColor = widget.isOnMic
        ? (widget.micEnabled ? SroodRoomColors.cyan : SroodRoomColors.danger)
        : Colors.white.withValues(alpha: 0.35);

    final pillBorder = _isFocused
        ? SroodRoomColors.violet.withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.10);

    return Container(
      decoration: BoxDecoration(
        gradient: SroodRoomColors.bottomBarGradient,
        border: Border(
          top: BorderSide(
            color: _isFocused
                ? SroodRoomColors.violet.withValues(alpha: 0.40)
                : SroodRoomColors.violet.withValues(alpha: 0.10),
            width: 0.7,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── @mention suggestion panel ────────────────────────────────────
          if (_mentionSuggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              decoration: BoxDecoration(
                color: SroodRoomColors.bgRaised,
                borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd),
                border: Border.all(color: const Color(0xFF3D2860)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  vertical: SroodRoomDims.space4,
                ),
                itemCount: _mentionSuggestions.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  color: Color(0xFF2A1945),
                  indent: 44,
                ),
                itemBuilder: (_, i) {
                  final m = _mentionSuggestions[i];
                  final name =
                      m.displayName ?? m.username ?? m.userId.substring(0, 8);
                  return InkWell(
                    onTap: () => _insertMention(m),
                    borderRadius: BorderRadius.circular(
                      SroodRoomDims.radiusSm + 2,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SroodRoomDims.space12,
                        vertical: SroodRoomDims.space8,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundImage: m.avatarUrl != null
                                ? NetworkImage(m.avatarUrl!)
                                : null,
                            backgroundColor: const Color(0xFF3D2860),
                            child: m.avatarUrl == null
                                ? const Icon(
                                    Icons.person,
                                    size: 14,
                                    color: Colors.white54,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '@$name',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: SroodRoomDims.textMd,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          Padding(
            padding: EdgeInsets.fromLTRB(10, 4, 10, 5 + widget.bottomPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Row 1: composer pill + send ──────────────────────────────
                Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: AnimatedContainer(
                        duration: SroodRoomMotion.fast,
                        curve: SroodRoomMotion.curve,
                        constraints: const BoxConstraints(minHeight: 40),
                        padding: const EdgeInsetsDirectional.only(start: 12),
                        decoration: BoxDecoration(
                          color: _isFocused
                              ? SroodRoomColors.bg.withValues(alpha: 0.92)
                              : const Color(0xFF1C0E38).withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(
                            SroodRoomDims.radiusXl - 2,
                          ),
                          border: Border.all(color: pillBorder, width: 1.0),
                          boxShadow: _isFocused
                              ? SroodRoomDecor.glow(
                                  SroodRoomColors.violet,
                                  opacity: 0.20,
                                )
                              : const [],
                        ),
                        child: Row(
                          textDirection: isArabic
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 13,
                              color: SroodRoomColors.violet.withValues(
                                alpha: 0.50,
                              ),
                            ),
                            const SizedBox(width: SroodRoomDims.space6),
                            Expanded(
                              child: TextField(
                                controller: _ctrl,
                                focusNode: _focus,
                                textDirection: isArabic
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: SroodRoomDims.textMd,
                                  height: 1.3,
                                ),
                                maxLength: 300,
                                minLines: 1,
                                maxLines: 2,
                                textInputAction: TextInputAction.send,
                                buildCounter:
                                    (
                                      _, {
                                      required currentLength,
                                      required isFocused,
                                      maxLength,
                                    }) => null,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: isArabic
                                      ? 'اكتب شيئاً...'
                                      : 'Say something...',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.46),
                                    fontSize: SroodRoomDims.textMd,
                                  ),
                                ),
                                onChanged: _onTextChanged,
                                onSubmitted: (_) => _submit(),
                              ),
                            ),
                            // Image picker — locked below VIP7. Tap always
                            // routes to onSendImage so the screen can show
                            // the VIP-required notice.
                            const SizedBox(width: SroodRoomDims.space4),
                            SizedBox.square(
                              dimension: 40,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: widget.myVipLevel >= 7
                                    ? (widget.isUploadingImage
                                          ? null
                                          : widget.onSendImage)
                                    : widget.onSendImage,
                                child: Center(
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      if (widget.isUploadingImage &&
                                          widget.myVipLevel >= 7)
                                        const SizedBox(
                                          width: 17,
                                          height: 17,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.6,
                                            color: Color(0x8DFFFFFF),
                                          ),
                                        )
                                      else
                                        Icon(
                                          Icons.image_outlined,
                                          size: 17,
                                          color: Colors.white.withValues(
                                            alpha: widget.myVipLevel >= 7
                                                ? 0.50
                                                : 0.20,
                                          ),
                                        ),
                                      if (widget.myVipLevel < 7)
                                        Positioned(
                                          right: -3,
                                          bottom: -3,
                                          child: Icon(
                                            Icons.lock,
                                            size: 8,
                                            color: Colors.white.withValues(
                                              alpha: 0.40,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    // Send button — glows violet when a draft is ready.
                    Semantics(
                      label: isArabic ? 'إرسال' : 'Send message',
                      button: true,
                      child: GestureDetector(
                        onTap: (_isTyping && !widget.isSendingMessage)
                            ? _submit
                            : null,
                        child: AnimatedContainer(
                          duration: SroodRoomMotion.fast,
                          curve: SroodRoomMotion.curve,
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _isTyping
                                  ? const [
                                      SroodRoomColors.violet,
                                      SroodRoomColors.violetSoft,
                                    ]
                                  : [
                                      Colors.white.withValues(alpha: 0.08),
                                      Colors.white.withValues(alpha: 0.04),
                                    ],
                            ),
                            border: Border.all(
                              color: _isTyping
                                  ? SroodRoomColors.violet.withValues(
                                      alpha: 0.55,
                                    )
                                  : Colors.white.withValues(alpha: 0.10),
                              width: 1.0,
                            ),
                            boxShadow: _isTyping
                                ? SroodRoomDecor.glow(
                                    SroodRoomColors.violet,
                                    opacity: 0.35,
                                  )
                                : const [],
                          ),
                          child: widget.isSendingMessage
                              ? Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: _isTyping
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.30),
                                  ),
                                )
                              : Icon(
                                  Icons.send_rounded,
                                  color: _isTyping
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.25),
                                  size: 18,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Row 2: quick actions (hidden while typing) ──────────────
                if (!keyboardOpen) ...[
                  const SizedBox(height: SroodRoomDims.space4),
                  Row(
                    textDirection: isArabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 1. Mic
                      SroodQuickActionButton(
                        icon: widget.isOnMic
                            ? (widget.micEnabled
                                  ? Icons.mic_rounded
                                  : Icons.mic_off_rounded)
                            : Icons.mic_none_rounded,
                        color: micColor,
                        highlighted: widget.isOnMic && widget.micEnabled,
                        highlightColor: micColor,
                        busy: widget.connectingAudio,
                        onTap: widget.isOnMic && !widget.connectingAudio
                            ? widget.onToggleMic
                            : null,
                        opacity: widget.isOnMic ? 1.0 : 0.38,
                        semanticLabel: isArabic ? 'المايك' : 'Microphone',
                      ),
                      // 2. Emoji / reactions
                      SroodQuickActionButton(
                        icon: Icons.emoji_emotions_outlined,
                        color: Colors.white.withValues(alpha: 0.80),
                        onTap: widget.onReactionTap,
                        semanticLabel: isArabic ? 'تفاعلات' : 'Reactions',
                      ),
                      // 3. Private messages
                      SroodQuickActionButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.80),
                        onTap: widget.onInboxTap,
                        badgeCount: widget.inboxUnreadCount,
                        semanticLabel: isArabic
                            ? 'الرسائل الخاصة'
                            : 'Private messages',
                      ),
                      // 4. Gift
                      SroodQuickActionButton(
                        icon: Icons.card_giftcard_rounded,
                        color: SroodRoomColors.gold,
                        highlighted: true,
                        highlightColor: SroodRoomColors.gold,
                        onTap: widget.onGiftTap,
                        semanticLabel: isArabic ? 'الهدايا' : 'Gifts',
                      ),
                      // 5. Tools / more (music, games, room tools)
                      SroodQuickActionButton(
                        icon: Icons.tune_rounded,
                        color: Colors.white.withValues(alpha: 0.80),
                        onTap: widget.onMoreTap,
                        semanticLabel: isArabic ? 'المزيد' : 'More',
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact circular icon button with a 44px hit target, active state,
/// busy spinner, and an optional unread badge.
class SroodQuickActionButton extends StatelessWidget {
  const SroodQuickActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.semanticLabel,
    this.highlighted = false,
    this.highlightColor,
    this.busy = false,
    this.opacity = 1.0,
    this.badgeCount = 0,
    super.key,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool highlighted;
  final Color? highlightColor;
  final bool busy;
  final double opacity;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final hl = highlightColor ?? color;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: SroodRoomDims.touchTarget,
          height: SroodRoomDims.touchTarget,
          child: Center(
            child: Opacity(
              opacity: onTap == null ? opacity : 1.0,
              child: Badge(
                isLabelVisible: badgeCount > 0,
                label: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(fontSize: 9),
                ),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: highlighted
                        ? hl.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.06),
                    border: Border.all(
                      color: highlighted
                          ? hl.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.09),
                      width: 0.9,
                    ),
                  ),
                  child: busy
                      ? Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: color,
                            ),
                          ),
                        )
                      : Icon(icon, color: color, size: 19),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
