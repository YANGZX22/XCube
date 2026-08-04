import { QuoteImpl } from '../impl/QuoteImpl';
import { TreeNode } from '../model/TreeNode';
import { IntactRender } from './IntactRender';

@Component
export struct BlockquoteRender {
  @Consume markdownUnion: string
  @State base: TreeNode | undefined = undefined

  aboutToAppear(): void {
    this.markQuoteNode(this.base)
  }

  private markQuoteNode(node?: TreeNode) {
    if (!node) {
      return
    }
    if (!node.extend) {
      node.extend = new Map<string, ESObject>()
    }
    node.extend.set("blockquote", true)
    if (!node.children) {
      return
    }
    for (let i = 0; i < node.children.length; i++) {
      this.markQuoteNode(node.children[i] as TreeNode)
    }
  }

  build() {
    if (this.base && this.base.children) {
      Column() {
        IntactRender({ children: this.base.children as TreeNode[] })
      }
      .margin({ top: 5, bottom: 5 })
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .backgroundColor(QuoteImpl.handleBackgroundColor(this.markdownUnion))
      .padding(QuoteImpl.handleQuotePadding(this.markdownUnion))
      .border({
        radius: QuoteImpl.handleBorderRadius(this.markdownUnion),
        color: {
          left: QuoteImpl.handleBorderColor(this.markdownUnion)
        },
        style: {
          left: BorderStyle.Solid
        },
        width: {
          left: QuoteImpl.handleBorderWidth(this.markdownUnion),
          right: '0',
          top: '0',
          bottom: '0'
        }
      })
    }
  }
}
