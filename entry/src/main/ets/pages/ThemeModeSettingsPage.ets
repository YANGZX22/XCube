import { DrawnFloatingTabBar } from '../components/DrawnFloatingTabBar'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getDrawnNavigationBorder, shouldUseDrawnNavigation } from '../utils/DrawnNavigationSupport'
import { ImmersiveButtonSurface } from '../components/ImmersiveButtonSurface'
import { getBlurBottomShadow } from '../utils/BlurShadowUtils'
import { isWrappedMaterialApiAvailable, shouldUseWrappedMaterial } from '../utils/WrappedMaterialSupport'
import {
  HdsNavigation,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsFloatingStyle
} from '@kit.UIDesignKit'
import { getHdsSystemMaterialEffect, HdsTabsBlurModifier, DrawnTabsContentModifier, getHdsMaterialLightColor } from '../utils/HdsMaterialSupport'
import { curves, uiMaterial } from '@kit.ArkUI'
import { picker } from '@kit.CoreFileKit'
import {
  ALL_THEMES,
  ColorTheme,
  getThemeColors,
  ThemeColorConfig,
  ThemeInfo,
  VisualEffectsMode
} from '../models/ThemeColors'
import { MarkdownRenderer, ThemeMode } from '../services/PreferencesService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { getSettingsPageContentMaxWidth, getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationMaskExtraHeight,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import { IndexBottomTabItem } from '../components/index/IndexBottomTabItem'
import { showToast } from '../utils/ToastUtil'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import {
  CHAT_SERIF_FONT_CINZEL,
  CHAT_SERIF_FONT_CMU,
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
import {
  ensureManuscriptFonts,
  MANUSCRIPT_BODY_FONT,
  MANUSCRIPT_HEADING_FONT
} from '../utils/ManuscriptVisualUtils'

let themeModeSettingsPathStack: NavPathStack | null = null

const TAB_INDEX_THEME = 0

const PREVIEW_TAB_INDEX_ASSISTANTS = 0
const PREVIEW_TAB_INDEX_CHAT = 1
const PREVIEW_TAB_INDEX_KNOWLEDGE = 2
const PREVIEW_TAB_INDEX_SETTINGS = 3
const APPEARANCE_BLOCK_GAP = 16
const APPEARANCE_FLOATING_TAB_BAR_HEIGHT = 60
const APPEARANCE_FLOATING_TAB_BAR_WIDTH = 280
const APPEARANCE_FLOATING_TAB_BAR_SIDE_MARGIN = 16
const APPEARANCE_FLOATING_TAB_BAR_BOTTOM_MARGIN = 12
const APPEARANCE_FLOATING_TAB_BAR_SAFE_BOTTOM_MARGIN = 24
const PREVIEW_FLOATING_TAB_BAR_HEIGHT = 52
const PREVIEW_FLOATING_TAB_CONTAINER_HEIGHT = 76
const PREVIEW_FLOATING_TAB_BOTTOM_MARGIN = 8
const PREVIEW_FLOATING_TAB_MAX_CONTAINER_WIDTH = 320
const PREVIEW_FLOATING_TAB_HORIZONTAL_PADDING = 16
const PREVIEW_FLOATING_TAB_ITEM_GAP = 8
const PREVIEW_FLOATING_ADD_BUTTON_SIZE = 52
const PREVIEW_FLOATING_TAB_BAR_WIDTH_ADJUSTMENT = 4

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
    if (this.visualEffectsMode === VisualEffectsMode.MANUSCRIPT) {
      return MANUSCRIPT_BODY_FONT
    }
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
  @Local visualEffectsMode: VisualEffectsMode = VisualEffectsMode.OFF
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
  @Local savingChatListMaterial: boolean = false
  @Local savingKnowledgeListMaterial: boolean = false
  @Local forceWrappedMaterialBlur: boolean = false
  @Local savingWrappedMaterialFallback: boolean = false

  @Local currentTabIndex: number = TAB_INDEX_THEME
  @Local previewTabIndex: number = PREVIEW_TAB_INDEX_CHAT
  @Local livePreviewExpanded: boolean = false

  private settingsManager = ServiceRegistry.settings()
  private themeScroller: Scroller = new Scroller()
  private fontScroller: Scroller = new Scroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    ensureManuscriptFonts()
    const fontAvailability: ChatSerifFontAvailability = detectAndRegisterChatSerifFonts(this.getUIContext())
    this.customSerifAvailable = fontAvailability.customAvailable
    this.customSerifName = getImportedChatSerifFontName()
    this.currentThemeMode = this.settingsManager.getThemeMode()
    this.currentColorTheme = this.settingsManager.getColorTheme()
    this.visualEffectsMode = this.settingsManager.getVisualEffectsMode()
    this.chatFontSize = this.settingsManager.getChatFontSize()
    this.chatSerifFontEnabled = this.settingsManager.getChatSerifFontEnabled()
    this.markdownRenderer = this.settingsManager.getMarkdownRenderer()
    const savedSerifFont = this.settingsManager.getChatSerifFontFamily()
    if (savedSerifFont === CHAT_SERIF_FONT_CINZEL || savedSerifFont === CHAT_SERIF_FONT_DOMINE ||
      savedSerifFont === CHAT_SERIF_FONT_LIBERTINUS || savedSerifFont === CHAT_SERIF_FONT_CMU) {
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
    this.forceWrappedMaterialBlur = this.settingsManager.getForceWrappedMaterialBlur()
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private shouldUsePreviewNavigationRail(): boolean {
    return this.layoutSizeClass === LayoutSizeClass.EXPANDED && this.windowWidthVp > this.windowHeightVp
  }

  private getLivePreviewHeight(): number {
    return this.isManuscriptMode() ? 360 : 350
  }

  private toggleLivePreview(): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.livePreviewExpanded = !this.livePreviewExpanded
    })
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
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp, this.windowHeightVp, (): void => this.CompactTitleStackBuilder(), [], this)
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
    if (this.visualEffectsMode === VisualEffectsMode.MANUSCRIPT) {
      return
    }
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
    if (this.visualEffectsMode === VisualEffectsMode.MANUSCRIPT) {
      return
    }
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

  private async handleVisualEffectsModeChanged(enabled: boolean): Promise<void> {
    const previousMode = this.visualEffectsMode
    const nextMode = enabled ? VisualEffectsMode.MANUSCRIPT : VisualEffectsMode.OFF
    animateTo({ duration: 400, curve: Curve.EaseInOut }, () => {
      this.visualEffectsMode = nextMode
    })
    try {
      await this.settingsManager.setVisualEffectsMode(nextMode)
    } catch (error) {
      console.error('ThemeAppearanceSettingsView',
        `Failed to update visual effects mode: ${JSON.stringify(error)}`)
      animateTo({ duration: 400, curve: Curve.EaseInOut }, () => {
        this.visualEffectsMode = previousMode
      })
    }
  }

  private getSerifFontOptions(): SelectOption[] {
    const options: SelectOption[] = [
      { value: $r('app.string.chat_serif_font_common') },
      { value: $r('app.string.chat_serif_font_cinzel') },
      { value: $r('app.string.chat_serif_font_domine') },
      { value: $r('app.string.chat_serif_font_libertinus') },
      { value: $r('app.string.chat_serif_font_cmu') }
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
    if (this.chatSerifFontFamily === CHAT_SERIF_FONT_CMU) {
      return 4
    }
    return this.chatSerifFontFamily === CHAT_SERIF_FONT_CUSTOM && this.customSerifAvailable ? 5 : 0
  }

  private async handleChatSerifFontFamilyChanged(index: number): Promise<void> {
    const importOptionIndex = this.customSerifAvailable ? 6 : 5
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
    } else if (index === 4) {
      nextFontFamily = CHAT_SERIF_FONT_CMU
    } else if (index === 5 && this.customSerifAvailable) {
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
    if (this.savingChatListMaterial || enabled === this.chatListImmersiveMaterial) {
      return
    }
    const previous = this.chatListImmersiveMaterial
    this.savingChatListMaterial = true
    this.chatListImmersiveMaterial = enabled
    try {
      await this.settingsManager.setChatListImmersiveMaterial(enabled)
    } catch (_error) {
      this.chatListImmersiveMaterial = previous
      showToast(this.getUIContext(), pickLocalizedText('材质设置保存失败，请重试', 'Could not save material settings. Try again.'))
    } finally {
      this.savingChatListMaterial = false
    }
  }

  private async handleKnowledgeListImmersiveMaterialChanged(enabled: boolean): Promise<void> {
    if (this.savingKnowledgeListMaterial || enabled === this.knowledgeListImmersiveMaterial) {
      return
    }
    const previous = this.knowledgeListImmersiveMaterial
    this.savingKnowledgeListMaterial = true
    this.knowledgeListImmersiveMaterial = enabled
    try {
      await this.settingsManager.setKnowledgeListImmersiveMaterial(enabled)
    } catch (_error) {
      this.knowledgeListImmersiveMaterial = previous
      showToast(this.getUIContext(), pickLocalizedText('材质设置保存失败，请重试', 'Could not save material settings. Try again.'))
    } finally {
      this.savingKnowledgeListMaterial = false
    }
  }

  private async handleWrappedMaterialFallbackChanged(enabled: boolean): Promise<void> {
    if (this.savingWrappedMaterialFallback || enabled === this.forceWrappedMaterialBlur) {
      return
    }
    const previous = this.forceWrappedMaterialBlur
    this.savingWrappedMaterialFallback = true
    this.forceWrappedMaterialBlur = enabled
    try {
      await this.settingsManager.setForceWrappedMaterialBlur(enabled)
    } catch (_error) {
      this.forceWrappedMaterialBlur = previous
      showToast(this.getUIContext(), pickLocalizedText('材质设置保存失败，请重试', 'Could not save material settings. Try again.'))
    } finally {
      this.savingWrappedMaterialFallback = false
    }
  }

  private getWrappedMaterialStatus(): Resource {
    if (this.forceWrappedMaterialBlur) {
      return $r('app.string.wrapped_material_status_forced')
    }
    return isWrappedMaterialApiAvailable()
      ? $r('app.string.wrapped_material_status_available')
      : $r('app.string.wrapped_material_status_fallback')
  }

  private buildPreviewFloatingStyle(): HdsTabsFloatingStyle {
    return {
      barSideMargin: 8,
      barBottomMargin: PREVIEW_FLOATING_TAB_BOTTOM_MARGIN,
      barWidth: {
        smallWidth: this.getPreviewFloatingTabBarWidth(),
        mediumWidth: this.getPreviewFloatingTabBarWidth(),
        largeWidth: this.getPreviewFloatingTabBarWidth()
      },
      gradientMask: { maskColor: Color.Transparent },
      lightColor: getHdsMaterialLightColor(Color.White),
      systemMaterialEffect: getHdsSystemMaterialEffect()
    }
  }

  private getPreviewBottomNavigationWidth(): number {
    if (this.windowWidthVp <= 0 || this.isDetailPaneMode()) {
      return PREVIEW_FLOATING_TAB_MAX_CONTAINER_WIDTH
    }
    return Math.min(PREVIEW_FLOATING_TAB_MAX_CONTAINER_WIDTH, this.windowWidthVp - 32)
  }

  private getPreviewFloatingTabHostWidth(): number {
    return this.getPreviewBottomNavigationWidth() - PREVIEW_FLOATING_TAB_HORIZONTAL_PADDING -
      PREVIEW_FLOATING_TAB_ITEM_GAP - PREVIEW_FLOATING_ADD_BUTTON_SIZE
  }

  private getPreviewFloatingTabBarWidth(): number {
    return this.getPreviewFloatingTabHostWidth() - PREVIEW_FLOATING_TAB_BAR_WIDTH_ADJUSTMENT
  }

  private getAppearanceFloatingTabBottomMargin(): number {
    return this.px2vp(this.bottomAvoidHeight) > 0 ? APPEARANCE_FLOATING_TAB_BAR_SAFE_BOTTOM_MARGIN :
      APPEARANCE_FLOATING_TAB_BAR_BOTTOM_MARGIN
  }

  private buildAppearanceFloatingStyle(): HdsTabsFloatingStyle {
    return {
      barSideMargin: APPEARANCE_FLOATING_TAB_BAR_SIDE_MARGIN,
      barBottomMargin: this.getAppearanceFloatingTabBottomMargin(),
      barWidth: {
        smallWidth: APPEARANCE_FLOATING_TAB_BAR_WIDTH,
        mediumWidth: APPEARANCE_FLOATING_TAB_BAR_WIDTH,
        largeWidth: APPEARANCE_FLOATING_TAB_BAR_WIDTH
      },
      gradientMask: { maskColor: Color.Transparent },
      lightColor: getHdsMaterialLightColor(Color.White),
      systemMaterialEffect: getHdsSystemMaterialEffect()
    }
  }

  private getThemeRowStartIndexes(): number[] {
    const indexes: number[] = []
    for (let index = 0; index < ALL_THEMES.length; index += 2) {
      indexes.push(index)
    }
    return indexes
  }

  private isManuscriptMode(): boolean {
    return this.visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private getManuscriptAccent(): string {
    return this.isDarkMode ? '#C99A52' : '#B68235'
  }

  private getManuscriptAccentDeep(): string {
    return this.isDarkMode ? '#D9B274' : '#8A6228'
  }

  @Builder
  private ManuscriptVignette() {
    Column({ space: 5 }) {
      Text('A')
        .fontFamily(MANUSCRIPT_HEADING_FONT)
        .fontSize(25)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkMode ? '#ECEAE5' : '#201F1D')

      Divider()
        .width(28)
        .strokeWidth(1)
        .color(this.getManuscriptAccent())

      Column().width(31).height(2).backgroundColor(this.isDarkMode ? '#7B766D' : '#98938A')
      Column().width(24).height(2).backgroundColor(this.isDarkMode ? '#7B766D' : '#98938A')
    }
    .width(54)
    .height(72)
    .padding({ top: 7, bottom: 6 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isDarkMode ? '#242320' : '#FBFAF8')
    .border({ width: 1, color: this.getManuscriptAccent() })
    .shadow({
      radius: 0,
      color: this.isDarkMode ? '#4A3B27' : '#E8D8BE',
      offsetX: 2,
      offsetY: 2
    })
  }

  @Builder
  private VisualEffectsEntryCard() {
    Column({ space: 0 }) {
      Row({ space: 14 }) {
        this.ManuscriptVignette()

        Column({ space: 4 }) {
          Row({ space: 7 }) {
            Text($r('app.string.visual_effects_title'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))

            Text($r('app.string.visual_effects_new'))
              .fontSize(9)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .letterSpacing(1)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#8A6228')
              .borderRadius(5)
          }
          .width('100%')

          Text($r('app.string.visual_effects_manuscript'))
            .fontFamily(MANUSCRIPT_HEADING_FONT)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getManuscriptAccentDeep())

          Text($r('app.string.visual_effects_desc'))
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(18)
            .maxLines(3)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.isManuscriptMode() })
          .selectedColor(this.getManuscriptAccentDeep())
          .switchPointColor(Color.White)
          .onChange((enabled: boolean) => {
            this.handleVisualEffectsModeChanged(enabled)
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.isManuscriptMode()) {
        Text($r('app.string.visual_effects_themes_locked'))
          .width('100%')
          .fontFamily(MANUSCRIPT_BODY_FONT)
          .fontSize(12)
          .fontStyle(FontStyle.Italic)
          .fontColor(this.getManuscriptAccentDeep())
          .lineHeight(18)
          .padding({ top: 12 })
          .transition(
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -6 }))
              .animation({ duration: 400, curve: Curve.EaseOut })
          )
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.Transparent)
    .borderRadius(24)
    .border({
      width: this.isManuscriptMode() ? 2 : 1,
      color: this.isManuscriptMode() ? this.getManuscriptAccent() : this.themePrimaryLight
    })
    .backdropBlur(16)
    .shadow(getBlurBottomShadow())
    .animation({ duration: 400, curve: Curve.EaseInOut })
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
    .backdropBlur(16)
    .shadow(getBlurBottomShadow())
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
    .backdropBlur(16)
    .shadow(getBlurBottomShadow())
    .opacity(this.isManuscriptMode() ? 0.45 : 1)
    .enabled(!this.isManuscriptMode())
    .onClick(() => {
      if (!this.isManuscriptMode()) {
        this.handleColorThemeSelected(theme.id)
      }
    })
  }

  @Builder
  private FontPresetButton(label: Resource, size: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      ImmersiveButtonSurface({
        materialFactory: () => (new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
            materialColor: this.chatFontSize === size ? withColorAlpha(this.themePrimary, '26') : Color.Transparent,
            applyShadow: false,
            interactive: true,
            lightEffect: { color: undefined }
          })),
        fallbackShadow: false,
        cornerRadius: 18
      }) {
        Button(label)
          .height(36)
          .fontSize(13)
          .fontWeight(shouldUseWrappedMaterial() && this.chatFontSize === size ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.themePrimary)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .border({
            width: shouldUseWrappedMaterial() ? 0 : 1,
            color: this.chatFontSize === size ? this.themePrimary : this.themePrimaryLight
          })
          .onClick(() => {
            this.handleFontSizeChanged(size)
          })
        .width('100%')
      }
    }
    .height(36)
    .layoutWeight(1)
    .clip(false)
  }

  @Builder
  private MiniTabBarAssistants() {
    IndexBottomTabItem({
      disablePressScale: shouldUseDrawnNavigation(),
      active: this.previewTabIndex === PREVIEW_TAB_INDEX_ASSISTANTS,
      activeIcon: $r('sys.symbol.person_fill'),
      inactiveIcon: $r('sys.symbol.person'),
      label: $r('app.string.tab_assistants'),
      manuscriptLabel: $r('app.string.manuscript_tab_assistants')
    })
  }

  @Builder
  private MiniTabBarChat() {
    IndexBottomTabItem({
      disablePressScale: shouldUseDrawnNavigation(),
      active: this.previewTabIndex === PREVIEW_TAB_INDEX_CHAT,
      activeIcon: $r('sys.symbol.ellipsis_message_fill'),
      inactiveIcon: $r('sys.symbol.ellipsis_message'),
      label: $r('app.string.tab_chat'),
      manuscriptLabel: $r('app.string.manuscript_tab_chat')
    })
  }

  @Builder
  private MiniTabBarSettings() {
    IndexBottomTabItem({
      disablePressScale: shouldUseDrawnNavigation(),
      active: this.previewTabIndex === PREVIEW_TAB_INDEX_SETTINGS,
      activeIcon: $r('sys.symbol.gearshape_fill'),
      inactiveIcon: $r('sys.symbol.gearshape'),
      label: $r('app.string.tab_settings'),
      manuscriptLabel: $r('app.string.manuscript_tab_settings')
    })
  }

  @Builder
  private MiniTabBarKnowledge() {
    IndexBottomTabItem({
      disablePressScale: shouldUseDrawnNavigation(),
      active: this.previewTabIndex === PREVIEW_TAB_INDEX_KNOWLEDGE,
      activeIcon: $r('sys.symbol.externaldrive_fill'),
      inactiveIcon: $r('sys.symbol.externaldrive'),
      label: $r('app.string.tab_knowledge'),
      manuscriptLabel: $r('app.string.manuscript_tab_knowledge')
    })
  }

  @Builder
  private MiniPreviewTab(index: number) {
    Row() {
      if (index === PREVIEW_TAB_INDEX_ASSISTANTS) {
        this.MiniTabBarAssistants()
      } else if (index === PREVIEW_TAB_INDEX_CHAT) {
        this.MiniTabBarChat()
      } else if (index === PREVIEW_TAB_INDEX_KNOWLEDGE) {
        this.MiniTabBarKnowledge()
      } else {
        this.MiniTabBarSettings()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private MiniPreviewTabButton(index: number) {
    Row() {
      this.MiniPreviewTab(index)
    }
    .layoutWeight(1)
    .height('100%')
    .onClick(() => {
      this.previewTabIndex = index
    })
  }

  @Builder
  private MiniManuscriptBottomNavigation() {
    Stack() {
      Row() {
        this.MiniPreviewTabButton(PREVIEW_TAB_INDEX_ASSISTANTS)
        this.MiniPreviewTabButton(PREVIEW_TAB_INDEX_CHAT)
        this.MiniPreviewTabButton(PREVIEW_TAB_INDEX_KNOWLEDGE)
        this.MiniPreviewTabButton(PREVIEW_TAB_INDEX_SETTINGS)
      }
      .width('100%')
      .height(52)
      .backgroundColor(this.themeSurface)
      .border({ width: { top: 1 }, color: getAppUiState().themeDivider })
      .position({ x: 0, y: 24 })

      Row() {
        Blank()

        Button({ type: ButtonType.Normal, stateEffect: false }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([this.getManuscriptAccentDeep()])
        }
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
      }
      .width('100%')
      .height(40)
      .padding({ right: 12 })
      .position({ x: 0, y: 0 })
    }
    .width('100%')
    .height(PREVIEW_FLOATING_TAB_CONTAINER_HEIGHT)
    .clip(false)
  }

  @Builder
  private DrawnPreviewTab(index: number) {
    if (index === 0) {
      this.MiniPreviewTab(PREVIEW_TAB_INDEX_ASSISTANTS)
    }
    else if (index === 1) {
      this.MiniPreviewTab(PREVIEW_TAB_INDEX_CHAT)
    }
    else if (index === 2) {
      this.MiniPreviewTab(PREVIEW_TAB_INDEX_KNOWLEDGE)
    }
    else {
      this.MiniPreviewTab(PREVIEW_TAB_INDEX_SETTINGS)
    }
  }

  @Builder
  private MiniFloatingBottomNavigation() {
    Row() {
      Stack({ alignContent: Alignment.Bottom }) {
        HdsTabs({ barPosition: BarPosition.End, index: this.previewTabIndex }) {
          TabContent() {
            Column()
          }
          .tabBar(this.MiniPreviewTab(PREVIEW_TAB_INDEX_ASSISTANTS))

          TabContent() {
            Column()
          }
          .tabBar(this.MiniPreviewTab(PREVIEW_TAB_INDEX_CHAT))

          TabContent() {
            Column()
          }
          .tabBar(this.MiniPreviewTab(PREVIEW_TAB_INDEX_KNOWLEDGE))

          TabContent() {
            Column()
          }
          .tabBar(this.MiniPreviewTab(PREVIEW_TAB_INDEX_SETTINGS))
        }
        .width(this.getPreviewFloatingTabHostWidth())
        .height(PREVIEW_FLOATING_TAB_CONTAINER_HEIGHT)
        .barMode(BarMode.Fixed)
        .barHeight(shouldUseDrawnNavigation() ? 0 : PREVIEW_FLOATING_TAB_BAR_HEIGHT)
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .vertical(false)
        .scrollable(false)
        .animationDuration(260)
        .barFloatingStyle(shouldUseDrawnNavigation() ? undefined : this.buildPreviewFloatingStyle())
        .attributeModifier(shouldUseDrawnNavigation() ? new DrawnTabsContentModifier() : new HdsTabsBlurModifier(shouldUseWrappedMaterial()))
        .backgroundColor(Color.Transparent)
        .clip(false)
        .onChange((index: number) => {
          this.previewTabIndex = index
        })
        if (shouldUseDrawnNavigation()) {
          DrawnFloatingTabBar({
            tabCount: 4,
            selectedIndex: this.previewTabIndex,
            showSelectionBubble: false,
            barWidth: this.getPreviewFloatingTabBarWidth(),
            barHeight: PREVIEW_FLOATING_TAB_BAR_HEIGHT,
            itemContent: (index: number): void => this.DrawnPreviewTab(index),
            onSelect: (index: number) => {
              this.previewTabIndex = index
            }
          })
          .margin({ bottom: PREVIEW_FLOATING_TAB_BOTTOM_MARGIN })
        }
      }
      .width(this.getPreviewFloatingTabHostWidth())
      .height(PREVIEW_FLOATING_TAB_CONTAINER_HEIGHT)

      Blank()
        .layoutWeight(1)
        .constraintSize({ minWidth: PREVIEW_FLOATING_TAB_ITEM_GAP })

      Stack({ alignContent: Alignment.TopStart }) {
        ImmersiveButtonSurface({
          materialFactory: () => (new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR,
            materialColor: Color.Transparent,
            applyShadow: true,
            interactive: false,
            lightEffect: { color: Color.White }
          })),
          fallbackShadow: false,
          cornerRadius: 26
        }) {
          Button({ type: ButtonType.Circle, stateEffect: false }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(23)
              .fontColor([this.isManuscriptMode() ? this.getManuscriptAccentDeep() : this.themePrimary])
          }
          .width(52)
          .height(52)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .borderRadius(26)
          .border(shouldUseDrawnNavigation() ? getDrawnNavigationBorder() : undefined)
          .shadow(shouldUseWrappedMaterial() ? undefined : getBlurBottomShadow())
        }
      }
      .width(52)
      .height(52)
      .margin({ bottom: PREVIEW_FLOATING_TAB_BOTTOM_MARGIN })
      .clip(false)
    }
    .width('100%')
    .height(PREVIEW_FLOATING_TAB_CONTAINER_HEIGHT)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Bottom)
    .clip(false)
  }

  @Builder
  private MiniCurrentBottomNavigation() {
    if (this.isManuscriptMode()) {
      this.MiniManuscriptBottomNavigation()
    } else {
      this.MiniFloatingBottomNavigation()
    }
  }

  @Builder
  private MiniPreviewNavigationRail() {
    Column({ space: 4 }) {
      this.MiniPreviewRailTab(PREVIEW_TAB_INDEX_ASSISTANTS)
      this.MiniPreviewRailTab(PREVIEW_TAB_INDEX_CHAT)
      this.MiniPreviewRailTab(PREVIEW_TAB_INDEX_KNOWLEDGE)
      this.MiniPreviewRailTab(PREVIEW_TAB_INDEX_SETTINGS)

      Blank()
    }
    .width(64)
    .height('100%')
    .padding({ left: 6, right: 6, top: 8, bottom: 8 })
    .backgroundColor(this.themeSurface)
    .borderRadius({
      topLeft: this.isManuscriptMode() ? 3 : 22,
      bottomLeft: this.isManuscriptMode() ? 3 : 22
    })
    .border({ width: { right: 1 }, color: getAppUiState().themeDivider })
    .clip(true)
  }

  @Builder
  private MiniPreviewRailTab(index: number) {
    Column() {
      this.MiniPreviewTab(index)
    }
    .width('100%')
    .height(58)
    .borderRadius(this.isManuscriptMode() ? 0 : 16)
    .backgroundColor(this.previewTabIndex === index && !this.isManuscriptMode() ?
      this.themePrimaryLight : Color.Transparent)
    .onClick(() => {
      this.previewTabIndex = index
    })
  }

  @Builder
  private MiniPreviewHeaderIcon(symbol: Resource) {
    Stack({ alignContent: Alignment.TopStart }) {
      ImmersiveButtonSurface({
        materialFactory: this.isManuscriptMode() ? undefined : () => (new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Color.Transparent,
          applyShadow: false,
          interactive: false,
          lightEffect: { color: undefined }
        })),
        cornerRadius: this.isManuscriptMode() ? 0 : 17
      }) {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          SymbolGlyph(symbol)
            .fontSize(this.isManuscriptMode() ? 15 : 17)
            .fontColor([this.isManuscriptMode() ? this.getManuscriptAccentDeep() : this.themePrimary])
        }
        .width(34)
        .height(34)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(this.isManuscriptMode() ? 0 : 17)
      }
    }
    .width(34)
    .height(34)
    .clip(false)
  }

  @Builder
  private CurrentPreviewHeader() {
    Row() {
      this.MiniPreviewHeaderIcon($r('sys.symbol.chevron_left'))

      Column({ space: 1 }) {
        if (this.isManuscriptMode()) {
          Text(pickLocalizedText('对话 · 编号 XII', 'CONVERSATION · N° XII'))
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(8)
            .fontColor(getAppUiState().themeTextTertiary)
            .letterSpacing(1)
        }

        Text(pickLocalizedText('预览对话', 'Preview Conversation'))
          .fontFamily(this.isManuscriptMode() ? MANUSCRIPT_HEADING_FONT : this.previewChatTypeface)
          .fontSize(this.isManuscriptMode() ? 18 : 14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themeTextPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      this.MiniPreviewHeaderIcon($r('sys.symbol.plus'))
      this.MiniPreviewHeaderIcon($r('sys.symbol.dot_grid_2x2'))
    }
    .width('100%')
    .height(this.isManuscriptMode() ? 58 : 50)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: getAppUiState().themeDivider })
  }

  @Builder
  private PreviewMessageActions(alignment: FlexAlign) {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
        .fontSize(12)
        .fontColor([this.isManuscriptMode() ? this.getManuscriptAccentDeep() : $r('app.color.text_tertiary')])
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(12)
        .fontColor([this.isManuscriptMode() ? this.getManuscriptAccentDeep() : $r('app.color.text_tertiary')])
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(12)
        .fontColor([this.isManuscriptMode() ? this.getManuscriptAccentDeep() : $r('app.color.text_tertiary')])
    }
    .width('100%')
    .height(22)
    .justifyContent(alignment)
  }

  @Builder
  private PreviewReasoningBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.AI_deep_thinking'))
        .fontSize(12)
        .fontColor([this.isManuscriptMode() ? this.getManuscriptAccentDeep() : $r('app.color.text_secondary')])

      Text($r('app.string.reasoning_process'))
        .fontFamily(this.isManuscriptMode() ? MANUSCRIPT_BODY_FONT : 'HarmonyOS Sans')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isManuscriptMode() ? this.getManuscriptAccentDeep() : $r('app.color.text_secondary'))
        .margin({ left: 5 })

      Blank()

      Text($r('app.string.common_details'))
        .fontSize(9)
        .fontColor($r('app.color.text_tertiary'))

      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(9)
        .fontColor([$r('app.color.text_tertiary')])
        .margin({ left: 2 })
    }
    .width('100%')
    .height(this.isManuscriptMode() ? 28 : 30)
    .padding({ left: 10, right: 10 })
    .backgroundColor(Color.Transparent)
    .borderRadius(this.isManuscriptMode() ? 0 : 10)
    .border({
      width: this.isManuscriptMode() ? { top: 1, bottom: 1 } : 0.5,
      color: this.isManuscriptMode() ? getAppUiState().themeDivider : this.themePrimaryLight
    })
    .backdropBlur(this.isManuscriptMode() ? 0 : 24)
    .shadow(getBlurBottomShadow(!(this.isManuscriptMode())))
  }

  @Builder
  private CurrentMessagePreview() {
    if (this.isManuscriptMode()) {
      Column({ space: 13 }) {
        Column({ space: 3 }) {
          Text($r('app.string.manuscript_you'))
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(8)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getManuscriptAccentDeep())
            .letterSpacing(1.2)
            .width('100%')
            .textAlign(TextAlign.End)

          Text($r('app.string.font_preview_user_message'))
            .fontSize(Math.max(12, this.chatFontSize - 1))
            .lineHeight(Math.max(12, this.chatFontSize - 1) + 6)
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontStyle(FontStyle.Italic)
            .fontColor(this.themeTextPrimary)
            .width('100%')
            .textAlign(TextAlign.End)

          this.PreviewMessageActions(FlexAlign.End)
        }
        .width('100%')

        Column({ space: 8 }) {
          Text('XCUBE')
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(8)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getManuscriptAccentDeep())
            .letterSpacing(1.2)
            .width('100%')

          this.PreviewReasoningBar()

          Text($r('app.string.font_preview_ai_message'))
            .fontSize(this.getAiPreviewFontSize())
            .lineHeight(this.getAiPreviewFontSize() + 7)
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontColor(this.themeTextPrimary)
            .width('100%')

          this.PreviewMessageActions(FlexAlign.End)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 14, bottom: 10 })
    } else {
      Column({ space: 12 }) {
        Row() {
          Blank()

          Column() {
            Text($r('app.string.font_preview_user_message'))
              .fontSize(this.chatFontSize)
              .lineHeight(this.chatFontSize + 7)
              .fontFamily(this.previewChatTypeface)
              .fontColor($r('app.color.text_primary'))
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(Color.Transparent)
          .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 5 })
          .constraintSize({ maxWidth: '78%' })
          .backdropBlur(24)
          .shadow(getBlurBottomShadow())
        }
        .width('100%')

        this.PreviewMessageActions(FlexAlign.End)

        Column({ space: 7 }) {
          Row({ space: 7 }) {
            Column() {
              Text('AI')
                .fontSize(8)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.themePrimary)
            }
            .width(22)
            .height(22)
            .borderRadius(7)
            .backgroundColor(this.themePrimaryLight)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            Text('XCube')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themeTextPrimary)
          }
          .width('100%')

          Column({ space: 8 }) {
            this.PreviewReasoningBar()

            Text($r('app.string.font_preview_ai_message'))
              .fontSize(this.getAiPreviewFontSize())
              .lineHeight(this.getAiPreviewFontSize() + 7)
              .fontFamily(this.previewChatTypeface)
              .fontColor(this.themeTextPrimary)
              .width('100%')
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(Color.Transparent)
          .borderRadius(14)
          .border({ width: 0.5, color: this.themePrimaryLight })
          .backdropBlur(24)
          .shadow(getBlurBottomShadow())

          this.PreviewMessageActions(FlexAlign.Start)
        }
        .width('92%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })
    }
  }

  @Builder
  private MiniPreviewMainContent(showBottomNavigation: boolean) {
    Column() {
      this.CurrentPreviewHeader()

      Scroll() {
        this.CurrentMessagePreview()
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
      .clip(true)

      if (showBottomNavigation) {
        this.MiniCurrentBottomNavigation()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private CurrentAppearancePreview() {
    Stack() {
      if (this.shouldUsePreviewNavigationRail()) {
        Row() {
          this.MiniPreviewNavigationRail()

          Column() {
            this.MiniPreviewMainContent(false)
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .height('100%')
      } else {
        this.MiniPreviewMainContent(true)
      }
    }
    .width('100%')
    .height(this.getLivePreviewHeight())
    .backgroundColor(this.themeBackground)
    .borderRadius(this.isManuscriptMode() ? 3 : 22)
    .border({ width: 1, color: this.isManuscriptMode() ? getAppUiState().themeDivider : this.themePrimaryLight })
    .clip(false)
    .animation({ duration: 400, curve: Curve.EaseInOut })
  }

  @Builder
  private LivePreviewHeader() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text($r('app.string.appearance_live_preview_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Text($r('app.string.appearance_live_preview_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 3 }) {
        Text(this.livePreviewExpanded ? $r('app.string.common_collapse') : $r('app.string.common_expand'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([this.themePrimary])
          .rotate({ angle: this.livePreviewExpanded ? 180 : 0 })
          .animation({ duration: 220, curve: Curve.EaseOut })
      }
      .height(32)
      .padding({ left: 10, right: 8 })
      .borderRadius(16)
      .backgroundColor(Color.Transparent)
      .border({ width: 1, color: this.themePrimaryLight })
      .backdropBlur(16)
      .shadow(getBlurBottomShadow())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.toggleLivePreview()
    })
  }

  @Builder
  private LivePreviewSection() {
    Column({ space: 0 }) {
      this.LivePreviewHeader()

      Blank()
        .width('100%')
        .height(this.livePreviewExpanded ? APPEARANCE_BLOCK_GAP : 0)

      Column() {
        this.CurrentAppearancePreview()
      }
      .width('100%')
      .height(this.livePreviewExpanded ? this.getLivePreviewHeight() : 0)
      .opacity(this.livePreviewExpanded ? 1 : 0)
      .translate({ y: this.livePreviewExpanded ? 0 : -10 })
      .clip(!this.livePreviewExpanded)
    }
    .width('100%')
  }

  @Builder
  private AppearanceFloatingTab(index: number, icon: Resource, label: Resource) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.currentTabIndex === index ? (shouldUseDrawnNavigation() ? Color.White : this.themePrimary) : $r('app.color.text_secondary')])

      Text(label)
        .fontSize(10)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentTabIndex === index ? (shouldUseDrawnNavigation() ? Color.White : this.themePrimary) : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ThemeTabContent() {
    Scroll(this.themeScroller) {
      Row() {
        Column({ space: APPEARANCE_BLOCK_GAP }) {
          this.LivePreviewSection()

          this.VisualEffectsEntryCard()

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
      .padding({
        left: 16,
        right: 16,
        top: this.getCompactContentTopPadding() + 16,
        bottom: this.getScrollBottomPadding()
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  private FontTabContent() {
    Scroll(this.fontScroller) {
      Row() {
        Column({ space: APPEARANCE_BLOCK_GAP }) {
          this.LivePreviewSection()

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
          .backdropBlur(16)
          .shadow(getBlurBottomShadow())

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
          .backdropBlur(16)
          .shadow(getBlurBottomShadow())

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
              .enabled(!this.isManuscriptMode())
              .opacity(this.isManuscriptMode() ? 0.45 : 1)
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
          .backdropBlur(16)
          .shadow(getBlurBottomShadow())

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
              .enabled(this.chatSerifFontEnabled && !this.isManuscriptMode())
              .opacity(this.isManuscriptMode() ? 0.45 : 1)
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
          .backdropBlur(16)
          .shadow(getBlurBottomShadow())
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({
        left: 16,
        right: 16,
        top: this.getCompactContentTopPadding() + 16,
        bottom: this.getScrollBottomPadding()
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  private MaterialCompatibilitySection() {
    Column({ space: 12 }) {
      Text($r('app.string.wrapped_material_compatibility_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Row({ space: 16 }) {
        Column({ space: 4 }) {
          Text($r('app.string.wrapped_material_force_blur_title'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text($r('app.string.wrapped_material_force_blur_desc'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(18)
            .width('100%')
        }
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.forceWrappedMaterialBlur })
          .selectedColor(this.themePrimary)
          .switchPointColor(Color.White)
          .enabled(!this.savingWrappedMaterialFallback)
          .onChange((enabled: boolean) => {
            this.handleWrappedMaterialFallbackChanged(enabled)
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.getWrappedMaterialStatus())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(18)
        .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.Transparent)
    .borderRadius(24)
    .border({ width: 1, color: this.themePrimaryLight })
    .backdropBlur(16)
    .shadow(getBlurBottomShadow())
  }

  @Builder
  private MaterialTabContent() {
    Scroll() {
      Row() {
        Column({ space: APPEARANCE_BLOCK_GAP }) {
          this.LivePreviewSection()
          this.MaterialCompatibilitySection()

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
                .enabled(!this.savingChatListMaterial)
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
                .enabled(!this.savingKnowledgeListMaterial)
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
          .backdropBlur(16)
          .shadow(getBlurBottomShadow())

          if (this.isManuscriptMode()) {
            Text(pickLocalizedText(
              '手稿模式保留纸面样式；切回普通模式后应用上述材质设置。',
              'Manuscript mode keeps its paper style. These material settings apply in standard mode.'
            ))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(18)
              .width('100%')
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({
        left: 16,
        right: 16,
        top: this.getCompactContentTopPadding() + 16,
        bottom: this.getScrollBottomPadding()
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  private DrawnAppearanceTab(index: number) {
    if (index === 0) {
      this.AppearanceFloatingTab(0, $r('sys.symbol.paintbrush_pointed_waveform'),
          $r('app.string.appearance_tab_theme'))
    }
    else if (index === 1) {
      this.AppearanceFloatingTab(1, $r('sys.symbol.textformat'),
          $r('app.string.appearance_tab_font'))
    }
    else {
      this.AppearanceFloatingTab(2, $r('sys.symbol.square_stack_3d'),
          $r('app.string.appearance_tab_material'))
    }
  }

  @Builder
  private PageBody() {
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        HdsTabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
          TabContent() {
            this.ThemeTabContent()
          }
          .width('100%')
          .height('100%')
          .tabBar(this.AppearanceFloatingTab(0, $r('sys.symbol.paintbrush_pointed_waveform'),
            $r('app.string.appearance_tab_theme')))

          TabContent() {
            this.FontTabContent()
          }
          .width('100%')
          .height('100%')
          .tabBar(this.AppearanceFloatingTab(1, $r('sys.symbol.textformat'),
            $r('app.string.appearance_tab_font')))

          TabContent() {
            this.MaterialTabContent()
          }
          .width('100%')
          .height('100%')
          .tabBar(this.AppearanceFloatingTab(2, $r('sys.symbol.square_stack_3d'),
            $r('app.string.appearance_tab_material')))
        }
        .width('100%')
        .height('100%')
        .barMode(BarMode.Fixed)
        .barHeight(shouldUseDrawnNavigation() ? 0 : APPEARANCE_FLOATING_TAB_BAR_HEIGHT)
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .vertical(false)
        .scrollable(true)
        .animationDuration(280)
        .barFloatingStyle(shouldUseDrawnNavigation() ? undefined : this.buildAppearanceFloatingStyle())
        .attributeModifier(shouldUseDrawnNavigation() ? new DrawnTabsContentModifier() : new HdsTabsBlurModifier(shouldUseWrappedMaterial()))
        .backgroundColor(Color.Transparent)
        .clip(false)
        .onChange((index: number) => {
          this.currentTabIndex = index
        })
        if (shouldUseDrawnNavigation()) {
          DrawnFloatingTabBar({
            tabCount: 3,
            selectedIndex: this.currentTabIndex,
            barWidth: APPEARANCE_FLOATING_TAB_BAR_WIDTH,
            barHeight: APPEARANCE_FLOATING_TAB_BAR_HEIGHT,
            itemContent: (index: number): void => this.DrawnAppearanceTab(index),
            onSelect: (index: number) => {
              this.currentTabIndex = index
            }
          })
          .margin({ bottom: this.getAppearanceFloatingTabBottomMargin() })
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(Color.Transparent)
    .clip(false)
  }

  @Builder
  private CompactBody() {
    Column() {
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
        .hideBackButton(shouldUseDrawnNavigation())
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
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
        .hideBackButton(shouldUseDrawnNavigation())
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
