# Room UI v2 — Phase 1 Audit & Dependency Map

Date: 2026-07-13. Read-only audit; no code changed in this phase.

## 1. File inventory

### The monolith (primary replacement target)

`lib/features/rooms/screens/room_details_screen.dart` — 12,918 lines (452 KB).

| Region | Lines | Classification |
| --- | --- | --- |
| Imports + seat constants | 1–68 | mixed (constants move to design system) |
| `RoomDetailsScreen` (public API) | 69–81 | **contract — keep** (`room`, `isArabic`) |
| `_RoomDetailsScreenState` | 83–4520 | **logic — keep** (state ownership, services, realtime, LiveKit, timers). Only `build()` (4064–4518) is rewired. |
| ~80 private presentation classes | 4521–12918 | **presentation — replace** |

### Private presentation classes to replace

- Header/background: `_CompactRoomHeader`, `_FullRoomBackground`, `_RoomGradientBg`, `_RoomIdChip`, `_RoomLevelBadge`, `_MiniRoomStatusPill`
- Stage/seats: `_LiveRoomStage`, `_SeatGrid`, `_StageSeat`, `RoomSeatTheme`, `_LiveSeatBubble`, `_LuxuryEmptySeat`, `_SeatSmileyAccent`, `_EmptySeatAction`, `_OccupiedSeatAction`
- Chat: `_LiveChatPanel` (unused by build), `_ChatBubbleRow`, `_RoomChatFeed`, `_ChatImageThumbnail`
- Banners: `_GiftRoomBanner`, `_VipEntryRoomBanner`, `_UserEntryRoomBanner`, `_GiftMiniImage`, `_GiftFeedRow`
- Gift overlays: `_GiftEventOverlay`, `_GiftEventBanner`, `_GiftSendResult`, `_RoomGiftEvent`, `_ActiveLuxuryGiftVideo`, `_LuxuryGiftVideoConfig`, `_LuxuryGiftVideoOverlay`, `_LuxuryGiftInfoCard`
- Gift sheet: `_GiftSheet`, `_GiftSheetGrabber`, `_GiftReceiverRail`, `_RoomAvatar`, `_GiftReceiverBubble`, `_GiftCategoryTabs`, `_GiftArtwork`, `_GiftCard`, `_GiftSendBar`, `_QuantityChip`
- Bottom bar: `_LiveBottomActionBar` (+composer/mentions), `_QuickActionBtn`, `_SupportPill`
- Lucky bag / envelope: `_RedEnvelopeBanner`, `_BannerBagIcon`, `_LuckyBagEntranceOverlay`, `_LuckyBagWinOverlay`
- Exit/close: `_RoomExitSheet`, `_ExitOption`, `_RoomExitAction`, `_RoomClosingOverlay`, `_VaultRingPainter`, `_PulsingDots`
- Participants: `_RoomParticipantsSheet`, `_CompactParticipantRow`
- Level/XP: `_LevelData`, `_RoomLevelInfo`, `_RoomLevelProgressSheet`, `_XpStatCard`, `_RoomLevelUpOverlay`, `_GlowingCrown`, `_LevelPill`, `_SparklePainter`

### External room widgets — KEEP (functional, referenced by state logic)

- `widgets/room_tools_sheet.dart` (3,222 ln) — `RoomToolsSheet` + lucky bag/PK/game-center sub-sheets
- `widgets/music_panel.dart` (1,438 ln), `widgets/room_mini_player.dart` — music UI bound to `RoomMusicService`/`RoomSyncedMusicService`
- `widgets/pk_stage_overlay.dart` — `PkBanner`, `PkResultBanner`, `PkBattleBar`, `pkSeatTeam`, `kPkRed/kPkBlue`
- `widgets/pk_start_sheet.dart`, `widgets/reaction_picker_sheet.dart`, `widgets/seat_reaction_overlay.dart`, `widgets/vault_pin_sheet.dart`, `widgets/agent_identity_badge.dart`, `widgets/room_settings_sheet.dart`, `widgets/room_details/room_status_badges.dart`
- `features/profile/widgets/room_user_profile_sheet.dart`
- Shared: `avatar_with_frame.dart`, `vip_framed_avatar.dart`, `vip_badge.dart`, `vip_username.dart`, `vip_mic_wave_ring.dart`, `srood_toast.dart`, `floating_room_bar.dart`

### Services / models — DO NOT TOUCH

