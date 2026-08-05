# Theme set expansion — four new themes

Four additions alongside Atelier, XCube Lavender, Claude, and Porcelain (eight total). Same construction rules: hand-tuned light/dark, matched bubble tints, markdown ramp derived from `primaryLight` / `surface` as in the Atelier spec. All four keep HarmonyOS Sans chat type (serif default remains Atelier-only).

Enum additions:

```ts
HERBARIUM = 'herbarium',
SALON     = 'salon',
GALLERY   = 'gallery',
NOCTURNE  = 'nocturne'
```

`ALL_THEMES` order: `ATELIER, LAVENDER, CLAUDE, PORCELAIN, HERBARIUM, SALON, GALLERY, NOCTURNE`.

---

## Herbarium — "Pressed-leaf green"

Botanical green, dried rather than lush; the calm natural option.

| Role | Light | Dark |
| --- | --- | --- |
| primary | `#4E7A5A` | `#8CBB9A` |
| primaryLight | `#DEEAE0` | `#24382A` |
| background | `#F4F8F2` | `#161D17` |
| surface / aiBubble | `#FBFEFA` | `#202A21` |
| userBubble | `#486E55` | `#3F6A4E` |
| userBubbleText | `#F1FAF3` | `#EDFAF0` |
| textPrimary | `#1F271F` | `#ECF5EC` |
| textSecondary | `#61705F` | `#ABBCAB` |
| textTertiary | `#8C9A8A` | `#77877A` |

Preview swatches: `['#F4F8F2', '#DEEAE0', '#4E7A5A']`
Strings: "Herbarium" / "Pressed-leaf green" — zh_CN "植物标本" / "压叶之绿"

---

## Salon — "Powdered rose"

Dusty rose with warm neutrals; soft without turning saccharine.

| Role | Light | Dark |
| --- | --- | --- |
| primary | `#A44E5E` | `#D98D9C` |
| primaryLight | `#F2DDE1` | `#402329` |
| background | `#FAF4F3` | `#221718` |
| surface / aiBubble | `#FFFBFA` | `#2C2022` |
| userBubble | `#8F4A57` | `#7E4250` |
| userBubbleText | `#FFF2F2` | `#FFEDEF` |
| textPrimary | `#2A2022` | `#F6EAEC` |
| textSecondary | `#746165` | `#C0AAAE` |
| textTertiary | `#A08D91` | `#8A767A` |

Preview swatches: `['#FAF4F3', '#F2DDE1', '#A44E5E']`
Strings: "Salon" / "Powdered rose" — zh_CN "沙龙" / "扑粉玫瑰"

---

## Gallery — "Graphite monochrome"

The accent-free option: warm graphite on museum white; hierarchy carried by value, not hue.

| Role | Light | Dark |
| --- | --- | --- |
| primary | `#3E3A34` | `#C9C3B8` |
| primaryLight | `#E4E1DB` | `#34312B` |
| background | `#F3F2F0` | `#191816` |
| surface / aiBubble | `#FBFAF8` | `#232220` |
| userBubble | `#33302B` | `#4A463F` |
| userBubbleText | `#F4F2EE` | `#F2EFE9` |
| textPrimary | `#201F1D` | `#EFEDE8` |
| textSecondary | `#6B675F` | `#ADA89F` |
| textTertiary | `#98938A` | `#7B766D` |

Preview swatches: `['#F3F2F0', '#E4E1DB', '#3E3A34']`
Strings: "Gallery" / "Graphite monochrome" — zh_CN "画廊" / "石墨单色"

---

## Nocturne — "Indigo before dawn"

Deep indigo tuned for evening use; the dark variant is the star, the light variant a pale predawn blue.

| Role | Light | Dark |
| --- | --- | --- |
| primary | `#3F4C7E` | `#9AA6E0` |
| primaryLight | `#DCE0F0` | `#262C4A` |
| background | `#F3F4F9` | `#14151E` |
| surface / aiBubble | `#FBFCFF` | `#1D1F2B` |
| userBubble | `#3A4670` | `#39436E` |
| userBubbleText | `#EFF2FF` | `#ECF0FF` |
| textPrimary | `#1E2130` | `#EBEEFA` |
| textSecondary | `#5F6478` | `#A9AFC6` |
| textTertiary | `#8B90A4` | `#757B93` |

Preview swatches: `['#F3F4F9', '#DCE0F0', '#3F4C7E']`
Strings: "Nocturne" / "Indigo before dawn" — zh_CN "夜曲" / "破晓前的靛蓝"

---

## string.json additions

```json
{ "name": "theme_color_herbarium",      "value": "Herbarium" },
{ "name": "theme_color_herbarium_desc", "value": "Pressed-leaf green" },
{ "name": "theme_color_salon",          "value": "Salon" },
{ "name": "theme_color_salon_desc",     "value": "Powdered rose" },
{ "name": "theme_color_gallery",        "value": "Gallery" },
{ "name": "theme_color_gallery_desc",   "value": "Graphite monochrome" },
{ "name": "theme_color_nocturne",       "value": "Nocturne" },
{ "name": "theme_color_nocturne_desc",  "value": "Indigo before dawn" }
```

One-line identities:

- **Herbarium** — Pressed-leaf green: dried botanical calm on paper white.
- **Salon** — Powdered rose: dusty warmth with a velvet edge.
- **Gallery** — Graphite monochrome: value does the work, hue stays out.
- **Nocturne** — Indigo before dawn: built for the dark, pale blue by day.
