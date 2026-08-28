import { ToolCall, ToolResult } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { buildToolArgumentsPreview, buildToolResultPreview, ToolPayloadPreview } from '../utils/ToolPayloadSummaryUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { uiMaterial } from '@kit.ArkUI'
import { VisualEffectsMode } from '../models/ThemeColors'
import { MANUSCRIPT_COMPACT_BAR_HEIGHT } from '../utils/ManuscriptVisualUtils'
import {
  getLocalizedBuiltinToolName,
  getLocalizedToolSourceLabel
} from '../utils/ToolDisplayTextUtils'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import {
  buildTimelineBarExpandTransition,
  getTimelineBarExpandAnimation
} from '../utils/TimelineBarTransitionUtils'
import {
  resolveToolIconImageKind,
  resolveToolSymbolResource,
  TOOL_ICON_IMAGE_DOCX,
  TOOL_ICON_IMAGE_XLSX
} from '../utils/ToolIconUtils'

// 同一工具的单次调用（调用 + 对应结果），多次调用合并进同一张卡片
export class ToolCallCardEntry {
  toolCall: ToolCall = new ToolCall()
  toolResult: ToolResult | null = null

  constructor(toolCall: ToolCall, toolResult: ToolResult | null) {
    this.toolCall = toolCall
    this.toolResult = toolResult
  }
}

// 获取工具显示名称
function getToolDisplayName(toolCall: ToolCall): string | Resource {
  const raw = toolCall.functionName as string | null | undefined
  const fallback = toolCall.displayName.trim() !== '' ? toolCall.displayName : (raw ?? '')
  const lookupId = raw !== undefined && raw !== null && raw.trim() !== '' ? raw : toolCall.toolId
  if (lookupId.trim() === '') {
    return pickLocalizedText('未知工具', 'Unknown Tool')
  }
  const normalized = lookupId.toLowerCase().replace(/[\s\-]+/g, '_')
  if (normalized === 'web_search' || normalized === 'exa_search' || normalized === 'websearch'
    || normalized === 'search_web' || normalized === 'internet_search' || normalized === 'web_search_exa') {
    return $r('app.string.web_search')
  }
  return getLocalizedBuiltinToolName(lookupId, fallback)
}

