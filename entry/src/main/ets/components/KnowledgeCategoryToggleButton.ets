import { ChatFloatingImmersiveButton } from './ChatFloatingImmersiveButton'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'

// 分类展开按钮共用透明材质与原生点击，不再绘制分类色底。
@ComponentV2
export struct KnowledgeCategoryToggleButton {
  @Param expanded: boolean = false
  @Param accentColor: ResourceColor = $r('app.color.primary')
  @Event onToggle: () => void = (): void => {}

  private get buttonWidth(): number {
    const context = this.getUIContext()
    const measure = context.getMeasureUtils()
    const expandSize = measure.measureTextSize({
      textContent: pickLocalizedText('展开', 'Expand'),
      fontSize: 11,
      fontWeight: FontWeight.Medium
    })
    const collapseSize = measure.measureTextSize({
      textContent: pickLocalizedText('收起', 'Collapse'),
      fontSize: 11,
      fontWeight: FontWeight.Medium
    })
    // 两种状态共用较宽的尺寸，避免切换时挤动分类标题；兼容中英文与系统字号。
    return Math.ceil(context.px2vp(Math.max(Number(expandSize.width), Number(collapseSize.width)) +
      context.fp2px(12))) + 24
  }

  @Builder
  private ButtonContent() {
    Row({ space: 4 }) {
      Text(this.expanded ? pickLocalizedText('收起', 'Collapse') : pickLocalizedText('展开', 'Expand'))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accentColor)
        .maxLines(1)

      SymbolGlyph($r('sys.symbol.chevron_down'))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontSize(12)
        .fontColor([this.accentColor])
        .rotate({ angle: this.expanded ? 180 : 0 })
        .animation({ duration: 220, curve: Curve.EaseOut })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Stack() {
      ChatFloatingImmersiveButton({
        barWidth: this.buttonWidth,
        barHeight: 32,
        responsePadding: 0,
        enableMaterialInteraction: true,
        enableShadow: true,
        contentBuilder: (): void => this.ButtonContent(),
        onButtonClick: (): void => this.onToggle()
      })
    }
    .width(this.buttonWidth)
    .height(32)
    .flexShrink(0)
    .clip(false)
  }
}
