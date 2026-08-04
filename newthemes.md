# Curated theme set — the three companion themes

Restyle spec for the themes that remain alongside Atelier. Each keeps its identity but gets hand-tuned light/dark palettes and a new description. Derive each theme's markdown ramp from its `primaryLight` / `surface` the same way Atelier does.

---

## XCube Lavender — "Luminous violet glass"

The brand default. Cooler and more luminous than the old lavender; violet reads as glass, not plastic. Sans chat type.

| Role | Light | Dark |
| --- | --- | --- |
| primary | `#7A68F0` | `#A99DFF` |
| primaryLight | `#E6E1FD` | `#332C52` |
| background | `#F7F5FF` | `#171422` |
| surface | `#FDFCFF` | `#211D31` |
| userBubble | `#6D5CE0` | `#6A5AD0` |
| userBubbleText | `#F7F4FF` | `#F4F0FF` |
| aiBubble | `#FDFCFF` | `#211D31` |
| textPrimary | `#221E38` | `#F1EDFF` |
| textSecondary | `#645E7C` | `#B4ADCC` |
| textTertiary | `#948FA8` | `#7E7794` |

Preview swatches: `['#F7F5FF', '#E6E1FD', '#7A68F0']`

Strings: `theme_color_lavender_desc` → "Luminous violet glass" / zh_CN "通透的紫罗兰玻璃"

---

## Claude — "Terracotta and paper"

Warm terracotta deepened toward fired clay; the ground shifts from generic cream to a warmer paper that sits well next to Atelier's linen without duplicating it.

| Role | Light | Dark |
| --- | --- | --- |
| primary | `#B15B33` | `#D98A5F` |
| primaryLight | `#F0E2D5` | `#40291D` |
| background | `#FAF6EF` | `#221B15` |
| surface | `#FFFCF6` | `#2C241C` |
| userBubble | `#9A5638` | `#87492F` |
| userBubbleText | `#FFF6EE` | `#FFEFE4` |
| aiBubble | `#FFFCF6` | `#2C241C` |
| textPrimary | `#28211A` | `#F5ECE1` |
| textSecondary | `#6F6459` | `#BDAF9E` |
| textTertiary | `#9C9082` | `#87796A` |

Preview swatches: `['#FAF6EF', '#F0E2D5', '#B15B33']`

Strings: `theme_color_claude_desc` → "Terracotta and paper" / zh_CN "赤陶与纸"

---

## Porcelain — "Glazed cool blue"

Successor to Soft Blue (`ColorTheme.PORCELAIN = 'porcelain'`, renamed from `CHATGPT`). Cool blue-gray with a glazed, ceramic calm — the one cold theme in the set.

| Role | Light | Dark |
| --- | --- | --- |
| primary | `#3E6E96` | `#85AECF` |
| primaryLight | `#DCE7EE` | `#213648` |
| background | `#F4F7F9` | `#151C22` |
| surface | `#FCFEFF` | `#1E272F` |
| userBubble | `#3A6285` | `#3D6484` |
| userBubbleText | `#F2F8FD` | `#EFF7FE` |
| aiBubble | `#FCFEFF` | `#1E272F` |
| textPrimary | `#1D242B` | `#EAF2F9` |
| textSecondary | `#5F6C77` | `#A9B8C4` |
| textTertiary | `#8C99A4` | `#748492` |

Preview swatches: `['#F4F7F9', '#DCE7EE', '#3E6E96']`

Strings: add `theme_color_porcelain` → "Porcelain" / zh_CN "青瓷"; `theme_color_porcelain_desc` → "Glazed cool blue" / zh_CN "釉面冷蓝"

---

## Removed themes and migration

Removed: Warm Paper (`default`), Soft Blue (`chatgpt`), Pine Mist (`mint`), Mist Violet (`violet`), Notion (`notion`).

Persisted-id migration on load:

- `chatgpt` → `porcelain` (restyled successor)
- `default`, `mint`, `violet`, `notion` → `lavender`

Final `ALL_THEMES` order: `ATELIER_THEME, LAVENDER_THEME, CLAUDE_THEME, PORCELAIN_THEME`. Only Atelier defaults serif chat on; the three companions keep HarmonyOS Sans.
