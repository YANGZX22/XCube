import { FootnoteImpl } from '../impl/FootnoteImpl';
import { TextImpl } from '../impl/TextImpl';
import { FootnoteNode, TreeNode } from '../model/TreeNode';
import { IntactRender } from './IntactRender';

@Component
export struct FootnotesRender {
  @State base: TreeNode | undefined = undefined

  build() {
    if (this.base?.type == "footnotes" && this.base && this.base.children && this.base.children.length > 0) {
      Column() {
        ForEach(this.base.children, (item: FootnoteNode) => {
          Footnote({ item, base: this.base })
        })
      }
      .margin({ top: 26 })
      .width("100%")
    }
  }
}

@Component
export struct Footnote {
  @Consume markdownUnion: string
  @State base: TreeNode | undefined = undefined
  @State item: FootnoteNode | undefined = undefined
  @State titleWidth: Length = 10

  build() {
    Row() {
      Text() {
        Span(`[${this.item?.id}]`)
        Span("：")
      }
      .fontSize(TextImpl.handleFontSize(this.markdownUnion, this.item, this.base))
      .lineHeight(TextImpl.handleLineHeight(this.markdownUnion, this.base))
      .fontColor(FootnoteImpl.handleFootnoteTextColor(this.markdownUnion))
      .onAreaChange((old, newVal) => {
        this.titleWidth = newVal.width
      })

      IntactRender({ children: this.item?.children || [] })
        .width(`calc(100% - ${this.titleWidth}vp)`)
    }
    .alignItems(VerticalAlign.Top)
    .width("100%")
  }
}