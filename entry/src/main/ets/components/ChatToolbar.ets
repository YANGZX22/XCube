/**
 * 聊天工具栏组件
 * 包含工具选择入口、推理开关等功能按钮
 */

import { ReasoningLevel } from '../models/ChatModels'
import { ReasoningControlMode } from '../services/ProviderCompatibilityRegistry'
import { getAppUiState } from '../state/AppUiState'
import { uiMaterial } from '@kit.ArkUI'

@ComponentV2
export struct ChatToolbar {
  @Param toolSelectionAvailable: boolean = false
  @Param hasSelectedTools: boolean = false
  @Event onOpenTools: () => void = (): void => {}
  // 当前模型是否支持推理
  @Param reasoningAvailable: boolean = false
  @Param reasoningControlMode: ReasoningControlMode = ReasoningControlMode.NONE
  @Param reasoningXhighAvailable: boolean = false
  // 推理级别状态
  @Param reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  @Event onReasoningLevelChange: (value: ReasoningLevel) => void =
    (_value: ReasoningLevel): void => {}
  @Param knowledgeEnabled: boolean = false
  @Param knowledgeAvailable: boolean = false
  @Event onKnowledgeToggle: (enabled: boolean) => void =
    (_enabled: boolean): void => {}
  // 推理强度滑块面板是否展开
  @Local showReasoningPanel: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private withAlpha(color: string, alphaHex: string): string {
    if (color.startsWith('#') && color.length === 7) {
      return `#${alphaHex}${color.slice(1)}`
    }
    if (color.startsWith('#') && color.length === 9) {
      return `#${alphaHex}${color.slice(3)}`
    }
    return color
  }

  private getToolbarChipBarHeight(): number {
    return 36
  }

  private getToolChipWidth(): number {
    return 68
  }

  private getReasoningChipWidth(): number {
    return 112
  }

  private getKnowledgeChipWidth(): number {
    return 96
  }

  private getToolChipForegroundColor(): ResourceColor {
    return this.hasSelectedTools ? this.themePrimary : $r('app.color.text_secondary')
  }

  private getReasoningChipForegroundColor(): ResourceColor {
    return this.isReasoningEnabled() ? this.themePrimary : $r('app.color.text_secondary')
  }

  private getKnowledgeChipForegroundColor(): ResourceColor {
    if (this.knowledgeEnabled) {
      return this.themePrimary
    }
    return $r('app.color.text_secondary')
  }

  build() {
    Row() {
      if (this.toolSelectionAvailable) {
        this.ToolImmersiveChip()
      }

      if (this.reasoningAvailable) {
        this.ReasoningImmersiveChip()
      }

      this.KnowledgeImmersiveChip()

      Blank()
    }
    .width('100%')
    .height(this.getToolbarChipBarHeight())
    .clip(false)
    .margin({ bottom: 4 })
  }

