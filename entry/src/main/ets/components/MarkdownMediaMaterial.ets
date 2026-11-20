import { FrameNode, inspector } from '@kit.ArkUI'
import { util } from '@kit.ArkTS'
import { chatRichContentBackdrop } from './ChatRichContentSurface'

export const CANGJIE_TABLE_RADIUS: number = 6
export const CANGJIE_TABLE_BORDER: number = 1

interface MediaArea {
  id: number
  isTable: boolean
  x: number
  y: number
  width: number
  height: number
}

// 仓颉超宽表的 Scroll 会在滑动中露出方形的单元格切面。只从前景擦除圆角以外及外框的像素。
@ComponentV2
struct TablePerimeterMask {
  @Require @Param area: MediaArea
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))

  @Monitor('area')
  private draw(): void {
    const width = this.area.width
    const height = this.area.height
    const inset = CANGJIE_TABLE_BORDER
    const innerWidth = width - 2 * inset
    const innerHeight = height - 2 * inset
    this.context.clearRect(0, 0, width, height)
    this.context.beginPath()
    this.context.rect(0, 0, width, height)
    if (innerWidth > 0 && innerHeight > 0) {
      this.context.roundRect(inset, inset, innerWidth, innerHeight, CANGJIE_TABLE_RADIUS - inset)
    }
    this.context.fill('evenodd')
  }

  build() {
    Canvas(this.context)
      .width(this.area.width)
      .height(this.area.height)
      .position({ x: this.area.x, y: this.area.y })
      .blendMode(BlendMode.DST_OUT)
      .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
      .accessibilityLevel('no-hide-descendants')
      .onReady((): void => { this.draw() })
      .onSizeChange((): void => { this.draw() })
  }
}

@ComponentV2
export struct MarkdownMediaMaterial {
  @Param table: boolean = false
  @Param images: boolean = true
  @Param imageRadius: number = 14
  @BuilderParam content: () => void
  @Local private areas: MediaArea[] = []
  private readonly contentId: string = 'md_media_' + util.generateRandomUUID()
  private observer: inspector.ComponentObserver | null = null
  private readonly onMediaLayout = (): void => { this.measureMedia() }

  private observeLayout(): void {
    this.observer = this.getUIContext().getUIInspector().createComponentObserver(this.contentId)
    this.observer.on('layout', this.onMediaLayout)
    this.measureMedia()
  }

  aboutToDisappear(): void {
    this.observer?.off('layout', this.onMediaLayout)
    this.observer = null
  }

  private measureMedia(): void {
    const root = this.getUIContext().getFrameNodeById(this.contentId)
    if (!root) {
      return
    }
    const origin = root.getPositionToWindow()
    const areas: MediaArea[] = []
    this.collectMediaAreas(root, Number(origin.x), Number(origin.y), areas)
    if (areas.length !== this.areas.length || areas.some((a: MediaArea, i: number): boolean => {
      const previous = this.areas[i]
      return a.id !== previous.id || Math.abs(a.x - previous.x) > 0.1 || Math.abs(a.y - previous.y) > 0.1 ||
        Math.abs(a.width - previous.width) > 0.1 || Math.abs(a.height - previous.height) > 0.1
    })) {
      this.areas = areas
    }
  }

  private collectMediaAreas(node: FrameNode, originX: number, originY: number, areas: MediaArea[]): void {
    const type = node.getNodeType()
    const isImage = this.images && (type === 'Image' || type === 'ImageSpan')
    // Markdown4cj 1.4 把圆角和边框绘在 md-tbl-* 横向滚动视口的父 Column 上。
    const tableFrame = this.table && type === 'Scroll' && node.getId()?.startsWith('md-tbl-') ?
      node.getParent() : null
    const surface = isImage ? node : tableFrame
    if (surface) {
      const position = surface.getPositionToWindow()
      const size = surface.getMeasuredSize()
      if (size.width > 0 && size.height > 0) {
        areas.push({
          id: surface.getUniqueId(), isTable: !isImage, x: Number(position.x) - originX, y: Number(position.y) - originY,
          width: this.getUIContext().px2vp(size.width), height: this.getUIContext().px2vp(size.height)
        })
      }
      if (isImage || !this.images) {
        return
      }
    }
    for (let i = 0; i < node.getChildrenCount(); i++) {
      const child = node.getChild(i)
      if (child) {
        this.collectMediaAreas(child, originX, originY, areas)
      }
    }
  }

  build() {
    Column() {
      ForEach(this.areas, (_area: MediaArea, index: number) => {
        Stack() {
          chatRichContentBackdrop(this.areas[index].isTable ? CANGJIE_TABLE_RADIUS : this.imageRadius)
        }
        .width(this.areas[index].width)
        .height(this.areas[index].height)
        .clip(false)
        .position({ x: this.areas[index].x, y: this.areas[index].y })
        .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
        .accessibilityLevel('no-hide-descendants')
      }, (area: MediaArea) => area.id.toString())
      Column() {
        this.content()
        if (this.table) {
          ForEach(this.areas, (_area: MediaArea, index: number) => {
            if (this.areas[index].isTable) {
              TablePerimeterMask({ area: this.areas[index] })
            }
          }, (area: MediaArea) => area.id.toString())
        }
      }
      .width('100%')
      .id(this.contentId)
      .alignItems(HorizontalAlign.Start)
      .blendMode(BlendMode.SRC_OVER, this.table ? BlendApplyType.OFFSCREEN : BlendApplyType.FAST)
      .onAppear((): void => { this.observeLayout() })
    }
    .width('100%')
    .clip(false)
  }
}

@Builder
export function chatMarkdownImageMaterial(content: () => void) {
  MarkdownMediaMaterial({ content: content })
}
