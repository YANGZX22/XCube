import { ReplyAnnotation } from '../../models/ReplyAnnotation'
import { getAppUiState } from '../../state/AppUiState'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'
import { WRAPPED_MATERIAL_REGULAR } from '../../utils/WrappedMaterialSupport'
import { ImmersiveFieldSurface } from '../ImmersiveFieldSurface'
import { InteractiveMaterialButton } from '../InteractiveMaterialButton'
import { getSettingsTypography } from '../settings/SettingsTypography'

@ComponentV2
export struct ReplyAnnotationEditor {
  @Require @Param notes: ReplyAnnotation[]
  @Require @Param initialIndex: number
  @Param readOnly: boolean = false
  @Event onSave: (notes: ReplyAnnotation[]) => void = () => {}
  @Event onCancel: () => void = () => {}
  @Local private edits: ReplyAnnotation[] = []
  @Local private index: number = 0

  aboutToAppear(): void {
    this.edits = this.notes.slice()
    this.index = this.initialIndex
  }

  private updateComment(pageIndex: number, comment: string): void {
    const updated = this.edits.slice()
    updated[pageIndex] = { quote: updated[pageIndex].quote, comment: comment }
    this.edits = updated
  }

  @Builder
  private QuotedPassage(pageIndex: number) {
    Text(this.edits[pageIndex].quote)
      .width('100%')
      .fontSize(14)
      .fontColor(getAppUiState().themeTextSecondary)
      .padding({ left: 10 })
      .border({ width: { left: 2 }, color: getAppUiState().themePrimary })
  }

  @Builder
  private PageButton(next: boolean) {
    InteractiveMaterialButton({
      surfaceWidth: 36,
      surfaceHeight: 36,
      buttonType: ButtonType.Circle,
      materialStyle: WRAPPED_MATERIAL_REGULAR,
      applyShadow: true,
      accessibilityLabel: next ? pickLocalizedText('下一处注释', 'Next annotation') :
        pickLocalizedText('上一处注释', 'Previous annotation'),
      isEnabled: next ? this.index < this.edits.length - 1 : this.index > 0,
      onActivate: (): void => { this.index += next ? 1 : -1 }
    }) {
      SymbolGlyph(next ? $r('sys.symbol.chevron_right') : $r('sys.symbol.chevron_left'))
        .fontSize(15)
        .fontColor([getAppUiState().themePrimary])
    }
  }

  @Builder
  private FooterButton(label: Resource, activate: () => void, enabled: boolean = true) {
    Button(label, { buttonStyle: ButtonStyleMode.TEXTUAL })
      .layoutWeight(1)
      .height(42)
      .fontSize(14)
      .fontColor(getAppUiState().themePrimary)
      .enabled(enabled)
      .onClick(activate)
  }

  @Builder
  private AnnotationPage(pageIndex: number) {
    if (this.readOnly) {
      Scroll() {
        Column({ space: 12 }) {
          this.QuotedPassage(pageIndex)
          if (this.edits[pageIndex].comment.trim() !== '') {
            Text(this.edits[pageIndex].comment)
              .width('100%')
              .fontSize(15)
              .fontColor(getAppUiState().themeTextPrimary)
          } else {
            Text(pickLocalizedText('未添加评论', 'No comment'))
              .width('100%')
              .fontSize(14)
              .fontColor(getAppUiState().themeTextSecondary)
          }
        }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 240 })
    } else {
      Scroll() {
        this.QuotedPassage(pageIndex)
      }.width('100%').constraintSize({ maxHeight: 112 })
      ImmersiveFieldSurface() {
        TextArea({ text: this.edits[pageIndex].comment, placeholder: pickLocalizedText('写下评论（可选）', 'Add a comment (optional)') })
          .width('100%')
          .height(80)
          .fontSize(15)
          .fontColor(getAppUiState().themeTextPrimary)
          .backgroundColor(Color.Transparent)
          .padding(12)
          .onChange((value: string): void => this.updateComment(pageIndex, value))
      }
    }
  }

  build() {
    Column({ space: 12 }) {
      Text(pickLocalizedText('回复注释', 'Reply annotations'))
        .font(getSettingsTypography().pageTitle)
        .fontColor(getAppUiState().themeTextPrimary)
      if (this.edits.length > 1) {
        Row({ space: 8 }) {
          this.PageButton(false)
          Text(`${this.index + 1} / ${this.edits.length}`)
            .fontSize(13)
            .fontColor(getAppUiState().themeTextSecondary)
          this.PageButton(true)
        }
      }
      if (this.edits[this.index]) {
        // 每次切页重建选文和输入框，延迟到达的输入事件仍写回原页。
        ForEach([this.index], (pageIndex: number) => {
          this.AnnotationPage(pageIndex)
        }, (pageIndex: number): string => pageIndex.toString())
      }
      Row({ space: 12 }) {
        if (this.readOnly) {
          this.FooterButton($r('app.string.common_done'), this.onCancel)
        } else {
          this.FooterButton($r('app.string.cancel'), this.onCancel)
          this.FooterButton($r('app.string.save'), (): void => this.onSave(this.edits), this.edits.length > 0)
        }
      }.width('100%').clip(false)
    }
    .width('100%')
    .padding(20)
  }
}
