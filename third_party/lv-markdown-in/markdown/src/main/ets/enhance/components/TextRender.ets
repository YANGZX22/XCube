import { BaseSpanRenderBuilder, SpanRenderBuilder } from '../builders/SpanRenderBuilder';
import { MDBaseController } from '../controller/BaseController';
import { TextSelectionController } from '../controller/TextSelectionController';
import { TextImpl } from '../impl/TextImpl';
import { LatexImpl } from '../impl/LatexImpl';
import { getLatexText, preloadLatexImage } from '../builders/LatexBuilder';
import { LatexNode, PluginNode, TreeNode } from '../model/TreeNode';
import { BlockSelectionStartInfo } from '../model/TextSelectionInfo';
import { buildSelectionSegmentsFromBlock } from '../utils/selectionText';
import { generateRandomString } from '../utils/RandomString';
import {
  getPluginRenderer, PluginInlineRenderHost
} from './PluginRenderHost';
import {
  buildInlinePluginRects,
  buildTextInlinePluginPlacements,
  InlinePluginPlacement,
  InlinePluginRect,
  isSameInlinePluginRects
} from '../utils/inlinePluginOverlay';
import { TextSelectionMouseTracker } from '../utils/TextSelectionMouseUtil';

@Component
export struct TextRender {
  @Consume markdownUnion: string
  @Consume selectionUnion: string
  @Consume pluginUnion: string
  @State @Watch('syncSelectionBlock') base: TreeNode | undefined = undefined
  @State private latexRefreshTick: number = 0
  @State private inlinePluginPlacements: InlinePluginPlacement[] = []
  @State private inlinePluginRects: InlinePluginRect[] = []
  private latexLoadingSet: Set<string> = new Set()
  private textController: TextController = new TextController()
  private selectionId: string = `md_select_${generateRandomString()}`
  private inlinePluginRefreshTimer: number = 0
  private selectionMouseTracker: TextSelectionMouseTracker = new TextSelectionMouseTracker()

  aboutToAppear(): void {
    this.prepareInlinePluginPlacements()
    this.loadTextLatex()
  }

  private prepareInlinePluginPlacements() {
    const placements = buildTextInlinePluginPlacements(this.markdownUnion, this.pluginUnion, this.base)
    if (placements.length == 0 && this.inlinePluginPlacements.length == 0) {
      return
    }
    this.inlinePluginPlacements = placements
  }

  private refreshInlinePluginRects() {
    if (this.inlinePluginPlacements.length == 0) {
      if (this.inlinePluginRects.length > 0) {
        this.inlinePluginRects = []
      }
      return
    }
    try {
      const rects = buildInlinePluginRects(this.textController, this.inlinePluginPlacements, this.getUIContext())
      if (!isSameInlinePluginRects(this.inlinePluginRects, rects)) {
        this.inlinePluginRects = rects
      }
    } catch (_err) {
      if (this.inlinePluginRects.length > 0) {
        this.inlinePluginRects = []
      }
    }
  }

  private refreshInlinePluginRectsSoon() {
    if (this.inlinePluginPlacements.length == 0 || this.inlinePluginRefreshTimer > 0) {
      return
    }
    this.inlinePluginRefreshTimer = setTimeout(() => {
      this.inlinePluginRefreshTimer = 0
      this.refreshInlinePluginRects()
    }, 16)
  }

  private clearInlinePluginRefreshTimer() {
    if (this.inlinePluginRefreshTimer > 0) {
      clearTimeout(this.inlinePluginRefreshTimer)
      this.inlinePluginRefreshTimer = 0
    }
  }

  private handleTextAreaChange(oldValue: Area, newValue: Area) {
    const sizeSame = oldValue.width == newValue.width && oldValue.height == newValue.height
    if (this.inlinePluginPlacements.length == 0 || sizeSame) {
      return
    }
    this.refreshInlinePluginRectsSoon()
  }

  private syncSelectionBlock() {
    TextSelectionController.getInstance(this.selectionUnion)
      .registerBlock(this.selectionId, this.textController, buildSelectionSegmentsFromBlock(this.base))
    this.prepareInlinePluginPlacements()
    this.refreshInlinePluginRectsSoon()
    this.loadTextLatex()
  }

  private collectLatexNodes(node: TreeNode | undefined, nodes: LatexNode[]) {
    if (!node) {
      return
    }
    if (node.type == 'latex') {
      nodes.push(node as LatexNode)
      return
    }
    if (!node.children || node.children.length == 0) {
      return
    }
    for (let i = 0; i < node.children.length; i++) {
      this.collectLatexNodes(node.children[i] as TreeNode, nodes)
    }
  }

