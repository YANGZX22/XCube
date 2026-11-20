import { MarkdownController } from './controller/MarkdonwController';
import { MarkdownPluginRegistry } from './controller/PluginRegistry';
import { TextSelectionController } from './controller/TextSelectionController';
import { TableNode, TreeNode } from './model/TreeNode';

import { MarkdownPlugin, toPluginSyntaxManifestList } from './model/MarkdownPlugin';
import { MdCallback } from './model/MdCallback';
import { Logger } from './utils/Logger';
import {
  WorkerParam,
  WorkerParseReq,
  WorkerResTextParam,
  WorkerStringResp,
  WorkerTreeNodeResp
} from './model/WorkerParam';
import { IntactRender } from './components/IntactRender';
import { MainReader } from './mainThreadReader/reater';
import { BusinessError } from '@kit.BasicServicesKit';
import { WorkerManager } from './worker/WorkerManager';
import { generateRandomString } from './utils/RandomString';
import { getLatexText, preloadLatexImage } from './builders/LatexBuilder';
import { common2D } from '@kit.ArkGraphics2D';
import text from '@ohos.graphics.text';
import { BlockSelectionStartInfo, CaretInfo, LongPressMenuInfo, LongPressSelectionType, RegisteredTextBlock, SelectedTextInfo, SelectionHighlightRect, TextSelectionActionContext, TextSelectionActionItem } from './model/TextSelectionInfo';
import { componentUtils, FrameCallback, Magnifier } from '@kit.ArkUI';
import { clearActiveTextSelectionMouseTracker, isPrimaryMouseButton } from './utils/TextSelectionMouseUtil';

const TAG = "LV-MARKDOWN-IN"

class SelectionDragFrame extends FrameCallback {
  private flush: () => void

  constructor(flush: () => void) {
    super()
    this.flush = flush
  }

  onFrame(_time: number): void { this.flush() }
}

/**
 * 承载 Markdown 内容渲染的组件。
 *
 * @controller 通过 MarkdownController 可以控制 Markdown 组件各种行为，如：自定义样式、设置图片点击拦截、设置超链接点击拦截等。
 * @text markdown 文本内容。
 * @mode Markdown 组件加载模式，支持纯文本加载、沙箱文件加载、资源文件加载，不填默认为 "text"。
 * @context mode 字段设置为 rawfile 时， context 为必填项。
 * @rawfilePath mode 字段设置为 rawfile 时， rawfilePath 为必填项，需传入 resources/rawfile 目录下对应的 rawfile 文件路径。
 * @sandboxPath mode 字段设置为 sandbox 时， sandboxPath 为必填项，需传入沙箱 text/md 文件的完整沙箱路径。例：getContext().getApplicationContext().filesDir + "/t2/text.md"。
 * @call callback回调方法，Markdown 组件加载状态结果告知。用于组件加载完成时，组件加载失败时回调，并返回错误码 code，错误信息 message，可用于问题分析。
 */
@Component
export struct Markdown {
  controller: MarkdownController = new MarkdownController()
  // 每次返回新的原生菜单配置，供组件补充定位及生命周期；库不依赖应用的主题或材质逻辑。
  selectionMenuOptions: () => MenuOptions = (): MenuOptions => ({})
  @Provide markdownUnion: string = ""
  @Provide selectionUnion: string = generateRandomString()
  @Provide pluginUnion: string = generateRandomString()
  /** 纯文本数据，mode：text */
  @Prop @Watch("_parseMarkdown") text: string = "";
  plugins: MarkdownPlugin[] = []
  /** 加载模式：
   * text：纯文本模式
   * rawfile：rawfile资源文件模式
   * sandbox：本地沙箱路径文件模式
   */
  @Prop mode: "text" | "rawfile" | "sandbox" = "text";
  /**
   * 资源文件path
   */
  @Prop rawfilePath: string
  /**
   * 沙箱文件path
   */
  @Prop sandboxPath: string
  /**
   * 应用上下文
   */
  context: Context | undefined = undefined
  /**
   * 增强node集合
   */
  @State private treeNode: TreeNode[] = []
  private startCaretInfo: CaretInfo = new CaretInfo()
  private endCaretInfo: CaretInfo = new CaretInfo()
  private selectedTextInfos: SelectedTextInfo[] = []
  @State private selectionActive: boolean = false
  @State private selectionActionBarVisible: boolean = false
  @State private startCaretX: number = -100
  @State private startCaretY: number = -100
  @State private endCaretX: number = -100
  @State private endCaretY: number = -100
  private selectedRangeStartOrder: number = -1
  private selectedRangeEndOrder: number = -1
  private pendingDrag: boolean = false
  private dragFramePosted: boolean = false
  private dragX: number = 0
  private dragY: number = 0
  private dragStartCaret: boolean = false
  private dragMagnifier?: Magnifier
  private magnifiedBlockId: string = ''
  private dragFrame: SelectionDragFrame = new SelectionDragFrame(() => {
    this.dragFramePosted = false
    this.flushCaretDrag()
  })
  private readonly initialSelectionLength: number = 3
  private selectionItemWidths: Map<string, number> = new Map()
  private getSelectionActionBarWidth(): number {
    const items = this.controller.getTextSelectionActionItems()
    const desired = items.length === 0 ? 188 : items.reduce((width: number, item: TextSelectionActionItem) =>
      width + this.selectionItemWidth(item.title), 8)
    return this.selectionLayerWidth > 16 ? Math.min(desired, this.selectionLayerWidth - 16) : desired
  }

  private selectionItemWidth(title: string): number {
    const context = this.getUIContext()
    const key = `${context.fp2px(14)}|${title}`
    const cached = this.selectionItemWidths.get(key)
    if (cached !== undefined) return cached
    const size = context.getMeasureUtils().measureTextSize({ textContent: title, fontSize: 14 })
    const width = Math.max(60, Math.ceil(context.px2vp(Number(size.width))) + 16)
    this.selectionItemWidths.set(key, width)
    return width
  }
  private readonly selectionActionBarHeight: number = 40
  private readonly selectionActionBarSpacing: number = 12
  private readonly selectionActionBarEdgeInset: number = 8
  private mouseSelecting: boolean = false
  private mouseSelectionDragged: boolean = false
  private mouseSelectionStartGlobalX: number = 0
  private mouseSelectionStartGlobalY: number = 0
  private readonly mouseSelectionDragThreshold: number = 2
  private suppressSelectionOverlayClick: boolean = false
  private workerManager: WorkerManager = WorkerManager.getInstance();
  private workerUnion: string = generateRandomString()
  private workerRegistered: boolean = false
  private parseRequestId: number = 0
  // latest-wins 解析闸门: 同一组件同一时刻只允许一个解析在途。
  // worker 解析不可中断, 流式每 token 全量重解析会让被新 token 超越的中间态白烧 CPU;
  // 在途时新文本只记 pendingParse, 待结果返回后用最新 this.text 再发一次。
  private parseInFlight: boolean = false
  private pendingParse: boolean = false
  private treeNodeSignatures: string[] = []
  private selectionRootId: string = `md_selection_root_${generateRandomString()}`
  // 选区高亮改为声明式叠层(一组定位矩形), 与手柄走同一渲染管线 → 同帧提交, 高亮不再尾随手柄;
  // 取代原 Canvas(独立画布提交晚一帧 + 每帧 reset 整张"内容尺寸"画布的开销)。
  @State private selectionRectList: SelectionHighlightRect[] = []
  private selectionRootInfo?: componentUtils.ComponentInfo
  @State private selectionMenuPosition: Position = { x: 0, y: 0 }
  @State private selectionLayerWidth: number = 0
  @State private selectionLayerHeight: number = 0
  /**
   * 事件回调
   */
  callback: MdCallback = {
    complete() {
    },
    fail(code: number, message: string) {
    }
  }

