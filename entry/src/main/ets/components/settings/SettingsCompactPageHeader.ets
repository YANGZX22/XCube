import { getAppUiState } from '../../state/AppUiState'
import { getHdsTopNavigationMaskExtraHeight } from '../../utils/HdsVisualEffectUtil'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'

@ComponentV2
export struct SettingsCompactTitleBarContent {
  @Param title: string | Resource = ''
  @Param titleStartInset: number = 64
  @Param titleEndInset: number = 16
  @Event onBack: () => void = () => {}

  build() {
    Row() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: this.titleStartInset, right: this.titleEndInset })
    .alignItems(VerticalAlign.Center)
  }
}

@ComponentV2
export struct SettingsCompactPageHeader {
  @Param title: string | Resource = ''
  @Param topAvoidHeight: number = 0
  @Event onBack: () => void = () => {}

  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }

  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private getMaskExtraHeight(): number {
    return getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
  }

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.px2vp(this.topAvoidHeight))

      SettingsCompactTitleBarContent({
        title: this.title,
        onBack: this.onBack
      })

      Column()
        .width('100%')
        .height(this.getMaskExtraHeight())
        .backgroundColor(withColorAlpha(getAppUiState().themeBackground, '00'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    }
    .width('100%')
    .backgroundColor(withColorAlpha(getAppUiState().themeBackground, 'E6'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .renderGroup(true)
  }
}