  private loadTextLatex() {
    const nodes: LatexNode[] = []
    this.collectLatexNodes(this.base, nodes)
    if (nodes.length == 0) {
      return
    }
    let uiContext: UIContext
    try {
      uiContext = this.getUIContext()
    } catch (_err) {
      return
    }
    const taskList: Promise<void>[] = []
    for (let i = 0; i < nodes.length; i++) {
      const latexText = getLatexText(nodes[i] as ESObject)
      const taskKey = `${this.markdownUnion}_${latexText}`
      if (!latexText || this.latexLoadingSet.has(taskKey)) {
        continue
      }
      this.latexLoadingSet.add(taskKey)
      taskList.push(preloadLatexImage(this.markdownUnion, latexText, uiContext).then(() => {
        this.latexLoadingSet.delete(taskKey)
      }).catch(() => {
        this.latexLoadingSet.delete(taskKey)
      }))
    }
    if (taskList.length > 0) {
      Promise.all(taskList).then(() => {
        this.latexRefreshTick++
        this.refreshInlinePluginRectsSoon()
      })
    }
  }

  private hasLatexNode(node?: TreeNode): boolean {
    if (!node) {
      return false
    }
    if (node.type == 'latex') {
      return true
    }
    if (!node.children || node.children.length == 0) {
      return false
    }
    for (let i = 0; i < node.children.length; i++) {
      if (this.hasLatexNode(node.children[i] as TreeNode)) {
        return true
      }
    }
    return false
  }

  private getTextLineHeight(): ResourceStr | number {
    const lineHeight = TextImpl.handleLineHeight(this.markdownUnion, this.base)
    if (!this.hasLatexNode(this.base)) {
      return lineHeight
    }
    const latexSize = LatexImpl.handleLatexMathTextSize(this.markdownUnion)
    const latexLineHeight = Math.ceil(latexSize * 1.8)
    if (typeof lineHeight === 'number') {
      return Math.max(lineHeight, latexLineHeight)
    }
    return latexLineHeight
  }

  @Builder
  private RenderInlineContent() {
    if (this.base?.type == "text" || this.base?.type == "inlineCode" || this.base?.type == "footnoteRef" ||
      this.base?.type == "inlineHtmlFont") {
      BaseSpanRenderBuilder(this.markdownUnion, this.base)
    } else {
      ForEach(this.base?.children, (item: TreeNode) => {
        SpanRenderBuilder(this.markdownUnion, this.pluginUnion, item, this.getUIContext(), this.latexRefreshTick,
          this.base?.type == "heading" ? this.base : undefined)
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (MDBaseController.getMarkdownController(this.markdownUnion).getTextSelectionEnable()) {
        Text('', { controller: this.textController }) {
          ContainerSpan() {
            this.RenderInlineContent()
          }
        }
        .id(this.selectionId)
        .lineHeight(this.getTextLineHeight())
        .copyOption(TextImpl.handleCopyOption(this.markdownUnion))
        // 只有开启跨 Text 选择复制时才挂载长按手势；否则内部手势会抢占外层用户自定义 LongPressGesture。
        .gesture(
          LongPressGesture()
            .onAction((event: GestureEvent) => {
              if (event.fingerList.length == 0) {
                return
              }
              const finger = event.fingerList[0]
              TextSelectionController.getInstance(this.selectionUnion)
                .triggerStartSelection(new BlockSelectionStartInfo(this.selectionId, finger.localX, finger.localY, true,
                  finger.globalX, finger.globalY))
            })
        )
        .onMouse((event: MouseEvent) => {
          this.selectionMouseTracker.handleBlockSelectionMouseEvent(this.selectionUnion, this.selectionId, event)
        })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.handleTextAreaChange(oldValue, newValue)
        })
      } else {
        Text('', { controller: this.textController }) {
          ContainerSpan() {
            this.RenderInlineContent()
          }
        }
        .id(this.selectionId)
        .lineHeight(this.getTextLineHeight())
        .copyOption(TextImpl.handleCopyOption(this.markdownUnion))
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.handleTextAreaChange(oldValue, newValue)
        })
      }

      if (this.inlinePluginPlacements.length > 0) {
        ForEach(this.inlinePluginRects, (item: InlinePluginRect) => {
          if (getPluginRenderer(this.pluginUnion, item.node)) {
            PluginInlineRenderHost({
              node: item.node,
              renderer: getPluginRenderer(this.pluginUnion, item.node) as (node: PluginNode) => void
            })
              .width(item.width)
              .height(item.height)
              .position({ x: item.left, y: item.top })
              .hitTestBehavior(HitTestMode.Transparent)
              .zIndex(1)
          }
        })
      }
    }
    .id(TextImpl.handleSpanId(this.markdownUnion, this.base))
    .margin({
      top: (this.base?.type == "heading") ? 6 : null,
      bottom: (this.base?.type == "heading") ? 6 : null
    })
    .onAppear(() => {
      this.syncSelectionBlock()
    })
    .onDisAppear(() => {
      this.clearInlinePluginRefreshTimer()
      TextSelectionController.getInstance(this.selectionUnion).unregisterBlock(this.selectionId)
    })
  }
}
