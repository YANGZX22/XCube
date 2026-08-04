import { componentUtils } from '@kit.ArkUI'
import { BlockHitInfo, BlockSelectionStartInfo, RegisteredTextBlock, TextSelectionSegment } from '../model/TextSelectionInfo'

export class TextSelectionController {
  private static controllerMap: Map<string, TextSelectionController> = new Map()
  private static activeMarkdownUnion?: string
  private markdownUnion: string
  private blocks: Map<string, RegisteredTextBlock> = new Map()
  private orderedBlocksCache: RegisteredTextBlock[] = []
  private blockRectCache: Map<string, componentUtils.ComponentInfo> = new Map()
  private layoutCacheValid: boolean = false
  private nextOrder: number = 0
  private readonly HIT_SLOP: number = 24
  private startSelectionHandler?: (info: BlockSelectionStartInfo) => void
  private updateSelectionHandler?: (globalX: number, globalY: number) => void
  private endSelectionHandler?: () => void
  private clearSelectionHandler?: () => void

  private constructor(markdownUnion: string) {
    this.markdownUnion = markdownUnion
  }

  static getInstance(markdownUnion: string): TextSelectionController {
    if (!TextSelectionController.controllerMap.has(markdownUnion)) {
      TextSelectionController.controllerMap.set(markdownUnion, new TextSelectionController(markdownUnion))
    }
    return TextSelectionController.controllerMap.get(markdownUnion)!
  }

  static destroy(markdownUnion: string) {
    if (TextSelectionController.activeMarkdownUnion == markdownUnion) {
      TextSelectionController.activeMarkdownUnion = undefined
    }
    TextSelectionController.controllerMap.delete(markdownUnion)
  }

  registerBlock(id: string, controller: TextController, segments: TextSelectionSegment[]) {
    const existing = this.blocks.get(id)
    if (existing) {
      existing.controller = controller
      existing.segments = segments
      existing.renderedLength = segments.reduce((sum: number, item: TextSelectionSegment) => sum + item.renderedLength, 0)
      this.invalidateLayoutCache()
      return
    }
    const block = new RegisteredTextBlock(id, this.nextOrder++, controller, segments)
    this.blocks.set(id, block)
    this.invalidateLayoutCache()
  }

  unregisterBlock(id: string) {
    this.blocks.delete(id)
    this.invalidateLayoutCache()
  }

  clear() {
    this.blocks.clear()
    this.nextOrder = 0
    this.invalidateLayoutCache()
  }

  setStartSelectionHandler(handler?: (info: BlockSelectionStartInfo) => void) {
    this.startSelectionHandler = handler
  }

  setUpdateSelectionHandler(handler?: (globalX: number, globalY: number) => void) {
    this.updateSelectionHandler = handler
  }

  setEndSelectionHandler(handler?: () => void) {
    this.endSelectionHandler = handler
  }

  setClearSelectionHandler(handler?: () => void) {
    this.clearSelectionHandler = handler
  }

  releaseActiveSelection() {
    if (TextSelectionController.activeMarkdownUnion == this.markdownUnion) {
      TextSelectionController.activeMarkdownUnion = undefined
    }
  }

  triggerStartSelection(info: BlockSelectionStartInfo) {
    if (TextSelectionController.activeMarkdownUnion &&
      TextSelectionController.activeMarkdownUnion != this.markdownUnion) {
      const activeController = TextSelectionController.controllerMap.get(TextSelectionController.activeMarkdownUnion)
      activeController?.clearSelectionHandler?.()
    }
    TextSelectionController.activeMarkdownUnion = this.markdownUnion
    this.refreshLayoutSnapshot()
    if (this.startSelectionHandler) {
      this.startSelectionHandler(info)
    }
  }

  triggerUpdateSelection(globalX: number, globalY: number): boolean {
    if (TextSelectionController.activeMarkdownUnion != this.markdownUnion || !this.updateSelectionHandler) {
      return false
    }
    this.updateSelectionHandler(globalX, globalY)
    return true
  }

  triggerEndSelection(): boolean {
    if (TextSelectionController.activeMarkdownUnion != this.markdownUnion || !this.endSelectionHandler) {
      return false
    }
    this.endSelectionHandler()
    return true
  }

  getOrderedBlocks(): RegisteredTextBlock[] {
    if (!this.layoutCacheValid) {
      this.refreshLayoutSnapshot()
    }
    return this.orderedBlocksCache
  }

  private refreshLayoutSnapshot() {
    const blocks = Array.from(this.blocks.values())
    const rectCache: Map<string, componentUtils.ComponentInfo> = new Map()
    blocks.sort((a: RegisteredTextBlock, b: RegisteredTextBlock) => {
      const rectA = this.loadBlockRect(a.id, rectCache)
      const rectB = this.loadBlockRect(b.id, rectCache)
      if (!rectA && !rectB) {
        return a.order - b.order
      }
      if (!rectA) {
        return 1
      }
      if (!rectB) {
        return -1
      }
      const deltaY = rectA.screenOffset.y - rectB.screenOffset.y
      if (Math.abs(deltaY) > this.HIT_SLOP) {
        return deltaY
      }
      return rectA.screenOffset.x - rectB.screenOffset.x
    })
    for (let i = 0; i < blocks.length; i++) {
      blocks[i].order = i
    }
    this.orderedBlocksCache = blocks
    this.blockRectCache = rectCache
    this.layoutCacheValid = true
  }

  getBlockByOrder(order: number): RegisteredTextBlock | undefined {
    const blocks = this.getOrderedBlocks()
    if (order < 0 || order >= blocks.length) {
      return undefined
    }
    return blocks[order]
  }

  getBlockById(id: string): RegisteredTextBlock | undefined {
    return this.blocks.get(id)
  }

