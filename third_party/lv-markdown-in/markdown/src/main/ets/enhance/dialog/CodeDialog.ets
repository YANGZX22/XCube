import { CodeDialogController } from '../controller/CodeDialogController'
import { MDBaseController } from '../controller/BaseController'
import { CodeBlockImpl } from '../impl/CodeBlockImpl'
import { CodeSourceRender } from '../components/CodeSourceRender'

@Builder
export function CodeDialogBuilder() {
  CodeDialog()
}

@Component
export struct CodeDialog {
  private getMarkdownUnion(): string {
    return CodeDialogController.getInstance().markdownUnion
  }

  private isDarkTheme(): boolean {
    return MDBaseController.getMarkdownController(this.getMarkdownUnion()).getCodeBlockTheme() == "dark"
  }

  private getCodeFontFamily(): ResourceStr {
    return MDBaseController.getMarkdownController(this.getMarkdownUnion()).getCodeBlockFontFamily()
  }

  build() {
    Column() {
      Row() {
        Text(CodeDialogController.getInstance().lang || "code")
          .fontSize(17)
          .fontFamily(this.getCodeFontFamily())
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isDarkTheme() ? "#F9FAFB" : "#cd000000")
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ right: 8 })

        Row({ space: 4 }) {
          Button() {
            if (this.isDarkTheme()) {
              Image($rawfile("imgs/plus_square_on_square_fill_w.png")).width(16.6)
                .interpolation(ImageInterpolation.Medium)
            } else {
              Image($rawfile("imgs/plus_square_on_square_fill_b.png")).width(16.6)
                .interpolation(ImageInterpolation.Medium)
            }
          }
          .backgroundColor(Color.Transparent)
          .width(30)
          .height(30)
          .borderRadius(8)
          .onClick(() => {
            CodeBlockImpl.copyText(this.getMarkdownUnion(), CodeDialogController.getInstance().text)
          })

          Button({ type: ButtonType.Normal }) {
            Text("关闭")
              .fontSize(14)
              .fontColor(this.isDarkTheme() ? "#F9FAFB" : "#303133")
          }
          .backgroundColor(Color.Transparent)
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(8)
          .onClick(() => {
            CodeDialogController.getInstance().closeBindSheet()
          })
        }
      }
      .width("100%")
      .height(56)
      .padding({ left: 16, right: 12 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor(this.isDarkTheme() ? "#24262B" : "#F3F4F6")

      Scroll() {
        CodeSourceRender({
          markdownUnion: this.getMarkdownUnion(),
          text: CodeDialogController.getInstance().text,
          lang: CodeDialogController.getInstance().lang || "code",
          autoCollapse: false,
          selectable: true,
          lineNumberWidth: 42,
          contentBottomPadding: 16
        })
      }
      .layoutWeight(1)
      .width("100%")
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.TopStart)
    }
    .width("100%")
    .height("100%")
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(CodeBlockImpl.handleBackgroundColor(MDBaseController.getMarkdownController(this.getMarkdownUnion())
      .getCodeBlockTheme()))
  }
}
