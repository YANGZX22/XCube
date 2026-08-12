import { Want, bundleManager, common } from '@kit.AbilityKit'
import { uiMaterial } from '@kit.ArkUI'
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
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'

const TAG = 'AboutPage'
const GITHUB_URL = 'https://github.com/YANGZX22/XCube'

let aboutPagePathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct AboutPage {
  @Local versionName: string = '1.3.1'
  @Local isCheckingUpdate: boolean = false
  @Local showLicensesSheet: boolean = false

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

  aboutToAppear(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      this.versionName = info.versionName
    } catch (error) {
      console.error(TAG, `Get version failed: ${JSON.stringify(error)}`)
    }
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
  private AppLogoBuilder() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Image($r('app.media.foreground'))
        .width(96)
        .height(96)
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
