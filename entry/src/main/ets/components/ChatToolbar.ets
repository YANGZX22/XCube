/**
 * 聊天工具栏组件
 * 包含工具选择入口、推理开关等功能按钮
 */

import { ReasoningLevel } from '../models/ChatModels'
import { ReasoningControlMode } from '../services/ProviderCompatibilityRegistry'
import { getAppUiState } from '../state/AppUiState'
import { HdsTabs, DividerMode, hdsMaterial } from '@kit.UIDesignKit'

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

  private getChipBackgroundColor(): string {
    return this.withAlpha(this.themeAiBubble, '33')
  }

  private getToolbarChipBarHeight(): number {
    return 32
  }

  private getToolbarChipContentPadding(): number {
    return 3
  }

  private getToolbarChipContainerHeight(): number {
    return this.getToolbarChipBarHeight() + this.getToolbarChipContentPadding() * 4
  }

  private getToolbarChipContainerWidth(barWidth: number): number {
    return barWidth + this.getToolbarChipContentPadding() * 4
  }

  private getToolChipWidth(): number {
    return 68
  }

  private getReasoningChipWidth(): number {
    return 112
  }

  private getToolChipForegroundColor(): ResourceColor {
    return this.hasSelectedTools ? this.themePrimary : $r('app.color.text_secondary')
  }

  private getReasoningChipForegroundColor(): ResourceColor {
    return this.isReasoningEnabled() ? this.themePrimary : $r('app.color.text_secondary')
  }

  build() {
    Row() {
      if (this.toolSelectionAvailable) {
        this.ToolImmersiveChip()
      }

      if (this.reasoningAvailable) {
        this.ReasoningImmersiveChip()
      }

      Blank()
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
    .margin({ bottom: 2 })
  }

  @Builder
  private ToolImmersiveChip() {
    Stack({ alignContent: Alignment.Center }) {
      HdsTabs() {
        TabContent() {
        }
        .tabBar(this.ToolChipContent())
      }
      .barWidth(this.getToolChipWidth())
      .barHeight(this.getToolbarChipBarHeight())
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barBackgroundColor(Color.Transparent)
      .width(this.getToolChipWidth())
      .height(this.getToolbarChipBarHeight())
      .backgroundColor(Color.Transparent)
      .borderRadius(this.getToolbarChipBarHeight() / 2)
      .clip(false)
      .barFloatingStyle({
        barBottomMargin: 2,
        gradientMask: { maskColor: Color.Transparent },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onTabBarClick(() => {
        this.onOpenTools()
      })

      Row() {
      }
      .size({
        width: this.getToolbarChipContainerWidth(this.getToolChipWidth()),
        height: this.getToolbarChipContainerHeight()
      })
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.Transparent)
      .onClick(() => {
        this.onOpenTools()
      })
    }
    .size({
      width: this.getToolbarChipContainerWidth(this.getToolChipWidth()),
      height: this.getToolbarChipContainerHeight()
    })
    .backgroundColor(Color.Transparent)
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
    .borderRadius(this.getToolbarChipBarHeight() / 2)
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .translate({ y: -4 })
    .animation({ duration: 200, curve: Curve.EaseOut })
  }

  @Builder
  private ReasoningImmersiveChip() {
    Stack({ alignContent: Alignment.Center }) {
      HdsTabs() {
        TabContent() {
        }
        .tabBar(this.ReasoningChipContent())
      }
      .barWidth(this.getReasoningChipWidth())
      .barHeight(this.getToolbarChipBarHeight())
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barBackgroundColor(Color.Transparent)
      .width(this.getReasoningChipWidth())
      .height(this.getToolbarChipBarHeight())
      .backgroundColor(Color.Transparent)
      .borderRadius(this.getToolbarChipBarHeight() / 2)
      .clip(false)
      .barFloatingStyle({
        barBottomMargin: 2,
        gradientMask: { maskColor: Color.Transparent },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onTabBarClick(() => {
      })

      Row() {
      }
      .size({
        width: this.getToolbarChipContainerWidth(this.getReasoningChipWidth()),
        height: this.getToolbarChipContainerHeight()
      })
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.Transparent)
      .onClick(() => {
        this.showReasoningPanel = true
      })
      .bindPopup(this.showReasoningPanel, {
        builder: this.ReasoningSliderPanel(),
        placement: Placement.Top,
        enableArrow: false,
        popupColor: Color.Transparent,
        backgroundBlurStyle: BlurStyle.NONE,
        radius: 0,
        shadow: {
          radius: 0,
          color: Color.Transparent,
          offsetX: 0,
          offsetY: 0
        },
        onStateChange: (event: PopupStateChangeParam) => {
          if (!event.isVisible) {
            this.showReasoningPanel = false
          }
        }
      })
    }
    .size({
      width: this.getToolbarChipContainerWidth(this.getReasoningChipWidth()),
      height: this.getToolbarChipContainerHeight()
    })
    .backgroundColor(Color.Transparent)
    .margin({ left: this.toolSelectionAvailable ? 4 : 0 })
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
    .borderRadius(this.getToolbarChipBarHeight() / 2)
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .translate({ y: -4 })
    .animation({ duration: 200, curve: Curve.EaseOut })
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

  private getReasoningPanelWidth(): number {
    return 280
  }

  private getReasoningPanelHeight(): number {
    return 96
  }

  private getReasoningPanelHaloPadding(): number {
    return 8
  }

  private getReasoningPanelHostWidth(): number {
    return this.getReasoningPanelWidth() + this.getReasoningPanelHaloPadding() * 2
  }

  private getReasoningPanelHostHeight(): number {
    return this.getReasoningPanelHeight() + this.getReasoningPanelHaloPadding() * 2
  }

  // 用 HdsTabs 沉浸浮动条把滑块面板包成与 chip 一致的光感材质
  @Builder
  private ReasoningSliderPanel() {
    Stack({ alignContent: Alignment.Center }) {
      HdsTabs() {
        TabContent() {
        }
        .tabBar(this.ReasoningSliderContent())
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barWidth(this.getReasoningPanelWidth())
      .barHeight(this.getReasoningPanelHeight())
      .width(this.getReasoningPanelWidth())
      .height(this.getReasoningPanelHeight())
      .barBackgroundColor(Color.Transparent)
      .backgroundColor(Color.Transparent)
      .borderRadius(this.getReasoningPanelHeight() / 2)
      .clip(false)
      .divider({ mode: DividerMode.NONE })
      .barFloatingStyle({
        barBottomMargin: 0,
        barSideMargin: 0,
        barWidth: {
          smallWidth: this.getReasoningPanelWidth(),
          mediumWidth: this.getReasoningPanelWidth(),
          largeWidth: this.getReasoningPanelWidth()
        },
        gradientMask: { maskColor: Color.Transparent },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
    }
    .width(this.getReasoningPanelHostWidth())
    .height(this.getReasoningPanelHostHeight())
    .backgroundColor(Color.Transparent)
    .clip(false)
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
        .showSteps(true)
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
    .width(this.getReasoningPanelWidth())
    .height(this.getReasoningPanelHeight())
    .padding({ left: 18, right: 18, top: 10, bottom: 10 })
    .justifyContent(FlexAlign.Center)
  }
}
