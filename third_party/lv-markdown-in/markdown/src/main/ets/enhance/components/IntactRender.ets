import { IntactImpl } from '../impl/IntactImpl'
import { CodeBlockNode, PluginNode, TableNode, TreeNode } from '../model/TreeNode'
import { BlockquoteRender } from './BlockquoteRender'
import { CodeRender } from './CodeRender'
import { FootnotesRender } from './FootnotesRender'
import { LineRender } from './LineRender'
import { OlRender } from './OlRender'
import { ParagraphRender } from './ParagraphRender'
import { getPluginRenderer, PluginBlockRenderHost } from './PluginRenderHost'
import { TableRender } from './TableRender'
import { TextRender } from './TextRender'
import { UlRender } from './UlRender'

@Component
struct BlockNodeRender {
  @Consume markdownUnion: string
  @Consume pluginUnion: string
  @Prop item: TreeNode | undefined = undefined

  build() {
    if (this.item) {
      if (this.item.type == "hr") {
        LineRender()
      }
      if (this.item.type == "paragraph") {
        ParagraphRender({ base: this.item })
      }
      if (this.item.type == "heading") {
        TextRender({ base: this.item })
      }
      if (this.item.type == "blockquote") {
        BlockquoteRender({ base: this.item })
      }
      if (this.item.type == "ul") {
        UlRender({ base: this.item })
      }
      if (this.item.type == "ol") {
        OlRender({ base: this.item })
      }
      if (this.item.type == "table") {
        TableRender({ base: this.item })
      }
      if (this.item.type == "codeBlock") {
        CodeRender({ base: this.item })
      }
      if (this.item.type == "plugin" && (this.item as PluginNode).display == 'block') {
        if (getPluginRenderer(this.pluginUnion, this.item as PluginNode)) {
          PluginBlockRenderHost({
            node: this.item as PluginNode,
            renderer: getPluginRenderer(this.pluginUnion, this.item as PluginNode)
          })
        } else {
          Text((this.item as PluginNode).raw)
        }
      }
      if (this.item.type == "footnotes") {
        FootnotesRender({ base: this.item })
      }
    }
  }
}

@Component
struct LazyBlockGroupRender {
  @Consume markdownUnion: string
  @Prop groupChildren: TreeNode[] = []
  @Prop eagerRender: boolean = false
  @State private active: boolean = false
  @State private placeholderHeight: number = 64

  aboutToAppear(): void {
    this.placeholderHeight = this.estimateGroupHeight()
    this.active = this.eagerRender
  }

  private shouldRender(): boolean {
    return this.active
  }

  private updateActiveState(isActive: boolean) {
    if (this.active == isActive) {
      return
    }
    this.active = isActive
  }

  private updatePlaceholderHeight(newValue: Area) {
    const height = Number(newValue.height)
    if (height > 0) {
      this.placeholderHeight = height
    }
  }

  private estimateGroupHeight(): number {
    let height = 0
    for (let i = 0; i < this.groupChildren.length; i++) {
      height += this.estimateHeight(this.groupChildren[i])
    }
    return Math.max(64, height)
  }

  private estimateHeight(node: TreeNode | undefined): number {
    if (!node) {
      return 64
    }
    if (node.type == 'heading') {
      return 56
    }
    if (node.type == 'paragraph') {
      return Math.max(56, Math.min(160, 40 + this.estimateTextLength(node) / 8 * 18))
    }
    if (node.type == 'hr') {
      return 20
    }
    if (node.type == 'ul' || node.type == 'ol') {
      return Math.max(48, this.estimateChildCount(node) * 42)
    }
    if (node.type == 'blockquote') {
      return Math.max(72, this.estimateChildCount(node) * 72)
    }
    if (node.type == 'codeBlock') {
      return Math.max(72, (node as CodeBlockNode).text.split('\n').length * 22 + 36)
    }
    if (node.type == 'table') {
      return Math.max(96, ((node as TableNode).rows.length + 1) * 44)
    }
    if (node.type == 'footnotes') {
      return Math.max(64, this.estimateChildCount(node) * 48)
    }
    if (node.type == 'plugin') {
      return 96
    }
    return 64
  }

  private estimateChildCount(node: TreeNode): number {
    if (!node.children) {
      return 1
    }
    return Math.max(1, node.children.length)
  }

  private estimateTextLength(node: TreeNode): number {
    if (node.type == 'text' || node.type == 'inlineCode' || node.type == 'latex') {
      return node.text ? node.text.length : 0
    }
    if (!node.children) {
      return 0
    }
    const children = node.children as TreeNode[]
    let length = 0
    for (let i = 0; i < children.length; i++) {
      length += this.estimateTextLength(children[i])
    }
    return length
  }

  private getNodeRenderKey(item: TreeNode): string {
    return item.renderKey || `${item.type}_${JSON.stringify(item)}`
  }

  build() {
    Column({ space: IntactImpl.handleBlockSpacing(this.markdownUnion) }) {
      if (this.shouldRender()) {
        ForEach(this.groupChildren, (item: TreeNode) => {
          BlockNodeRender({ item })
        }, (item: TreeNode) => this.getNodeRenderKey(item))
      } else {
        Blank()
          .height(this.placeholderHeight)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      if (this.active) {
        this.updatePlaceholderHeight(newValue)
      }
    })
    .onVisibleAreaChange([0.01], (isVisible: boolean, currentRatio: number) => {
      this.updateActiveState(isVisible || currentRatio > 0)
    })
  }
}

@Component
export struct IntactRender {
  @Consume markdownUnion: string
  @Prop children: TreeNode[] = []
  @Prop lazyRender: boolean = false
  @Prop preloadBlockCount: number = 3
  private readonly lazyGroupSize: number = 4

  private getNodeRenderKey(item: TreeNode): string {
    return item.renderKey || `${item.type}_${JSON.stringify(item)}`
  }

  private getLazyGroupStartIndexes(): number[] {
    const indexes: number[] = []
    for (let i = 0; i < this.children.length; i += this.lazyGroupSize) {
      indexes.push(i)
    }
    return indexes
  }

  private getPreloadGroupCount(): number {
    return Math.max(1, Math.ceil(this.preloadBlockCount / this.lazyGroupSize))
  }

  private getLazyGroupChildren(startIndex: number): TreeNode[] {
    return this.children.slice(startIndex, startIndex + this.lazyGroupSize)
  }

  build() {
    Column({ space: IntactImpl.handleBlockSpacing(this.markdownUnion) }) {
      if (this.lazyRender) {
        ForEach(this.getLazyGroupStartIndexes(), (startIndex: number) => {
          LazyBlockGroupRender({
            groupChildren: this.getLazyGroupChildren(startIndex),
            eagerRender: startIndex < this.lazyGroupSize * (this.getPreloadGroupCount() + 1)
          })
        }, (startIndex: number) => `${startIndex}`)
      } else {
        ForEach(this.children, (item: TreeNode) => {
          BlockNodeRender({ item })
        }, (item: TreeNode) => this.getNodeRenderKey(item))
      }
    }
    .alignItems(HorizontalAlign.Start)
  }
}
