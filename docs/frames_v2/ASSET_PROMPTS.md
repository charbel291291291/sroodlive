# Frame System v2 — Asset-Generation Prompts (VIP 1–9)

Use with any image model that supports transparent output. After generation:
verify the circular opening ≥ 74 % of min-dimension, center the opening,
export 1024×1024 lossless WebP + 256×256 thumbnail. Never accept output that
contains text, logos, crowns copied from other apps, or recognizable
third-party motifs.

**Shared prompt suffix (append to every tier prompt):**

> …ornamental circular avatar frame on a fully transparent background,
> perfectly centered circular opening taking at least 74% of the image,
> decoration only on the ring rim, nothing covering the center, symmetrical,
> clean edges, game-UI asset style, high detail metalwork, no text, no logo,
> no watermark, no background, PNG/WebP with alpha, original design.

**Negative prompt (all tiers):** text, watermark, logo, human, face, mascot,
background scenery, motion blur, heavy glow bloom, copyrighted characters,
crown designs from existing games.

| Tier | Prompt core |
|---|---|
| VIP 1 | Clean brushed bronze metal ring, simple beveled geometry, single subtle rim highlight, minimal design, matte finish, warm bronze #B87C36 with light edge #E8AE60, one small diamond-shaped stud at the top |
| VIP 2 | Polished silver ring with fine engraved meridian lines, small precise decorative details, cool silver #B9C2D3 with bright polish #F2F5FB, two small diamond studs along the top arc |
| VIP 3 | Royal gold ring, controlled specular light, two thin inlaid gold hairlines, warm royal gold #D9A62B with highlights #FFE9A8, three small diamond studs across the top arc |
| VIP 4 | Royal emerald ring with four ornate gold corner mounts at the diagonals, premium jewelry finish, emerald #1E9E5A with gold accents #F0C15A, four small studs across the top arc |
| VIP 5 | Deep ruby ring with gold under-rim, one large faceted ruby gem mounted at the top of the ring, prestigious jewelry treatment, ruby #C81E3E with gold #FFD978, five small studs across the top arc |
| VIP 6 | Royal sapphire ring with three luminous light studs placed around the rim, elegant regalia styling, sapphire #1A5CE8 with ice highlights #80CCFF, six small studs across the top arc. Animated variant: the three light studs orbit slowly around the ring |
| VIP 7 | Imperial purple ring with fine gold filigree woven around the rim, tiny sparkling glints, amethyst #8B26D9 with gold #F0C15A, seven small studs across the top arc. Animated variant: subtle traveling glints along the filigree |
| VIP 8 | Near-black faceted diamond ring with ice-blue inner energy lines, two thin luminous energy arcs resting on the rim, black diamond #23202E with ice blue #9BE8FF, eight small studs across the top arc. Animated variant: the two energy arcs sweep around the ring |
| VIP 9 | Majestic double ring — outer violet #8B26D9 under-ring, main royal gold #F0C15A ring over deep black #120722, apex crest made of three abstract arcs suggesting an owl silhouette (original, minimal, geometric), nine small studs across the top arc. Animated variant: gentle shimmer traveling around the gold ring plus a soft pulse in the crest |

## Acceptance checklist per asset

1. Transparent background, no stray pixels outside the ring.
2. Opening ≥ 74 %, measured on the alpha channel; record
   `avatarFillRatio`/`avatarDyFraction` for `VipFrameLayout`-style calibration.
3. Recognizable at 44 px (compare against the other 8 tiers side by side).
4. Static file ≤ 150 KB, animated ≤ 400 KB, loop length 2–3 s, ≤ 24 fps.
5. Register in `frame_catalog` via the admin screen (asset_type `network` or
   ship bundled and use `bundled`), then flip `preferV2TierArt` after QA.
