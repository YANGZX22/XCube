import { TextImpl } from '../impl/TextImpl'
import { TreeNode } from '../model/TreeNode'
import { Logger } from '../utils/Logger'
import { BlockquoteRender } from './BlockquoteRender'
import { ParagraphRender } from './ParagraphRender'
import { TableRender } from './TableRender'
import { TextRender } from './TextRender'
import { UlRender } from './UlRender'

const TAG = "OlRender"

@Component
export struct OlRender {
  @Consume markdownUnion: string
  @State base: TreeNode | undefined = undefined
  @State idxWidth: Length[] = []

  aboutToAppear(): void {
    Logger.info(TAG, "OlRender data > " + JSON.stringify(this.base))

    // 初始化idxWidth数组
    if (this.base?.children) {
      for (let i: number = 0; i < this.base?.children.length || 0; i++) {
        // 初始值设置为40，确保有足够的空间
        this.idxWidth.push(29)
      }
    }
  }

  build() {
    if (this.base) {
      Column() {
        ForEach(this.base?.children, (item: TreeNode, fIdx: number) => {
          if (item.type == "listItem") {
            Row() {
              Column() {
                Text(fIdx + 1 + ". ")
                  .fontSize(TextImpl.handleFontSize(this.markdownUnion))
                  .fontFamily(TextImpl.handleFontFamily(this.markdownUnion, undefined, item))
                  .fontColor(TextImpl.handleFontColor(this.markdownUnion, item))
                  .lineHeight(TextImpl.handleLineHeight(this.markdownUnion))
              }
              .padding({ left: 12 })
              .height(TextImpl.handleLineHeight(this.markdownUnion))
              .justifyContent(FlexAlign.Center)
              .constraintSize({ minWidth: 0, maxWidth: 50 })
              .onAreaChange((oldValue: Area, newValue: Area) => {
                // 动态计算序号的宽度
                const newWidth = Math.ceil(newValue.width as number);
                if (newWidth > this.idxWidth[fIdx]) {
                  this.idxWidth[fIdx] = newWidth;
                }
              })

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
