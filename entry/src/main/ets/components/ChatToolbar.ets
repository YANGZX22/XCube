/**
 * 聊天工具栏组件
 * 包含工具选择入口、推理开关等功能按钮
 */

import { ReasoningLevel } from '../models/ChatModels'
import { ReasoningControlMode } from '../services/ProviderCompatibilityRegistry'
import { getAppUiState } from '../state/AppUiState'
import { LengthMetrics, uiMaterial } from '@kit.ArkUI'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'
import { VisualEffectsMode } from '../models/ThemeColors'
import { MANUSCRIPT_BODY_FONT, MANUSCRIPT_COMPOSER_TOOLBAR_HEIGHT } from '../utils/ManuscriptVisualUtils'
import { isChineseAppLanguage } from '../utils/LocalizedTextUtils'

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

  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private get manuscriptAccent(): string {
    return getAppUiState().isDarkMode ? '#C99A52' : '#B68235'
  }

  private get manuscriptAccentDeep(): string {
    return getAppUiState().isDarkMode ? '#D9B274' : '#8A6228'
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
    return this.isManuscriptMode ? MANUSCRIPT_COMPOSER_TOOLBAR_HEIGHT : 36
  }

  private getToolChipWidth(): number {
    return isChineseAppLanguage() ? 68 : 76
  }

  private getReasoningChipWidth(): number {
    if (isChineseAppLanguage()) {
      return 112
    }
    if (this.reasoningLevel === ReasoningLevel.MEDIUM || this.reasoningLevel === ReasoningLevel.XHIGH) {
      return 164
    }
    if (this.reasoningLevel === ReasoningLevel.OFF) {
      return 138
    }
    return 148
  }

  private getKnowledgeChipWidth(): number {
    return isChineseAppLanguage() ? 96 : 128
  }

  private getToolChipForegroundColor(): ResourceColor {
    if (this.isManuscriptMode) {
      return this.hasSelectedTools ? this.themePrimary : getAppUiState().themeTextSecondary
    }
    return this.hasSelectedTools ? this.themePrimary : $r('app.color.text_secondary')
  }

  private getReasoningChipForegroundColor(): ResourceColor {
    if (this.isManuscriptMode) {
      return this.isReasoningEnabled() ? this.themePrimary : getAppUiState().themeTextSecondary
    }
    return this.isReasoningEnabled() ? this.themePrimary : $r('app.color.text_secondary')
  }

  private getKnowledgeChipForegroundColor(): ResourceColor {
    if (this.isManuscriptMode) {
      return this.knowledgeEnabled ? this.themePrimary : getAppUiState().themeTextSecondary
    }
    if (this.knowledgeEnabled) {
      return this.themePrimary
    }
    return $r('app.color.text_secondary')
  }

  build() {
    if (this.isManuscriptMode) {
      Scroll() {
        Row({ space: 8 }) {
          if (this.toolSelectionAvailable) {
            this.ToolImmersiveChip()
          }

          if (this.reasoningAvailable) {
            this.ReasoningImmersiveChip()
          }

          this.KnowledgeImmersiveChip()
        }
        .padding(0)
      }
      .width('100%')
      .height(MANUSCRIPT_COMPOSER_TOOLBAR_HEIGHT)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .margin({ bottom: 6 })
    } else {
      Flex({
        wrap: FlexWrap.Wrap,
        space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) }
      }) {
        if (this.toolSelectionAvailable) {
          this.ToolImmersiveChip()
        }

        if (this.reasoningAvailable) {
          this.ReasoningImmersiveChip()
        }

        this.KnowledgeImmersiveChip()
      }
      .width('100%')
      .padding({ left: 2, right: 2, top: 2, bottom: 6 })
      .margin({ bottom: 4 })
    }
  }

  @Builder
  private ToolImmersiveChip() {
    if (this.isManuscriptMode) {
      Stack({ alignContent: Alignment.Center }) {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          this.ToolChipContent()
        }
        .width(this.getToolChipWidth())
        .height(this.getToolbarChipBarHeight())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .border({ width: 0, color: Color.Transparent })
        .onClick(() => {
          this.onOpenTools()
        })
      }
      .width(this.getToolChipWidth())
      .height(this.getToolbarChipBarHeight())
      .backgroundColor(Color.Transparent)
      .borderRadius(this.getToolbarChipBarHeight() / 2)
      .border({
        width: { bottom: 1 },
        color: this.hasSelectedTools ? this.manuscriptAccentDeep : this.manuscriptAccent
      })
    } else {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        this.ToolChipContent()
      }
      .width(this.getToolChipWidth())
      .height(this.getToolbarChipBarHeight())
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(Math.min(this.getToolChipWidth(), this.getToolbarChipBarHeight()) / 2)
      .onClick(() => {
        this.onOpenTools()
      })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
    }
  }

  @Builder
  private ToolChipContent() {
    Row() {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(16)
        .fontColor([this.getToolChipForegroundColor()])

      Text($r('app.string.chat_toolbar_tools'))
        .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : '')
        .fontSize(this.isManuscriptMode ? 11.5 : 14)
        .letterSpacing(this.isManuscriptMode ? (isChineseAppLanguage() ? 1.3 : 0.2) : 0)
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
    if (this.isManuscriptMode) {
      Stack({ alignContent: Alignment.Center }) {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          this.ReasoningChipContent()
        }
        .width(this.getReasoningChipWidth())
        .height(this.getToolbarChipBarHeight())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .border({ width: 0, color: Color.Transparent })
        .onClick(() => {
          this.showReasoningPanel = true
        })
      }
      .width(this.getReasoningChipWidth())
      .height(this.getToolbarChipBarHeight())
      .backgroundColor(Color.Transparent)
      .borderRadius(this.getToolbarChipBarHeight() / 2)
      .border({
        width: { bottom: 1 },
        color: this.isReasoningEnabled() ? this.manuscriptAccentDeep : this.manuscriptAccent
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
    } else {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        this.ReasoningChipContent()
      }
      .width(this.getReasoningChipWidth())
      .height(this.getToolbarChipBarHeight())
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(Math.min(this.getReasoningChipWidth(), this.getToolbarChipBarHeight()) / 2)
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
    }
  }

  @Builder
  private ReasoningChipContent() {
    Row() {
      SymbolGlyph($r('sys.symbol.lightbulb'))
        .fontSize(16)
        .fontColor([this.getReasoningChipForegroundColor()])

      Text($r('app.string.chat_toolbar_reasoning'))
        .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : '')
        .fontSize(this.isManuscriptMode ? 11.5 : 14)
        .letterSpacing(this.isManuscriptMode ? (isChineseAppLanguage() ? 1.3 : 0.2) : 0)
        .fontColor(this.getReasoningChipForegroundColor())
        .fontWeight(this.isReasoningEnabled() ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: isChineseAppLanguage() ? 44 : 72 })
        .margin({ left: 4 })

      Text(this.getReasoningLevelText(this.reasoningLevel))
        .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : '')
        .fontSize(this.isManuscriptMode ? 11 : 13)
        .fontColor(this.getReasoningChipForegroundColor())
        .fontWeight(this.isReasoningEnabled() ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: isChineseAppLanguage() ? 34 : 52 })
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
    if (this.isManuscriptMode) {
      Stack({ alignContent: Alignment.Center }) {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          this.KnowledgeChipContent()
        }
        .width(this.getKnowledgeChipWidth())
        .height(this.getToolbarChipBarHeight())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .border({ width: 0, color: Color.Transparent })
        .enabled(this.knowledgeAvailable)
        .onClick(() => {
          if (this.knowledgeAvailable) {
            this.onKnowledgeToggle(!this.knowledgeEnabled)
          }
        })
      }
      .width(this.getKnowledgeChipWidth())
      .height(this.getToolbarChipBarHeight())
      .backgroundColor(Color.Transparent)
      .borderRadius(this.getToolbarChipBarHeight() / 2)
      .border({
        width: { bottom: 1 },
        color: this.knowledgeEnabled ? this.manuscriptAccentDeep : this.manuscriptAccent
      })
      .opacity(this.knowledgeAvailable ? 1 : 0.45)
    } else {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        this.KnowledgeChipContent()
      }
      .width(this.getKnowledgeChipWidth())
      .height(this.getToolbarChipBarHeight())
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(Math.min(this.getKnowledgeChipWidth(), this.getToolbarChipBarHeight()) / 2)
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
    }
  }

  @Builder
  private KnowledgeChipContent() {
    Row() {
      SymbolGlyph($r('sys.symbol.externaldrive'))
        .fontSize(16)
        .fontColor([this.getKnowledgeChipForegroundColor()])

      Text($r('app.string.tab_knowledge'))
        .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : '')
        .fontSize(this.isManuscriptMode ? 11.5 : 14)
        .letterSpacing(this.isManuscriptMode ? (isChineseAppLanguage() ? 1.3 : 0.2) : 0)
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

  private getReasoningTrackGradient(): LinearGradient {
    return new LinearGradient([
      { color: this.withAlpha(this.themePrimaryLight, '99'), offset: 0 },
      { color: this.withAlpha(this.themePrimary, 'CC'), offset: 1 }
    ])
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
      ImmersiveSheetHeader({
        title: $r('app.string.chat_toolbar_reasoning'),
        onLeadingClick: (): void => {
          this.showReasoningPanel = false
        }
      })

      Column() {
        this.ReasoningSliderContent()
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private ReasoningSliderContent() {
    Column() {
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

      Slider({
        value: this.getReasoningLevelIndex(),
        min: 0,
        max: this.getReasoningLevelOptions().length - 1,
        step: 1,
        style: SliderStyle.InSet,
        direction: Axis.Horizontal
      })
        .width('100%')
        .trackColor(this.withAlpha(this.themeAiBubble, '66'))
        .trackThickness(20)
        .blockSize({ width: 40, height: 40 })
        .blockColor(Color.Transparent)
        .blockBorderColor(Color.Transparent)
        .blockBorderWidth(0)
        .selectedColor(this.getReasoningTrackGradient())
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN
        }))
        .margin({ top: 8, bottom: 4 })
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

      Row() {
        ForEach(this.getReasoningLevelOptions(), (level: ReasoningLevel) => {
          Text(this.getReasoningLevelText(level))
            .fontSize(11)
            .fontColor(level === this.reasoningLevel
              ? this.themePrimary : $r('app.color.text_secondary'))
            .fontWeight(level === this.reasoningLevel ? FontWeight.Medium : FontWeight.Regular)
            .width(40)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .constraintSize({ maxWidth: 560 })
    .padding({ left: 20, right: 20, top: 10, bottom: 16 })
    .justifyContent(FlexAlign.Center)
  }
}
