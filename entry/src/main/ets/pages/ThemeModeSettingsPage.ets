import {
  HdsNavigation,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsFloatingStyle
} from '@kit.UIDesignKit'
import { curves, uiMaterial } from '@kit.ArkUI'
import { picker } from '@kit.CoreFileKit'
import { ALL_THEMES, ColorTheme, getThemeColors, ThemeColorConfig, ThemeInfo } from '../models/ThemeColors'
import { MarkdownRenderer, ThemeMode } from '../services/PreferencesService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { getSettingsPageContentMaxWidth, getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationMaskExtraHeight,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import {
  buildCompactTabsFloatingStyle,
  CompactTabsFloatingStyleOptions
} from '../utils/HdsTabsFloatingStyleHelper'
import { IndexBottomTabItem } from '../components/index/IndexBottomTabItem'
import { showToast } from '../utils/ToastUtil'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import {
  CHAT_SERIF_FONT_CINZEL,
  CHAT_SERIF_FONT_COMMON,
  CHAT_SERIF_FONT_CUSTOM,
  CHAT_SERIF_FONT_DOMINE,
  CHAT_SERIF_FONT_LIBERTINUS,
  ChatSerifFontAvailability,
  detectAndRegisterChatSerifFonts,
  getImportedChatSerifFontName,
  importChatSerifFont,
  resolveChatSerifFontFamily
} from '../utils/ChatSerifFontUtils'

let themeModeSettingsPathStack: NavPathStack | null = null

const TAB_INDEX_THEME = 0

const PREVIEW_TAB_INDEX_ASSISTANTS = 0
const PREVIEW_TAB_INDEX_CHAT = 1
const PREVIEW_TAB_INDEX_SETTINGS = 2
const APPEARANCE_BLOCK_GAP = 16

