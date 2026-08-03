import {
  getSubAgentService,
  SubAgentLiveState,
  SubAgentPreviewState,
  SubAgentToolEventState,
  SUB_AGENT_STATUS_CANCELLED,
  SUB_AGENT_STATUS_FAILED,
  SUB_AGENT_STATUS_RUNNING,
  SUB_AGENT_TOOL_EVENT_ERROR,
  SUB_AGENT_TOOL_EVENT_RUNNING
} from '../services/SubAgentService'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { uiMaterial } from '@kit.ArkUI'

// 子智能体实时预览面板：展示最近一批子智能体各自调用了哪些工具、生成了什么内容。
// 状态来自 SubAgentService 的 @ObservedV2 预览状态，运行期间实时刷新。
@ComponentV2
export struct SubAgentPreviewSheetContent {
  @Event onClose: () => void = (): void => {}
  @Local collapsedAgentKeys: string[] = []

  private get previewState(): SubAgentPreviewState {
    return getSubAgentService().getPreviewState()
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private getCardBorderColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '88' : '55')
  }

  private getInnerBorderColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '55' : '33')
  }

  private getAgentCardMaterial(): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: Color.Transparent,
      applyShadow: true,
      interactive: false,
      lightEffect: { color: undefined }
    })
  }

  private getCollapseButtonMaterial(): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    })
  }

  private getAgentKey(agent: SubAgentLiveState, index: number): string {
    return index.toString() + '_' + agent.name
  }

  private isAgentCollapsed(agent: SubAgentLiveState, index: number): boolean {
    return this.collapsedAgentKeys.includes(this.getAgentKey(agent, index))
  }

  private toggleAgentCollapsed(agent: SubAgentLiveState, index: number): void {
    const key = this.getAgentKey(agent, index)
    if (this.collapsedAgentKeys.includes(key)) {
      this.collapsedAgentKeys = this.collapsedAgentKeys.filter((item: string): boolean => item !== key)
    } else {
      this.collapsedAgentKeys = this.collapsedAgentKeys.concat([key])
    }
  }

  private getAgentStatusText(status: string): string {
    if (status === SUB_AGENT_STATUS_RUNNING) {
      return '运行中'
    }
    if (status === SUB_AGENT_STATUS_FAILED) {
      return '失败'
    }
    if (status === SUB_AGENT_STATUS_CANCELLED) {
      return '已取消'
    }
    return '已完成'
  }

  private getAgentStatusSymbol(status: string): Resource {
    if (status === SUB_AGENT_STATUS_FAILED || status === SUB_AGENT_STATUS_CANCELLED) {
      return $r('sys.symbol.xmark_circle')
    }
    return $r('sys.symbol.checkmark_circle')
  }

  private getAgentStatusColor(status: string): ResourceColor {
    if (status === SUB_AGENT_STATUS_FAILED) {
      return $r('app.color.status_error')
    }
    if (status === SUB_AGENT_STATUS_CANCELLED) {
      return $r('app.color.text_tertiary')
    }
    return $r('app.color.status_success')
  }

  build() {
    Column() {
      ImmersiveSheetHeader({
        title: '子智能体实时预览',
        onLeadingClick: (): void => {
          this.onClose()
        }
      })

      if (this.previewState.agents.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(28)
            .fontColor([$r('app.color.text_tertiary')])

          Text(this.previewState.hasEverRun ? '子智能体运行记录已失效' : '当前还没有运行过子智能体')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))

          Text('模型调用「子智能体」工具后，这里会实时显示每个子智能体的工具调用与生成内容')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.previewState.agents, (agent: SubAgentLiveState, index: number) => {
              this.AgentCard(agent, index)
            }, (agent: SubAgentLiveState, index: number) => index.toString() + '_' + agent.name)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 24 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AgentCard(agent: SubAgentLiveState, index: number) {
    Column({ space: 8 }) {
      // 标题行：状态 + 名称 + 轮次统计
      Row() {
        if (agent.status === SUB_AGENT_STATUS_RUNNING) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(this.themePrimary)
        } else {
          SymbolGlyph(this.getAgentStatusSymbol(agent.status))
            .fontSize(14)
            .fontColor([this.getAgentStatusColor(agent.status)])
        }

        Column({ space: 2 }) {
          Text(agent.name)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(`${this.getAgentStatusText(agent.status)} · 第 ${agent.rounds} 轮 · 工具 ${agent.toolEvents.length} 次`)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
          .margin({ left: 6 })
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

        Button({ type: ButtonType.Circle, stateEffect: false }) {
          SymbolGlyph(this.isAgentCollapsed(agent, index)
            ? $r('sys.symbol.chevron_down')
            : $r('sys.symbol.chevron_up'))
            .fontSize(13)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(30)
        .height(30)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(15)
        .systemMaterial(this.getCollapseButtonMaterial())
        .margin({ left: 8 })
        .onClick(() => {
          this.toggleAgentCollapsed(agent, index)
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.isAgentCollapsed(agent, index)) {
        // 任务提示词预览
        if (agent.promptPreview !== '') {
          Text(agent.promptPreview)
            .fontSize(11)
            .lineHeight(15)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        // 工具调用时间线
        if (agent.toolEvents.length > 0) {
          Column({ space: 6 }) {
            ForEach(agent.toolEvents, (event: SubAgentToolEventState, eventIndex: number) => {
              this.ToolEventRow(event)
            }, (event: SubAgentToolEventState, eventIndex: number) => eventIndex.toString())
          }
          .width('100%')
          .padding(8)
          .borderRadius(10)
          .border({ width: 0.5, color: this.getInnerBorderColor() })
          .backgroundColor(Color.Transparent)
        }

        // 实时生成内容
        if (agent.liveContent !== '') {
          Scroll() {
            Text(agent.liveContent)
              .width('100%')
              .fontSize(11)
              .lineHeight(16)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .constraintSize({ maxHeight: 220 })
          .padding(10)
          .borderRadius(10)
          .border({ width: 0.5, color: this.getInnerBorderColor() })
          .backgroundColor(Color.Transparent)
          .scrollBar(BarState.Auto)
          .align(Alignment.TopStart)
        } else if (agent.status === SUB_AGENT_STATUS_RUNNING) {
          Text('等待模型输出...')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.Transparent)
    .borderRadius(16)
    .border({ width: 0.5, color: this.getCardBorderColor() })
    .systemMaterial(this.getAgentCardMaterial())
  }

  @Builder
  ToolEventRow(event: SubAgentToolEventState) {
    Row() {
      if (event.status === SUB_AGENT_TOOL_EVENT_RUNNING) {
        LoadingProgress()
          .width(12)
          .height(12)
          .color(this.themePrimary)
          .margin({ top: 2 })
      } else {
        SymbolGlyph(event.status === SUB_AGENT_TOOL_EVENT_ERROR
          ? $r('sys.symbol.xmark_circle')
          : $r('sys.symbol.checkmark_circle'))
          .fontSize(12)
          .fontColor([event.status === SUB_AGENT_TOOL_EVENT_ERROR
            ? $r('app.color.status_error')
            : $r('app.color.status_success')])
          .margin({ top: 2 })
      }

      Column({ space: 2 }) {
        Row() {
          Text(event.displayName)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text(event.argsPreview)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 6 })
            .layoutWeight(1)
        }
        .width('100%')

        if (event.resultPreview !== '') {
          Text(event.resultPreview)
            .fontSize(10)
            .lineHeight(14)
            .fontColor(event.status === SUB_AGENT_TOOL_EVENT_ERROR
              ? $r('app.color.status_error')
              : $r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 6 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