  private baseCallback(type: "success" | "fail", code?: number, message?: string) {
    if (type == "success") {
      if (this.callback.complete) {
        this.callback?.complete()
      }
    }
    if (type == "fail") {
      if (this.callback.fail && code && message) {
        this.callback?.fail(code, message)
      }
    }
  }

  aboutToAppear(): void {
    Logger.infoForce(TAG, "Thank you for using.")
    this.markdownUnion = this.controller.getUnion()
    this.registerPlugins()
    TextSelectionController.getInstance(this.selectionUnion)
      .setStartSelectionHandler((info: BlockSelectionStartInfo) => {
        this.startSelection(info)
      })
    TextSelectionController.getInstance(this.selectionUnion)
      .setUpdateSelectionHandler((globalX: number, globalY: number) => {
        this.updateSelectionByMouse(globalX, globalY)
      })
    TextSelectionController.getInstance(this.selectionUnion)
      .setEndSelectionHandler((x: number, y: number) => {
        this.endSelectionByMouse(x, y)
      })
    TextSelectionController.getInstance(this.selectionUnion)
      .setClearSelectionHandler(() => {
        this.clearSelection()
      })
    this.ensureWorkerRegistered()
    this.handleLodeType()
  }

  aboutToDisappear(): void {
    this.pendingDrag = false
    this.releaseMagnifier()
    MarkdownPluginRegistry.destroy(this.pluginUnion)
    if (this.workerRegistered) {
      this.workerManager.unregister(this.workerUnion)
      this.workerRegistered = false
    }
    TextSelectionController.getInstance(this.selectionUnion).setStartSelectionHandler(undefined)
    TextSelectionController.getInstance(this.selectionUnion).setUpdateSelectionHandler(undefined)
    TextSelectionController.getInstance(this.selectionUnion).setEndSelectionHandler(undefined)
    TextSelectionController.getInstance(this.selectionUnion).setClearSelectionHandler(undefined)
    TextSelectionController.getInstance(this.selectionUnion).releaseActiveSelection()
    TextSelectionController.destroy(this.selectionUnion)
    // 公式图片缓存改为 LRU/FIFO 自动管理（见 LatexUtil.saveCache，上限 128），
    // 不在单实例卸载时清空，避免一个气泡划出列表就清掉其他存活气泡的公式缓存导致滚动闪烁。
    // MDBaseController.destroyMarkdownUnion(this.markdownUnion)
  }

  private clearSelection() {
    this.pendingDrag = false
    this.releaseMagnifier()
    this.selectionRootInfo = undefined
    this.selectionActive = false
    this.selectionActionBarVisible = false
    clearActiveTextSelectionMouseTracker()
    TextSelectionController.getInstance(this.selectionUnion).releaseActiveSelection()
    this.startCaretInfo.reset()
    this.endCaretInfo.reset()
    this.startCaretX = -100
    this.startCaretY = -100
    this.endCaretX = -100
    this.endCaretY = -100
    this.selectedRangeStartOrder = -1
    this.selectedRangeEndOrder = -1
    this.mouseSelecting = false
    this.mouseSelectionDragged = false
    this.suppressSelectionOverlayClick = false
    this.selectedTextInfos = []
    this.selectionRectList = []
  }

  private hasSelectionState(): boolean {
    return this.selectionActive ||
      this.selectionActionBarVisible ||
      this.selectedTextInfos.length > 0 ||
      this.selectedRangeStartOrder >= 0 ||
      this.selectedRangeEndOrder >= 0
  }

  private shouldUseLazyRender(): boolean {
    return this.controller.getLazyRender() && !this.controller.getTextSelectionEnable()
  }

  private registerPlugins() {
    MarkdownPluginRegistry.registerPlugins(this.pluginUnion, this.plugins || [])
  }

  private ensureWorkerRegistered() {
    if (!this.controller.getThreadRenderEnable() || this.workerRegistered) {
      return
    }
    this.workerManager.register(this.workerUnion, (message) => {
      this.handleWorkerMessage(message);
    })
    this.workerRegistered = true
  }

  private handleWorkerMessage(message: WorkerTreeNodeResp | WorkerStringResp) {
    if (message.union !== this.workerUnion) {
      return;
    }

    if (message.key == "readerRawfile") {
      let data = message as WorkerStringResp;
      Logger.info(TAG, 'workerInstance onmessage is: ', data.data);
      this.text = data.data
      this._parseMarkdown()
    }
    if (message.key == "readerSandbox") {
      let data = message as WorkerStringResp;
      Logger.info(TAG, 'workerInstance onmessage is: ', data.data);
      this.text = data.data
      this._parseMarkdown()
    }
    if (message.key == "parse") {
      let data = message as WorkerTreeNodeResp;
      // 过期结果(requestId 不匹配)或解析出错(error)都不渲染, 但仍必须 onParseSettled 释放 in-flight 闸门,
      // 否则 parseInFlight 卡死会让后续解析永远进 pendingParse 分支、渲染冻结。
      const isStaleParse = !!data.requestId && data.requestId != this.parseRequestId
      if (!isStaleParse && !data.error) {
        this.renderTreeNodeWithLatex(data.data, data.requestId || this.parseRequestId)
      }
      this.onParseSettled()
    }
  }

  private collectLatexTexts(node: TreeNode, latexTextSet: Set<string>) {
    if (node.type == 'latex') {
      const latexText = getLatexText(node as ESObject)
      if (latexText) {
        latexTextSet.add(latexText)
      }
      return
    }

    if (node.type == 'table') {
      const tableNode = node as TableNode
      if (tableNode.header) {
        for (let i = 0; i < tableNode.header.length; i++) {
          this.collectLatexTexts(tableNode.header[i] as TreeNode, latexTextSet)
        }
      }
      if (tableNode.rows) {
        for (let i = 0; i < tableNode.rows.length; i++) {
          this.collectLatexTexts(tableNode.rows[i] as TreeNode, latexTextSet)
        }
      }
      return
    }

    if (!node.children || node.children.length == 0) {
      return
    }
    for (let i = 0; i < node.children.length; i++) {
      this.collectLatexTexts(node.children[i] as TreeNode, latexTextSet)
    }
  }

