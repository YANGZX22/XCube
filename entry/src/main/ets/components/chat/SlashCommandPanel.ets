import { uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../../state/AppUiState'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'
import {
  SLASH_COMMAND_CANVAS,
  SLASH_COMMAND_COMPACT,
  SLASH_COMMAND_MODELS,
  SLASH_COMMAND_REASONING,
  SlashCommandItem
} from '../../utils/SlashCommandUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { VisualEffectsMode } from '../../models/ThemeColors'
import { buildModelIconRenderData, ModelIconRenderData } from '../../utils/ModelIconRenderUtils'

// 输入框上方的斜杠命令面板：输入 "/" 时浮出，点选后立即执行对应命令
@ComponentV2
export struct SlashCommandPanel {
  @Param commands: SlashCommandItem[] = []
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param currentModelName: string = ''
  @Event onSelectCommand: (commandId: string) => void = (_commandId: string): void => {}
  @Local pressedCommandId: string = ''

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private getCommandSymbol(commandId: string): Resource {
    if (commandId === SLASH_COMMAND_COMPACT) {
      return $r('sys.symbol.arrow_down_right_and_arrow_up_left')
    }
    if (commandId === SLASH_COMMAND_REASONING) {
      return $r('sys.symbol.lightbulb')
    }
    if (commandId === SLASH_COMMAND_CANVAS) {
      return $r('sys.symbol.paintbrush_pointed_waveform')
    }
    return $r('sys.symbol.bolt')
  }

  private getCurrentModelIcon(): ModelIconRenderData {
    return buildModelIconRenderData(this.currentModelId, this.currentProviderId, this.currentModelName)
  }

  private getCommandTitle(commandId: string): string {
    if (commandId === SLASH_COMMAND_COMPACT) {
      return pickLocalizedText('压缩上下文', 'Compact context')
    }
    if (commandId === SLASH_COMMAND_MODELS) {
      return pickLocalizedText('选择模型', 'Select model')
    }
    if (commandId === SLASH_COMMAND_REASONING) {
      return pickLocalizedText('调整推理强度', 'Adjust reasoning effort')
    }
    if (commandId === SLASH_COMMAND_CANVAS) {
      return pickLocalizedText('打开 Canvas', 'Open Canvas')
    }
    return commandId
  }

  private getRowBackgroundColor(commandId: string): ResourceColor {
    return this.pressedCommandId === commandId
      ? withColorAlpha(this.themeUserBubble, '33') : Color.Transparent
  }

  private getCommandDescription(commandId: string): string {
    if (commandId === SLASH_COMMAND_COMPACT) {
      return pickLocalizedText(
        '把更早的对话压缩成摘要，聊天记录不受影响',
        'Summarize earlier turns; your chat records stay unchanged'
      )
    }
    if (commandId === SLASH_COMMAND_MODELS) {
      return pickLocalizedText('打开当前对话的模型选择面板', 'Open the model picker for this chat')
    }
    if (commandId === SLASH_COMMAND_REASONING) {
      return pickLocalizedText('设置当前模型的推理级别', 'Set the reasoning level for the current model')
    }
    if (commandId === SLASH_COMMAND_CANVAS) {
      return pickLocalizedText('激活并展开当前对话的 Canvas', 'Activate and expand Canvas for this chat')
    }
    return ''
  }

  build() {
    Column() {
      ForEach(this.commands, (command: SlashCommandItem, index: number) => {
        this.CommandRow(command, index)
      }, (command: SlashCommandItem): string => command.id)
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .borderRadius(this.isManuscriptMode ? 0 : 20)
    .border({
      width: this.isManuscriptMode ? { top: 1, bottom: 1 } : 0,
      color: this.isManuscriptMode ? getAppUiState().themeDivider : this.themePrimary
    })
    .clip(!this.isManuscriptMode)
    .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .shadow({
      radius: this.isManuscriptMode ? 0 : 24,
      color: this.isManuscriptMode ? Color.Transparent : 'rgba(0, 0, 0, 0.12)',
      offsetX: 0,
      offsetY: 6
    })
    .margin({ bottom: 8 })
    // 输入 "/" 时从输入框上方浮出，删掉命令时淡出
    .transition(
      TransitionEffect.asymmetric(
        TransitionEffect.translate({ y: 12 }).combine(TransitionEffect.OPACITY),
        TransitionEffect.OPACITY
      ).animation({ duration: 180, curve: Curve.EaseOut })
    )
  }

  @Builder
  private CommandRow(command: SlashCommandItem, index: number) {
    Column() {
      if (index > 0) {
        Divider()
          .strokeWidth(0.5)
          .color(withColorAlpha(this.themeUserBubble, '40'))
          .margin({ left: 52 })
      }

      Row() {
        Column() {
          if (command.id === SLASH_COMMAND_MODELS && this.getCurrentModelIcon().hasIcon()) {
            if (this.getCurrentModelIcon().isRawfile()) {
              Image($rawfile(this.getCurrentModelIcon().resourcePath))
                .width(16)
                .height(16)
                .objectFit(ImageFit.Contain)
                .fillColor(this.themePrimary)
            } else {
              Image(this.getCurrentModelIcon().resourcePath)
                .width(16)
                .height(16)
                .objectFit(ImageFit.Contain)
                .fillColor(this.themePrimary)
            }
          } else {
            SymbolGlyph(command.id === SLASH_COMMAND_MODELS
              ? $r('sys.symbol.ai_edit') : this.getCommandSymbol(command.id))
              .fontSize(16)
              .fontColor([this.themePrimary])
          }
        }
        .width(28)
        .height(28)
        .borderRadius(9)
        .backgroundColor(withColorAlpha(this.themeUserBubble, '40'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column() {
          Row() {
            Text(command.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
              .maxLines(1)

            Text(this.getCommandTitle(command.id))
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 6 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.getCommandDescription(command.id))
            .fontSize(11)
            .lineHeight(16)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
      }
      .width('100%')
      .padding({
        left: 12,
        right: 12,
        top: 10,
        bottom: 10
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.getRowBackgroundColor(command.id))
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedCommandId = command.id
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedCommandId = ''
      }
    })
    .onClick(() => {
      this.pressedCommandId = ''
      this.onSelectCommand(command.id)
    })
  }
}
