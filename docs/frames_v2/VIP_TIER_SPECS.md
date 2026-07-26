# Frame System v2 — VIP 1–9 Tier Design Specifications

Original Srood Live visual identities. No third-party artwork, characters,
logos, or copied game/app assets. Placeholder implementation:
`lib/core/frames/frame_tier_painter.dart` (programmatic vector, NOT final).

## Shared production constraints (all tiers)

- Canvas: 1024×1024, transparent background, exported as lossless WebP
  (static) — animated tiers additionally export an animated WebP ≤ 400 KB.
- Circular opening: the transparent avatar hole is centered and ≥ 74 % of the
  canvas min-dimension. The avatar face is never covered; decorations live on
  the rim only (an apex ornament may rise above the rim but never inward).
- Small-size legibility: each tier must be identifiable at 44 px. The tier
  signature = palette + apex notch count (N diamonds for VIP N along the top
  arc) — this survives any art direction change.
- Restraint: no full-canvas glow, no heavy particle fields, no motion blur.
  Glow is a tight rim light. Animated accents affect ≤ 10 % of the rim area.
- Deliverables per tier: `frame.webp` (static), `frame_anim.webp` (tiers 6–9),
  `thumb.webp` (256×256).

## Tier identities

| Tier | Name | Identity | Palette (base / light / dark / accent) | Motion |
|---|---|---|---|---|
| 1 | Bronze Sentinel | Clean brushed-bronze ring, simple bevel geometry, minimal rim light | #B87C36 / #E8AE60 / #6E4318 / #F4D3A0 | none |
| 2 | Silver Meridian | Polished silver ring with fine meridian engraving lines | #B9C2D3 / #F2F5FB / #6B7488 / #DCE4F2 | none |
| 3 | Royal Aurum | Royal gold ring, controlled specular highlights, twin hairline inlays | #D9A62B / #FFE9A8 / #8A6410 / #FFF3C9 | none |
| 4 | Emerald Court | Emerald ring with four gold corner mounts at the diagonals | #1E9E5A / #7BE8AC / #0B5A32 / #F0C15A (gold) | none |
| 5 | Ruby Sovereign | Ruby ring, stronger prestige: gold under-rim + faceted apex ruby | #C81E3E / #FF7A8C / #6E0E20 / #FFD978 (gold) | none |
| 6 | Sapphire Regalia | Sapphire ring, royal profile; three slow orbiting light studs | #1A5CE8 / #80CCFF / #0C2C74 / #D8F6FF | orbit studs, 2.6 s loop |
| 7 | Imperial Amethyst | Imperial purple ring with gold filigree; fine particle glints | #8B26D9 / #E4B5FF / #43106E / #F0C15A | glint particles, subtle |
| 8 | Black Diamond | Near-black faceted ring, ice-blue energy; two sweeping energy arcs | #23202E / #9BE8FF / #0C0A12 / #DFF8FF | dual energy arcs |
| 9 | Srood Mythic | Gold main ring over violet under-ring on black; apex crest of three arcs echoing the Srood owl silhouette (original mark) | #F0C15A / #FFE9A8 / #120722 / #8B26D9 | arcs + crest shimmer |

## Placeholder status

The `SroodTierFramePainter` output is a temporary stand-in that encodes the
palette, notch signature, and per-tier treatments above. It must be replaced
by produced bitmap assets before the v2 art ships. Rendering it is gated
behind `preferV2TierArt: true` (default false), so nothing in production
changes until explicitly enabled.
