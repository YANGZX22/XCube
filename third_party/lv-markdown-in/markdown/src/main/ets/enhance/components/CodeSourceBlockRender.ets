import { markdownCodeThemeChangeEventName } from '../constant/CodeTheme'
import { CodeDialogController } from '../controller/CodeDialogController'
import { MDBaseController } from '../controller/BaseController'
import { CodeBlockImpl } from '../impl/CodeBlockImpl'
import { CodeSourceRender } from './CodeSourceRender'

@Component
export struct CodeSourceBlockRender {
  @Prop markdownUnion: string = ''
  @Prop lang: string = 'code'
  @Prop text: string = ''
  @Prop autoCollapse: boolean = true
  @Prop selectable: boolean = false
  @Prop lineNumberWidth: number = 34
  @Prop contentBottomPadding: number = 12
  @State themeVersion: number = 0
  private codeThemeListener: (() => void) | null = null

  aboutToAppear(): void {
    this.codeThemeListener = (): void => {
      this.themeVersion++
    }
    getContext().eventHub.on(markdownCodeThemeChangeEventName, this.codeThemeListener)
  }

  aboutToDisappear(): void {
    if (this.codeThemeListener) {
      getContext().eventHub.off(markdownCodeThemeChangeEventName, this.codeThemeListener)
      this.codeThemeListener = null
    }
  }

  private isDarkTheme(): boolean {
    return MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockTheme() == 'dark'
  }

  private getCodeFontFamily(): ResourceStr {
    return MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockFontFamily()
  }

  private openCodeDialog() {
    CodeDialogController.getInstance().openBindSheet(this.markdownUnion, this.lang || 'code', this.text || '')
  }

  build() {
    Column() {
      Row() {
        Text(this.lang || 'code')
          .fontSize(15)
          .fontFamily(this.getCodeFontFamily())
          .fontColor(this.isDarkTheme() ? '#F9FAFB' : '#cd000000')
          .fontWeight(FontWeight.Medium)

        Row({ space: 4 }) {
          Button() {
            if (this.isDarkTheme()) {
              Image($rawfile('imgs/plus_square_on_square_fill_w.png')).width(16.6)
                .syncLoad(true)
                .interpolation(ImageInterpolation.Medium)
            } else {
              Image($rawfile('imgs/plus_square_on_square_fill_b.png')).width(16.6)
                .syncLoad(true)
                .interpolation(ImageInterpolation.Medium)
            }
          }
          .backgroundColor(Color.Transparent)
          .width(30)
          .height(30)
          .borderRadius(8)
          .onClick(() => {
            CodeBlockImpl.copyText(this.markdownUnion, this.text || '')
          })

          Button() {
            if (this.isDarkTheme()) {
              Image($rawfile('imgs/arrow_up_left_and_arrow_down_right_w.png'))
                .width(18)
                .height(18)
                .syncLoad(true)
                .interpolation(ImageInterpolation.Medium)
            } else {
              Image($rawfile('imgs/arrow_up_left_and_arrow_down_right_b.png'))
                .width(18)
                .height(18)
                .syncLoad(true)
                .interpolation(ImageInterpolation.Medium)
            }
          }
          .backgroundColor(Color.Transparent)
          .width(30)
          .height(30)
          .borderRadius(8)
          .onClick(() => {
            this.openCodeDialog()
          })
        }
      }
      .width('100%')
      .padding({
        left: 14,
        right: 10
      })
      .height(44)
      .margin({ bottom: 10 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor(this.isDarkTheme() ? '#24262B' : '#F3F4F6')

      if (this.themeVersion >= 0) {
        CodeSourceRender({
          markdownUnion: this.markdownUnion,
          text: this.text || '',
          lang: this.lang || 'code',
          autoCollapse: this.autoCollapse,
          selectable: this.selectable,
          lineNumberWidth: this.lineNumberWidth,
          contentBottomPadding: this.contentBottomPadding
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(CodeBlockImpl.handleCodeBlockBorderRadius(this.markdownUnion))
    .clip(true)
    .backgroundColor(CodeBlockImpl.handleBackgroundColor(MDBaseController.getMarkdownController(this.markdownUnion)
      .getCodeBlockTheme()))
    .border({
      width: 1,
      color: this.isDarkTheme() ? '#24262B' : '#F3F4F6'
    })
  }
}
