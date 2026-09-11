import { curves } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getBlurBottomShadow } from '../utils/BlurShadowUtils'
import { getDrawnNavigationBorder, PlainNavigationButtonModifier } from '../utils/DrawnNavigationSupport'

// 仅负责降级外观和点击；页面仍由原有 Tabs 保留、切换，不复制业务内容或拖拽手势。
@ComponentV2
export struct DrawnFloatingTabBar {
  @Param selectedIndex: number = 0
  @Param showSelectionBubble: boolean = true
  @Param tabCount: number = 2
  @Param barWidth: number = 280
  @Param barHeight: number = 56
  @BuilderParam itemContent: (index: number) => void
  @Event onSelect: (index: number) => void = (): void => {}

  private get itemWidth(): number {
    return Math.max(0, this.barWidth - 12) / Math.max(1, this.tabCount)
  }

  private get indicatorOffsetX(): number {
    return Math.max(0, Math.min(this.tabCount - 1, this.selectedIndex)) * this.itemWidth
  }

  private get indexes(): number[] {
    const indexes: number[] = []
    for (let index = 0; index < this.tabCount; index++) {
      indexes.push(index)
    }
    return indexes
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.showSelectionBubble) {
        Row()
          .width(Math.max(0, this.itemWidth - 6))
          .height(this.barHeight - 10)
          .borderRadius((this.barHeight - 10) / 2)
          .backgroundColor(withColorAlpha(getAppUiState().themePrimary, getAppUiState().isDarkMode ? 'CC' : 'AA'))
          .border({ width: 0.5, color: getAppUiState().isDarkMode ? '#40FFFFFF' : '#35FFFFFF' })
          .shadow({ radius: 20, color: withColorAlpha(getAppUiState().themePrimary, '35'), offsetY: 4, fill: false })
          .position({ x: 9, y: 5 })
          .animation(undefined)
          // 动画直接绑定位移，避免 Monitor 二次更新坐标时丢失动画上下文，
          // 或尺寸同步先把坐标写到终点。仅滑块移动，不动画化背景和按钮命中区域。
          .translate({ x: this.indicatorOffsetX })
          .animation({ duration: 500, curve: curves.springMotion(0.68, 0.88) })
          .hitTestBehavior(HitTestMode.None)
      }

      Row() {
        ForEach(this.indexes, (index: number) => {
          Button({ type: ButtonType.Normal, stateEffect: false }) {
            this.itemContent(index)
          }
          .layoutWeight(1)
          .height('100%')
          .padding(0)
          .backgroundColor(Color.Transparent)
          .attributeModifier(new PlainNavigationButtonModifier())
          .onClick(() => this.onSelect(index))
        }, (index: number): string => index.toString())
      }
      .width('100%')
      .height('100%')
      .padding({ left: 6, right: 6 })
    }
    .width(this.barWidth)
    .height(this.barHeight)
    .backgroundColor(Color.Transparent)
    .backdropBlur(24)
    .borderRadius(this.barHeight / 2)
    .border(getDrawnNavigationBorder())
    .shadow(getBlurBottomShadow())
    .clip(false)
  }
}