  private preloadTreeLatex(treeNodes: TreeNode[]): Promise<void> {
    if (!treeNodes || treeNodes.length == 0) {
      return Promise.resolve()
    }

    const latexTextSet: Set<string> = new Set()
    for (let i = 0; i < treeNodes.length; i++) {
      this.collectLatexTexts(treeNodes[i], latexTextSet)
    }
    if (latexTextSet.size == 0) {
      return Promise.resolve()
    }

    let uiContext: UIContext
    try {
      uiContext = this.getUIContext()
    } catch (_err) {
      return Promise.resolve()
    }

    const taskList: Promise<void>[] = []
    latexTextSet.forEach((latexText: string) => {
      taskList.push(preloadLatexImage(this.markdownUnion, latexText, uiContext).then(() => {
      }).catch(() => {
      }))
    })

    return Promise.all(taskList).then(() => {
    })
  }

  private getTreeNodeSignature(node: TreeNode): string {
    const renderKey = node.renderKey
    node.renderKey = undefined
    const signature = JSON.stringify(node)
    node.renderKey = renderKey
    return signature
  }

  private prepareStableTreeNodes(treeNodes: TreeNode[]): TreeNode[] {
    const previousTreeNodes = this.treeNode
    const previousSignatures = this.treeNodeSignatures
    const nextSignatures: string[] = []
    const stableTreeNodes: TreeNode[] = []
    const now = Date.now()

    for (let i = 0; i < treeNodes.length; i++) {
      const signature = this.getTreeNodeSignature(treeNodes[i])
      nextSignatures.push(signature)
      if (i < previousTreeNodes.length && previousSignatures[i] == signature) {
        stableTreeNodes.push(previousTreeNodes[i])
      } else {
        treeNodes[i].renderKey = `${i}_${now}`
        stableTreeNodes.push(treeNodes[i])
      }
    }

    this.treeNodeSignatures = nextSignatures
    return stableTreeNodes
  }

  private applyTreeNode(treeNodes: TreeNode[]) {
    const stableTreeNodes = this.prepareStableTreeNodes(treeNodes)
    if (this.hasSelectionState()) {
      this.clearSelection()
    }
    this.treeNode = stableTreeNodes
    Logger.info(TAG, "treeNode data prepared. length: " + this.treeNode.length)
  }

  private renderTreeNodeWithLatex(treeNodes: TreeNode[], requestId: number) {
    this.preloadTreeLatex(treeNodes).then(() => {
      if (requestId == this.parseRequestId) {
        this.applyTreeNode(treeNodes)
      }
    }).catch(() => {
      if (requestId == this.parseRequestId) {
        this.applyTreeNode(treeNodes)
      }
    })
  }

  private handleLodeType() {
    if (this.mode == "text") {
      this._parseMarkdown()
    }
    if (this.mode == "rawfile") {
      this._loadRawfile()
    }
    if (this.mode == "sandbox") {
      this._loadSandbox()
    }
  }

  // 1
  private _loadRawfile() {
    if (!this.rawfilePath) {
      this.baseCallback("fail", 50011, "The rawfile resource file is incorrect.")
      return
    }
    if (!this.context) {
      this.baseCallback("fail", 50030, "The context is incorrect.")
      return
    }
    let r: WorkerResTextParam = { ctx: this.context, rawfilePath: this.rawfilePath }
    let handleTask: WorkerParam = {
      key: "readerRawfile",
      data: r,
      union: this.workerUnion
    }
    if (this.controller.getThreadRenderEnable()) {
      this.ensureWorkerRegistered()
      // 发送消息给Worker线程
      this.workerManager.postMessage(handleTask);
    } else {
      MainReader.reader(handleTask).then(res => {
        // 确保返回的结果包含正确的union
        if (res.union === this.workerUnion) {
          this.text = res.data as string
          this._parseMarkdown()
        }
      })
        .catch((err: BusinessError) => {

        })
    }
  }

  // 2
  private _loadSandbox() {
    if (!this.sandboxPath) {
      this.baseCallback("fail", 50021, "The sandbox file is incorrect.")
      return
    }
    let handleTask: WorkerStringResp = {
      key: "readerSandbox",
      data: this.sandboxPath,
      union: this.workerUnion
    }
    if (this.controller.getThreadRenderEnable()) {
      this.ensureWorkerRegistered()
      // 发送消息给Worker线程
      this.workerManager.postMessage(handleTask);
    } else {
      MainReader.reader(handleTask).then(res => {
        // 确保返回的结果包含正确的union
        if (res.union === this.workerUnion) {
          this.text = res.data as string
          this._parseMarkdown()
        }
      })
        .catch((err: BusinessError) => {

        })
    }
  }

  private onParseSettled() {
    this.parseInFlight = false
    if (this.pendingParse) {
      this.pendingParse = false
      this._parseMarkdown()
    }
  }

  private _parseMarkdown() {
    Logger.info(TAG, "_parseMarkdown")
    this.registerPlugins()
    // latest-wins: 已有解析在途时不再 postMessage(worker 不可中断, 中间态会白烧 CPU),
    // 只记 pendingParse, 在途解析返回(onParseSettled)后再用最新 this.text 重发一次。
    if (this.parseInFlight) {
      this.pendingParse = true
      return
    }
    this.parseInFlight = true
    this.pendingParse = false
    const requestId = ++this.parseRequestId
    let handleTask: WorkerParseReq = {
      key: "parse",
      data: {
        text: this.text?.toString() ?? "",
        plugins: toPluginSyntaxManifestList(this.plugins),
        parseOptions: {
          setextHeading: this.controller.getSetextHeadingEnable()
        }
      },
      union: this.workerUnion,
      requestId: requestId
    }
    if (this.controller.getThreadRenderEnable()) {
      this.ensureWorkerRegistered()
      // 发送消息给Worker线程
      this.workerManager.postMessage(handleTask);
    } else {
      MainReader.reader(handleTask).then(res => {
        // 确保返回的结果包含正确的union
        const parseResp = res as WorkerTreeNodeResp
        if (parseResp.union === this.workerUnion && parseResp.requestId == this.parseRequestId) {
          this.renderTreeNodeWithLatex(parseResp.data, parseResp.requestId || requestId)
        }
        this.onParseSettled()
      })
        .catch((err: BusinessError) => {
          this.onParseSettled()
        })
    }
  }

