# Manuscript — component style guide (buttons, toolbars, results pane)

Supplement to `manuscript-visual-effects.md`. That doc covers the chat page, conversation list, and settings entry; this one specifies the interactive chrome — buttons, toolbars, and the code/preview (Canvas) results pane — which currently all reuse the same rounded filled-card format and therefore look incongruous in Manuscript.

## 0. The root problem, and the rule that fixes it

Today the tab switcher (代码/预览), the action buttons, and the preview pane are each a filled, heavily-rounded container. Three different roles, one identical shape — so nothing reads as chrome vs. content vs. action.

Manuscript separates the three roles by **drawing method**, not by container shape:

| Role | Drawing method |
| --- | --- |
| **Actions** (buttons, tabs, send) | Type + underline. Never a filled pill. |
| **Chrome** (toolbars, headers, folios) | Hairline rules above/below a transparent strip. Never a bar with its own fill. |
| **Content surfaces** (results pane, code sheet) | The only elements allowed a fill: `surface` on `background (paper)`, 1px `divider` border, small radius. |

Global geometry: radius is **3vp** on content surfaces, **0** on everything else (buttons and toolbars have no box, so no radius). No shadows except the plate mat (§4). All accent (gilt) usage is stroke: rules, underlines, borders, glyphs — the sole permitted gilt fill is the tiny NEW badge.

Palette and type tokens are in `manuscript-visual-effects.md` §1–2. Shorthand below: paper `#F3F2F2`/`#1B1A18`, surface `#FBFAF8`/`#242320`, ink `#201F1D`/`#ECEAE5`, secondary `#6B675F`/`#ADA89F`, gilt `#B68235`/`#C99A52`, giltDeep `#8A6228`/`#D9B274`, divider `#E4E1DB`/`#34312B`.

## 1. Buttons

Four variants, all typographic. Minimum hit target 44×44vp — pad the touch area, not the visible mark.

### 1.1 Primary text button ("SEND", "RUN", dialog confirm)
- Label: Cormorant Garamond semibold, 13fp, letter-spacing 0.16em, UPPERCASE, giltDeep.
- Underline: 1px solid gilt, 2vp below the baseline, exactly the width of the label.
- Padding: 8vp vertical / 2vp horizontal visible; expand `responseRegion` to 44vp height.
- States — pressed: label and underline → gilt, underline thickens to 1.5px; disabled: 45% opacity, underline dotted; focus: 2px gilt outline, offset 2vp.

### 1.2 Secondary text button ("VIEW DOCS", cancel)
- Same type, but ink at 13fp and **no underline at rest**; underline (1px, divider color) appears on press.
- Never place two primaries side by side; pairs are primary + secondary separated by 28vp.

### 1.3 Outlined button (only where a boxed button is unavoidable — e.g. inside a rendered HTML preview's own UI leave it alone; in app chrome, empty-state CTAs)
- 1px giltDeep border, transparent fill, radius 3vp, height 40vp, padding 0 20vp.
- Label as 1.1 without the underline. Pressed: background gilt-100 tint (`#F5EDE0` / `#33291B`).

### 1.4 Icon button (copy, retry, edit, expand, more)
- Lucide icon, 18vp, 1.5px stroke, secondary color; no circle, no fill, no border.
- Hit area 44×44vp. Pressed: icon → giltDeep. Active/toggled: giltDeep + a 3vp gilt dot centered 4vp below the icon.
- Message action row (under a sent message): icons right-aligned, 26vp apart, 10vp below the text block, preceded by nothing — no divider; the row is quiet until the message is long-pressed or focused, then fades in (200ms).

## 2. Toolbars

### 2.1 The rule
A toolbar is a **transparent strip bounded by hairlines** — 1px divider top and bottom (or bottom only when it caps a surface). It never has its own background fill or corner radius. On scroll-over content, use paper at 85% + 10vp blur (as the chat input bar already does).

### 2.2 Artifact toolbar (code/preview switcher — the 代码/预览 bar)
Replaces the current dark bar with pill tabs.

