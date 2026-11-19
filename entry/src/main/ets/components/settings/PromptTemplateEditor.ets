import { LengthMetrics } from '@kit.ArkUI'
import { SystemPromptTemplateVariables } from '../../utils/SystemPromptTemplateUtils'
import { IMMERSIVE_MATERIAL_SHADOW_OUTSET } from '../ImmersiveMaterialBackdrop'
import { ImmersiveFieldSurface } from '../ImmersiveFieldSurface'
import { PromptEditorButton } from './PromptEditorButton'
import { getSettingsTypography } from './SettingsTypography'

export interface PromptVariable {
  label: Resource
  token: string
}

export const SYSTEM_PROMPT_VARIABLES: PromptVariable[] = [
  { label: $r('app.string.system_prompt_variable_datetime'), token: SystemPromptTemplateVariables.CURRENT_TIME },
  { label: $r('app.string.system_prompt_variable_date'), token: SystemPromptTemplateVariables.CURRENT_DATE },
  { label: $r('app.string.system_prompt_variable_time'), token: SystemPromptTemplateVariables.CURRENT_CLOCK },
  { label: $r('app.string.system_prompt_variable_weekday'), token: SystemPromptTemplateVariables.CURRENT_WEEKDAY },
  { label: $r('app.string.system_prompt_variable_lunar'), token: SystemPromptTemplateVariables.CURRENT_LUNAR }
]

@ComponentV2
export struct PromptTemplateEditor {
  @Require @Param editorId: string
  @Require @Param text: string
  @Require @Param variables: PromptVariable[]
  @Param placeholder: ResourceStr = ''
  @Param editable: boolean = true
  @Param cornerRadius: number = 16
  @Event onTextChange: (text: string) => void = () => {}

  private controller: TextAreaController = new TextAreaController()
  private focused: boolean = false
  private selection: TextRange | undefined = undefined
  private textAtBlur: string = ''

  private insertVariable(token: string): void {
    if (!this.editable) {
      return
    }
    let range: TextRange | undefined
    if (this.focused) {
      range = this.controller.getSelection()
    } else {
      if (this.text === this.textAtBlur) {
        range = this.selection
      }
      try {
        this.getUIContext().getFocusController().requestFocus(this.editorId)
      } catch (error) {
        console.warn('PromptTemplateEditor', `Cannot focus prompt editor: ${JSON.stringify(error)}`)
        return
      }
    }
    let position: TextContentControllerOptions | undefined
    if (range?.start !== undefined && range.end !== undefined && range.start >= 0 && range.end >= 0) {
      const start = Math.min(range.start, range.end)
      const end = Math.max(range.start, range.end)
      if (end > start) {
        this.controller.deleteText({ start: start, end: end })
      }
      position = { offset: start }
    }
    const caret = this.controller.addText(token, position)
    this.selection = { start: caret, end: caret }
  }

  build() {
    Column() {
      Text($r('app.string.prompt_insert_variable'))
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Start)

      Scroll() {
        Flex({
          wrap: FlexWrap.Wrap,
          justifyContent: FlexAlign.Start,
          alignContent: FlexAlign.Start,
          space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) }
        }) {
          ForEach(this.variables, (variable: PromptVariable) => {
            PromptEditorButton({
              label: variable.label,
              token: variable.token,
              isEnabled: this.editable,
              onActivate: () => this.insertVariable(variable.token)
            })
          }, (variable: PromptVariable): string => variable.token)
        }
        .width('100%')
        .clip(false)
      }
      // 滚动边界包含阴影留白，按钮仍与编辑框的左边缘对齐。
      .width(`calc(100% + ${IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2}vp)`)
      .padding(IMMERSIVE_MATERIAL_SHADOW_OUTSET)
      .margin({ left: -IMMERSIVE_MATERIAL_SHADOW_OUTSET, right: -IMMERSIVE_MATERIAL_SHADOW_OUTSET })
      .clipContent(ContentClipMode.BOUNDARY)
      .clip(false)
      .align(Alignment.TopStart)
      .constraintSize({ maxHeight: `calc(45% + ${IMMERSIVE_MATERIAL_SHADOW_OUTSET}vp)` })
      .scrollBar(BarState.Auto)

      ImmersiveFieldSurface({ cornerRadius: this.cornerRadius, fillHeight: true, layoutWeightValue: 1 }) {
        TextArea({ text: this.text, controller: this.controller, placeholder: this.placeholder })
          .id(this.editorId)
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .textAlign(TextAlign.Start)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .padding(16)
          .borderRadius(this.cornerRadius)
          .enabled(this.editable)
          .onChange((value: string) => this.onTextChange(value))
          .onFocus(() => { this.focused = true })
          .onBlur(() => {
            this.focused = false
            this.textAtBlur = this.text
          })
          .onTextSelectionChange((start: number, end: number) => {
            if (this.focused) {
              this.selection = { start: start, end: end }
            }
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .clip(false)
    .opacity(this.editable ? 1 : 0.5)
  }
}