  private getTextIndex(localX: number, localY: number, layout: LayoutManager, length: number): number {
    const context = this.getUIContext()
    const hit = layout.getGlyphPositionAtCoordinate(context.vp2px(localX), context.vp2px(localY))
    return Math.max(0, Math.min(hit.position, length))
  }

  private getLayoutTextLength(layout: LayoutManager): number {
    const lines = layout.getLineCount()
    return lines > 0 ? layout.getLineMetrics(lines - 1).endIndex + 1 : 0
  }

  private getRectsForRange(start: number, end: number, layoutManager: LayoutManager): common2D.Rect[] {
    return layoutManager.getRectsForRange({ start, end }, text.RectWidthStyle.TIGHT,
      text.RectHeightStyle.TIGHT).map((item): common2D.Rect => {
      return {
        left: this.getUIContext().px2vp(item.rect.left),
        right: this.getUIContext().px2vp(item.rect.right),
        top: this.getUIContext().px2vp(item.rect.top),
        bottom: this.getUIContext().px2vp(item.rect.bottom)
      }
    })
  }

  private getCaretInfo(globalX: number, globalY: number, info: CaretInfo) {
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    const hit = registry.getBlockInfoByPoint(globalX, globalY, info.blockOrder)
    if (!hit) {
      if (this.magnifiedBlockId) {
        this.dragMagnifier?.unbind()
        this.magnifiedBlockId = ''
      }
      return false
    }
    const localX = globalX - px2vp(hit.info.screenOffset.x)
    const localY = globalY - px2vp(hit.info.screenOffset.y)
    if (this.dragMagnifier) {
      if (this.magnifiedBlockId !== hit.block.id) {
        this.dragMagnifier.bind(hit.block.id)
        this.magnifiedBlockId = hit.block.id
      }
      this.dragMagnifier.show(Math.max(0, Math.min(localX, px2vp(hit.info.size.width))),
        Math.max(0, Math.min(localY, px2vp(hit.info.size.height))))
    }
    const layoutManager = hit.block.controller.getLayoutManager()
    const layoutLength = this.getLayoutTextLength(layoutManager)
    const caretIndex = this.getTextIndex(localX, localY, layoutManager, layoutLength)
    info.blockOrder = hit.block.order
    info.caretIndex = Math.max(0, Math.min(caretIndex, layoutLength))
    return true
  }

  private buildSelectedTextInfo(order: number, start: CaretInfo, end: CaretInfo,
    registry: TextSelectionController, previous?: SelectedTextInfo): SelectedTextInfo | undefined {
    const block: RegisteredTextBlock | undefined = registry.getBlockByOrder(order)
    if (!block) {
      return undefined
    }
    try {
      const blockInfo = registry.getBlockRect(block.id)
      if (!blockInfo) {
        return undefined
      }
      const layoutManager = block.controller.getLayoutManager()
      const layoutLength = this.getLayoutTextLength(layoutManager)
      const startIndex = order == start.blockOrder ? start.caretIndex : 0
      const endIndex = order == end.blockOrder ? end.caretIndex : layoutLength
      const rangeStart = Math.max(0, Math.min(startIndex, layoutLength))
      const rangeEnd = Math.max(rangeStart, Math.min(endIndex, layoutLength))
      if (previous && previous.block === block && previous.componentInfo === blockInfo &&
        previous.startIndex === rangeStart && previous.endIndex === rangeEnd) {
        return previous
      }
      const rects = this.getRectsForRange(rangeStart, rangeEnd, layoutManager)
      return new SelectedTextInfo(block, blockInfo, rects, rangeStart, rangeEnd)
    } catch (_err) {
      return undefined
    }
  }

  private rebuildSelectedTextInfos(start: CaretInfo, end: CaretInfo, registry: TextSelectionController) {
    const nextInfos: SelectedTextInfo[] = []
    for (let i = start.blockOrder; i <= end.blockOrder; i++) {
      const info = this.buildSelectedTextInfo(i, start, end, registry)
      if (info) {
        nextInfos.push(info)
      }
    }
    this.selectedTextInfos = nextInfos
    if (nextInfos.length == end.blockOrder - start.blockOrder + 1) {
      this.selectedRangeStartOrder = start.blockOrder
      this.selectedRangeEndOrder = end.blockOrder
    } else {
      this.selectedRangeStartOrder = -1
      this.selectedRangeEndOrder = -1
    }
  }

  private updateSelectedTextInfoAtOrder(order: number, info: SelectedTextInfo | undefined) {
    if (!info) {
      return
    }
    const index = order - this.selectedRangeStartOrder
    if (index < 0 || index >= this.selectedTextInfos.length) {
      return
    }
    this.selectedTextInfos[index] = info
  }

  private refreshSelectedTextInfosComponentInfo(registry: TextSelectionController) {
    for (let i = 0; i < this.selectedTextInfos.length; i++) {
      // 拖动开始时已清空布局缓存，同一次拖动内复用块位置。
      const blockInfo = registry.getBlockRect(this.selectedTextInfos[i].block.id)
      if (blockInfo) {
        this.selectedTextInfos[i].componentInfo = blockInfo
      }
    }
  }

  private collectSelectedTextInfos(start: CaretInfo, end: CaretInfo) {
    const rootInfo = this.selectionRootInfo ?? componentUtils.getRectangleById(this.selectionRootId)
    this.selectionRootInfo = rootInfo
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    const expectedCount = end.blockOrder - start.blockOrder + 1
    const canIncrementallyUpdate = this.selectedTextInfos.length > 0 &&
      this.selectedRangeStartOrder >= 0 &&
      this.selectedRangeEndOrder >= this.selectedRangeStartOrder &&
      this.selectedTextInfos.length == this.selectedRangeEndOrder - this.selectedRangeStartOrder + 1
    if (!canIncrementallyUpdate) {
      this.rebuildSelectedTextInfos(start, end, registry)
    } else {
      const oldStartOrder = this.selectedRangeStartOrder
      const oldEndOrder = this.selectedRangeEndOrder
      const overlapStart = Math.max(oldStartOrder, start.blockOrder)
      const overlapEnd = Math.min(oldEndOrder, end.blockOrder)
      if (overlapStart > overlapEnd) {
        this.rebuildSelectedTextInfos(start, end, registry)
      } else {
        if (oldStartOrder < overlapStart) {
          this.selectedTextInfos.splice(0, overlapStart - oldStartOrder)
        }
        if (oldEndOrder > overlapEnd) {
          const removeCount = oldEndOrder - overlapEnd
          this.selectedTextInfos.splice(this.selectedTextInfos.length - removeCount, removeCount)
        }
        for (let i = overlapStart - 1; i >= start.blockOrder; i--) {
          const info = this.buildSelectedTextInfo(i, start, end, registry)
          if (info) {
            this.selectedTextInfos.unshift(info)
          }
        }
        for (let i = overlapEnd + 1; i <= end.blockOrder; i++) {
          const info = this.buildSelectedTextInfo(i, start, end, registry)
          if (info) {
            this.selectedTextInfos.push(info)
          }
        }
        if (this.selectedTextInfos.length != expectedCount) {
          this.rebuildSelectedTextInfos(start, end, registry)
        } else {
          this.selectedRangeStartOrder = start.blockOrder
          this.selectedRangeEndOrder = end.blockOrder
          const touchedOrders: number[] = [oldStartOrder, oldEndOrder, start.blockOrder, end.blockOrder]
          const updatedOrders: Set<number> = new Set()
          for (let i = 0; i < touchedOrders.length; i++) {
            const order = touchedOrders[i]
            if (order < start.blockOrder || order > end.blockOrder || updatedOrders.has(order)) {
              continue
            }
            updatedOrders.add(order)
            const previous = this.selectedTextInfos[order - start.blockOrder]
            this.updateSelectedTextInfoAtOrder(order, this.buildSelectedTextInfo(order, start, end, registry, previous))
          }
        }
      }
    }
    this.updateCaretPositions(rootInfo)
    this.paintSelection(rootInfo)
  }

