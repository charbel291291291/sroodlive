/// Compact live chat feed with auto-follow and an explicit jump-to-latest
/// pill when the user scrolls up. Renders over the stage with a readability
/// gradient; message data and moderation callbacks are owned by the screen.
library;

import 'package:flutter/material.dart';

import '../../../../services/room_messages_service.dart';
import '../../../theme/srood_room_theme.dart';
import 'srood_chat_message_row.dart';

class SroodRoomChatFeed extends StatefulWidget {
  const SroodRoomChatFeed({
    required this.chatMessages,
    required this.isArabic,
    required this.onProfileTap,
    required this.currentUserId,
    this.bottomPad = 0,
    this.onRemoveTap,
    this.onReportTap,
    super.key,
  });

  final List<RoomMessage> chatMessages;
  final bool isArabic;
  final ValueChanged<String> onProfileTap;
  final double bottomPad;
  final String currentUserId;
  final ValueChanged<RoomMessage>? onRemoveTap;
  final ValueChanged<RoomMessage>? onReportTap;

  @override
  State<SroodRoomChatFeed> createState() => _SroodRoomChatFeedState();
}

class _SroodRoomChatFeedState extends State<SroodRoomChatFeed> {
  final ScrollController _ctrl = ScrollController();
  bool _userScrolledUp = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_ctrl.hasClients) return;
    final atBottom = _ctrl.position.maxScrollExtent - _ctrl.offset < 80;
    if (atBottom == _userScrolledUp) {
      setState(() => _userScrolledUp = !atBottom);
    }
  }

  void _scrollToLatest() {
    if (!_ctrl.hasClients || !mounted) return;
    _ctrl.jumpTo(_ctrl.position.maxScrollExtent);
  }

  void _animateToLatest() {
    if (!_ctrl.hasClients || !mounted) return;
    _ctrl.animateTo(
      _ctrl.position.maxScrollExtent,
      duration: SroodRoomMotion.normal,
      curve: SroodRoomMotion.curve,
    );
  }

  @override
  void didUpdateWidget(SroodRoomChatFeed old) {
    super.didUpdateWidget(old);
    if (widget.chatMessages.length != old.chatMessages.length &&
        !_userScrolledUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ctrl.hasClients && mounted) {
          _animateToLatest();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.30),
            SroodRoomColors.bgDeep.withValues(alpha: 0.62),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: Directionality(
        textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: widget.chatMessages.isEmpty
            ? Align(
                alignment: AlignmentDirectional.bottomStart,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    SroodRoomDims.gutter,
                    0,
                    SroodRoomDims.gutter,
                    10,
                  ),
                  child: Text(
                    widget.isArabic ? 'الدردشة هنا' : 'Chat appears here',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.28),
                      fontSize: SroodRoomDims.textSm,
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              )
            : Stack(
                children: [
                  ListView.builder(
                    controller: _ctrl,
                    padding: EdgeInsets.fromLTRB(
                      10,
                      SroodRoomDims.space8,
                      10,
                      SroodRoomDims.space8 + widget.bottomPad,
                    ),
                    itemCount: widget.chatMessages.length,
                    itemBuilder: (context, index) {
                      final msg = widget.chatMessages[index];
                      return SroodChatMessageRow(
                        message: msg,
                        isArabic: widget.isArabic,
                        onProfileTap: msg.isSystem
                            ? null
                            : () => widget.onProfileTap(msg.senderId),
                        onRemoveTap:
                            (!msg.isSystem &&
                                !msg.isRemoved &&
                                widget.onRemoveTap != null)
                            ? () => widget.onRemoveTap!(msg)
                            : null,
                        onReportTap:
                            (!msg.isSystem &&
                                !msg.isRemoved &&
                                msg.senderId != widget.currentUserId &&
                                widget.onReportTap != null)
                            ? () => widget.onReportTap!(msg)
                            : null,
                      );
                    },
                  ),

                  // Jump-to-latest pill — appears only while scrolled up.
                  if (_userScrolledUp)
                    PositionedDirectional(
                      bottom: SroodRoomDims.space8 + widget.bottomPad,
                      end: SroodRoomDims.space8,
                      child: Semantics(
                        label: widget.isArabic
                            ? 'الانتقال لأحدث الرسائل'
                            : 'Jump to latest messages',
                        button: true,
                        child: GestureDetector(
                          onTap: _animateToLatest,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: SroodRoomColors.violetSoft.withValues(
                                alpha: 0.85,
                              ),
                              borderRadius: BorderRadius.circular(
                                SroodRoomDims.radiusPill,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 0.8,
                              ),
                              boxShadow: SroodRoomDecor.glow(
                                SroodRoomColors.violet,
                                opacity: 0.35,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.arrow_downward_rounded,
                                  color: Colors.white,
                                  size: 12,
                                ),
                                const SizedBox(width: SroodRoomDims.space4),
                                Text(
                                  widget.isArabic ? 'الأحدث' : 'Latest',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: SroodRoomDims.textXs,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