  @Builder
  private ToolImmersiveChip() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      this.ToolChipContent()
    }
    .width(this.getToolChipWidth())
    .height(this.getToolbarChipBarHeight())
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(Math.min(this.getToolChipWidth(), this.getToolbarChipBarHeight()) / 2)
    .clip(true)
    .onClick(() => {
      this.onOpenTools()
    })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      interactive: true,
      lightEffect: { color: undefined }
    }))
  }

  @Builder
  private ToolChipContent() {
    Row() {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(16)
        .fontColor([this.getToolChipForegroundColor()])

      Text($r('app.string.chat_toolbar_tools'))
        .fontSize(14)
        .fontColor(this.getToolChipForegroundColor())
        .fontWeight(this.hasSelectedTools ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 4 })
    }
    .width(this.getToolChipWidth())
    .height(this.getToolbarChipBarHeight())
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ReasoningImmersiveChip() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      this.ReasoningChipContent()
    }
    .width(this.getReasoningChipWidth())
    .height(this.getToolbarChipBarHeight())
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(Math.min(this.getReasoningChipWidth(), this.getToolbarChipBarHeight()) / 2)
    .clip(true)
    .onClick(() => {
      this.showReasoningPanel = true
    })
    .bindSheet($$this.showReasoningPanel, this.ReasoningSliderSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR
      }),
      preferType: SheetType.BOTTOM,
      onDisappear: (): void => {
        this.showReasoningPanel = false
      }
    })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .margin({ left: this.toolSelectionAvailable ? 6 : 0 })
  }

  @Builder
  private ReasoningChipContent() {
    Row() {
      SymbolGlyph($r('sys.symbol.lightbulb'))
        .fontSize(16)
        .fontColor([this.getReasoningChipForegroundColor()])

      Text($r('app.string.chat_toolbar_reasoning'))
        .fontSize(14)
        .fontColor(this.getReasoningChipForegroundColor())
        .fontWeight(this.isReasoningEnabled() ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 44 })
        .margin({ left: 4 })

      Text(this.getReasoningLevelText(this.reasoningLevel))
        .fontSize(13)
        .fontColor(this.getReasoningChipForegroundColor())
        .fontWeight(this.isReasoningEnabled() ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 34 })
        .margin({ left: 4 })

      SymbolGlyph($r('sys.symbol.chevron_up'))
        .fontSize(12)
        .fontColor([this.getReasoningChipForegroundColor()])
        .margin({ left: 2 })
        .rotate({ angle: this.showReasoningPanel ? 180 : 0 })
        .animation({ duration: 200, curve: Curve.EaseInOut })
    }
    .width(this.getReasoningChipWidth())
    .height(this.getToolbarChipBarHeight())
    .padding({ left: 8, right: 6 })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private KnowledgeImmersiveChip() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row() {
        SymbolGlyph($r('sys.symbol.externaldrive'))
          .fontSize(16)
          .fontColor([this.getKnowledgeChipForegroundColor()])

        Text('知识库')
          .fontSize(14)
          .fontColor(this.getKnowledgeChipForegroundColor())
          .fontWeight(this.knowledgeEnabled ? FontWeight.Medium : FontWeight.Regular)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 4 })

        SymbolGlyph(this.knowledgeEnabled
          ? $r('sys.symbol.checkmark_circle_fill')
          : $r('sys.symbol.xmark_circle_fill'))
          .fontSize(14)
          .fontColor([this.getKnowledgeChipForegroundColor()])
          .margin({ left: 4 })
      }
      .width(this.getKnowledgeChipWidth())
      .height(this.getToolbarChipBarHeight())
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width(this.getKnowledgeChipWidth())
    .height(this.getToolbarChipBarHeight())
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(Math.min(this.getKnowledgeChipWidth(), this.getToolbarChipBarHeight()) / 2)
    .clip(true)
    .enabled(this.knowledgeAvailable)
    .opacity(this.knowledgeAvailable ? 1 : 0.45)
    .onClick(() => {
      if (this.knowledgeAvailable) {
        this.onKnowledgeToggle(!this.knowledgeEnabled)
      }
    })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      interactive: this.knowledgeAvailable,
      lightEffect: { color: undefined }
    }))
    .margin({ left: this.toolSelectionAvailable || this.reasoningAvailable ? 6 : 0 })
  }

  private isReasoningEnabled(): boolean {
    return this.reasoningLevel !== ReasoningLevel.OFF
  }

  private supportsEffortLevels(): boolean {
    return this.reasoningControlMode === ReasoningControlMode.EFFORT
  }

  private supportsHighMaxLevels(): boolean {
    return this.reasoningControlMode === ReasoningControlMode.HIGH_MAX
  }

  // 按当前控制模式返回有序的可选推理级别（用于滑块分档）
  private getReasoningLevelOptions(): ReasoningLevel[] {
    const options: ReasoningLevel[] = [ReasoningLevel.OFF, ReasoningLevel.AUTO]
    if (this.supportsEffortLevels()) {
      options.push(ReasoningLevel.LOW)
      options.push(ReasoningLevel.MEDIUM)
      options.push(ReasoningLevel.HIGH)
      if (this.reasoningXhighAvailable) {
        options.push(ReasoningLevel.XHIGH)
      }
    } else if (this.supportsHighMaxLevels()) {
      options.push(ReasoningLevel.HIGH)
      if (this.reasoningXhighAvailable) {
        options.push(ReasoningLevel.XHIGH)
      }
    }
    return options
  }

  private getReasoningLevelIndex(): number {
    const index = this.getReasoningLevelOptions().indexOf(this.reasoningLevel)
    return index < 0 ? 0 : index
  }

  private getReasoningLevelText(level: ReasoningLevel): ResourceStr {
    switch (level) {
      case ReasoningLevel.AUTO:
        return $r('app.string.reasoning_level_auto')
      case ReasoningLevel.LOW:
        return $r('app.string.reasoning_level_low')
      case ReasoningLevel.MEDIUM:
        return $r('app.string.reasoning_level_medium')
      case ReasoningLevel.HIGH:
        return $r('app.string.reasoning_level_high')
      case ReasoningLevel.XHIGH:
        return $r('app.string.reasoning_level_xhigh')
      default:
        return $r('app.string.reasoning_level_off')
    }
  }

  @Builder
  private ReasoningSliderSheet() {
    Column() {
      this.ReasoningSliderContent()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 12 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private ReasoningSliderContent() {
    Column() {
      // 顶部：图标 + 标题 + 当前档位文案
      Row() {
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(16)
          .fontColor([this.themePrimary])

        Text($r('app.string.chat_toolbar_reasoning'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium)
          .margin({ left: 6 })

        Blank()

        Text(this.getReasoningLevelText(this.reasoningLevel))
          .fontSize(13)
          .fontColor(this.themePrimary)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 分档滑块
      Slider({
        value: this.getReasoningLevelIndex(),
        min: 0,
        max: this.getReasoningLevelOptions().length - 1,
        step: 1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .blockColor(Color.White)
        .selectedColor(this.themePrimary)
        .trackColor(this.withAlpha(this.themeAiBubble, '66'))
        .trackThickness(20)
        .blockSize({ width: 18, height: 18 })
        .showSteps(true)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN
        }))
        .margin({ top: 8, bottom: 2 })
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click ||
            mode === SliderChangeMode.Moving) {
            const options = this.getReasoningLevelOptions()
            const index = Math.round(value)
            const clamped = index < 0 ? 0 : (index >= options.length ? options.length - 1 : index)
            const next = options[clamped]
            if (next !== this.reasoningLevel) {
              this.onReasoningLevelChange(next)
            }
          }
        })

      // 底部档位刻度文案
      Row() {
        ForEach(this.getReasoningLevelOptions(), (level: ReasoningLevel) => {
          Text(this.getReasoningLevelText(level))
            .fontSize(11)
            .fontColor(level === this.reasoningLevel
              ? this.themePrimary : $r('app.color.text_secondary'))
            .fontWeight(level === this.reasoningLevel ? FontWeight.Medium : FontWeight.Regular)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .maxLines(1)
        })
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxWidth: 560 })
    .padding({ left: 20, right: 20, top: 10, bottom: 16 })
    .justifyContent(FlexAlign.Center)
  }
}