  private updateCaretPositions(rootInfo: componentUtils.ComponentInfo) {
    if (this.selectedTextInfos.length == 0) {
      this.startCaretX = -100
      this.startCaretY = -100
      this.endCaretX = -100
      this.endCaretY = -100
      return
    }
    const startPosition = this.selectedTextInfos[0].getCaretPosition(rootInfo, false)
    const endPosition = this.selectedTextInfos[this.selectedTextInfos.length - 1].getCaretPosition(rootInfo, true)
    this.startCaretX = typeof startPosition?.x === 'number' ? startPosition.x + 2 : -100
    this.startCaretY = typeof startPosition?.y === 'number' ? startPosition.y : -100
    this.endCaretX = typeof endPosition?.x === 'number' ? endPosition.x + 2 : -100
    this.endCaretY = typeof endPosition?.y === 'number' ? endPosition.y : -100
  }

  private updateSelectionByOrderedCaret(infoA: CaretInfo, infoB: CaretInfo) {
    if (infoA.lessThan(infoB)) {
      this.collectSelectedTextInfos(infoA, infoB)
    } else {
      this.collectSelectedTextInfos(infoB, infoA)
    }
    this.selectionActive = this.selectedTextInfos.length > 0
  }

  private paintSelection(rootInfo: componentUtils.ComponentInfo) {
    const rects: SelectionHighlightRect[] = []
    for (const info of this.selectedTextInfos) {
      for (const rect of info.getHighlights(rootInfo)) rects.push(rect)
    }
    // 赋新数组引用驱动声明式叠层重渲染; 与 caret @State 同管线, 同帧上屏。
    this.selectionRectList = rects
  }

  private startSelection(selectionInfo: BlockSelectionStartInfo) {
    this.pendingDrag = false
    this.releaseMagnifier()
    this.selectionRootInfo = undefined
    // 长按菜单模式: 不立即选区, 改为把按压点 / 段落文本 / 选取动作交给消费端渲染蒙层菜单。
    if (this.controller.getLongPressMenuEnable()) {
      this.handleLongPressMenu(selectionInfo)
      return
    }
    if (selectionInfo.fromBlankArea) {
      this.startWholeBlockSelection(selectionInfo.blockId)
      return
    }
    this.startSelectionAtPoint(selectionInfo)
  }

  private startSelectionAtPoint(selectionInfo: BlockSelectionStartInfo): boolean {
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    if (registry.getOrderedBlocks().length == 0) {
      return false
    }
    const block = registry.getBlockById(selectionInfo.blockId)
    const blockRect = registry.getBlockRect(selectionInfo.blockId)
    if (!block || !blockRect) {
      this.clearSelection()
      return false
    }
    const localX = selectionInfo.localX
    const localY = selectionInfo.localY
    const layoutManager = block.controller.getLayoutManager()
    const layoutLength = this.getLayoutTextLength(layoutManager)
    const caretIndex = this.getTextIndex(localX, localY, layoutManager, layoutLength)
    this.startCaretInfo.blockOrder = block.order
    this.startCaretInfo.caretIndex = Math.max(0, Math.min(caretIndex, layoutLength))
    this.endCaretInfo.blockOrder = this.startCaretInfo.blockOrder
    if (layoutLength == 0) {
      this.clearSelection()
      return false
    }
    this.endCaretInfo.caretIndex = Math.min(this.startCaretInfo.caretIndex + this.initialSelectionLength, layoutLength)
    if (this.endCaretInfo.caretIndex - this.startCaretInfo.caretIndex < this.initialSelectionLength) {
      this.startCaretInfo.caretIndex = Math.max(0, this.endCaretInfo.caretIndex - this.initialSelectionLength)
    }
    this.updateSelectionByOrderedCaret(this.startCaretInfo, this.endCaretInfo)
    this.mouseSelecting = !selectionInfo.showActionBarOnStart
    this.mouseSelectionDragged = false
    this.mouseSelectionStartGlobalX = selectionInfo.globalX ?? 0
    this.mouseSelectionStartGlobalY = selectionInfo.globalY ?? 0
    this.suppressSelectionOverlayClick = false
    if (selectionInfo.showActionBarOnStart) {
      this.showSelectionActionBar()
    } else {
      this.hideSelectionActionBar()
    }
    return true
  }

  private startLongPressSelection(info: BlockSelectionStartInfo,
    type: LongPressSelectionType = LongPressSelectionType.CUSTOM) {
    if (type == LongPressSelectionType.ALL) {
      this.mouseSelecting = false
      this.mouseSelectionDragged = false
      this.suppressSelectionOverlayClick = false
      this.triggerTextSelectionSelectAll()
      return
    }
    if (type == LongPressSelectionType.PARAGRAPH || info.fromBlankArea) {
      this.startWholeBlockSelection(info.blockId)
      return
    }
    if (!this.startSelectionAtPoint(info)) {
      this.startWholeBlockSelection(info.blockId)
    }
  }

  private handleLongPressMenu(info: BlockSelectionStartInfo) {
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    const block = registry.getBlockById(info.blockId)
    if (!block) {
      return
    }
    // 复用 buildCopyText 取按压所在文本块(段落)的完整可复制文本, 供消费端「复制」按钮使用。
    const paragraphText = registry.buildCopyText(block.order, 0, block.order, block.renderedLength)
    // 选区动作闭包绑定本实例, 消费端点「选取文本」时精确作用于被长按的块。
    const menuInfo = new LongPressMenuInfo(info.blockId, paragraphText, info.globalX ?? 0, info.globalY ?? 0,
      (type?: LongPressSelectionType) => {
        this.startLongPressSelection(info, type)
      })
    this.controller.getLongPressMenuListener()(menuInfo)
  }

