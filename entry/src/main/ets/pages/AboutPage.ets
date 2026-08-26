import { Want, bundleManager, common } from '@kit.AbilityKit'
import { LengthMetricsUnit, uiMaterial } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { ImmersiveSheetHeader } from '../components/ImmersiveSheetHeader'
import { showToast } from '../utils/ToastUtil'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import {
  ASSET_LICENSES,
  DEVELOPMENT_LICENSES,
  LicenseCatalogItem,
  RUNTIME_LICENSES
} from '../config/OpenSourceLicenseCatalog'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import { AppUpdateInfo, getAppUpdateService, XCUBE_RELEASES_URL } from '../services/AppUpdateService'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { ServiceRegistry } from '../services/ServiceRegistry'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'

const TAG = 'AboutPage'
const GITHUB_URL = 'https://github.com/YANGZX22/XCube'
const LOGO_CANVAS_SIZE = 96
const LOGO_VIEWBOX_SIZE = 1024
const LOGO_ANIMATION_FRAME_INTERVAL_MS = 16
const LOGO_ANIMATION_DURATION_MS = 2550

interface LogoPoint {
  x: number
  y: number
}

const LOGO_FRAME_POINTS: LogoPoint[] = [
  { x: 512, y: 174 }, { x: 792, y: 336 }, { x: 792, y: 660 }, { x: 512, y: 822 },
  { x: 232, y: 660 }, { x: 232, y: 336 }, { x: 512, y: 174 }
]
const LOGO_DETAIL_PATHS: LogoPoint[][] = [
  [{ x: 232, y: 336 }, { x: 360, y: 410 }],
  [{ x: 664, y: 410 }, { x: 792, y: 336 }],
  [{ x: 512, y: 674 }, { x: 512, y: 822 }]
]
const LOGO_X_POINTS: LogoPoint[] = [
  { x: 294, y: 310 }, { x: 390, y: 310 }, { x: 512, y: 438 }, { x: 634, y: 310 },
  { x: 730, y: 310 }, { x: 566, y: 512 }, { x: 730, y: 714 }, { x: 634, y: 714 },
  { x: 512, y: 586 }, { x: 390, y: 714 }, { x: 294, y: 714 }, { x: 458, y: 512 },
  { x: 294, y: 310 }
]
const LOGO_APERTURE_POINTS: LogoPoint[] = [
  { x: 512, y: 466 }, { x: 558, y: 512 }, { x: 512, y: 558 }, { x: 466, y: 512 },
  { x: 512, y: 466 }
]

let aboutPagePathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct AboutPage {
  @Local versionName: string = '1.3.6'
  @Local isCheckingUpdate: boolean = false
  @Local isCleaningCache: boolean = false
  @Local showLicensesSheet: boolean = false
  @Local isLogoAnimating: boolean = false
  @Local logoCanvasOpacity: number = 1
  @Local logoStaticOpacity: number = 0

  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
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
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }
  private compactScroller: Scroller = new Scroller()
  private logoAnimationTimer: number = -1
  private logoAnimationSequence: number = 0
  private logoAnimationElapsedMs: number = 0
  private logoCanvasReady: boolean = false
  private logoCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private logoCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.logoCanvasSettings,
    LengthMetricsUnit.DEFAULT)

  aboutToAppear(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      this.versionName = info.versionName
    } catch (error) {
      console.error(TAG, `Get version failed: ${JSON.stringify(error)}`)
    }
  }

  aboutToDisappear(): void {
    this.logoAnimationSequence += 1
    this.clearLogoAnimationTimer()
    this.resetLogoAnimation()
  }

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private pageToast(message: string | Resource): void {
    showToast(this.getUIContext(), message, 2000)
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private handleBack(): void {
    if (aboutPagePathStack !== null && aboutPagePathStack.size() > 0) {
      aboutPagePathStack.pop()
    }
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp,
      this.windowHeightVp, (): void => this.CompactTitleStackBuilder())
  }

  private getAboutMaterial(interactive: boolean, applyShadow: boolean): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: Color.Transparent,
      applyShadow: applyShadow,
      interactive: interactive,
      lightEffect: { color: undefined }
    })
  }

  private getAboutAccentMaterial(): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: this.themePrimaryLight,
      applyShadow: false,
      interactive: false,
      lightEffect: { color: undefined }
    })
  }

  @Builder
  private AnimatedLogoBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      Canvas(this.logoCanvasContext)
        .width(LOGO_CANVAS_SIZE)
        .height(LOGO_CANVAS_SIZE)
        .opacity(this.logoCanvasOpacity)
        .onReady((): void => {
          this.logoCanvasReady = true
          this.drawLogoCanvasFrame(this.logoAnimationElapsedMs)
        })

      Image($r('app.media.foreground'))
        .width(LOGO_CANVAS_SIZE)
        .height(LOGO_CANVAS_SIZE)
        .opacity(this.logoStaticOpacity)
    }
    .width(LOGO_CANVAS_SIZE)
    .height(LOGO_CANVAS_SIZE)
  }

  @Builder
  private AppLogoBuilder() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      if (this.isLogoAnimating) {
        this.AnimatedLogoBuilder()
      } else {
        Image($r('app.media.foreground'))
          .width(96)
          .height(96)
      }
    }
    .width(96)
    .height(96)
    .padding(0)
    .backgroundColor('#17132E')
    .borderRadius(22)
    .clip(false)
    .shadow({
      radius: 22,
      color: 'rgba(23, 19, 46, 0.32)',
      offsetX: 0,
      offsetY: 8
    })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: '#17132E',
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .accessibilityText($r('app.string.about_play_logo_animation'))
    .onClick((): void => {
      this.startLogoAnimation()
    })
  }

  @Builder
  private LicenseItemCard(item: LicenseCatalogItem) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(item.version !== '' ? `${item.name} · v${item.version}` : item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(item.licenseName)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .systemMaterial(this.getAboutAccentMaterial())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(pickLocalizedText(item.noticeZh, item.noticeEn))
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Color.Transparent)
    .borderRadius(14)
    .border({ width: 0.5, color: this.themePrimaryLight })
    .systemMaterial(this.getAboutMaterial(false, false))
  }

  @Builder
  private LicenseSection(title: ResourceStr, items: LicenseCatalogItem[]) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 4, top: 8 })
      .width('100%')

    ForEach(items, (item: LicenseCatalogItem) => {
      this.LicenseItemCard(item)
    }, (item: LicenseCatalogItem) => `${item.name}_${item.version}_${item.licenseName}`)
  }

  @Builder
  private LicensesSheetBuilder() {
    Column() {
      ImmersiveSheetHeader({
        title: $r('app.string.about_license_sheet_title'),
        showLeading: true,
        showTrailing: false,
        onLeadingClick: () => {
          this.showLicensesSheet = false
        }
      })

      Scroll() {
        Row() {
          Column({ space: 10 }) {
            Text($r('app.string.about_license_sheet_note'))
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: 4, right: 4, bottom: 2 })

            this.LicenseSection($r('app.string.about_license_runtime_section'), RUNTIME_LICENSES)
            this.LicenseSection($r('app.string.about_license_assets_section'), ASSET_LICENSES)
            this.LicenseSection($r('app.string.about_license_development_section'), DEVELOPMENT_LICENSES)
          }
          .width('100%')
          .constraintSize({ maxWidth: 720 })
          .padding({ left: 16, right: 16, bottom: 32 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private PageContent() {
    Scroll(this.compactScroller) {
      Row() {
        Column() {
          if (!this.isDetailPaneMode()) {
            Blank()
              .width('100%')
              .height(this.getCompactContentTopPadding())
          }

          // Header: App icon + name + version + slogan
          Column({ space: 8 }) {
            this.AppLogoBuilder()

            Text('XCube')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Text(`v${this.versionName}`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))

            Text($r('app.string.about_page_slogan'))
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding({ top: 24, bottom: 28 })
          .alignItems(HorizontalAlign.Center)

          Text($r('app.string.about_updates_section'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, bottom: 6 })
            .width('100%')

          Column() {
            Row() {
              Column() {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(20)
                  .fontColor([this.themePrimary])
              }
              .width(36)
              .height(36)
              .borderRadius(9)
              .backgroundColor(Color.Transparent)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .systemMaterial(this.getAboutAccentMaterial())

              Column({ space: 2 }) {
                Text($r('app.string.about_check_for_updates'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text(this.isCheckingUpdate ? $r('app.string.about_checking_for_updates') : `v${this.versionName}`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)

              if (this.isCheckingUpdate) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(this.themePrimary)
              } else {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(18)
                  .fontColor([$r('app.color.text_tertiary')])
              }
            }
            .width('100%')
            .height(64)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .enabled(!this.isCheckingUpdate)
            .onClick(() => {
              this.handleCheckForUpdates()
            })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(16)
          .border({ width: 0.5, color: this.themePrimaryLight })
          .systemMaterial(this.getAboutMaterial(!this.isCheckingUpdate, true))
          .margin({ bottom: 24 })

          Text($r('app.string.about_storage_section'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, bottom: 6 })
            .width('100%')

          Column() {
            Row() {
              Column() {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(20)
                  .fontColor([this.themePrimary])
              }
              .width(36)
              .height(36)
              .borderRadius(9)
              .backgroundColor(Color.Transparent)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .systemMaterial(this.getAboutAccentMaterial())

              Column({ space: 2 }) {
                Text($r('app.string.about_clear_cache'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text(this.isCleaningCache ? $r('app.string.about_clearing_cache') :
                  $r('app.string.about_clear_cache_desc'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)

              if (this.isCleaningCache) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(this.themePrimary)
              } else {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(18)
                  .fontColor([$r('app.color.text_tertiary')])
              }
            }
            .width('100%')
            .height(64)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .enabled(!this.isCleaningCache)
            .onClick((): void => {
              this.showCacheCleanupWarning()
            })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(16)
          .border({ width: 0.5, color: this.themePrimaryLight })
          .systemMaterial(this.getAboutMaterial(!this.isCleaningCache, true))
          .margin({ bottom: 24 })

          Text($r('app.string.about_contact_section'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, bottom: 6 })
            .width('100%')

          Column() {
            Row() {
              Column() {
                SymbolGlyph($r('sys.symbol.link'))
                  .fontSize(20)
                  .fontColor([this.themePrimary])
              }
              .width(36)
              .height(36)
              .borderRadius(9)
              .backgroundColor(Color.Transparent)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .systemMaterial(this.getAboutAccentMaterial())

              Column({ space: 2 }) {
                Text($r('app.string.about_github'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text('YANGZX22/XCube')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(18)
                .fontColor([$r('app.color.text_tertiary')])
            }
            .width('100%')
            .height(64)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.openGitHubInBrowser()
            })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(16)
          .border({ width: 0.5, color: this.themePrimaryLight })
          .systemMaterial(this.getAboutMaterial(true, true))
          .margin({ bottom: 24 })

          Text($r('app.string.about_legal_section'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, bottom: 6 })
            .width('100%')

          Column() {
            Row() {
              Column() {
                SymbolGlyph($r('sys.symbol.doc_text'))
                  .fontSize(20)
                  .fontColor([this.themePrimary])
              }
              .width(36)
              .height(36)
              .borderRadius(9)
              .backgroundColor(Color.Transparent)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .systemMaterial(this.getAboutAccentMaterial())

              Column({ space: 2 }) {
                Text($r('app.string.about_open_source_licenses'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text($r('app.string.about_open_source_licenses_desc'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(18)
                .fontColor([$r('app.color.text_tertiary')])
            }
            .width('100%')
            .height(64)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.showLicensesSheet = true
            })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(16)
          .border({ width: 0.5, color: this.themePrimaryLight })
          .systemMaterial(this.getAboutMaterial(true, true))
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, bottom: 32 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_about'))
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
    .backgroundColor(getAppUiState().themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.settings_about'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        Column() {
          this.DetailPaneHeader()
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(getAppUiState().themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .bindToScrollable([this.compactScroller])
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
    .backgroundColor(getAppUiState().themeBackground)
    .bindSheet($$this.showLicensesSheet, this.LicensesSheetBuilder(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: Color.Transparent
      }),
      preferType: SheetType.BOTTOM,
      onDisappear: () => {
        this.showLicensesSheet = false
      }
    })
  }

  private async openGitHubInBrowser(): Promise<void> {
    try {
      const hostContext = this.getUIContext().getHostContext()
      if (!hostContext) {
        throw new Error('UI context unavailable')
      }
      const context = hostContext as common.UIAbilityContext
      await this.startBrowsableAbility(context, GITHUB_URL)
    } catch (err) {
      hilog.error(0x0000, TAG, 'Open GitHub failed: %{public}s', JSON.stringify(err))
      this.pageToast('无法打开 GitHub 链接')
    }
  }

  private clearLogoAnimationTimer(): void {
    if (this.logoAnimationTimer !== -1) {
      clearInterval(this.logoAnimationTimer)
      this.logoAnimationTimer = -1
    }
  }

  private resetLogoAnimation(): void {
    this.isLogoAnimating = false
    this.logoAnimationElapsedMs = 0
    this.logoCanvasReady = false
    this.logoCanvasOpacity = 1
    this.logoStaticOpacity = 0
  }

  private startLogoAnimation(): void {
    if (this.isLogoAnimating) {
      return
    }

    this.clearLogoAnimationTimer()
    const sequence = this.logoAnimationSequence + 1
    this.logoAnimationSequence = sequence
    this.resetLogoAnimation()
    this.isLogoAnimating = true
    const startedAt = Date.now()
    this.updateLogoAnimationFrame(0)
    this.logoAnimationTimer = setInterval((): void => {
      if (sequence !== this.logoAnimationSequence || !this.isLogoAnimating) {
        this.clearLogoAnimationTimer()
        return
      }

      const elapsedMs = Date.now() - startedAt
      this.updateLogoAnimationFrame(elapsedMs)
      if (elapsedMs >= LOGO_ANIMATION_DURATION_MS) {
        this.clearLogoAnimationTimer()
        this.resetLogoAnimation()
      }
    }, LOGO_ANIMATION_FRAME_INTERVAL_MS)
  }

  private getLogoTimelineProgress(elapsedMs: number, startMs: number, endMs: number): number {
    if (elapsedMs <= startMs) {
      return 0
    }
    if (elapsedMs >= endMs) {
      return 1
    }
    return (elapsedMs - startMs) / (endMs - startMs)
  }

  private getLogoSmoothProgress(progress: number): number {
    return progress * progress * (3 - 2 * progress)
  }

  private updateLogoAnimationFrame(elapsedMs: number): void {
    this.logoAnimationElapsedMs = elapsedMs
    const restoreProgress = this.getLogoSmoothProgress(this.getLogoTimelineProgress(elapsedMs, 2250,
      LOGO_ANIMATION_DURATION_MS))
    this.logoCanvasOpacity = 1 - restoreProgress
    this.logoStaticOpacity = restoreProgress
    if (this.logoCanvasReady) {
      this.drawLogoCanvasFrame(elapsedMs)
    }
  }

  private drawLogoCanvasFrame(elapsedMs: number): void {
    const context = this.logoCanvasContext
    context.clearRect(0, 0, LOGO_CANVAS_SIZE, LOGO_CANVAS_SIZE)
    const frameProgress = this.getLogoTimelineProgress(elapsedMs, 0, 1000)
    const detailProgress = this.getLogoTimelineProgress(elapsedMs, 700, 1150)
    const xProgress = this.getLogoSmoothProgress(this.getLogoTimelineProgress(elapsedMs, 1000, 1700))
    const apertureProgress = this.getLogoSmoothProgress(this.getLogoTimelineProgress(elapsedMs, 1600, 1850))
    const xFillProgress = this.getLogoSmoothProgress(this.getLogoTimelineProgress(elapsedMs, 1850, 2250))
    this.drawLogoPolyline(LOGO_FRAME_POINTS, frameProgress, '#8576FF', 42)
    for (let index = 0; index < LOGO_DETAIL_PATHS.length; index += 1) {
      this.drawLogoPolyline(LOGO_DETAIL_PATHS[index], detailProgress, '#8576FF', 42)
    }
    this.drawLogoPolyline(LOGO_X_POINTS, xProgress, '#FFFFFF', 32)
    this.drawLogoPolyline(LOGO_APERTURE_POINTS, apertureProgress, '#FFFFFF', 32)
    this.drawLogoXFill(xFillProgress)
  }

  private drawLogoXFill(progress: number): void {
    if (progress <= 0) {
      return
    }
    const scale = LOGO_CANVAS_SIZE / LOGO_VIEWBOX_SIZE
    const context = this.logoCanvasContext
    context.beginPath()
    context.moveTo(LOGO_X_POINTS[0].x * scale, LOGO_X_POINTS[0].y * scale)
    for (let index = 1; index < LOGO_X_POINTS.length; index += 1) {
      context.lineTo(LOGO_X_POINTS[index].x * scale, LOGO_X_POINTS[index].y * scale)
    }
    context.closePath()
    context.moveTo(LOGO_APERTURE_POINTS[0].x * scale, LOGO_APERTURE_POINTS[0].y * scale)
    for (let index = 1; index < LOGO_APERTURE_POINTS.length; index += 1) {
      context.lineTo(LOGO_APERTURE_POINTS[index].x * scale, LOGO_APERTURE_POINTS[index].y * scale)
    }
    context.closePath()
    context.globalAlpha = Math.min(progress, 1)
    context.fillStyle = '#FFFFFF'
    context.fill('evenodd')
    context.globalAlpha = 1
  }

  private drawLogoPolyline(points: LogoPoint[], progress: number, color: string, svgStrokeWidth: number): void {
    if (progress <= 0 || points.length < 2) {
      return
    }
    let totalLength = 0
    for (let index = 1; index < points.length; index += 1) {
      totalLength += this.getLogoSegmentLength(points[index - 1], points[index])
    }
    const targetLength = totalLength * Math.min(progress, 1)
    let drawnLength = 0
    const scale = LOGO_CANVAS_SIZE / LOGO_VIEWBOX_SIZE
    const context = this.logoCanvasContext
    context.beginPath()
    context.moveTo(points[0].x * scale, points[0].y * scale)
    for (let index = 1; index < points.length; index += 1) {
      const from = points[index - 1]
      const to = points[index]
      const segmentLength = this.getLogoSegmentLength(from, to)
      if (drawnLength + segmentLength <= targetLength) {
        context.lineTo(to.x * scale, to.y * scale)
        drawnLength += segmentLength
        continue
      }
      const segmentProgress = Math.max(0, (targetLength - drawnLength) / segmentLength)
      context.lineTo((from.x + (to.x - from.x) * segmentProgress) * scale,
        (from.y + (to.y - from.y) * segmentProgress) * scale)
      break
    }
    context.strokeStyle = color
    context.lineWidth = svgStrokeWidth * scale
    context.lineCap = 'round'
    context.lineJoin = 'round'
    context.stroke()
  }

  private getLogoSegmentLength(from: LogoPoint, to: LogoPoint): number {
    const deltaX = to.x - from.x
    const deltaY = to.y - from.y
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY)
  }

  private handleCheckForUpdates(): void {
    if (this.isCheckingUpdate) {
      return
    }
    this.isCheckingUpdate = true
    this.performCheckForUpdates().catch((error: Object): void => {
      hilog.error(0x0000, TAG, 'Check for updates failed: %{public}s', `${error}`)
      this.pageToast($r('app.string.about_update_check_failed'))
    })
  }

  private showCacheCleanupWarning(): void {
    if (this.isCleaningCache) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.about_clear_cache_warning_title'),
      message: $r('app.string.about_clear_cache_warning_message'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.about_clear_cache_confirm'),
        fontColor: $r('app.color.status_error'),
        action: () => {
          this.startCacheCleanup()
        }
      }
    })
  }

  private startCacheCleanup(): void {
    if (this.isCleaningCache) {
      return
    }
    this.isCleaningCache = true
    this.performCacheCleanup().catch((error: Object): void => {
      hilog.error(0x0000, TAG, 'Cache cleanup failed: %{public}s', `${error}`)
      this.pageToast($r('app.string.about_clear_cache_failed'))
    })
  }

  private async performCacheCleanup(): Promise<void> {
    try {
      const result = await ServiceRegistry.database().cleanupOrphanedAttachmentCache()
      if (result.deletedFiles === 0 && result.failedFiles === 0) {
        this.pageToast(pickLocalizedText('没有发现可清理的残留文件', 'No unreferenced cache files were found'))
      } else if (result.failedFiles === 0) {
        this.pageToast(pickLocalizedText(
          `已清理 ${result.deletedFiles} 个残留文件`,
          `Removed ${result.deletedFiles} unreferenced cache files`
        ))
      } else {
        this.pageToast(pickLocalizedText(
          `清理完成：删除 ${result.deletedFiles} 个，失败 ${result.failedFiles} 个`,
          `Cleanup finished: ${result.deletedFiles} removed, ${result.failedFiles} failed`
        ))
      }
    } finally {
      this.isCleaningCache = false
    }
  }

  private async performCheckForUpdates(): Promise<void> {
    try {
      const update = await getAppUpdateService().checkForUpdate(this.versionName)
      if (!update.hasUpdate) {
        this.pageToast($r('app.string.about_already_latest'))
        return
      }
      this.showUpdateAvailableDialog(update)
    } finally {
      this.isCheckingUpdate = false
    }
  }

  private showUpdateAvailableDialog(update: AppUpdateInfo): void {
    const notesFallback = pickLocalizedText('请前往 GitHub Releases 查看本次更新内容。',
      'Open GitHub Releases to view what is included in this update.')
    let notes = update.releaseNotes !== '' ? update.releaseNotes : notesFallback
    if (notes.length > 1600) {
      notes = `${notes.substring(0, 1600)}…`
    }
    const versionSummary = pickLocalizedText(
      `当前版本 v${this.versionName}，最新版本 v${update.latestVersion}`,
      `Installed v${this.versionName}; latest v${update.latestVersion}`
    )
    this.getUIContext().showAlertDialog({
      title: pickLocalizedText(`发现新版本 v${update.latestVersion}`, `XCube v${update.latestVersion} is available`),
      message: `${versionSummary}\n\n${notes}`,
      primaryButton: {
        value: $r('app.string.about_update_later'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.about_view_releases'),
        action: () => {
          this.openReleasesInBrowser()
        }
      }
    })
  }

  private async openReleasesInBrowser(): Promise<void> {
    try {
      const hostContext = this.getUIContext().getHostContext()
      if (!hostContext) {
        throw new Error('UI context unavailable')
      }
      const context = hostContext as common.UIAbilityContext
      await this.startBrowsableAbility(context, XCUBE_RELEASES_URL)
    } catch (err) {
      hilog.error(0x0000, TAG, 'Open GitHub Releases failed: %{public}s', JSON.stringify(err))
      this.pageToast($r('app.string.about_open_releases_failed'))
    }
  }

  private async startBrowsableAbility(context: common.UIAbilityContext, url: string): Promise<void> {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    }
    await context.startAbility(want)
  }
}

@Builder
export function AboutPageBuilder(name: string, param: Object) {
  NavDestination() {
    AboutPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    aboutPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (aboutPagePathStack !== null && aboutPagePathStack.size() > 0) {
      aboutPagePathStack.pop()
    }
    return true
  })
}
