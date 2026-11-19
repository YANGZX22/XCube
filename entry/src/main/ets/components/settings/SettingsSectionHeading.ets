import { getAppUiState } from '../../state/AppUiState'
import { getSettingsTypography, SETTINGS_HEADING_CONTENT_GAP, SETTINGS_SUBTITLE_LINE_HEIGHT } from './SettingsTypography'

@ComponentV2
export struct SettingsSectionHeading {
  @Require @Param title: ResourceStr
  @Param subtitle: ResourceStr | null = null
  @Param trailingSymbol: Resource | undefined = undefined
  @Param topGap: number = 0

  build() {
    Column({ space: 2 }) {
      Row({ space: 8 }) {
        Text(this.title)
          .font(getSettingsTypography().sectionTitle)
          .fontColor(getAppUiState().themeTextPrimary)
          .textAlign(TextAlign.Start)
          .layoutWeight(1)

        if (this.trailingSymbol !== undefined) {
          SymbolGlyph(this.trailingSymbol)
            .fontSize(19)
            .fontColor([getAppUiState().themePrimary])
            .accessibilityLevel('no')
        }
      }
      .width('100%')

      if (this.subtitle !== null) {
        Text(this.subtitle)
          .font(getSettingsTypography().subtitle)
          .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
          .fontColor($r('app.color.text_caption'))
          .textAlign(TextAlign.Start)
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: this.topGap, bottom: SETTINGS_HEADING_CONTENT_GAP })
  }
}
