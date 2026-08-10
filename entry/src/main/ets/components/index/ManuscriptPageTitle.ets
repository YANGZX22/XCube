import { getAppUiState } from '../../state/AppUiState'
import {
  ensureManuscriptFonts,
  MANUSCRIPT_BODY_FONT,
  MANUSCRIPT_HEADING_FONT
} from '../../utils/ManuscriptVisualUtils'

@ComponentV2
export struct ManuscriptPageTitle {
  @Param title: ResourceStr = ''
  @Param subtitle: ResourceStr = ''
  @Param topPadding: number = 2
  @Param bottomPadding: number = 26
  @Local ruleScale: number = 0

  aboutToAppear(): void {
    ensureManuscriptFonts()
    setTimeout(() => {
      animateTo({ duration: 800, curve: Curve.EaseOut }, () => {
        this.ruleScale = 1
      })
    }, 200)
  }

  build() {
    Column({ space: 5 }) {
      Text(this.title)
        .fontFamily(MANUSCRIPT_HEADING_FONT)
        .fontSize(34)
        .fontWeight(600)
        .fontColor(getAppUiState().themeTextPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.subtitle)
        .fontFamily(MANUSCRIPT_BODY_FONT)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(getAppUiState().themeTextSecondary)
        .letterSpacing(2)
        .textCase(TextCase.UpperCase)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Column()
        .width(56)
        .height(1)
        .backgroundColor(getAppUiState().isDarkMode ? '#C99A52' : '#B68235')
        .scale({ x: this.ruleScale, y: 1 })
    }
    .width('100%')
    .padding({ top: this.topPadding, bottom: this.bottomPadding })
    .alignItems(HorizontalAlign.Center)
    .transition(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 550, curve: Curve.EaseInOut })
    )
  }
}