@ComponentV2
export struct ThemeAppearanceSettingsView {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }
  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get themeUserBubbleText(): string {
    return getAppUiState().themeUserBubbleText
  }
  private get themeTextPrimary(): string {
    return getAppUiState().themeTextPrimary
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get previewChatTypeface(): string {
    return this.chatSerifFontEnabled ? resolveChatSerifFontFamily(this.chatSerifFontFamily) : 'HarmonyOS Sans'
  }
  private get themeCardTypeface(): string {
    return resolveChatSerifFontFamily(this.chatSerifFontFamily)
  }
  private get themeCardTitleTypeface(): string {
    return resolveChatSerifFontFamily(CHAT_SERIF_FONT_CINZEL)
  }

  @Param compactTitle: string | Resource = $r('app.string.settings_appearance')
  @Event onCompactBack: () => void = () => {}

  @Local currentThemeMode: ThemeMode = ThemeMode.SYSTEM
  @Local currentColorTheme: ColorTheme = ColorTheme.LAVENDER
  @Local chatFontSize: number = 15
  @Local chatSerifFontEnabled: boolean = false
  @Local chatSerifFontFamily: string = CHAT_SERIF_FONT_COMMON
  @Local markdownRenderer: MarkdownRenderer = MarkdownRenderer.CANGJIE
  @Local customSerifAvailable: boolean = false
  @Local customSerifName: string = ''
  @Local serifFontSelectRevision: number = 0
  @Local materialType: number = 100
  @Local materialLevel: number = 10
  @Local lightColorMode: string = 'default'
  @Local chatListImmersiveMaterial: boolean = false
  @Local knowledgeListImmersiveMaterial: boolean = false

  @Local currentTabIndex: number = TAB_INDEX_THEME
  @Local previewTabIndex: number = PREVIEW_TAB_INDEX_CHAT

  private settingsManager = ServiceRegistry.settings()
  private appearanceTabsController: TabsController = new TabsController()
  private themeScroller: Scroller = new Scroller()
  private fontScroller: Scroller = new Scroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    const fontAvailability: ChatSerifFontAvailability = detectAndRegisterChatSerifFonts(this.getUIContext())
    this.customSerifAvailable = fontAvailability.customAvailable
    this.customSerifName = getImportedChatSerifFontName()
    this.currentThemeMode = this.settingsManager.getThemeMode()
    this.currentColorTheme = this.settingsManager.getColorTheme()
    this.chatFontSize = this.settingsManager.getChatFontSize()
    this.chatSerifFontEnabled = this.settingsManager.getChatSerifFontEnabled()
    this.markdownRenderer = this.settingsManager.getMarkdownRenderer()
    const savedSerifFont = this.settingsManager.getChatSerifFontFamily()
    if (savedSerifFont === CHAT_SERIF_FONT_CINZEL || savedSerifFont === CHAT_SERIF_FONT_DOMINE ||
      savedSerifFont === CHAT_SERIF_FONT_LIBERTINUS) {
      this.chatSerifFontFamily = savedSerifFont
    } else {
      this.chatSerifFontFamily = savedSerifFont === CHAT_SERIF_FONT_CUSTOM && this.customSerifAvailable ?
        CHAT_SERIF_FONT_CUSTOM : CHAT_SERIF_FONT_COMMON
    }
    this.materialType = this.settingsManager.getMaterialType()
    this.materialLevel = this.settingsManager.getMaterialLevel()
    this.lightColorMode = this.settingsManager.getLightColorMode()
    this.chatListImmersiveMaterial = this.settingsManager.getChatListImmersiveMaterial()
    this.knowledgeListImmersiveMaterial = this.settingsManager.getKnowledgeListImmersiveMaterial()
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private getScrollBottomPadding(): number {
    return 96 + getSettingsPageCompactTabsTotalInset(this.px2vp(this.bottomAvoidHeight),
      this.settingsDetailPresentationMode)
  }

  private getCompactTitleBarMaskExtraHeight(): number {
    return getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
  }

  private getCompactContentTopPadding(): number {
    return this.px2vp(this.topAvoidHeight) + 56 + this.getCompactTitleBarMaskExtraHeight()
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(
      this.materialType,
      this.materialLevel,
      this.windowWidthVp,
      this.windowHeightVp,
      (): void => this.CompactTitleStackBuilder()
    )
  }

  private getResolvedDarkMode(mode: ThemeMode = this.currentThemeMode): boolean {
    if (mode === ThemeMode.DARK) {
      return true
    }
    if (mode === ThemeMode.LIGHT) {
      return false
    }
    return this.isDarkMode
  }

  private getPreviewColors(themeId: ColorTheme = this.currentColorTheme, mode: ThemeMode = this.currentThemeMode): ThemeColorConfig {
    return getThemeColors(themeId, this.getResolvedDarkMode(mode))
  }

  private getThemeName(themeId: ColorTheme): Resource {
    if (themeId === ColorTheme.ATELIER) {
      return $r('app.string.theme_color_atelier')
    }
    if (themeId === ColorTheme.LAVENDER) {
      return $r('app.string.theme_color_lavender')
    }
    if (themeId === ColorTheme.CLAUDE) {
      return $r('app.string.theme_color_claude')
    }
    if (themeId === ColorTheme.PORCELAIN) {
      return $r('app.string.theme_color_porcelain')
    }
    if (themeId === ColorTheme.HERBARIUM) {
      return $r('app.string.theme_color_herbarium')
    }
    if (themeId === ColorTheme.SALON) {
      return $r('app.string.theme_color_salon')
    }
    if (themeId === ColorTheme.GALLERY) {
      return $r('app.string.theme_color_gallery')
    }
    if (themeId === ColorTheme.NOCTURNE) {
      return $r('app.string.theme_color_nocturne')
    }
    return $r('app.string.theme_color_lavender')
  }

  private getThemeDescription(themeId: ColorTheme): Resource {
    if (themeId === ColorTheme.ATELIER) {
      return $r('app.string.theme_color_atelier_desc')
    }
    if (themeId === ColorTheme.LAVENDER) {
      return $r('app.string.theme_color_lavender_desc')
    }
    if (themeId === ColorTheme.CLAUDE) {
      return $r('app.string.theme_color_claude_desc')
    }
    if (themeId === ColorTheme.PORCELAIN) {
      return $r('app.string.theme_color_porcelain_desc')
    }
    if (themeId === ColorTheme.HERBARIUM) {
      return $r('app.string.theme_color_herbarium_desc')
    }
    if (themeId === ColorTheme.SALON) {
      return $r('app.string.theme_color_salon_desc')
    }
    if (themeId === ColorTheme.GALLERY) {
      return $r('app.string.theme_color_gallery_desc')
    }
    if (themeId === ColorTheme.NOCTURNE) {
      return $r('app.string.theme_color_nocturne_desc')
    }
    return $r('app.string.theme_color_lavender_desc')
  }

  private getThemePreviewSwatch(theme: ThemeInfo, index: number): string {
    if (index >= 0 && index < theme.previewColors.length) {
      return theme.previewColors[index]
    }
    return this.getPreviewColors(theme.id).primary
  }

  private getFontSizeText(size: number): Resource {
    if (size <= 13) {
      return $r('app.string.font_size_small')
    }
    if (size <= 15) {
      return $r('app.string.font_size_default')
    }
    if (size <= 17) {
      return $r('app.string.font_size_large')
    }
    return $r('app.string.font_size_extra_large')
  }

  private getAiPreviewFontSize(): number {
    return this.chatFontSize - 1 < 12 ? 12 : this.chatFontSize - 1
  }

  private async handleThemeModeSelected(mode: ThemeMode): Promise<void> {
    const previousMode = this.currentThemeMode
    this.currentThemeMode = mode
    try {
      await this.settingsManager.setThemeMode(mode)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView', `Failed to set theme mode: ${JSON.stringify(error)}`)
      this.currentThemeMode = previousMode
    }
  }

  private async handleColorThemeSelected(theme: ColorTheme): Promise<void> {
    const previousTheme = this.currentColorTheme
    animateTo({ duration: 450, curve: Curve.EaseInOut }, () => {
      this.currentColorTheme = theme
    })
    try {
      await this.settingsManager.setColorTheme(theme)
      if (theme === ColorTheme.ATELIER && !this.chatSerifFontEnabled) {
        await this.handleChatSerifFontChanged(true)
      }
    } catch (error) {
      console.error('ThemeAppearanceSettingsView', `Failed to set color theme: ${JSON.stringify(error)}`)
      animateTo({ duration: 450, curve: Curve.EaseInOut }, () => {
        this.currentColorTheme = previousTheme
      })
    }
  }

  private handleFontSizeChanged(size: number): void {
    this.chatFontSize = size
    this.settingsManager.setChatFontSize(size).catch((error: Error): void => {
      console.error('ThemeAppearanceSettingsView', `Failed to update chat font size: ${JSON.stringify(error)}`)
    })
  }

  private async handleChatSerifFontChanged(enabled: boolean): Promise<void> {
    const previous = this.chatSerifFontEnabled
    animateTo({ duration: 280, curve: curves.springMotion(0.35, 0.8) }, () => {
      this.chatSerifFontEnabled = enabled
    })
    try {
      if (enabled) {
        const availability = detectAndRegisterChatSerifFonts(this.getUIContext())
        this.customSerifAvailable = availability.customAvailable
      }
      await this.settingsManager.setChatSerifFontEnabled(enabled)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView',
        `Failed to update chat serif font setting: ${JSON.stringify(error)}`)
      animateTo({ duration: 280, curve: curves.springMotion(0.35, 0.8) }, () => {
        this.chatSerifFontEnabled = previous
      })
    }
  }

  private getSerifFontOptions(): SelectOption[] {
    const options: SelectOption[] = [
      { value: $r('app.string.chat_serif_font_common') },
      { value: $r('app.string.chat_serif_font_cinzel') },
      { value: $r('app.string.chat_serif_font_domine') },
      { value: $r('app.string.chat_serif_font_libertinus') }
    ]
    if (this.customSerifAvailable) {
      options.push({ value: this.customSerifName !== '' ? this.customSerifName :
        pickLocalizedText('已导入字体', 'Imported font') })
    }
    options.push({ value: $r('app.string.chat_serif_font_import') })
    return options
  }

  private getSerifFontSelectedIndex(): number {
    if (this.chatSerifFontFamily === CHAT_SERIF_FONT_CINZEL) {
      return 1
    }
    if (this.chatSerifFontFamily === CHAT_SERIF_FONT_DOMINE) {
      return 2
    }
    if (this.chatSerifFontFamily === CHAT_SERIF_FONT_LIBERTINUS) {
      return 3
    }
    return this.chatSerifFontFamily === CHAT_SERIF_FONT_CUSTOM && this.customSerifAvailable ? 4 : 0
  }

  private async handleChatSerifFontFamilyChanged(index: number): Promise<void> {
    const importOptionIndex = this.customSerifAvailable ? 5 : 4
    if (index === importOptionIndex) {
      await this.importCustomSerifFont()
      return
    }
    let nextFontFamily = CHAT_SERIF_FONT_COMMON
    if (index === 1) {
      nextFontFamily = CHAT_SERIF_FONT_CINZEL
    } else if (index === 2) {
      nextFontFamily = CHAT_SERIF_FONT_DOMINE
    } else if (index === 3) {
      nextFontFamily = CHAT_SERIF_FONT_LIBERTINUS
    } else if (index === 4 && this.customSerifAvailable) {
      nextFontFamily = CHAT_SERIF_FONT_CUSTOM
    }
    const previous = this.chatSerifFontFamily
    this.chatSerifFontFamily = nextFontFamily
    try {
      await this.settingsManager.setChatSerifFontFamily(nextFontFamily)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView',
        `Failed to update chat serif font family: ${JSON.stringify(error)}`)
      this.chatSerifFontFamily = previous
    }
  }

  private async importCustomSerifFont(): Promise<void> {
    const previous = this.chatSerifFontFamily
    try {
      const context = this.getUIContext().getHostContext()
      if (context === undefined || context === null) {
        throw new Error('UI context unavailable')
      }
      const options = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 1
      options.fileSuffixFilters = ['.ttf', '.otf']
      const documentPicker = new picker.DocumentViewPicker(context)
      const uris = await documentPicker.select(options)
      if (uris.length === 0) {
        return
      }
      importChatSerifFont(this.getUIContext(), uris[0])
      this.customSerifAvailable = true
      this.customSerifName = getImportedChatSerifFontName()
      this.chatSerifFontFamily = CHAT_SERIF_FONT_CUSTOM
      await this.settingsManager.setChatSerifFontFamily(CHAT_SERIF_FONT_CUSTOM)
      showToast(this.getUIContext(), pickLocalizedText('字体导入成功', 'Font imported successfully'))
    } catch (error) {
      console.error('ThemeAppearanceSettingsView', `Failed to import serif font: ${JSON.stringify(error)}`)
      this.chatSerifFontFamily = previous
      showToast(this.getUIContext(), pickLocalizedText(
        '字体导入失败，请选择有效的 TTF 或 OTF 文件',
        'Could not import the font. Select a valid TTF or OTF file.'
      ))
    } finally {
      // “从本机导入”是操作项；取消选择器后也要恢复当前字体对应的选中项。
      this.serifFontSelectRevision += 1
    }
  }

  private getMarkdownRendererOptions(): SelectOption[] {
    return [
      { value: $r('app.string.markdown_renderer_cangjie') },
      { value: $r('app.string.markdown_renderer_lv') }
    ]
  }

  private getMarkdownRendererSelectedIndex(): number {
    return this.markdownRenderer === MarkdownRenderer.LV_MARKDOWN_IN ? 1 : 0
  }

  private async handleMarkdownRendererChanged(index: number): Promise<void> {
    const nextRenderer = index === 1 ? MarkdownRenderer.LV_MARKDOWN_IN : MarkdownRenderer.CANGJIE
    const previous = this.markdownRenderer
    this.markdownRenderer = nextRenderer
    try {
      await this.settingsManager.setMarkdownRenderer(nextRenderer)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView',
        `Failed to update Markdown renderer: ${JSON.stringify(error)}`)
      this.markdownRenderer = previous
    }
  }

  private async handleChatListImmersiveMaterialChanged(enabled: boolean): Promise<void> {
    const previous = this.chatListImmersiveMaterial
    animateTo({ duration: 280, curve: curves.springMotion(0.35, 0.8) }, () => {
      this.chatListImmersiveMaterial = enabled
    })
    try {
      await this.settingsManager.setChatListImmersiveMaterial(enabled)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView',
        `Failed to set chat list immersive material: ${JSON.stringify(error)}`)
      animateTo({ duration: 280, curve: curves.springMotion(0.35, 0.8) }, () => {
        this.chatListImmersiveMaterial = previous
      })
    }
  }

  private async handleKnowledgeListImmersiveMaterialChanged(enabled: boolean): Promise<void> {
    const previous = this.knowledgeListImmersiveMaterial
    animateTo({ duration: 280, curve: curves.springMotion(0.35, 0.8) }, () => {
      this.knowledgeListImmersiveMaterial = enabled
    })
    try {
      await this.settingsManager.setKnowledgeListImmersiveMaterial(enabled)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView',
        `Failed to set knowledge list immersive material: ${JSON.stringify(error)}`)
      animateTo({ duration: 280, curve: curves.springMotion(0.35, 0.8) }, () => {
        this.knowledgeListImmersiveMaterial = previous
      })
    }
  }

  private buildPreviewFloatingStyle(): HdsTabsFloatingStyle {
    const opts = new CompactTabsFloatingStyleOptions()
    opts.materialType = this.materialType
    opts.materialLevel = this.materialLevel
    opts.lightColorMode = this.lightColorMode
    opts.themePrimary = this.themePrimary
    opts.barSideMargin = 10
    opts.barBottomMargin = 8
    opts.barWidth = { smallWidth: 200, mediumWidth: 220, largeWidth: 240 }
    return buildCompactTabsFloatingStyle(opts)
  }

  private getAppearanceBlockMaterial(interactive: boolean = false): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: Color.Transparent,
      applyShadow: true,
      interactive: interactive,
      lightEffect: { color: undefined }
    })
  }

  private getThemeRowStartIndexes(): number[] {
    const indexes: number[] = []
    for (let index = 0; index < ALL_THEMES.length; index += 2) {
      indexes.push(index)
    }
    return indexes
  }

  @Builder
  private SectionHeader(title: Resource, subtitle: Resource) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text(subtitle)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(18)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private PreviewLine(color: string, widthValue: string) {
    Column()
      .width(widthValue)
      .height(8)
      .borderRadius(4)
      .backgroundColor(color)
  }

  @Builder
  private ModeRadioRow(mode: ThemeMode, title: Resource) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Regular)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({ value: mode, group: 'appearanceThemeMode' })
        .checked(this.currentThemeMode === mode)
        .radioStyle({
          checkedBackgroundColor: this.themePrimary,
          indicatorColor: Color.White
        })
        .onChange((isChecked: boolean) => {
          if (isChecked && this.currentThemeMode !== mode) {
            this.handleThemeModeSelected(mode)
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (this.currentThemeMode !== mode) {
        this.handleThemeModeSelected(mode)
      }
    })
  }

  @Builder
  private ModeRadioGroup() {
    Column() {
      this.ModeRadioRow(ThemeMode.SYSTEM, $r('app.string.theme_system'))
      Divider().color(this.themePrimaryLight).margin({ left: 16, right: 16 })
      this.ModeRadioRow(ThemeMode.LIGHT, $r('app.string.theme_light'))
      Divider().color(this.themePrimaryLight).margin({ left: 16, right: 16 })
      this.ModeRadioRow(ThemeMode.DARK, $r('app.string.theme_dark'))
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .borderRadius(24)
    .border({ width: 1, color: this.themePrimaryLight })
    .padding({ top: 6, bottom: 6 })
    .systemMaterial(this.getAppearanceBlockMaterial(false))
  }

  @Builder
  private ThemeCard(theme: ThemeInfo) {
    Column() {
      Column({ space: 12 }) {
        Column({ space: 14 }) {
          Row({ space: 10 }) {
            Column()
              .layoutWeight(1)
              .height(16)
              .borderRadius(8)
              .backgroundColor(this.getThemePreviewSwatch(theme, 0))
              .border({ width: 1, color: this.getPreviewColors(theme.id).primaryLight })

            Column()
              .layoutWeight(1)
              .height(16)
              .borderRadius(8)
              .backgroundColor(this.getThemePreviewSwatch(theme, 1))

            Column()
              .layoutWeight(1)
              .height(16)
              .borderRadius(8)
              .backgroundColor(this.getThemePreviewSwatch(theme, 2))
          }
          .width('100%')

          Row({ space: 12 }) {
            Column({ space: 8 }) {
              this.PreviewLine(this.getPreviewColors(theme.id).primary, '100%')
              this.PreviewLine(this.getPreviewColors(theme.id).primaryLight, '72%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column()
              .width(30)
              .height(30)
              .borderRadius(15)
              .backgroundColor(this.getPreviewColors(theme.id).userBubble)
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.getPreviewColors(theme.id).background)
        .borderRadius(18)
        .border({ width: 1, color: this.getPreviewColors(theme.id).primaryLight })

        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(this.getThemeName(theme.id))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.themeCardTitleTypeface)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.getThemeDescription(theme.id))
              .fontSize(11)
              .fontFamily(this.themeCardTypeface)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(16)
              .width('100%')
              .height(18)
              .textOverflow({ overflow: TextOverflow.MARQUEE })
              .marqueeOptions({
                start: true,
                step: 3,
                loop: -1,
                fromStart: true,
                delay: 1200,
                fadeout: true
              })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.currentColorTheme === theme.id) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(18)
              .fontColor([this.themePrimary])
              .transition(
                TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
                  .animation({ duration: 350, curve: curves.springMotion(0.35, 0.8) })
              )
          }
        }
        .width('100%')
      }
      .width('100%')
      .padding(10)
      .backgroundColor(Color.Transparent)
      .borderRadius(20)
    }
    .padding(2)
    .backgroundColor(Color.Transparent)
    .borderRadius(24)
    .border({
      width: this.currentColorTheme === theme.id ? 2 : 1,
      color: this.currentColorTheme === theme.id ? this.themePrimary : this.themePrimaryLight
    })
    .layoutWeight(1)
    .systemMaterial(this.getAppearanceBlockMaterial(true))
    .onClick(() => {
      this.handleColorThemeSelected(theme.id)
    })
  }

  @Builder
  private FontPresetButton(label: Resource, size: number) {
    Button(label)
      .height(36)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.chatFontSize === size ? Color.White : this.themePrimary)
      .backgroundColor(Color.Transparent)
      .borderRadius(18)
      .border({
        width: 1,
        color: this.chatFontSize === size ? this.themePrimary : this.themePrimaryLight
      })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        materialColor: this.chatFontSize === size ? this.themePrimary : Color.Transparent,
        applyShadow: false,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .layoutWeight(1)
      .onClick(() => {
        this.handleFontSizeChanged(size)
      })
  }

  @Builder
  private MiniTabBarAssistants() {
    IndexBottomTabItem({
      active: this.previewTabIndex === PREVIEW_TAB_INDEX_ASSISTANTS,
      activeIcon: $r('sys.symbol.person_fill'),
      inactiveIcon: $r('sys.symbol.person'),
      label: $r('app.string.tab_assistants')
    })
  }

  @Builder
  private MiniTabBarChat() {
    IndexBottomTabItem({
      active: this.previewTabIndex === PREVIEW_TAB_INDEX_CHAT,
      activeIcon: $r('sys.symbol.ellipsis_message_fill'),
      inactiveIcon: $r('sys.symbol.ellipsis_message'),
      label: $r('app.string.tab_chat')
    })
  }

  @Builder
  private MiniTabBarSettings() {
    IndexBottomTabItem({
      active: this.previewTabIndex === PREVIEW_TAB_INDEX_SETTINGS,
      activeIcon: $r('sys.symbol.gearshape_fill'),
      inactiveIcon: $r('sys.symbol.gearshape'),
      label: $r('app.string.tab_settings')
    })
  }

  @Builder
  private MiniHdsTabs() {
    Column() {
      HdsTabs({ barPosition: BarPosition.End, index: this.previewTabIndex }) {
        TabContent() {
          Column().width('100%').height('100%').backgroundColor(this.themeBackground)
        }
        .tabBar(this.MiniTabBarAssistants())

        TabContent() {
          Column().width('100%').height('100%').backgroundColor(this.themeBackground)
        }
        .tabBar(this.MiniTabBarChat())

        TabContent() {
          Column().width('100%').height('100%').backgroundColor(this.themeBackground)
        }
        .tabBar(this.MiniTabBarSettings())
      }
      .barOverlap(true)
      .barBackgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .barBackgroundColor(Color.Transparent)
      .barMode(BarMode.Fixed)
      .barFloatingStyle(this.buildPreviewFloatingStyle())
      .scrollable(false)
      .onChange((idx: number) => {
        if (this.previewTabIndex !== idx) {
          this.previewTabIndex = idx
        }
      })
    }
    .width('100%')
    .height(105)
    .borderRadius(18)
    .clip(true)
    .backgroundColor(this.themeBackground)
    .border({ width: 1, color: this.themePrimaryLight })
  }

  @Builder
  private DualBubblePreview() {
    Column({ space: 12 }) {
      Row() {
        Column() {
          Text($r('app.string.font_preview_ai_message'))
            .fontSize(this.getAiPreviewFontSize())
            .lineHeight(this.getAiPreviewFontSize() + 7)
            .fontFamily(this.previewChatTypeface)
            .fontColor(this.themeTextPrimary)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.themeAiBubble)
        .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 6, bottomRight: 18 })
        .border({ width: 1, color: this.themePrimaryLight })
        .constraintSize({ maxWidth: '76%' })

        Blank()
      }
      .width('100%')

      Row() {
        Blank()

        Column() {
          Text($r('app.string.font_preview_user_message'))
            .fontSize(this.chatFontSize)
            .lineHeight(this.chatFontSize + 7)
            .fontFamily(this.previewChatTypeface)
            .fontColor(this.themeUserBubbleText)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.themeUserBubble)
        .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 6 })
        .constraintSize({ maxWidth: '76%' })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private LivePreviewSection() {
    Column({ space: APPEARANCE_BLOCK_GAP }) {
      this.SectionHeader($r('app.string.appearance_live_preview_title'),
        $r('app.string.appearance_live_preview_desc'))

      Column({ space: 10 }) {
        this.DualBubblePreview()
        this.MiniHdsTabs()
      }
      .width('100%')
      .padding(12)
      .backgroundColor(Color.Transparent)
      .borderRadius(24)
      .border({ width: 1, color: this.themePrimaryLight })
      .systemMaterial(this.getAppearanceBlockMaterial(false))
    }
    .width('100%')
  }

  @Builder
  private AppearanceTabBar(label: Resource, index: number) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row() {
        Text(label)
          .fontSize(14)
          .fontWeight(this.currentTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.currentTabIndex === index ? this.themeUserBubbleText : $r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .borderRadius(20)
      .backgroundColor(this.currentTabIndex === index ? this.themePrimary : Color.Transparent)
    }
    .layoutWeight(1)
    .height(40)
    .padding(0)
    .borderRadius(20)
    .clip(true)
    .backgroundColor(Color.Transparent)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: Color.White }
    }))
    .onClick(() => {
      if (this.currentTabIndex !== index) {
        this.appearanceTabsController.changeIndex(index)
      }
    })
  }

  @Builder
  private AppearanceFloatingTabs() {
    Row({ space: 8 }) {
      this.AppearanceTabBar($r('app.string.appearance_tab_theme'), 0)
      this.AppearanceTabBar($r('app.string.appearance_tab_font'), 1)
      this.AppearanceTabBar($r('app.string.appearance_tab_material'), 2)
    }
    .width(this.windowWidthVp >= 600 ? 272 : 248)
    .height(40)
    .margin({ bottom: 28 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private ThemeTabContent() {
    Scroll(this.themeScroller) {
      Row() {
        Column({ space: APPEARANCE_BLOCK_GAP }) {
          this.SectionHeader($r('app.string.appearance_display_mode_title'),
            $r('app.string.appearance_display_mode_desc'))

          this.ModeRadioGroup()

          this.SectionHeader($r('app.string.settings_color_theme'),
            $r('app.string.appearance_color_theme_desc'))

          ForEach(this.getThemeRowStartIndexes(), (startIndex: number) => {
            Row({ space: APPEARANCE_BLOCK_GAP }) {
              this.ThemeCard(ALL_THEMES[startIndex])

              if (startIndex + 1 < ALL_THEMES.length) {
                this.ThemeCard(ALL_THEMES[startIndex + 1])
              } else {
                Blank()
                  .layoutWeight(1)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (startIndex: number) => `theme_row_${startIndex}`)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, top: 16, bottom: this.getScrollBottomPadding() })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private FontTabContent() {
    Scroll(this.fontScroller) {
      Row() {
        Column({ space: APPEARANCE_BLOCK_GAP }) {
          this.SectionHeader($r('app.string.appearance_tab_font'),
            $r('app.string.settings_chat_font_desc'))

          Column({ space: 16 }) {
            Row() {
              Column({ space: 2 }) {
                Text($r('app.string.settings_font_size'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))

                Text(this.getFontSizeText(this.chatFontSize))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)

              Blank()

              Text(`${this.chatFontSize} fp`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
            }
            .width('100%')

            Row({ space: 10 }) {
              Text('A')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))

              Slider({ value: this.chatFontSize, min: 12, max: 22, step: 1, style: SliderStyle.InSet })
                .systemMaterial(new uiMaterial.ImmersiveMaterial({
                  style: uiMaterial.ImmersiveStyle.ULTRA_THIN
                }))
                .selectedColor(this.themePrimary)
                .trackThickness(20)
                .layoutWeight(1)
                .onChange((value: number, _mode: SliderChangeMode) => {
                  this.handleFontSizeChanged(Math.round(value))
                })

              Text('A')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Row({ space: 8 }) {
              this.FontPresetButton($r('app.string.font_size_small'), 13)
              this.FontPresetButton($r('app.string.font_size_default'), 15)
              this.FontPresetButton($r('app.string.font_size_large'), 17)
              this.FontPresetButton($r('app.string.font_size_extra_large'), 19)
            }
            .width('100%')
          }
          .width('100%')
          .padding(18)
          .backgroundColor(Color.Transparent)
          .borderRadius(24)
          .border({ width: 1, color: this.themePrimaryLight })
          .systemMaterial(this.getAppearanceBlockMaterial(false))

          Column({ space: 10 }) {
            Text($r('app.string.settings_markdown_renderer'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            Text($r('app.string.settings_markdown_renderer_desc'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(18)
              .width('100%')

            Select(this.getMarkdownRendererOptions())
              .selected(this.getMarkdownRendererSelectedIndex())
              .value(this.getMarkdownRendererOptions()[this.getMarkdownRendererSelectedIndex()].value)
              .width('100%')
              .height(46)
              .font({ size: 13 })
              .fontColor($r('app.color.text_primary'))
              .selectedOptionFontColor(this.themePrimary)
              .backgroundColor(Color.Transparent)
              .borderRadius(16)
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
                materialColor: Color.Transparent,
                applyShadow: false
              }))
              .menuSystemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.THICK
              }))
              .onSelect((index: number, _value: string): void => {
                this.handleMarkdownRendererChanged(index)
              })
          }
          .width('100%')
          .padding(18)
          .alignItems(HorizontalAlign.Start)
          .backgroundColor(Color.Transparent)
          .borderRadius(24)
          .border({ width: 1, color: this.themePrimaryLight })
          .systemMaterial(this.getAppearanceBlockMaterial(false))

          Row({ space: 16 }) {
            Column({ space: 4 }) {
              Text($r('app.string.settings_chat_serif_font'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')

              Text($r('app.string.settings_chat_serif_font_desc'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(18)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.chatSerifFontEnabled })
              .selectedColor(this.themePrimary)
              .systemMaterial(new uiMaterial.Material())
              .switchPointColor(Color.White)
              .animation({ duration: 280, curve: curves.springMotion(0.35, 0.8) })
              .onChange((enabled: boolean) => {
                this.handleChatSerifFontChanged(enabled)
              })
          }
          .width('100%')
          .padding(18)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(Color.Transparent)
          .borderRadius(24)
          .border({ width: 1, color: this.themePrimaryLight })
          .systemMaterial(this.getAppearanceBlockMaterial(false))

          Column({ space: 10 }) {
            Text($r('app.string.settings_chat_serif_font_family'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            Select(this.getSerifFontOptions())
              .key(`serif_font_select_${this.serifFontSelectRevision.toString()}`)
              .selected(this.getSerifFontSelectedIndex())
              .value(this.getSerifFontOptions()[this.getSerifFontSelectedIndex()].value)
              .width('100%')
              .height(46)
              .font({ size: 13 })
              .fontColor($r('app.color.text_primary'))
              .selectedOptionFontColor(this.themePrimary)
              .backgroundColor(Color.Transparent)
              .borderRadius(16)
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
                materialColor: Color.Transparent,
                applyShadow: false
              }))
              .menuSystemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.THICK
              }))
              .enabled(this.chatSerifFontEnabled)
              .onSelect((index: number, _value: string): void => {
                this.handleChatSerifFontFamilyChanged(index)
              })
          }
          .width('100%')
          .padding(18)
          .alignItems(HorizontalAlign.Start)
          .backgroundColor(Color.Transparent)
          .borderRadius(24)
          .border({ width: 1, color: this.themePrimaryLight })
          .systemMaterial(this.getAppearanceBlockMaterial(false))
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, top: 16, bottom: this.getScrollBottomPadding() })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private MaterialTabContent() {
    Scroll() {
      Row() {
        Column() {
          Row({ space: 16 }) {
            Column({ space: 4 }) {
              Text($r('app.string.chat_list_immersive_material_title'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')

              Text($r('app.string.chat_list_immersive_material_desc'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(18)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.chatListImmersiveMaterial })
              .selectedColor(this.themePrimary)
              .systemMaterial(new uiMaterial.Material())
              .switchPointColor(Color.White)
              .animation({ duration: 280, curve: curves.springMotion(0.35, 0.8) })
              .onChange((enabled: boolean) => {
                this.handleChatListImmersiveMaterialChanged(enabled)
              })
          }
          .width('100%')
          .padding(18)
          .alignItems(VerticalAlign.Center)

          Divider()
            .color(this.themePrimaryLight)
            .margin({ left: 18, right: 18 })

          Row({ space: 16 }) {
            Column({ space: 4 }) {
              Text($r('app.string.knowledge_list_immersive_material_title'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')

              Text($r('app.string.knowledge_list_immersive_material_desc'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(18)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.knowledgeListImmersiveMaterial })
              .selectedColor(this.themePrimary)
              .systemMaterial(new uiMaterial.Material())
              .switchPointColor(Color.White)
              .animation({ duration: 280, curve: curves.springMotion(0.35, 0.8) })
              .onChange((enabled: boolean) => {
                this.handleKnowledgeListImmersiveMaterialChanged(enabled)
              })
          }
          .width('100%')
          .padding(18)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .backgroundColor(Color.Transparent)
        .borderRadius(24)
        .border({ width: 1, color: this.themePrimaryLight })
        .systemMaterial(this.getAppearanceBlockMaterial(false))
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, top: 16, bottom: this.getScrollBottomPadding() })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private PageBody() {
    Column({ space: APPEARANCE_BLOCK_GAP }) {
      Row() {
        Column() {
          this.LivePreviewSection()
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, top: 8 })

      Stack({ alignContent: Alignment.Bottom }) {
        Tabs({ index: this.currentTabIndex, controller: this.appearanceTabsController }) {
          TabContent() {
            this.ThemeTabContent()
          }

          TabContent() {
            this.FontTabContent()
          }

          TabContent() {
            this.MaterialTabContent()
          }
        }
        .barHeight(0)
        .backgroundColor(Color.Transparent)
        .scrollable(true)
        .width('100%')
        .height('100%')
        .animationDuration(280)
        .onChange((idx: number) => {
          if (this.currentTabIndex !== idx) {
            animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
              this.currentTabIndex = idx
            })
          }
        })

        this.AppearanceFloatingTabs()
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private CompactBody() {
    Column() {
      Blank()
        .width('100%')
        .height(this.getCompactContentTopPadding())

      this.PageBody()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: this.compactTitle,
      onBack: this.onCompactBack
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_appearance'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.themeBackground)
    .border({ width: { bottom: 1 }, color: this.themePrimaryLight })
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        Column() {
          this.DetailPaneHeader()
          this.PageBody()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.CompactBody()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(false)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }
}

@Entry
@ComponentV2
struct ThemeModeSettingsPage {
  private handleBack(): void {
    if (themeModeSettingsPathStack !== null && themeModeSettingsPathStack.size() > 0) {
      themeModeSettingsPathStack.pop()
    }
  }

  build() {
    Column() {
      ThemeAppearanceSettingsView({
        compactTitle: $r('app.string.settings_appearance'),
        onCompactBack: () => {
          this.handleBack()
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}

@Builder
export function ThemeModeSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    ThemeModeSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    themeModeSettingsPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (themeModeSettingsPathStack !== null && themeModeSettingsPathStack.size() > 0) {
      themeModeSettingsPathStack.pop()
    }
    return true
  })
}
