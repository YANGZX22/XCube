import { common2D } from '@kit.ArkGraphics2D'
import { componentUtils } from '@kit.ArkUI'

export class TextSelectionSegment {
  renderedLength: number = 0
  copyText: string = ""

  constructor(renderedLength: number, copyText: string) {
    this.renderedLength = renderedLength
    this.copyText = copyText
  }
}

export class RegisteredTextBlock {
  id: string
  order: number
  controller: TextController
  segments: TextSelectionSegment[]
  renderedLength: number

  constructor(id: string, order: number, controller: TextController, segments: TextSelectionSegment[]) {
    this.id = id
    this.order = order
    this.controller = controller
    this.segments = segments
    this.renderedLength = segments.reduce((sum: number, item: TextSelectionSegment) => sum + item.renderedLength, 0)
  }
}

export class SelectedTextInfo {
  block: RegisteredTextBlock
  componentInfo: componentUtils.ComponentInfo
  rects: common2D.Rect[]
  startIndex: number
  endIndex: number

  constructor(block: RegisteredTextBlock, componentInfo: componentUtils.ComponentInfo, rects: common2D.Rect[],
    startIndex: number, endIndex: number) {
    this.block = block
    this.componentInfo = componentInfo
    this.rects = rects
    this.startIndex = startIndex
    this.endIndex = endIndex
  }

  getCaretPosition(rootInfo: componentUtils.ComponentInfo, isEnd: boolean = true): Position | undefined {
    if (this.rects.length == 0) {
      return undefined
    }
    const rect = isEnd ? this.rects[this.rects.length - 1] : this.rects[0]
    const x = px2vp(this.componentInfo.screenOffset.x) - px2vp(rootInfo.screenOffset.x) +
      (isEnd ? rect.right : rect.left) - 10
    const y = px2vp(this.componentInfo.screenOffset.y) - px2vp(rootInfo.screenOffset.y) + rect.top
    return { x, y }
  }
}

export class BlockHitInfo {
  block: RegisteredTextBlock
  info: componentUtils.ComponentInfo

  constructor(block: RegisteredTextBlock, info: componentUtils.ComponentInfo) {
    this.block = block
    this.info = info
  }
}

export class BlockSelectionStartInfo {
  blockId: string
  localX: number
  localY: number
  showActionBarOnStart: boolean
  globalX?: number
  globalY?: number
  fromBlankArea: boolean

  constructor(blockId: string, localX: number, localY: number, showActionBarOnStart: boolean = true, globalX?: number,
    globalY?: number, fromBlankArea: boolean = false) {
    this.blockId = blockId
    this.localX = localX
    this.localY = localY
    this.showActionBarOnStart = showActionBarOnStart
    this.globalX = globalX
    this.globalY = globalY
    this.fromBlankArea = fromBlankArea
  }
}

export class CaretInfo {
  blockOrder: number = -1
  caretIndex: number = -1

  lessThan(another: CaretInfo): boolean {
    return !(this.blockOrder > another.blockOrder) &&
      (this.blockOrder < another.blockOrder || this.caretIndex < another.caretIndex)
  }

  reset() {
    this.blockOrder = -1
    this.caretIndex = -1
  }
}

export enum LongPressSelectionType {
  ALL,
  PARAGRAPH,
  CUSTOM
}

/**
 * 长按菜单(复制 / 选取文本)的事件载荷。
 * 由 Markdown 组件在「长按菜单模式」下组装并回调给消费端:
 * - paragraphText: 按压所在文本块(段落)的完整可复制文本, 供「复制」按钮使用。
 * - globalX / globalY: 按压点的窗口坐标(vp), 供消费端把蒙层菜单定位到手指位置。
 * - selectWholeBlock: 组件绑定的「选取文本」动作, 支持全部 / 段落 / 自定义三种选取类型。
 */
export class LongPressMenuInfo {
  blockId: string
  paragraphText: string
  globalX: number
  globalY: number
  selectWholeBlock: (type?: LongPressSelectionType) => void

  constructor(blockId: string, paragraphText: string, globalX: number, globalY: number,
    selectWholeBlock: (type?: LongPressSelectionType) => void) {
    this.blockId = blockId
    this.paragraphText = paragraphText
    this.globalX = globalX
    this.globalY = globalY
    this.selectWholeBlock = selectWholeBlock
  }
}

export class TextSelectionActionContext {
  selectedText: string
  copy: () => void
  selectAll: () => void
  clear: () => void

  constructor(selectedText: string, copy: () => void, selectAll: () => void, clear: () => void) {
    this.selectedText = selectedText
    this.copy = copy
    this.selectAll = selectAll
    this.clear = clear
  }
}

export class TextSelectionActionItem {
  title: string
  fontColor?: ResourceColor
  onClick: (context: TextSelectionActionContext) => void

  constructor(title: string, onClick: (context: TextSelectionActionContext) => void, fontColor?: ResourceColor) {
    this.title = title
    this.onClick = onClick
    this.fontColor = fontColor
  }
}