// 工具调用卡片组件（同一工具的多次调用合并为一张卡片，标题居中显示 x N）
@ComponentV2
export struct ToolCallCard {
  @Param entries: ToolCallCardEntry[] = []
  @Param isExecuting: boolean = false
  // 合并进条目块时由外层统一提供边框、材质与投影，卡片自身只出内容
  @Param embedded: boolean = false
  // 子智能体卡片点击“实时预览”时触发（由宿主打开 bindSheet）
  @Event onSubAgentPreview: () => void = (): void => {}
  @Local isExpanded: boolean = false
  @Local rawArgumentIndices: number[] = []
  @Local rawResultIndices: number[] = []
  // 跳动点动画状态
  @Local dot1Scale: number = 0.6
  @Local dot2Scale: number = 0.6
  @Local dot3Scale: number = 0.6
  // 主题颜色
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }
  private dotAnimationTimer: number = -1

  private getTimelineRailColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '88' : '55')
  }

  private getPrimaryCall(): ToolCall {
    return this.entries.length > 0 ? this.entries[0].toolCall : new ToolCall()
  }

  private hasAnyResult(): boolean {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].toolResult !== null) {
        return true
      }
    }
    return false
  }

  aboutToAppear(): void {
    if (this.isExecuting) {
      this.startDotAnimation()
    }
  }

  aboutToDisappear(): void {
    this.stopDotAnimation()
  }

  @Monitor('isExecuting')
  onExecutingStateChange(): void {
    if (this.isExecuting) {
      this.startDotAnimation()
      return
    }
    this.stopDotAnimation()
  }

  // 启动跳动点动画
  private startDotAnimation(): void {
    if (this.dotAnimationTimer !== -1) {
      return
    }
    let step = 0
    this.dotAnimationTimer = setInterval(() => {
      const currentDot = step % 3
      this.getUIContext().animateTo({
        duration: 300,
        curve: Curve.EaseInOut
      }, () => {
        this.dot1Scale = 0.6
        this.dot2Scale = 0.6
        this.dot3Scale = 0.6
        if (currentDot === 0) {
          this.dot1Scale = 1.0
        } else if (currentDot === 1) {
          this.dot2Scale = 1.0
        } else {
          this.dot3Scale = 1.0
        }
      })
      step++
    }, 300)
  }

  // 停止跳动点动画
  private stopDotAnimation(): void {
    if (this.dotAnimationTimer !== -1) {
      clearInterval(this.dotAnimationTimer)
      this.dotAnimationTimer = -1
    }
  }

  // 图标按工具身份解析：函数名优先，缺失时回落到工具 ID
  private getToolIconId(): string {
    const primaryCall = this.getPrimaryCall()
    const raw = primaryCall.functionName as string | null | undefined
    if (raw !== undefined && raw !== null && raw.trim() !== '') {
      return raw
    }
    return primaryCall.toolId
  }

  private getToolIconColor(): ResourceColor {
    return this.isManuscriptMode || this.isExecuting ? this.themePrimary : $r('app.color.text_secondary')
  }

  @Builder
  private ToolIcon() {
    if (resolveToolIconImageKind(this.getToolIconId()) === TOOL_ICON_IMAGE_DOCX) {
      Image($r('app.media.doc_docx'))
        .width(14)
        .height(14)
        .fillColor(this.getToolIconColor())
        .flexShrink(0)
    } else if (resolveToolIconImageKind(this.getToolIconId()) === TOOL_ICON_IMAGE_XLSX) {
      Image($r('app.media.doc_xlsx'))
        .width(14)
        .height(14)
        .fillColor(this.getToolIconColor())
        .flexShrink(0)
    } else {
      SymbolGlyph(resolveToolSymbolResource(this.getToolIconId()))
        .fontSize(14)
        .fontColor([this.getToolIconColor()])
        .flexShrink(0)
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        // 左侧信息区只使用扣除右侧操作后的剩余宽度，避免长名称挤出操作按钮。
        Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Center }) {
          // 工具图标：与工具中心、工具选择面板取同一套图标
          this.ToolIcon()

          // 工具名称
          Text(getToolDisplayName(this.getPrimaryCall()))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isManuscriptMode || this.isExecuting
              ? this.themePrimary : $r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.MARQUEE })
            .marqueeOptions({
              start: true,
              step: 3,
              loop: -1,
              fromStart: true,
              delay: 1200,
              fadeout: true
            })
            .flexShrink(1)
            .margin({ left: 6 })

          if (this.getPrimaryCall().sourceLabel.trim() !== '') {
            Text(getLocalizedToolSourceLabel(this.getPrimaryCall().sourceLabel))
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
              .flexShrink(0)
              .margin({ left: 6 })
          }

          // 执行状态
          if (this.isExecuting) {
            // 执行中：显示跳动点
            Row({ space: 2 }) {
              Column()
                .width(4)
                .height(4)
                .borderRadius(2)
                .backgroundColor(this.themePrimary)
                .scale({ x: this.dot1Scale, y: this.dot1Scale })

              Column()
                .width(4)
                .height(4)
                .borderRadius(2)
                .backgroundColor(this.themePrimary)
                .scale({ x: this.dot2Scale, y: this.dot2Scale })

              Column()
                .width(4)
                .height(4)
                .borderRadius(2)
                .backgroundColor(this.themePrimary)
                .scale({ x: this.dot3Scale, y: this.dot3Scale })
            }
            .flexShrink(0)
            .margin({ left: 8 })
          } else if (this.hasAnyResult() && !this.shouldHideStatusIcon()) {
            // 已完成：根据结果显示成功/失败状态
            SymbolGlyph(this.getResultStatusSymbol())
              .fontSize(14)
              .fontColor([this.getResultStatusColor()])
              .flexShrink(0)
              .margin({ left: 8 })
          }

          // 子智能体卡片：实时预览入口（bindSheet 由宿主 MessageBubble 承载）
          if (this.isSubAgentCard()) {
            Text(pickLocalizedText('实时预览', 'Live Preview'))
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .borderRadius(this.isManuscriptMode ? 0 : 9)
              .backgroundColor(this.isManuscriptMode ? Color.Transparent : this.themePrimaryLight)
              .border({ width: 0, color: this.themePrimary })
              .flexShrink(0)
              .margin({ left: 8 })
              .onClick(() => {
                this.onSubAgentPreview()
              })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .clip(true)

        // 多次调用合并显示：固定在详情按钮左侧。
        if (this.entries.length > 1) {
          Text(`× ${this.entries.length}`)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
            .textAlign(TextAlign.Center)
            .padding({ left: 7, right: 7, top: 1, bottom: 1 })
            .borderRadius(this.isManuscriptMode ? 0 : 9)
            .backgroundColor(this.isManuscriptMode ? Color.Transparent : this.themePrimaryLight)
            .border({ width: 0, color: this.themePrimary })
            .margin({ left: 8 })
        }

        // 右侧操作区按内容宽度占位，箭头始终贴右对齐，尽量把空间留给工具名称。
        if (this.hasAnyResult()) {
          Row() {
            Text(this.isExpanded ? $r('app.string.common_collapse') : $r('app.string.common_details'))
              .fontSize(11)
              .fontColor(this.isManuscriptMode ? this.themePrimary : $r('app.color.text_tertiary'))

            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([this.isManuscriptMode ? this.themePrimary : $r('app.color.text_tertiary')])
              .rotate({ angle: this.isExpanded ? 180 : 0 })
              .animation(getTimelineBarExpandAnimation())
              .margin({ left: 2 })
          }
          .justifyContent(FlexAlign.End)
          .margin({ left: 8 })
          .onClick(() => {
            this.getUIContext().animateTo(getTimelineBarExpandAnimation(), () => {
              if (this.isExpanded) {
                this.rawArgumentIndices = []
                this.rawResultIndices = []
              }
              this.isExpanded = !this.isExpanded
            })
          })
        }
      }
      .width('100%')
      .height(this.isManuscriptMode ? MANUSCRIPT_COMPACT_BAR_HEIGHT : 36)
      .padding({ left: this.isManuscriptMode ? 14 : 10, right: this.isManuscriptMode ? 14 : 10 })

      // 展开的详情内容：所有调用合并在同一个展开面板里
      if (this.isExpanded && this.hasAnyResult()) {
        Column({ space: 8 }) {
          ForEach(this.entries, (entry: ToolCallCardEntry, index: number) => {
            this.EntryDetail(entry, index)
          }, (entry: ToolCallCardEntry, index: number) => entry.toolCall.id + '_' + index.toString())
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })
        .transition(buildTimelineBarExpandTransition())
      }
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .borderRadius(this.embedded || this.isManuscriptMode ? 0 : 12)
    .border({
      width: this.embedded ? 0 : (this.isManuscriptMode ? { top: 1, bottom: 1 } : 0.5),
      color: this.isManuscriptMode ? getAppUiState().themeDivider : this.getTimelineRailColor()
    })
    .clip(false)
    .systemMaterial(this.embedded || this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.themeAiBubble,
      applyShadow: false,
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .shadow({
      radius: this.embedded || this.isManuscriptMode ? 0 : 12,
      color: this.embedded || this.isManuscriptMode ? Color.Transparent :
        (this.isDarkMode ? 'rgba(0, 0, 0, 0.32)' : 'rgba(15, 23, 42, 0.14)'),
      offsetX: 0,
      offsetY: 0
    })
  }

  @Builder
  EntryDetail(entry: ToolCallCardEntry, index: number) {
    Column({ space: 8 }) {
      // 多次调用时用序号分隔各次调用
      if (this.entries.length > 1) {
        Row() {
          Text(`#${index + 1}`)
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(this.isManuscriptMode ? 0 : 8)
            .backgroundColor(this.isManuscriptMode ? Color.Transparent : this.themePrimaryLight)
            .border({ width: 0, color: this.themePrimary })

          Row()
            .height(0.5)
            .layoutWeight(1)
            .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '55' : '33'))
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: index === 0 ? 0 : 4 })
      }

      Row() {
        Text($r('app.string.tool_call_args_label'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .width(56)

        Text(this.getEntryArgumentPreview(entry).summary)
          .fontSize(11)
          .lineHeight(16)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Blank()
        Text(this.isRawArgumentsShown(index)
          ? pickLocalizedText('收起原始参数', 'Hide Raw Arguments')
          : pickLocalizedText('查看原始参数', 'Show Raw Arguments'))
          .fontSize(10)
          .fontColor(this.themePrimary)
          .onClick(() => {
            this.toggleRawArguments(index)
          })
      }
      .width('100%')

      if (this.isRawArgumentsShown(index)) {
        Scroll() {
          Text(this.getEntryArgumentPreview(entry).rawPreview)
            .width('100%')
            .fontSize(11)
            .lineHeight(16)
            .fontFamily('monospace')
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .constraintSize({ maxHeight: 160 })
        .padding(10)
        .borderRadius(this.isManuscriptMode ? 3 : 8)
        .backgroundColor(Color.Transparent)
        .border({
          width: this.isManuscriptMode ? 1 : 0.5,
          color: this.isManuscriptMode ? getAppUiState().themeDivider :
            withColorAlpha(this.themePrimary, this.isDarkMode ? '55' : '33')
        })
      }

      Row() {
        Text($r('app.string.tool_call_result_label'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .width(56)

        Text(this.getEntryResultPreview(entry).summary)
          .fontSize(11)
          .lineHeight(16)
          .fontColor(this.entryHasFailedResult(entry) ? $r('app.color.status_error') : $r('app.color.text_secondary'))
          .layoutWeight(1)
      }
      .width('100%')

      if (entry.toolResult !== null) {
        Row() {
          Blank()
          Text(this.isRawResultShown(index)
            ? pickLocalizedText('收起原始结果', 'Hide Raw Result')
            : pickLocalizedText('查看原始结果', 'Show Raw Result'))
            .fontSize(10)
            .fontColor(this.themePrimary)
            .onClick(() => {
              this.toggleRawResult(index)
            })
        }
        .width('100%')
      }

      if (this.isRawResultShown(index) && entry.toolResult !== null) {
        Scroll() {
          Text(this.getEntryResultPreview(entry).rawPreview)
            .width('100%')
            .fontSize(11)
            .lineHeight(16)
            .fontFamily('monospace')
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .constraintSize({ maxHeight: 180 })
        .padding(10)
        .borderRadius(this.isManuscriptMode ? 3 : 8)
        .backgroundColor(Color.Transparent)
        .border({
          width: this.isManuscriptMode ? 1 : 0.5,
          color: this.isManuscriptMode ? getAppUiState().themeDivider :
            withColorAlpha(this.themePrimary, this.isDarkMode ? '55' : '33')
        })
      }
    }
    .width('100%')
  }

  private isRawArgumentsShown(index: number): boolean {
    return this.rawArgumentIndices.includes(index)
  }

  private toggleRawArguments(index: number): void {
    if (this.isRawArgumentsShown(index)) {
      this.rawArgumentIndices = this.rawArgumentIndices.filter((value: number) => value !== index)
    } else {
      this.rawArgumentIndices = this.rawArgumentIndices.concat([index])
    }
  }

  private isRawResultShown(index: number): boolean {
    return this.rawResultIndices.includes(index)
  }

  private toggleRawResult(index: number): void {
    if (this.isRawResultShown(index)) {
      this.rawResultIndices = this.rawResultIndices.filter((value: number) => value !== index)
    } else {
      this.rawResultIndices = this.rawResultIndices.concat([index])
    }
  }

  private getEntryArgumentPreview(entry: ToolCallCardEntry): ToolPayloadPreview {
    return buildToolArgumentsPreview(entry.toolCall.arguments, 3, 600)
  }

  private getEntryResultPreview(entry: ToolCallCardEntry): ToolPayloadPreview {
    if (entry.toolResult === null) {
      const executingText = pickLocalizedText('执行中...', 'Running...')
      return new ToolPayloadPreview(executingText, [], executingText, false)
    }
    return buildToolResultPreview(entry.toolResult.content, 3, 900)
  }

  private entryHasFailedResult(entry: ToolCallCardEntry): boolean {
    if (entry.toolResult === null) {
      return false
    }
    if (entry.toolResult.isError) {
      return true
    }
    try {
      const parsed = JSON.parse(entry.toolResult.content) as Record<string, Object>
      const errorField = parsed.error
      const hasError = errorField !== undefined && errorField !== null && errorField !== ''
      return parsed.isError === true || hasError
    } catch (_error) {
      return false
    }
  }

  private entryWasRejectedByUser(entry: ToolCallCardEntry): boolean {
    if (entry.toolResult === null) {
      return false
    }
    try {
      const parsed = JSON.parse(entry.toolResult.content) as Record<string, Object>
      return parsed.rejected === true
    } catch (_error) {
      return false
    }
  }

  private hasUserRejectedResult(): boolean {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entryWasRejectedByUser(this.entries[i])) {
        return true
      }
    }
    return false
  }

  private getResolvedResultCount(): number {
    let count = 0
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].toolResult !== null) {
        count++
      }
    }
    return count
  }

  private getFailedResultCount(): number {
    let count = 0
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entryHasFailedResult(this.entries[i])) {
        count++
      }
    }
    return count
  }

  private hasMixedResultStatus(): boolean {
    const resolvedCount = this.getResolvedResultCount()
    const failedCount = this.getFailedResultCount()
    return failedCount > 0 && failedCount < resolvedCount
  }

  private haveAllResolvedResultsFailed(): boolean {
    const resolvedCount = this.getResolvedResultCount()
    return resolvedCount > 0 && this.getFailedResultCount() === resolvedCount
  }

  // Python 工具不展示成功/失败状态图标（按产品要求）
  private shouldHideStatusIcon(): boolean {
    return this.getPrimaryCall().functionName === 'python_sandbox'
  }

  private isSubAgentCard(): boolean {
    const raw = this.getPrimaryCall().functionName as string | null | undefined
    if (raw === undefined || raw === null) {
      return false
    }
    const normalized = raw.toLowerCase().replace(/[\s\-]+/g, '_')
    return normalized === 'sub_agent' || normalized === 'sub_agent_message'
  }

  private getResultStatusSymbol(): Resource {
    if (this.hasUserRejectedResult()) {
      return $r('sys.symbol.hand_raised_filled_hexagon')
    }
    if (this.hasMixedResultStatus()) {
      return $r('sys.symbol.exclamationmark_circle')
    }
    return this.haveAllResolvedResultsFailed()
      ? $r('sys.symbol.xmark_circle')
      : $r('sys.symbol.checkmark_circle')
  }

  private getResultStatusColor(): ResourceColor {
    if (this.hasMixedResultStatus()) {
      return $r('app.color.status_warning')
    }
    return this.haveAllResolvedResultsFailed()
      ? $r('app.color.status_error')
      : $r('app.color.status_success')
  }
}
