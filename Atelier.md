# Atelier theme — implementation patch (chatcube)

Accent locked to **Indigo Ink** (per final tweak). Serif chat enabled by default when Atelier is selected. Three files to touch.

## 1. `entry/src/main/ets/models/ThemeColors.ets`

Add to the enum:

```ts
export enum ColorTheme {
  ATELIER = 'atelier',      // Atelier 亚麻墨色
  LAVENDER = 'lavender',
  // …unchanged
}
```

Add the theme const:

```ts
// Atelier 主题：亚麻纸底 + 靛墨点缀，聊天气泡默认衬线字体。
const ATELIER_THEME: ThemeInfo = {
  id: ColorTheme.ATELIER,
  nameKey: 'theme_color_atelier',
  descriptionKey: 'theme_color_atelier_desc',
  previewColors: ['#F7F1E6', '#DDE0EF', '#44518A', '#3D4877'],
  light: {
    primary: '#44518A',
    primaryLight: '#DDE0EF',
    background: '#F7F1E6',
    surface: '#FFFCF4',
    divider: '#EADFCB',
    userBubble: '#3D4877',
    userBubbleText: '#FFF6EE',
    aiBubble: '#FFFCF4',
    textPrimary: '#2A231A',
    textSecondary: '#6E6355',
    textTertiary: '#9C8F7E',
    markdownTitle: '#2A231A',
    markdownText: '#3F3729',
    markdownLink: '#44518A',
    markdownLinkBg: '#DDE0EF',
    markdownCodeBg: '#F3ECDD',
    markdownCodeText: '#3E4979',
    markdownQuoteBg: '#F3ECDD',
    markdownTableBg: '#FFFCF4',
    markdownTableHeaderBg: '#F3ECDD',
    markdownTableAltBg: '#FAF4E8',
    markdownTableBorder: '#DDE0EF'
  },
  dark: {
    primary: '#97A3D9',
    primaryLight: '#282D46',
    background: '#211B14',
    surface: '#2B241B',
    divider: '#282D46',
    userBubble: '#47528A',
    userBubbleText: '#FFF3EA',
    aiBubble: '#2B241B',
    textPrimary: '#F4ECDF',
    textSecondary: '#BCB09E',
    textTertiary: '#877B6A',
    markdownTitle: '#F4ECDF',
    markdownText: '#E8DFCE',
    markdownLink: '#A9B4E4',
    markdownLinkBg: '#282D46',
    markdownCodeBg: '#262019',
    markdownCodeText: '#C3CCF0',
    markdownQuoteBg: '#262019',
    markdownTableBg: '#2B241B',
    markdownTableHeaderBg: '#352D22',
    markdownTableAltBg: '#302921',
    markdownTableBorder: '#282D46'
  }
}
```

Register it (first, so it leads the grid):

```ts
export const ALL_THEMES: ThemeInfo[] = [
  ATELIER_THEME,
  LAVENDER_THEME,
  DEFAULT_THEME,
  CLAUDE_THEME,
  CHATGPT_THEME,
  MINT_THEME,
  VIOLET_THEME,
  NOTION_THEME
]
```

## 2. Strings

`entry/src/main/resources/base/element/string.json` (next to the other `theme_color_*` entries):

```json
{ "name": "theme_color_atelier", "value": "Atelier" },
{ "name": "theme_color_atelier_desc", "value": "Ink on linen, serif chat" }
```

`entry/src/main/resources/zh_CN/element/string.json`:

```json
{ "name": "theme_color_atelier", "value": "画室" },
{ "name": "theme_color_atelier_desc", "value": "亚麻纸上的靛墨，衬线对话" }
```

## 3. `ThemeModeSettingsPage.ets` — name/desc lookup + serif default

In `getThemeName` / `getThemeDescription`, add the branch:

```ts
if (themeId === ColorTheme.ATELIER) {
  return $r('app.string.theme_color_atelier')        // / _desc
}
```

Serif-by-default when Atelier is picked (in `handleColorThemeSelected`, after the theme is persisted):

```ts
if (theme === ColorTheme.ATELIER && !this.chatSerifFontEnabled) {
  await this.handleChatSerifFontChanged(true)
}
```

This reuses the existing serif toggle path, so the user can still turn it off — Atelier only sets the default on first selection.

## Motion notes (already in the prototype)

- Palette change: 450 ms ease crossfade on background / border / text (`animateTo` equivalent: duration 450, Curve.EaseInOut).
- Selection checkmark: 350 ms spring scale-in (`curves.springMotion(0.35, 0.8)`).
- Appearance tab slide: keep the existing 280 ms `animationDuration`.
- Toggles: 280 ms spring on the knob.
