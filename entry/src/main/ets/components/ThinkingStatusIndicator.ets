/**
 * 思考条的状态指示：图标 + "思考中 / 思考过程" 标题。
 *
 * 思考中时（仅默认模式）一束高光沿横向不断扫过图标与文字。图标和文字被当成
 * 一个整体：渐变画在同一层离屏画布上，用 SRC_IN 混合裁到内容形状里，
 * 所以高光穿过图标与文字之间时是连续的，不会在接缝处断开。
 *
 * 手稿模式有自己的工作指示语言（ManuscriptWorkingIndicator 的打字机动效），
 * 这里保持静止，不加任何动效。
 *
 * 渐变本身不变，只靠 translate 滚动：位移走系统动画线程，
 * 不必逐帧重建 shader，也不占 JS 计时器。
 */

import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { VisualEffectsMode } from '../models/ThemeColors'

// 高光带每 SWEEP_PERIOD 重复一次，整条铺三个周期，
// 位移正好走一个周期后回到起点，循环处看不出接缝。
const SWEEP_PERIOD: number = 96
const SWEEP_TOTAL_WIDTH: number = SWEEP_PERIOD * 3
const SWEEP_DURATION: number = 1400
// 高光自左向右扫过：图层先左移一个周期，再位移回 0。
// 反过来（0 → -SWEEP_PERIOD）会变成自右向左。
const SWEEP_START_OFFSET: number = -SWEEP_PERIOD
const SWEEP_END_OFFSET: number = 0

@ComponentV2
export struct ThinkingStatusIndicator {
  @Param isActive: boolean = false
  @Local private sweepOffset: number = SWEEP_START_OFFSET
  private animationStarted: boolean = false
  private startTimer: number = -1

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private shouldAnimate(): boolean {
    return this.isActive && !this.isManuscriptMode
  }

  private getAccentColor(): ResourceColor {
    return this.isManuscriptMode || this.isActive ? this.themePrimary : $r('app.color.text_secondary')
  }

  // 暗处用主题色压暗打底、纯白冲顶，亮处用主题色本色冲顶，两种底色下都够醒目
  private getSweepBaseColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '5C' : '52')
  }

  private getSweepHighlightColor(): string {
    return this.isDarkMode ? '#FFFFFF' : this.themePrimary
  }

  private getSweepColors(): Array<[ResourceColor, number]> {
    const base = this.getSweepBaseColor()
    const highlight = this.getSweepHighlightColor()
    return [
      [base, 0.0],
      [highlight, 1 / 6],
      [base, 2 / 6],
      [highlight, 3 / 6],
      [base, 4 / 6],
      [highlight, 5 / 6],
      [base, 1.0]
    ]
  }

  aboutToAppear(): void {
    this.syncAnimation()
  }

  aboutToDisappear(): void {
    this.stopAnimation()
  }

  @Monitor('isActive')
  onActiveStateChange(): void {
    this.syncAnimation()
  }

  private syncAnimation(): void {
    if (this.shouldAnimate()) {
      this.startAnimation()
      return
    }
    this.stopAnimation()
  }

  // 延到下一帧启动，等高光层完成首次布局，否则位移动画会丢
  private startAnimation(): void {
    if (this.animationStarted) {
      return
    }
    this.animationStarted = true
    this.sweepOffset = SWEEP_START_OFFSET
    this.startTimer = setTimeout(() => {
      this.startTimer = -1
      if (!this.animationStarted) {
        return
      }
      try {
        this.getUIContext().animateTo({
          duration: SWEEP_DURATION,
          curve: Curve.Linear,
          iterations: -1,
          playMode: PlayMode.Normal,
          expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
        }, (): void => {
          this.sweepOffset = SWEEP_END_OFFSET
        })
      } catch (_error) {
      }
    }, 0)
  }

  // 直接赋值即可中断正在播放的无限动画
  private stopAnimation(): void {
    this.animationStarted = false
    if (this.startTimer !== -1) {
      clearTimeout(this.startTimer)
      this.startTimer = -1
    }
    this.sweepOffset = SWEEP_START_OFFSET
  }

  @Builder
  private ThinkingContent() {
    Row() {
      SymbolGlyph($r('sys.symbol.AI_deep_thinking'))
        .fontSize(14)
        .fontColor([this.getAccentColor()])

      Text(this.isActive ? $r('app.string.reasoning_thinking') : $r('app.string.reasoning_process'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getAccentColor())
        .margin({ left: 6 })
    }
    .alignItems(VerticalAlign.Center)
  }

  build() {
    if (this.shouldAnimate()) {
      // 遮罩容器用 Row：position 的子组件在 Row/Column/Flex 下确定不占空间，
      // 高光层再宽也不会把标题栏撑开（Stack 无此保证）
      Row() {
        this.ThinkingContent()

        Row()
          .width(SWEEP_TOTAL_WIDTH)
          .height('100%')
          .position({ x: 0, y: 0 })
          .translate({ x: this.sweepOffset })
          .linearGradient({ angle: 90, colors: this.getSweepColors() })
          .blendMode(BlendMode.SRC_IN)
      }
      .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
    } else {
      this.ThinkingContent()
    }
  }
}