  private handleSelectionRootLongPress(event: GestureEvent) {
    if (!this.controller.getTextSelectionEnable() || !this.controller.getLongPressMenuEnable() ||
      event.fingerList.length == 0) {
      return
    }
    const finger = event.fingerList[0]
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    if (registry.getExactBlockInfoByPoint(finger.globalX, finger.globalY)) {
      return
    }
    const hit = registry.getNearestBlockInfoByPoint(finger.globalX, finger.globalY)
    if (!hit) {
      return
    }
    const localX = finger.globalX - px2vp(hit.info.screenOffset.x)
    const localY = finger.globalY - px2vp(hit.info.screenOffset.y)
    registry.triggerStartSelection(new BlockSelectionStartInfo(hit.block.id, localX, localY, true,
      finger.globalX, finger.globalY, true))
  }

  private startWholeBlockSelection(blockId: string) {
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    const block = registry.getBlockById(blockId)
    if (!block || block.renderedLength == 0) {
      this.clearSelection()
      return
    }
    this.startCaretInfo.blockOrder = block.order
    this.startCaretInfo.caretIndex = 0
    this.endCaretInfo.blockOrder = block.order
    this.endCaretInfo.caretIndex = block.renderedLength
    this.mouseSelecting = false
    this.mouseSelectionDragged = false
    this.suppressSelectionOverlayClick = false
    // 复用既有渲染管线: updateSelectionByOrderedCaret → 高亮 + 两手柄; showSelectionActionBar → 操作栏。
    this.updateSelectionByOrderedCaret(this.startCaretInfo, this.endCaretInfo)
    this.showSelectionActionBar()
  }

  private updateCaretByGesture(globalX: number, globalY: number, isStart: boolean) {
    this.dragX = globalX
    this.dragY = globalY
    this.dragStartCaret = isStart
    this.pendingDrag = true
    if (!this.dragFramePosted) {
      this.dragFramePosted = true
      this.getUIContext().postFrameCallback(this.dragFrame)
    }
  }

  private flushCaretDrag(): void {
    if (!this.pendingDrag) return
    this.pendingDrag = false
    if (!this.selectionActive) return
    const target = this.dragStartCaret ? this.startCaretInfo : this.endCaretInfo
    const oldOrder = target.blockOrder
    const oldIndex = target.caretIndex
    if (this.getCaretInfo(this.dragX, this.dragY, target) &&
      (target.blockOrder !== oldOrder || target.caretIndex !== oldIndex)) {
      this.updateSelectionByOrderedCaret(this.startCaretInfo, this.endCaretInfo)
    }
  }

  private updateSelectionByMouse(globalX: number, globalY: number) {
    if (!this.mouseSelecting || !this.selectionActive) {
      return
    }
    const movedX = Math.abs(globalX - this.mouseSelectionStartGlobalX)
    const movedY = Math.abs(globalY - this.mouseSelectionStartGlobalY)
    if (!this.mouseSelectionDragged && movedX < this.mouseSelectionDragThreshold &&
      movedY < this.mouseSelectionDragThreshold) {
      return
    }
    this.mouseSelectionDragged = true
    this.updateCaretByGesture(globalX, globalY, false)
  }

  private endSelectionByMouse(x: number, y: number) {
    if (!this.mouseSelecting) {
      return
    }
    this.updateSelectionByMouse(x, y)
    this.mouseSelecting = false
    clearActiveTextSelectionMouseTracker()
    if (!this.mouseSelectionDragged) {
      this.clearSelection()
      return
    }
    this.flushCaretDrag()
    this.showSelectionActionBar()
    this.suppressSelectionOverlayClick = true
  }

  private handleSelectionOverlayMouse(event: MouseEvent) {
    if (!this.mouseSelecting) {
      return
    }
    if (event.action == MouseAction.Move) {
      this.updateSelectionByMouse(event.windowX, event.windowY)
      event.stopPropagation()
      return
    }
    if (event.action == MouseAction.Release) {
      this.endSelectionByMouse(event.windowX, event.windowY)
      event.stopPropagation()
    }
  }

  private isSelectionDarkTheme(): boolean {
    return this.controller.getCodeBlockTheme() == 'dark'
  }

  private getSelectionActionItemTextColor(): ResourceColor {
    return this.isSelectionDarkTheme() ? '#F9FAFB' : '#111827'
  }

  private getSelectionPopupOptions(): CustomPopupOptions {
    const style = this.selectionMenuOptions()
    return {
      builder: (): void => { this.selectionActionMenu() },
      placement: Placement.BottomLeft,
      width: this.getSelectionActionBarWidth(),
      radius: this.selectionActionBarHeight / 2,
      targetSpace: 0,
      enableArrow: false,
      mask: false,
      autoCancel: false,
      focusable: false,
      showInSubWindow: false,
      systemMaterial: style.systemMaterial,
      popupColor: style.backgroundColor,
      backgroundBlurStyle: style.backgroundBlurStyle,
      backgroundEffect: style.backgroundEffect,
      onStateChange: (event): void => {
        if (!event.isVisible) style.onDisappear?.()
      }
    }
  }

  private getSelectedTextValue(): string {
    if (!this.selectionActive) {
      return ''
    }
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    if (this.startCaretInfo.lessThan(this.endCaretInfo)) {
      return registry.buildCopyText(this.startCaretInfo.blockOrder, this.startCaretInfo.caretIndex,
        this.endCaretInfo.blockOrder, this.endCaretInfo.caretIndex)
    }
    return registry.buildCopyText(this.endCaretInfo.blockOrder, this.endCaretInfo.caretIndex,
      this.startCaretInfo.blockOrder, this.startCaretInfo.caretIndex)
  }

  private triggerTextSelectionCopy() {
    const textValue = this.getSelectedTextValue()
    if (!textValue) {
      return
    }
    try {
      this.controller.getTextSelectionCopyListener()(textValue)
    } finally {
      this.clearSelection()
    }
  }

  private createSelectionActionContext(): TextSelectionActionContext {
    return new TextSelectionActionContext(this.getSelectedTextValue(), () => {
      this.triggerTextSelectionCopy()
    }, () => {
      this.triggerTextSelectionSelectAll()
    }, () => {
      this.clearSelection()
    })
  }