All of `lib/features/rooms/services/` (LiveKit, rooms, gifts, messages, music ×3, management, read, chat-image, PK, token) and `lib/features/rooms/models/`.

## 2. State ownership (all in `_RoomDetailsScreenState`)

- **Realtime channels**: `_roomChannel`, `_membersChannel`, `_giftTransactionsChannel`, `_walletChannel`, `_messagesChannel`, `_reactionsChannel`, `_redEnvelopesChannel`
- **Streams/listeners**: `_pkSub` (`TeamPkService.watchPk`), `_musicService.addListener`, LiveKit callbacks `onSpeakersChanged` / `onConnected` (via `LiveKitRoomService`)
- **Timers**: heartbeat, members refresh + debounce, reconnect debounce, gift banner/feed cleanup, VIP/entry banner, luxury video, reaction timers, banner auto-hide
- **Notifiers (partial rebuild)**: `_audioStateNotifier`, `_giftBannerNotifier`, `_vipBannerNotifier`, `_entryBannerNotifier`
- **Minimize/restore**: `ActiveRoomSession` reuse of LiveKit + music services; `VoiceRoomForegroundService`

## 3. Callback contract the new UI must accept (from current `build()`)

- **Header zone**: room meta (`_currentRoom`, name/level/xp/streak), `_activeSpeakerCount`, `_members.length`, `_walletCoins`, `_activeAnnouncementText`, `_showRoomLevelSheet`, `_openRoomManagement` (owner/host only), `_confirmLeave`, `_leaving`
- **Stage**: `_members`, `_currentMaxSeats`, `_pickListenerForSeat` (empty tap), `_handleOccupiedSeatTap`, `_showMemberSeatActions` (long-press), `_openUserProfileSheet`, `_showParticipantsSheet`, `_giftSupportByUserId`, `_selectedMicMoveMember`, `_speakingUserIds`, `_moderatorUserIds`, `_closedSeats`, `_toggleSeatClosed`, `_roomLevel`, `_activePk`/`_showPkResult`/`_handlePkAutoFinish`, `_seatReactions`
- **Chat**: `_chatMessages`, `_openUserProfileSheet`, `_removeMessage` (gated `_canRemoveMessages`), `_reportChatMessage`
- **Bottom bar**: audio notifier, `_micToggleBusy`, `_micEnabled`, `_isCurrentUserOnMic`, `_leaving`, `_isSendingMessage`, VIP level, `_uploadingChatImage`, `_toggleMic`, `_leaveRoom`, `_openGiftSheet`, `_openToolsSheet`, `_openReactionPicker`, `_openInbox`, `_inboxUnreadCount`, `_sendChatMessage`, `_sendChatImageMessage`, `_members` (mentions)
- **Music chip**: `_musicService`, `_syncedMusic.lastState`, `_openMusicPanel`, `_stopMusicForRoom`, `_musicAction`
- **Overlays**: `_giftEvents`, `_activeLuxuryGiftVideo` + `_clearLuxuryGiftVideo`, `_activeRedEnvelope` + `_claimRedEnvelope`/`_dismissRedEnvelope`, `_showLuckyBagEntrance`, `_luckyBagWinCoins`, `_isClosingRoom`, `_soundEnabled`/`_visualEnabled`

## 4. Navigation contract (KEEP)

`RoomDetailsScreen(room:, isArabic:)` constructed from: `discovery_screen.dart:371`, `floating_room_bar.dart:81`, `search_screen.dart:392`, `notifications_screen.dart:243`, `rooms_screen.dart:120,227`, `profile_screen.dart:351`.

## 5. Current seat sizing (baseline for parity)

Constants: seat 80 / min 78, box 96×116, label area 38–42. `_SeatGrid` computes per-layout: ≤6 → (80, 76, 84), ≤9 → (78, 72, 80), ≤12 → (70, 66, 74), else (64, 58, 68); cols = 3 (≤9 seats) or 4 (12). Empty and occupied already share the shell size — v2 must preserve this invariant with new tokens.

## 6. Replacement strategy

Keep `RoomDetailsScreen` + `_RoomDetailsScreenState` (public name, constructor, all logic). Replace `build()` composition + delete private presentation classes. New widgets live in `lib/features/rooms/presentation/`. Complex overlays with embedded behavior (luxury video controller, envelope countdown, lucky-bag audio/animation, closing vault animation) are ported faithfully with a re-skin, not re-engineered.
