# Frame System v2 — Performance Notes (Phase 7)

## Raster-pressure mitigations built into v2

| Requirement | Implementation |
|---|---|
| No oversized decodes for small avatars | `SroodAvatarFrame` passes `cacheWidth/cacheHeight` (bundled) and `memCacheWidth/Height` (network) at display size × DPR — same discipline as the legacy widget |
| No full-screen blur | v2 placeholder painters use **zero** `MaskFilter`/`ImageFilter`; "glow" is two layered translucent strokes |
| No nested Opacity | Painters use alpha-carrying colors (`withValues(alpha:)`), never `Opacity` widgets |
| No repeated ClipPath in scrolling | Frames draw as overlays in a `Stack`; only the avatar photo uses the existing single `ClipOval` |
| No rebuilds of animated frames on unrelated state | The animated painter sits behind its own `RepaintBoundary` + `AnimatedBuilder` scoped to the controller only |
| RepaintBoundary only where valuable | Exactly one, around the animated painter layer (mirrors the legacy widget's proven placement) |
| Pause off-screen | Controllers are created with the State's ticker → muted by `TickerMode` on inactive routes; animation is **opt-in per call site** (`animate: false` default), so list/seat call sites stay static unless deliberately enabled |
| Reduced-motion fallback | `MediaQuery.disableAnimations` forces the static frame; verified by test (`transientCallbackCount == 0`) |
| Cache frame assets | Bundled art uses Flutter's image cache with sized decode; network art uses `cached_network_image` |
| Dispose controllers | Verified by widget test (removal leaves 0 transient callbacks; leaked tickers fail `flutter_test`) |
| No duplicated players | At most one `AnimationController` per widget instance, created lazily only when an animated frame is actually visible and motion is allowed (verified: static tiers never create one) |
| Rooms with many framed avatars | The default render path for every existing code is a **delegation to the already-shipped `AvatarWithFrame`** — room grids keep today's exact raster cost until v2 art is deliberately enabled |

## On-device profiling status

**Not run.** This environment has no physical Android device attached, so the
required before/after `--profile` traces (profile scrolling, room scrolling,
seat updates, chat scrolling, leaderboard scrolling, tab switching) could not
be captured. Because v2 renders through the legacy pipeline by default, the
"before" and "after" of this phase are raster-identical until
`preferV2TierArt`/`animate` are enabled — the comparison that matters is the
one gating the new tier art.

### Runbook for the on-device pass (do before enabling v2 art)

```bash
flutter run --profile -d <android-device>
# DevTools → Performance; record 20 s per scenario:
#   1. Profile tab scroll     4. Chat scroll
#   2. Room scroll            5. Leaderboard scroll
#   3. Room seat updates      6. Home→Profile tab switch
# Repeat with preferV2TierArt=true + animate=true on room seats.
# Budget: UI avg < 8 ms, raster avg < 10 ms, no jank cluster > 3 frames.
```
