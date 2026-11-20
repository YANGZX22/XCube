/**
 * 思考条与合并栏共用的状态指示：图标 + 标题。
 *
 * 推理时一束高光沿横向扫过图标与文字。图标和文字被当成
 * 一个整体：渐变画在同一层离屏画布上，用 SRC_IN 混合裁到内容形状里，
 * 所以高光穿过图标与文字之间时是连续的，不会在接缝处断开。
 *
 * 独立思考条启用三点脉冲和缓动扫光；合并栏沿用原有的线性扫光和书写图标。
 *
 * 渐变本身不变，只靠 translate 滚动：位移走系统动画线程，
 * 不必逐帧重建 shader，也不占 JS 计时器。
 */

import { curves } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { VisualEffectsMode } from '../models/ThemeColors'
import { ExecutionWritingIcon } from './ExecutionWritingIcon'
import { statusPulseDots } from './TypingDots'

// 高光带每 SWEEP_PERIOD 重复一次，至少铺三个周期并覆盖完整标题宽度，
// 位移正好走一个周期后回到起点，循环处看不出接缝。
const SWEEP_PERIOD: number = 96
const SWEEP_DURATION: number = 1400
// 高光自左向右扫过：图层先左移一个周期，再位移回 0。
// 反过来（0 → -SWEEP_PERIOD）会变成自右向左。
const SWEEP_START_OFFSET: number = -SWEEP_PERIOD
const SWEEP_END_OFFSET: number = 0
// 合并栏与思考栏的图标共用占位，保持标题起点和垂直中心一致。
const STATUS_ICON_SIZE: number = 14

@ComponentV2
export struct ThinkingStatusIndicator {
  @Param isActive: boolean = false
  @Param showReasoningMotion: boolean = false
  @Param label: ResourceStr | undefined = undefined
  @Param showWritingIcon: boolean = false
  @Param inactiveColor: ResourceColor | undefined = undefined
  @Param fullWidth: boolean = false
  @Local private sweepOffset: number = SWEEP_START_OFFSET
  @Local private contentWidth: number = 0
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

  @Computed
  private get animationEnabled(): boolean {
    return this.isActive && (this.showReasoningMotion ? !getAppUiState().appInBackground : !this.isManuscriptMode)
  }

  private getAccentColor(): ResourceColor {
    if (this.isActive) {
      return this.themePrimary
    }
    return this.inactiveColor ?? (this.isManuscriptMode ? this.themePrimary : $r('app.color.text_secondary'))
  }

  private getSweepWidth(): number {
    // 左移一个周期时仍需完整覆盖长标题，避免尾部被 SRC_IN 遮罩裁掉。
    return SWEEP_PERIOD * Math.max(3, Math.ceil(this.contentWidth / SWEEP_PERIOD) + 1)
  }

  // 暗处用主题色压暗打底、纯白冲顶，亮处用主题色本色冲顶，两种底色下都够醒目
  private getSweepBaseColor(): string {
    if (this.showReasoningMotion) {
      return withColorAlpha(this.themePrimary, '99')
    }
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '5C' : '52')
  }

  private getSweepHighlightColor(): string {
    if (!this.isDarkMode) return this.themePrimary
    return this.showReasoningMotion ? getAppUiState().themeTextPrimary : '#FFFFFF'
  }

  private getSweepColors(): Array<[ResourceColor, number]> {
    const base = this.getSweepBaseColor()
    const highlight = this.getSweepHighlightColor()
    const periods = this.getSweepWidth() / SWEEP_PERIOD
    const colors: Array<[ResourceColor, number]> = [[base, 0]]
    for (let index = 0; index < periods; index++) {
      colors.push([highlight, (index + 0.5) / periods])
      colors.push([base, (index + 1) / periods])
    }
    return colors
  }

  aboutToAppear(): void {
    this.syncAnimation()
  }

  aboutToDisappear(): void {
    this.stopAnimation()
  }

  @Monitor('animationEnabled')
  onActiveStateChange(): void {
    this.syncAnimation()
  }

  private syncAnimation(): void {
    if (this.animationEnabled) {
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
        const context = this.getUIContext()
        if (this.showReasoningMotion) {
          context.keyframeAnimateTo({ iterations: -1 }, [
            { duration: 450, event: () => { this.sweepOffset = SWEEP_START_OFFSET } },
            { duration: 2100, curve: curves.cubicBezierCurve(0.714, 0.121, 0.211, 0.888),
              event: () => { this.sweepOffset = SWEEP_END_OFFSET } },
            { duration: 450, event: () => { this.sweepOffset = SWEEP_END_OFFSET } }
          ])
          return
        }
        context.animateTo({
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
      if (this.showWritingIcon) {
        ExecutionWritingIcon({ isActive: this.isActive, tint: this.getAccentColor() })
      } else {
        SymbolGlyph($r('sys.symbol.AI_deep_thinking'))
          .fontSize(STATUS_ICON_SIZE)
          .width(STATUS_ICON_SIZE)
          .height(STATUS_ICON_SIZE)
          .fontColor([this.getAccentColor()])
          .flexShrink(0)
      }

      Text(this.label ?? (this.isActive ? $r('app.string.reasoning_thinking') : $r('app.string.reasoning_process')))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getAccentColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(this.fullWidth ? 1 : 0)
        .flexShrink(this.fullWidth ? 0 : 1)
        .margin({ left: 6 })
      if (this.animationEnabled && this.showReasoningMotion) {
        statusPulseDots(5)
      }
    }
    .width(this.fullWidth ? '100%' : undefined)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    if (this.animationEnabled) {
      // 遮罩容器用 Row：position 的子组件在 Row/Column/Flex 下确定不占空间，
      // 高光层再宽也不会把标题栏撑开（Stack 无此保证）
      Row() {
        this.ThinkingContent()

        Row()
          .width(this.getSweepWidth())
          .height('100%')
          .position({ x: 0, y: 0 })
          .translate({ x: this.sweepOffset })
          .linearGradient({ angle: 90, colors: this.getSweepColors() })
          .blendMode(BlendMode.SRC_IN)
      }
      .width(this.fullWidth ? '100%' : undefined)
      .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        const width = Number(size.width)
        if (Number.isFinite(width) && width > 0 && Math.abs(width - this.contentWidth) > 0.1) {
          this.contentWidth = width
        }
      })
    } else {
      this.ThinkingContent()
    }
  }
}
