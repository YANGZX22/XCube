import { getSettingsTypography, SETTINGS_SUBTITLE_LINE_HEIGHT } from './settings/SettingsTypography'
import { uiMaterial } from '@kit.ArkUI'
import { BuiltinBrowserManagerState, getBuiltinBrowserManager } from '../services/BuiltinBrowserManager'
import { getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { getSettingsSheetContentMaxHeight } from '../utils/SettingsPageLayoutHelper'
import { ImmersiveButtonSurface } from './ImmersiveButtonSurface'
import { LIST_MATERIAL_CARD_RADIUS } from './ImmersiveListSurface'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'

@ComponentV2
export struct BrowserSettingsSheet {
  @Local settings: BuiltinBrowserManagerState = getBuiltinBrowserManager().state
  @Local saveCookies: boolean = getBuiltinBrowserManager().state.saveCookies
  @Event onClose: () => void = (): void => {}
  @Event onFeedback: (message: string, failed: boolean) => void = (_message: string, _failed: boolean): void => {}

  @Monitor('settings.saveCookies')
  private syncCookieSetting(): void {
    this.saveCookies = this.settings.saveCookies
  }

  private async changeCookies(enabled: boolean): Promise<void> {
    this.saveCookies = enabled
    try {
      await getBuiltinBrowserManager().setSaveCookies(enabled)
    } catch (error) {
      console.warn('BrowserSettingsSheet', `Could not update cookies: ${JSON.stringify(error)}`)
      this.onFeedback(pickLocalizedText('Cookie 设置未能更新，请稍后重试。',
        'Could not update cookies. Try again shortly.'), true)
    } finally {
      this.saveCookies = this.settings.saveCookies
    }
  }

  private async clearData(): Promise<void> {
    try {
      await getBuiltinBrowserManager().clearAllData()
      this.onFeedback(pickLocalizedText('浏览器数据已清空', 'Browsing data cleared'), false)
    } catch (error) {
      console.warn('BrowserSettingsSheet', `Could not clear browsing data: ${JSON.stringify(error)}`)
      this.onFeedback(pickLocalizedText('部分浏览器数据未能清空，请重试。',
        'Some browsing data could not be cleared. Please try again.'), true)
    }
  }

  build() {
    Column() {
      ImmersiveSheetHeader({
        titleFont: getSettingsTypography().pageTitle,
        titleColor: getAppUiState().themeTextPrimary,
        title: pickLocalizedText('浏览器配置', 'Browser Settings'),
        onLeadingClick: (): void => this.onClose()
      })

      Scroll() {
        Column({ space: 20 }) {
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.tracking_cookie_interception'))
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontSize(24)
              .fontColor([getAppUiState().themePrimary])
            Column({ space: 4 }) {
              Text(pickLocalizedText('保存 Cookie', 'Save Cookies'))
                .font(getSettingsTypography().itemTitle)
                .fontColor(getAppUiState().themeTextPrimary)
              Text(pickLocalizedText('保存登录状态并在各对话间共享。', 'Keep sign-ins across conversations.'))
                .font(getSettingsTypography().subtitle)
                .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
                .fontColor($r('app.color.text_caption'))
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.saveCookies })
              .selectedColor(getAppUiState().themePrimary)
              .systemMaterial(new uiMaterial.Material())
              .switchPointColor(Color.White)
              .enabled(!this.settings.changingCookies && !this.settings.clearingData)
              .onChange((enabled: boolean): void => { this.changeCookies(enabled) })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })

          Column({ space: 12 }) {
            ImmersiveButtonSurface({
              cornerRadius: LIST_MATERIAL_CARD_RADIUS,
              materialFactory: () => new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.REGULAR,
                materialColor: Color.Transparent,
                applyShadow: true,
                interactive: !this.settings.clearingData && !this.settings.changingCookies,
                lightEffect: {}
              })
            }) {
              Button({ type: ButtonType.Normal, stateEffect: false }) {
                Row({ space: 8 }) {
                  if (this.settings.clearingData) {
                    LoadingProgress().width(20).height(20).color($r('app.color.status_error'))
                  } else {
                    SymbolGlyph($r('sys.symbol.clean')).fontSize(20).fontColor([$r('app.color.status_error')])
                  }
                  Text(this.settings.clearingData ? pickLocalizedText('正在清空…', 'Clearing…') :
                    pickLocalizedText('清空浏览器数据', 'Clear Browsing Data'))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.status_error'))
                }
                .justifyContent(FlexAlign.Center)
              }
              .width('100%')
              .height(52)
              .backgroundColor(Color.Transparent)
              .borderRadius(LIST_MATERIAL_CARD_RADIUS)
              .enabled(!this.settings.clearingData && !this.settings.changingCookies)
              .onClick((): void => { this.clearData() })
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 24 })
      }
      .width('100%')
      .constraintSize({ maxHeight: getSettingsSheetContentMaxHeight(getAppUiState().windowHeightVp) })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }
}