  getExactBlockInfoByPoint(globalX: number, globalY: number): BlockHitInfo | undefined {
    const blocks = this.getOrderedBlocks()
    for (let i = 0; i < blocks.length; i++) {
      try {
        const info = this.getBlockRect(blocks[i].id)
        if (!info) {
          continue
        }
        const left = px2vp(info.screenOffset.x)
        const top = px2vp(info.screenOffset.y)
        const right = left + px2vp(info.size.width)
        const bottom = top + px2vp(info.size.height)
        if (globalX >= left && globalX <= right && globalY >= top && globalY <= bottom) {
          return new BlockHitInfo(blocks[i], info)
        }
      } catch (_err) {
      }
    }
    return undefined
  }

  getNearestBlockInfoByPoint(globalX: number, globalY: number): BlockHitInfo | undefined {
    const blocks = this.getOrderedBlocks()
    let nearest: BlockHitInfo | undefined = undefined
    let nearestDistance = Number.MAX_VALUE
    for (let i = 0; i < blocks.length; i++) {
      try {
        const info = this.getBlockRect(blocks[i].id)
        if (!info || blocks[i].renderedLength == 0) {
          continue
        }
        const left = px2vp(info.screenOffset.x)
        const top = px2vp(info.screenOffset.y)
        const right = left + px2vp(info.size.width)
        const bottom = top + px2vp(info.size.height)
        const dx = globalX < left ? left - globalX : (globalX > right ? globalX - right : 0)
        const dy = globalY < top ? top - globalY : (globalY > bottom ? globalY - bottom : 0)
        const distance = dx * dx + dy * dy
        if (distance < nearestDistance) {
          nearestDistance = distance
          nearest = new BlockHitInfo(blocks[i], info)
        }
      } catch (_err) {
      }
    }
    return nearest
  }

  getBlockInfoByPoint(globalX: number, globalY: number): BlockHitInfo | undefined {
    const blocks = this.getOrderedBlocks()
    // 不再每帧 refreshBlockRects 对全部块 getRectangleById(同步原生查询, 块越多越卡拖动)。
    // 矩形来自快照缓存: 拖动开始时由宿主 invalidateLayoutCache 触发一次全量重采(getOrderedBlocks
    // → refreshLayoutSnapshot), 之后本方法每帧只读缓存。拖动期间布局静止, 缓存有效。
    let nearestByY: BlockHitInfo | undefined = undefined
    for (let i = 0; i < blocks.length; i++) {
      try {
        const info = this.getBlockRect(blocks[i].id)
        if (!info) {
          continue
        }
        const left = px2vp(info.screenOffset.x)
        const top = px2vp(info.screenOffset.y)
        const right = left + px2vp(info.size.width)
        const bottom = top + px2vp(info.size.height)
        if (globalX >= left - this.HIT_SLOP && globalX <= right + this.HIT_SLOP &&
          globalY >= top - this.HIT_SLOP && globalY <= bottom + this.HIT_SLOP) {
          return new BlockHitInfo(blocks[i], info)
        }
        if (!nearestByY && globalY >= top - this.HIT_SLOP && globalY <= bottom + this.HIT_SLOP) {
          nearestByY = new BlockHitInfo(blocks[i], info)
        }
      } catch (_err) {
      }
    }
    return nearestByY
  }

  getBlockRect(id: string, forceRefresh: boolean = false): componentUtils.ComponentInfo | undefined {
    if (!forceRefresh && this.blockRectCache.has(id)) {
      return this.blockRectCache.get(id)
    }
    const info = this.loadBlockRect(id, this.blockRectCache, forceRefresh)
    if (info) {
      return info
    }
    return undefined
  }

  invalidateLayoutCache() {
    this.layoutCacheValid = false
    this.orderedBlocksCache = []
    this.blockRectCache.clear()
  }

  private loadBlockRect(id: string, targetCache: Map<string, componentUtils.ComponentInfo>,
    forceRefresh: boolean = false): componentUtils.ComponentInfo | undefined {
    if (!forceRefresh && targetCache.has(id)) {
      return targetCache.get(id)
    }
    try {
      const info = componentUtils.getRectangleById(id)
      targetCache.set(id, info)
      return info
    } catch (_err) {
      return undefined
    }
  }

  buildCopyText(orderStart: number, caretStart: number, orderEnd: number, caretEnd: number): string {
    const blocks = this.getOrderedBlocks()
    const start = Math.min(orderStart, orderEnd)
    const end = Math.max(orderStart, orderEnd)
    const result: string[] = []
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i]
      if (block.order < start || block.order > end) {
        continue
      }
      const rangeStart = block.order == orderStart ? caretStart : 0
      const rangeEnd = block.order == orderEnd ? caretEnd : block.renderedLength
      result.push(this.extractBlockCopyText(block, rangeStart, rangeEnd))
    }
    return result.join('\n')
  }

  private extractBlockCopyText(block: RegisteredTextBlock, startIndex: number, endIndex: number): string {
    if (endIndex <= startIndex) {
      return ''
    }
    let currentIndex = 0
    let result = ''
    for (let i = 0; i < block.segments.length; i++) {
      const segment = block.segments[i]
      const segmentStart = currentIndex
      const segmentEnd = currentIndex + segment.renderedLength
      currentIndex = segmentEnd
      const overlapStart = Math.max(startIndex, segmentStart)
      const overlapEnd = Math.min(endIndex, segmentEnd)
      if (overlapEnd <= overlapStart) {
        continue
      }
      if (segment.renderedLength == segment.copyText.length) {
        result += segment.copyText.slice(overlapStart - segmentStart, overlapEnd - segmentStart)
      } else {
        result += segment.copyText
      }
    }
    return result
  }
}
