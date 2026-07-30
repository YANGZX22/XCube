/**
 * 快速滚动按钮组件
 * 支持快速到顶部 / 快速到底部
 */

import { getAppUiState } from '../state/AppUiState'
import { ChatFloatingImmersiveButton } from './ChatFloatingImmersiveButton'

@ComponentV2
export struct ScrollToBottomButton {
  // 是否显示按钮
  @Param isVisible: boolean = false
  // 底部安全区域高度（vp）
  @Param bottomAvoidHeight: number = 0
  // 固定悬浮按钮距离底部的基准偏移（vp）
  @Param fixedBottomOffset: number = 128
  // 按钮方向：0=向下（到底部）, 1=向上（到顶部）
  @Param buttonDirection: number = 0
  // 0-1 的滚动进度，仅向上按钮使用
  @Param progress: number = -1
  // 额外纵向偏移（用于多按钮错位摆放）
  @Param extraOffsetY: number = 0
  // 点击回调
  @Event onScrollToBottom: () => void = () => {}
  @Event onScrollToTop: () => void = () => {}

  // 滚动快捷按钮应跟随当前主题主色
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get ringTrackColor(): string {
    return '#00000000'
  }

  private resolveProgressPercent(): number {
    if (!Number.isFinite(this.progress) || this.progress <= 0) {
      return 0
    }
    if (this.progress >= 1) {
      return 100
    }
    return this.progress * 100
  }

  private shouldShowProgressRing(): boolean {
    return this.buttonDirection === 1 && this.progress >= 0
  }

  build() {
    if (this.isVisible) {
      Stack({ alignContent: Alignment.Center }) {
        ChatFloatingImmersiveButton({
          barWidth: 40,
          barHeight: 40,
          iconResource: this.buttonDirection === 1 ? $r('sys.symbol.arrow_up_to_line') : $r('sys.symbol.chevron_down'),
          iconSize: this.shouldShowProgressRing() ? 16 : 20,
          iconColor: [this.themePrimary],
          onButtonClick: (): void => {
            if (this.buttonDirection === 1) {
              this.onScrollToTop()
            } else {
              this.onScrollToBottom()
            }
          }
        }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.shouldShowProgressRing()) {
              Progress({ value: this.resolveProgressPercent(), total: 100, type: ProgressType.Ring })
                .width(36)
                .height(36)
                .color(this.themePrimary)
                .backgroundColor(this.ringTrackColor)
                .style({
                  strokeWidth: 2.4,
                  shadow: false,
                  enableScanEffect: false
                })
            }

            SymbolGlyph(this.buttonDirection === 1 ? $r('sys.symbol.arrow_up_to_line') : $r('sys.symbol.chevron_down'))
              .fontSize(this.shouldShowProgressRing() ? 16 : 20)
              .fontColor([this.themePrimary])
          }
          .width(40)
          .height(40)
          .translate({ y: -4 })
        }
      }
      .width(40)
      .height(40)
      .position({ x: '100%', y: '100%' })
      .translate({
        x: -56,
        y: -(this.fixedBottomOffset + this.bottomAvoidHeight) + this.extraOffsetY
      })
      .animation({ duration: 200, curve: Curve.EaseOut })
      .zIndex(12)
      .transition(
        TransitionEffect.OPACITY.combine(
          TransitionEffect.scale({ x: 0.8, y: 0.8 })
        ).animation({ duration: 200, curve: Curve.EaseOut })
      )
    }
  }
}
