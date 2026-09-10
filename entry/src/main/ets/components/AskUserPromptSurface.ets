import { ToolCall } from '../models/ChatModels'
import { VisualEffectsMode } from '../models/ThemeColors'
import { getAppUiState } from '../state/AppUiState'
import { AskUserCard } from './AskUserCard'
import { ImmersiveMaterialBackdrop } from './ImmersiveMaterialBackdrop'

const PROMPT_CORNER_RADIUS = 20

// Tabs 仅提供底部 TabBar 生效区域，真正的材质绘制在固定圆角的 Row 上。
// 问答卡片保持独立前景，不进入 TabBar builder，也不被其命中测试拦截。
@ComponentV2
export struct AskUserPromptSurface {
  @Param toolCall: ToolCall = new ToolCall()
  @Param questionArguments: string | undefined = undefined
  @Param pendingCount: number = 1
  @Event onAnswer: (id: string, answer: string) => void = (_id: string, _answer: string): void => {}
  @Local surfaceWidth: number = 0
  @Local surfaceHeight: number = 0
  @Local contentHeight: number = 0

  private get usesSystemMaterial(): boolean {
    // 测量完成前也不启用卡片的 blur，避免用普通模糊代替原生材质。
    return getAppUiState().visualEffectsMode !== VisualEffectsMode.MANUSCRIPT
  }

  private get maxHeight(): number {
    const windowHeight = getAppUiState().windowHeightVp
    return windowHeight > 0 ? Math.max(160, windowHeight * 0.7) : 480
  }

  private get frameRadius(): number {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT ? 0 : PROMPT_CORNER_RADIUS
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.usesSystemMaterial && this.surfaceWidth > 0 && this.surfaceHeight > 0) {
        ImmersiveMaterialBackdrop({
          surfaceWidth: this.surfaceWidth,
          surfaceHeight: this.surfaceHeight,
          cornerRadius: PROMPT_CORNER_RADIUS
        })
          .position({ x: 0, y: 0 })
      }
      Scroll() {
        AskUserCard({
          toolCall: this.toolCall,
          questionArguments: this.questionArguments,
          isAnswered: false,
          compactMode: false,
          pendingCount: this.pendingCount,
          surfaceProvided: this.usesSystemMaterial,
          onAnswer: (id: string, answer: string) => { this.onAnswer(id, answer) }
        })
          .width('100%')
          .onAreaChange((_old: Area, area: Area) => {
            const height = Number(area.height)
            if (Number.isFinite(height) && height > 0 && Math.abs(height - this.contentHeight) > 0.1) {
              this.contentHeight = height
            }
          })
      }
      .width('100%')
      .height(this.contentHeight > 0 ? Math.min(this.contentHeight, this.maxHeight) : undefined)
      .constraintSize({ maxHeight: this.maxHeight })
      .scrollBar(BarState.Auto)
      .borderRadius(this.frameRadius)
      .clip(true)
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width)
        const height = Number(area.height)
        if (Number.isFinite(width) && width > 0 && Math.abs(width - this.surfaceWidth) > 0.1) {
          this.surfaceWidth = width
        }
        if (Number.isFinite(height) && height > 0 && Math.abs(height - this.surfaceHeight) > 0.1) {
          this.surfaceHeight = height
        }
      })
    }
    .width('100%')
    // 不裁剪原生材质边缘和阴影，也不叠加与其轮廓不符的矩形投影。
    .clip(false)
  }
}
