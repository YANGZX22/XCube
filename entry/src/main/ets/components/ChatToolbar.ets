/**
 * 聊天工具栏组件
 * 包含工具选择入口、推理开关等功能按钮
 */

import { ReasoningLevel } from '../models/ChatModels'
import { ReasoningControlMode } from '../services/ProviderCompatibilityRegistry'
import { getAppUiState } from '../state/AppUiState'
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit'

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
      .hitTestBehavior(HitTestMode.Block)
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
      .hitTestBehavior(HitTestMode.Block)
      .bindMenu(this.ReasoningMenuBuilder(), {
        placement: Placement.BottomLeft,
        offset: { x: 0, y: 6 },
        backgroundColor: this.getChipBackgroundColor(),
        backgroundBlurStyle: BlurStyle.COMPONENT_REGULAR
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
  private ReasoningMenuBuilder() {
    Menu() {
      this.ReasoningMenuItem(ReasoningLevel.OFF)
      this.ReasoningMenuItem(ReasoningLevel.AUTO)
      if (this.supportsEffortLevels()) {
        this.ReasoningMenuItem(ReasoningLevel.LOW)
        this.ReasoningMenuItem(ReasoningLevel.MEDIUM)
        this.ReasoningMenuItem(ReasoningLevel.HIGH)
        if (this.reasoningXhighAvailable) {
          this.ReasoningMenuItem(ReasoningLevel.XHIGH)
        }
      } else if (this.supportsHighMaxLevels()) {
        this.ReasoningMenuItem(ReasoningLevel.HIGH)
        if (this.reasoningXhighAvailable) {
          this.ReasoningMenuItem(ReasoningLevel.XHIGH)
        }
      }
    }
  }

  @Builder
  private ReasoningMenuItem(level: ReasoningLevel) {
    if (this.reasoningLevel === level) {
      MenuItem({
        startIcon: $r('sys.symbol.checkmark'),
        content: this.getReasoningLevelText(level)
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.onReasoningLevelChange(level)
        })
    } else {
      MenuItem({
        content: this.getReasoningLevelText(level)
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.onReasoningLevelChange(level)
        })
    }
  }
}