- Height 44vp; hairline below (the frame's own border draws the sides — see §3).
- Left: the two modes as **small-caps text tabs**, 24vp apart: `CODE` / `PREVIEW` (代码/预览) — 11fp, letter-spacing 0.2em, Lora.
    - Active: giltDeep + 1px gilt underline the width of the label, 4vp below baseline. Animate the underline between tabs: translate + width, 250ms ease-out (an ink stroke sliding, not a pill jumping).
    - Inactive: secondary color, no underline. Pressed: ink.
- Center-left of the tabs, optionally a kicker naming the artifact kind: `FIG. 3 — HTML` (10fp, tnum, tertiary). Omit when width < 360vp.
- Right: icon buttons per §1.4 — expand ⤢, copy, more — 18vp icons, 26vp apart, last one inset 14vp from the frame edge.
- No element in the toolbar has a fill. Ever.

### 2.3 Multi-select toolbar (ChatMultiSelectToolbar)
- Bottom-anchored strip, hairline top rule, paper 85% + blur; height 56vp.
- Actions as primary/secondary text buttons (§1.1/1.2) spread with 32vp gaps, centered.
- Selection count on the left as a folio: `— 3 selected —` (11fp, tnum, tertiary).

### 2.4 Suggestion chips row (联网查询 / 推理)
- Chips become **tags in the Classical sense**: transparent, 1px divider border, radius 3vp, height 30vp, padding 0 12vp, label 11.5fp Lora small-caps style (uppercase, 0.12em), secondary.
- Selected: border giltDeep, label giltDeep, gilt-100 tint fill (the tint is a state, not a resting fill).
- Row: horizontal scroll, 8vp gap, inset 20vp.

## 3. Results pane (Canvas / code / HTML preview)

The artifact is a **plate**: the one boxed, filled surface in the message column, treated like a tipped-in figure in a book.

### 3.1 Frame
- Container: surface fill, 1px divider border, radius 3vp, full message measure.
- Structure top-to-bottom: artifact toolbar (§2.2, hairline below) → content region → caption strip.
- Margin: 18vp above and below within the message flow; never edge-to-edge bleed.

### 3.2 Content region — code mode
- Padding 16vp 18vp; monospace 12.5fp/20 (bundle a mono such as JetBrains Mono Regular; system mono acceptable v1), ink at 90%.
- Line numbers: right-aligned tnum column, 11fp, tertiary, 14vp gutter, hairline rule between gutter and code (1px divider).
- Syntax palette (mono-accent, matching "color as stroke"): keywords giltDeep, strings ink, comments tertiary italic, literals secondary. No background highlights.
- Max height 320vp, then fade-out mask (24vp) + `EXPAND` primary text button centered on the fade.

### 3.3 Content region — preview mode
- The rendered HTML/LaTeX keeps its own styling (it is the author's document — do not re-theme it), but it sits **matted**: 10vp inset of paper color on all sides inside the frame, like the `.plate` wrapper. The mat is what makes foreign content sit comfortably on the page.
- Min height 200vp, max 420vp inline; loading state: centered fleuron ⁂ in gilt, gently pulsing opacity 0.4→1, 1.2s.
- Tab switch (code ↔ preview): crossfade 250ms + 6vp settle; never a horizontal slide inside the frame.

### 3.4 Caption strip
- Below the content, hairline above; height 32vp; centered caption: `— fig. 3 · tailwind hello world —` 10fp, tnum, letter-spacing 0.18em, tertiary. Falls back to `— fig. N —` when untitled.
- Errors surface here, not as a toast: caption turns `— error · see line 12 —` in giltDeep; tapping scrolls the code pane.

### 3.5 Fullscreen (expand)
- Pushes a page with the standard Manuscript header (kicker `ARTIFACT · N° 3`, Cormorant title), the same toolbar as §2.2 pinned below it, content filling the rest, folio at the bottom. 550ms crossfade + settle, matching the mode-toggle motion.

## 4. Shadows, radii, and what not to do

- Only the results-pane frame may cast: `0 1px 0 divider` (a whisper, effectively a rule). No blurred drop shadows anywhere.
- Radii: 3vp (frames, outlined buttons, chips). Nothing at 8+vp; no pills; no circles except avatars.
- Do not: fill the toolbar; put tabs in pills; round the results pane like a bubble; use blue/system accent anywhere; mix filled and outlined buttons in one row; let the artifact toolbar's icons take bordered/filled backgrounds.

## 5. Spacing reference (message column)

| Measure | Value |
| --- | --- |
| Page margin (chat) | 34vp |
| Space between message blocks | 22vp |
| Artifact frame margin (top/bottom) | 18vp |
| Toolbar height / caption height | 44vp / 32vp |
| Icon size / icon gap / min hit target | 18vp / 26vp / 44vp |
| Chip height / gap | 30vp / 8vp |
| Text button padding (visible) | 8vp × 2vp |

## 6. QA checklist

- Toolbar and buttons have zero filled containers; the results pane is the only filled surface in a message.
- The 代码/预览 underline slides between tabs; no pill indicator remains.
- Preview content sits inside the 10vp paper mat; code mode shows the hairline-ruled gutter.
- Every icon button hits 44vp; pressed states are gilt-tinted, not grey.
- Dark mode: gilt strokes ≥ 3:1 on dark paper; code text ≥ 4.5:1.
- The artifact frame, chips, and outlined buttons all share the same 3vp radius and 1px divider stroke.