  private triggerTextSelectionSelectAll() {
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    const blocks = registry.getOrderedBlocks()
    if (blocks.length == 0) {
      return
    }
    let firstBlock: RegisteredTextBlock | undefined = undefined
    let lastBlock: RegisteredTextBlock | undefined = undefined
    for (let i = 0; i < blocks.length; i++) {
      if (blocks[i].renderedLength > 0) {
        firstBlock = blocks[i]
        break
      }
    }
    for (let i = blocks.length - 1; i >= 0; i--) {
      if (blocks[i].renderedLength > 0) {
        lastBlock = blocks[i]
        break
      }
    }
    if (!firstBlock || !lastBlock) {
      return
    }
    this.startCaretInfo.blockOrder = firstBlock.order
    this.startCaretInfo.caretIndex = 0
    this.endCaretInfo.blockOrder = lastBlock.order
    this.endCaretInfo.caretIndex = lastBlock.renderedLength
    this.updateSelectionByOrderedCaret(this.startCaretInfo, this.endCaretInfo)
    this.showSelectionActionBar()
  }

  private showSelectionActionBar() {
    if (!this.selectionActive || this.selectedTextInfos.length == 0) {
      return
    }
    this.selectionMenuPosition = this.getSelectionActionBarPosition()
    this.selectionActionBarVisible = true
  }

  private hideSelectionActionBar() {
    if (this.selectionActionBarVisible) {
      this.selectionActionBarVisible = false
    }
  }

  private releaseMagnifier(): void {
    if (this.magnifiedBlockId) this.dragMagnifier?.unbind()
    this.magnifiedBlockId = ''
    this.dragMagnifier = undefined
  }

  private beginCaretDrag(touch: boolean): void {
    this.pendingDrag = false
    this.releaseMagnifier()
    if (touch) this.dragMagnifier = this.getUIContext().getMagnifier?.()
    this.hideSelectionActionBar()
    TextSelectionController.getInstance(this.selectionUnion).invalidateLayoutCache()
    this.refreshSelectionVisuals()
  }

  private endCaretDrag(): void {
    this.flushCaretDrag()
    this.releaseMagnifier()
    this.showSelectionActionBar()
  }

  private getSelectionBounds(rootInfo: componentUtils.ComponentInfo): common2D.Rect | undefined {
    let left = Number.MAX_VALUE
    let top = Number.MAX_VALUE
    let right = -Infinity
    let bottom = -Infinity
    let hasRect = false
    for (let i = 0; i < this.selectedTextInfos.length; i++) {
      const info = this.selectedTextInfos[i]
      const blockOffsetX = px2vp(info.componentInfo.screenOffset.x) - px2vp(rootInfo.screenOffset.x)
      const blockOffsetY = px2vp(info.componentInfo.screenOffset.y) - px2vp(rootInfo.screenOffset.y)
      for (let j = 0; j < info.rects.length; j++) {
        const rect = info.rects[j]
        left = Math.min(left, blockOffsetX + rect.left)
        top = Math.min(top, blockOffsetY + rect.top)
        right = Math.max(right, blockOffsetX + rect.right)
        bottom = Math.max(bottom, blockOffsetY + rect.bottom)
        hasRect = true
      }
    }
    if (!hasRect) {
      return undefined
    }
    return {
      left,
      top,
      right,
      bottom
    }
  }

  private getSelectionActionBarPosition(): Position {
    const root = componentUtils.getRectangleById(this.selectionRootId)
    const bounds = this.getSelectionBounds(root)
    const width = this.getSelectionActionBarWidth()
    const inset = this.selectionActionBarEdgeInset
    const x = Math.max(inset, Math.min(this.endCaretX + 10 - width / 2, this.selectionLayerWidth - width - inset))
    // 短段落的上方也可放工具栏。用当前窗口页面的可见空间，而非正文自身的高度。
    const page = this.getUIContext().getPageRootNode?.()
    const pageTop = page ? Number(page.getPositionToWindow().y) - px2vp(root.windowOffset.y) : 0
    const pageHeight = page ? px2vp(Number(page.getMeasuredSize().height)) : this.selectionLayerHeight
    const minY = pageTop + inset
    const maxY = Math.max(minY, pageTop + pageHeight - inset - this.selectionActionBarHeight)
    const above = (bounds?.top ?? this.startCaretY) - this.selectionActionBarSpacing - this.selectionActionBarHeight
    const below = Math.max(bounds?.bottom ?? this.endCaretY, this.startCaretY + 36, this.endCaretY + 36) +
      this.selectionActionBarSpacing
    let y: number
    if (above >= minY && above <= maxY) {
      y = above
    } else if (below >= minY && below <= maxY) {
      y = below
    } else {
      const activeCaret = this.dragStartCaret ? this.startCaretY : this.endCaretY
      y = activeCaret < (minY + maxY) / 2 ? maxY : minY
    }
    return { x, y }
  }

  private refreshSelectionVisuals(rootInfo?: componentUtils.ComponentInfo, registry?: TextSelectionController) {
    if (!this.selectionActive || this.selectedTextInfos.length == 0) {
      return
    }
    const currentRootInfo = rootInfo || componentUtils.getRectangleById(this.selectionRootId)
    this.selectionRootInfo = currentRootInfo
    const currentRegistry = registry || TextSelectionController.getInstance(this.selectionUnion)
    this.refreshSelectedTextInfosComponentInfo(currentRegistry)
    this.updateCaretPositions(currentRootInfo)
    this.paintSelection(currentRootInfo)
    if (this.selectionActionBarVisible) this.selectionMenuPosition = this.getSelectionActionBarPosition()
  }

  private updateSelectionLayerSize(newValue: Area) {
    const nextWidth = Math.max(0, Math.ceil(newValue.width as number))
    const nextHeight = Math.max(0, Math.ceil(newValue.height as number))
    let changed = false
    if (this.selectionLayerWidth != nextWidth) {
      this.selectionLayerWidth = nextWidth
      changed = true
    }
    if (this.selectionLayerHeight != nextHeight) {
      this.selectionLayerHeight = nextHeight
      changed = true
    }
    if (changed && this.selectionActive) {
      TextSelectionController.getInstance(this.selectionUnion).invalidateLayoutCache()
      this.selectionRootInfo = undefined
      this.selectedRangeStartOrder = -1
      this.updateSelectionByOrderedCaret(this.startCaretInfo, this.endCaretInfo)
      if (this.selectionActionBarVisible) this.selectionMenuPosition = this.getSelectionActionBarPosition()
    }
  }

