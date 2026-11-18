import { getSettingsTypography, SETTINGS_SUBTITLE_LINE_HEIGHT } from '../components/settings/SettingsTypography'
import { ImmersiveFieldSurface } from '../components/ImmersiveFieldSurface'
import { ImmersiveButtonSurface } from '../components/ImmersiveButtonSurface'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getAppPromptLanguage } from '../utils/LocalizedTextUtils'
import { shouldUseDrawnNavigation } from '../utils/DrawnNavigationSupport'
import { uiMaterial } from '@kit.ArkUI'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { PreferenceKeys } from '../services/PreferencesService'
import { normalizeSystemPromptTemplate, getDefaultSystemPromptTemplate } from '../utils/SystemPromptTemplateUtils'
import { getSettingsPageContentMaxWidth, getSettingsPageCompactTabsTotalInset } from '../utils/SettingsPageLayoutHelper'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState } from '../state/AppUiState'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'

let systemPromptSettingsPathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct SystemPromptSettingsPage {
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
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }

  @Local customSystemPrompt: string = ''
  @Local systemPromptEnabled: boolean = true

  private preferencesService = ServiceRegistry.preferences()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.loadSystemPrompt()
  }

  private async loadSystemPrompt(): Promise<void> {
    this.systemPromptEnabled = await this.preferencesService.getBoolean(
      PreferenceKeys.SYSTEM_PROMPT_ENABLED,
      true
    )
    const saved = await this.preferencesService.getString(
      PreferenceKeys.CUSTOM_SYSTEM_PROMPT,
      getDefaultSystemPromptTemplate(getAppPromptLanguage())
    )
    this.customSystemPrompt = normalizeSystemPromptTemplate(saved, getAppPromptLanguage())
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private getContentBottomPadding(): number {
    return 24 + getSettingsPageCompactTabsTotalInset(this.px2vp(this.bottomAvoidHeight),
      this.settingsDetailPresentationMode)
  }

  private saveSystemPrompt(): void {
    const normalizedTemplate = normalizeSystemPromptTemplate(this.customSystemPrompt, getAppPromptLanguage())
    this.customSystemPrompt = normalizedTemplate
    this.preferencesService.setString(PreferenceKeys.CUSTOM_SYSTEM_PROMPT, normalizedTemplate).then((): void => {
      const options = new SnackBarDisplayOptions()
      options.message = $r('app.string.system_prompt_saved')
      options.tone = SnackBarTone.SUCCESS
      showSnackBar(this.getUIContext(), options)
    }).catch((error: Error): void => {
      console.error('SystemPromptSettingsPage', `Failed to save system prompt: ${JSON.stringify(error)}`)
    })
  }

  private resetSystemPrompt(): void {
    this.customSystemPrompt = getDefaultSystemPromptTemplate(getAppPromptLanguage())
  }

  private handleBack(): void {
    if (systemPromptSettingsPathStack !== null && systemPromptSettingsPathStack.size() > 0) {
      systemPromptSettingsPathStack.pop()
    }
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp, this.windowHeightVp, (): void => this.CompactTitleStackBuilder(), [], this)
  }

  @Builder
  private PageContent() {
    Row() {
      Column({ space: 12 }) {
        if (!this.isDetailPaneMode()) {
          Blank()
            .width('100%')
            .height(this.getCompactContentTopPadding())
        }

        Text($r('app.string.system_prompt_hint'))
          .font(getSettingsTypography().subtitle)
          .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
          .fontColor(getAppUiState().themeTextSecondary)
          .width('100%')

        Text($r('app.string.system_prompt_variables_hint'))
          .font(getSettingsTypography().subtitle)
          .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
          .fontColor(getAppUiState().themeTextSecondary)
          .width('100%')

        Row() {
          Text($r('app.string.system_prompt_enabled_label'))
            .font(getSettingsTypography().itemTitle)
            .fontColor(getAppUiState().themeTextPrimary)
            .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.systemPromptEnabled })
            .systemMaterial(new uiMaterial.Material())
            .switchPointColor(Color.White)
            .onChange((isOn: boolean) => {
              this.systemPromptEnabled = isOn
              this.preferencesService.setBoolean(PreferenceKeys.SYSTEM_PROMPT_ENABLED, isOn)
            })
        }
        .width('100%')
        .padding({ left: 4, right: 4 })

        ImmersiveFieldSurface({ cornerRadius: 20, fillHeight: true, layoutWeightValue: 1 }) {
          TextArea({ text: this.customSystemPrompt, placeholder: $r('app.string.system_prompt_placeholder') })
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .borderRadius(20)
            .padding(16)
            .enabled(this.systemPromptEnabled)
            .opacity(this.systemPromptEnabled ? 1 : 0.5)
            .onChange((value: string) => {
              this.customSystemPrompt = value
            })
        }

        Row({ space: 12 }) {
          Stack() {
            ImmersiveButtonSurface({
              materialFactory: () => new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.REGULAR,
                materialColor: Color.Transparent,
                applyShadow: true,
                interactive: true,
                lightEffect: {}
              }),
              cornerRadius: 22
            }) {
              Button($r('app.string.system_prompt_clear'))
                .width('100%')
                .height(44)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor(Color.Transparent)
                .borderRadius(22)
                .onClick(() => {
                  this.resetSystemPrompt()
                })
            }
          }
          .layoutWeight(1)
          .height(44)
          .clip(false)

          Stack() {
            ImmersiveButtonSurface({
              materialFactory: () => new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.THIN,
                materialColor: withColorAlpha(this.themePrimary, '26'),
                applyShadow: true,
                interactive: true,
                lightEffect: {}
              }),
              cornerRadius: 22
            }) {
              Button($r('app.string.save'))
                .width('100%')
                .height(44)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .backgroundColor(Color.Transparent)
                .borderRadius(22)
                .onClick(() => {
                  this.saveSystemPrompt()
                })
            }
          }
          .layoutWeight(1)
          .height(44)
          .clip(false)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .constraintSize({ maxWidth: this.getContentMaxWidth() })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16, bottom: this.getContentBottomPadding() })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.system_prompt_edit_title'))
          .font(getSettingsTypography().pageTitle)
          .fontColor(getAppUiState().themeTextPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeBackground)
    .border({ width: { bottom: 1 }, color: getAppUiState().themePrimaryLight })
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.system_prompt_edit_title'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        HdsNavigation() {
          Column() {
            Blank()
              .width('100%')
              .height(this.getCompactContentTopPadding())

            this.PageContent()
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(getAppUiState().themeBackground)
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
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(getAppUiState().themeBackground)
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
    .backgroundColor(getAppUiState().themeBackground)
  }
}

@Builder
export function SystemPromptSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    SystemPromptSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    systemPromptSettingsPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (systemPromptSettingsPathStack !== null && systemPromptSettingsPathStack.size() > 0) {
      systemPromptSettingsPathStack.pop()
    }
    return true
  })
}
