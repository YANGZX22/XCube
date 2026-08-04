import { TextImpl } from '../impl/TextImpl'
import { UlImpl } from '../impl/UlImpl'
import { TreeNode } from '../model/TreeNode'
import { Logger } from '../utils/Logger'
import { BlockquoteRender } from './BlockquoteRender'
import { OlRender } from './OlRender'
import { ParagraphRender } from './ParagraphRender'
import { TableRender } from './TableRender'
import { TextRender } from './TextRender'

const TAG = "UlRender"

@Component
export struct UlRender {
  @Consume markdownUnion: string
  @State base: TreeNode | undefined = undefined
  @State idxWidth: Length[] = []

  aboutToAppear(): void {
    Logger.info(TAG, "UlRender data > " + JSON.stringify(this.base))

    // 提前设置列表宽度，避免快速渲染时闪屏
    let list = this.base?.children as TreeNode[]
    list?.forEach((item: TreeNode, idx: number) => {
      if (item.type == "listItem" && item.checked !== undefined) {
        let checkBoxSize = UlImpl.handleTodoSelectedSize(this.markdownUnion)
        let size = 0
        if (typeof checkBoxSize == "string") {
          if (checkBoxSize.indexOf("vp")) {
            size = Number(checkBoxSize.trim().split("vp")[0])
          }
          if (checkBoxSize.indexOf("px")) {
            size = px2vp(Number(checkBoxSize.trim().split("px")[0]))
          }
          this.idxWidth.push(UlImpl.handleTodoSelectedSize(this.markdownUnion))
        }
        if (typeof checkBoxSize == "number") {
          size = checkBoxSize
        }
        if (typeof checkBoxSize == "object") {
          this.getUIContext().getHostContext()?.resourceManager.getStringValue(checkBoxSize).then((res) => {
            size = Number(res)
          })
        }
        this.idxWidth.push(size + 12 + 6)
      } else {
        if (idx < 10) {
          this.idxWidth.push(29)
        } else {
          this.idxWidth.push(34)
        }
      }
    })
  }

  build() {
    if (this.base) {
      Column() {
        ForEach(this.base?.children, (item: TreeNode, fIdx: number) => {
          if (item.type == "listItem") {
            Row() {
              Column() {
                if (item.checked !== undefined) {
                  Row() {
                    Stack({ alignContent: Alignment.Center }) {
                      Row()
                        .width(UlImpl.handleTodoSelectedSize(this.markdownUnion))
                        .height(UlImpl.handleTodoSelectedSize(this.markdownUnion))
                        .borderRadius(4)
                        .border({
                          width: 1,
                          color: item.checked ? UlImpl.handleTodoSelectedColor(this.markdownUnion) : '#cc8a8a8a'
                        })
                        .backgroundColor(item.checked ? UlImpl.handleTodoSelectedColor(this.markdownUnion) :
                          Color.Transparent)
                      if (item.checked) {
                        Image($rawfile("imgs/checkmark.png"))
                          .draggable(false)
                          .interpolation(ImageInterpolation.High)
                          .width("68%")
                          .height("68%")
                      }
                    }
                    .width(UlImpl.handleTodoSelectedSize(this.markdownUnion))
                    .height(UlImpl.handleTodoSelectedSize(this.markdownUnion))
                  }
                  .height(TextImpl.handleLineHeight(this.markdownUnion))
                } else {
                  Text() {
                    ImageSpan("")
                      .width(UlImpl.handleUlPointSize(this.markdownUnion))
                      .height(UlImpl.handleUlPointSize(this.markdownUnion))
                      .borderRadius(99)
                      .backgroundColor(UlImpl.handleUlPointColor(this.markdownUnion, item))
                      .offset({ y: -6 })
                  }
                  .margin({ right: 5 })
                  .lineHeight(TextImpl.handleLineHeight(this.markdownUnion))
                }
              }
              .padding({ left: 12 })
              .height(TextImpl.handleLineHeight(this.markdownUnion))
              .justifyContent(FlexAlign.Center)
              .width(this.idxWidth[fIdx])
              .offset({ y: 1 })

              Column() {
                ForEach(item?.children, (item2: TreeNode, idx: number) => {
                  if (item2.type == "paragraph") {
                    ParagraphRender({ base: item2 })
                  } else if (item2.type == "ol") {
                    OlRender({ base: item2 })
                  } else if (item2.type == "ul") {
                    UlRender({ base: item2 })
                  } else if (item2.type == "blockquote") {
                    BlockquoteRender({ base: item2 })
                  } else if (item2.type == "table") {
                    TableRender({ base: item2 })
                  } else {
                    TextRender({ base: item2 })
                  }
                })
              }
              .width(`calc(100% - ${this.idxWidth[fIdx]}vp)`)
              .alignItems(HorizontalAlign.Start)
            }
            .alignItems(VerticalAlign.Top)
          }
        })
      }
      .margin({ top: 4 })
      .width("100%")
      .alignItems(HorizontalAlign.Start)
      .clip(true)
    }
  }
}