  @Builder
  private selectionActionItem(title: string, click: () => void, fontColor?: ResourceColor) {
    Button(title, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
      .width(this.selectionItemWidth(title))
      .height(this.selectionActionBarHeight)
      .padding(0)
      .fontSize(14)
      .fontWeight(FontWeight.Regular)
      .fontColor(fontColor ?? this.getSelectionActionItemTextColor())
      .stateStyles({
        normal: {
          .backgroundColor(Color.Transparent)
        },
        pressed: {
          .backgroundColor($r('sys.color.interactive_pressed'))
        }
      })
      .onClick(click)
  }

  @Builder
  private selectionActionMenu() {
    Scroll() {
      Row() {
        if (this.controller.getTextSelectionActionItems().length > 0) {
          ForEach(this.controller.getTextSelectionActionItems(), (item: TextSelectionActionItem) => {
            this.selectionActionItem(item.title, () => {
              item.onClick(this.createSelectionActionContext())
            }, item.fontColor)
          }, (item: TextSelectionActionItem, index: number): string => `${index}_${item.title}`)
        } else {
          this.selectionActionItem('复制', () => {
            this.triggerTextSelectionCopy()
          })
          this.selectionActionItem('全选', () => {
            this.triggerTextSelectionSelectAll()
          })
          this.selectionActionItem('取消', () => {
            this.clearSelection()
          })
        }
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 4, right: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width(this.getSelectionActionBarWidth())
    .height(this.selectionActionBarHeight)
    // 只绘制操作内容，背景、阴影和材质由原生浮层负责。
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private selectionActionBar() {
    Row()
    .width(this.getSelectionActionBarWidth())
    .height(0)
    .position(this.selectionMenuPosition)
    .zIndex(30)
    .focusable(false)
    .accessibilityLevel('no')
    .bindPopup(this.selectionActionBarVisible, this.getSelectionPopupOptions())
  }

  build() {
    if (this.treeNode.length > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        IntactRender({
          children: this.treeNode,
          lazyRender: this.shouldUseLazyRender(),
          preloadBlockCount: this.controller.getLazyPreloadBlockCount()
        })
          .width('100%')
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.updateSelectionLayerSize(newValue)
          })

        if (this.controller.getTextSelectionEnable()) {
          ForEach(this.selectionRectList, (r: SelectionHighlightRect) => {
            Column()
              .width(r.w)
              .height(r.h)
              .backgroundColor('#4C0A59F7')
              .position({ x: r.x, y: r.y })
              .hitTestBehavior(HitTestMode.None)
          }, (r: SelectionHighlightRect): string => r.key)
        }

        if (this.controller.getTextSelectionEnable() && this.selectionActive) {
          Column()
            .width(this.selectionLayerWidth)
            .height(this.selectionLayerHeight)
            .backgroundColor(Color.Transparent)
            .zIndex(10)
            .position({ x: 0, y: 0 })
            .onClick(() => {
              if (this.suppressSelectionOverlayClick) {
                this.suppressSelectionOverlayClick = false
                return
              }
              this.clearSelection()
            })
            .onMouse((event: MouseEvent) => {
              this.handleSelectionOverlayMouse(event)
            })

          SelectionCaret({
            caretX: this.startCaretX,
            caretY: this.startCaretY,
            isStart: true,
            caretDragStart: (touch: boolean) => this.beginCaretDrag(touch),
            caretDragUpdate: (globalX: number, globalY: number, isStart: boolean) => {
              this.updateCaretByGesture(globalX, globalY, isStart)
            },
            caretDragEnd: () => this.endCaretDrag()
          })
          SelectionCaret({
            caretX: this.endCaretX,
            caretY: this.endCaretY,
            isStart: false,
            caretDragStart: (touch: boolean) => this.beginCaretDrag(touch),
            caretDragUpdate: (globalX: number, globalY: number, isStart: boolean) => {
              this.updateCaretByGesture(globalX, globalY, isStart)
            },
            caretDragEnd: () => this.endCaretDrag()
          })
          // 手柄拖动时只关闭菜单，保留锚点，结束拖动后可重新打开原生菜单。
          this.selectionActionBar()
        }
      }
      .id(this.selectionRootId)
      .width('100%')
      .gesture(
        LongPressGesture()
          .onAction((event: GestureEvent) => {
            this.handleSelectionRootLongPress(event)
          })
      )
      .onAppear(() => {
        this.baseCallback("success")
      })
    }
  }
}

@Component
struct SelectionCaret {
  @Prop caretX: number = -100
  @Prop caretY: number = -100
  @Prop isStart: boolean = true
  caretDragStart: (touch: boolean) => void = (_touch: boolean) => {}
  caretDragUpdate: (globalX: number, globalY: number, isStart: boolean) => void =
    (_globalX: number, _globalY: number, _isStart: boolean) => {
    }
  caretDragEnd: () => void = () => {
  }
  private mouseDragging: boolean = false
  private grabOffsetX: number = 0
  private grabOffsetY: number = 0

  private beginDrag(localX: number, localY: number, touch: boolean): void {
    // 44vp 命中区内，竖线所在字符的命中点为 (20, 20)；抓住下方圆点时也从同一字符移动。
    this.grabOffsetX = 20 - localX
    this.grabOffsetY = 20 - localY
    this.caretDragStart(touch)
  }

  private moveTo(x: number, y: number): void {
    this.caretDragUpdate(x + this.grabOffsetX, y + this.grabOffsetY, this.isStart)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Column()
          .width(1)
          .height(20)
          .backgroundColor('#0A59F7')
        Column()
          .width(16)
          .aspectRatio(1)
          .borderRadius(10)
          .backgroundColor('#FFF')
          .border({ width: 2, color: "#0A59F7" })
      }
      .offset({ x: 12, y: 12 })
    }
    .width(44)
    .height(44)
    .position({ x: this.caretX - 12, y: this.caretY - 12 })
    .zIndex(20)
    .gesture(
      PanGesture({ distance: 1 })
        .onActionStart((event: GestureEvent) => {
          const finger = event.fingerList[0]
          if (finger) {
            this.beginDrag(finger.localX, finger.localY, event.source === SourceType.TouchScreen ||
              event.sourceTool === SourceTool.Finger || event.sourceTool === SourceTool.Pen)
            this.moveTo(finger.globalX, finger.globalY)
          }
        })
        .onActionUpdate((event: GestureEvent) => {
          const finger = event.fingerList[0]
          if (finger) this.moveTo(finger.globalX, finger.globalY)
        })
        .onActionEnd((event: GestureEvent) => {
          const finger = event.fingerList[0]
          if (finger) this.moveTo(finger.globalX, finger.globalY)
          this.caretDragEnd()
        })
        .onActionCancel(() => this.caretDragEnd())
    )
    .onMouse((event: MouseEvent) => {
      if (event.action == MouseAction.Press && isPrimaryMouseButton(event)) {
        this.mouseDragging = true
        this.beginDrag(event.x, event.y, false)
        event.stopPropagation()
        return
      }
      if (event.action == MouseAction.Move && this.mouseDragging) {
        this.moveTo(event.windowX, event.windowY)
        event.stopPropagation()
        return
      }
      if (event.action == MouseAction.Release && this.mouseDragging) {
        this.mouseDragging = false
        this.moveTo(event.windowX, event.windowY)
        this.caretDragEnd()
        event.stopPropagation()
      }
    })
  }
}
