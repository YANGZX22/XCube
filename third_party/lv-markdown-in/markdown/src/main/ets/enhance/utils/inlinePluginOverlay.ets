import { common2D } from '@kit.ArkGraphics2D'
import text from '@ohos.graphics.text'
import { hasPluginInlineOverlay, getPluginInlineLayout } from '../components/PluginRenderHost'
import { TextImpl } from '../impl/TextImpl'
import { InlinePluginLayout } from '../model/MarkdownPlugin'
import { PluginNode, TextNode, TreeNode } from '../model/TreeNode'

export class InlinePluginPlacement {
  node: PluginNode
  start: number
  end: number
  layout: InlinePluginLayout

  constructor(node: PluginNode, start: number, end: number, layout: InlinePluginLayout) {
    this.node = node
    this.start = start
    this.end = end
    this.layout = layout
  }
}

export class InlinePluginRect {
  node: PluginNode
  start: number
  end: number
  left: number
  top: number
  width: number
  height: number

  constructor(placement: InlinePluginPlacement, rect: common2D.Rect) {
    this.node = placement.node
    this.start = placement.start
    this.end = placement.end
    this.left = rect.left
    this.top = rect.top
    this.width = placement.layout.width
    this.height = placement.layout.height
  }
}

export function isSameInlinePluginRects(left: InlinePluginRect[], right: InlinePluginRect[]): boolean {
  if (left.length != right.length) {
    return false
  }
  for (let i = 0; i < left.length; i++) {
    if (left[i].start != right[i].start || left[i].end != right[i].end || left[i].node.raw != right[i].node.raw ||
      Math.abs(left[i].left - right[i].left) > 0.5 || Math.abs(left[i].top - right[i].top) > 0.5 ||
      Math.abs(left[i].width - right[i].width) > 0.5 || Math.abs(left[i].height - right[i].height) > 0.5) {
      return false
    }
  }
  return true
}

function getRenderedTextLength(markdownUnion: string, data: ESObject): number {
  const value = TextImpl.handleText(markdownUnion, data as TreeNode)
  return value ? value.length : 0
}

function appendInlinePlugin(pluginUnion: string, node: PluginNode, list: InlinePluginPlacement[], index: number): number {
  const layout = getPluginInlineLayout(pluginUnion, node)
  if (hasPluginInlineOverlay(pluginUnion, node) && layout) {
    list.push(new InlinePluginPlacement(node, index, index + 1, layout))
    return index + 1
  }
  return index + (node.raw || '').length
}

function appendSpanBuilderNode(markdownUnion: string, pluginUnion: string, data: TreeNode,
  base: TreeNode | undefined, list: InlinePluginPlacement[], index: number): number {
  if (data.type == 'text' || data.type == 'inlineCode' || data.type == 'footnoteRef' ||
    data.type == 'inlineHtmlFont') {
    return index + getRenderedTextLength(markdownUnion, data as ESObject)
  }
  if (data.type == 'plugin') {
    return appendInlinePlugin(pluginUnion, data as PluginNode, list, index)
  }
  if (data.type == 'latex') {
    return index + 1
  }
  if (!data.children || data.children.length == 0) {
    return index
  }
  for (let i = 0; i < data.children.length; i++) {
    const item = data.children[i] as TreeNode
    if (item.type == 'text') {
      index += getRenderedTextLength(markdownUnion, {
        text: (item as TextNode).text,
        type: data.type,
        url: data.type == 'link' ? (data as ESObject).url : undefined
      })
      continue
    }
    if (item.type == 'plugin') {
      index = appendInlinePlugin(pluginUnion, item as PluginNode, list, index)
      continue
    }
    if (item.type == 'inlineCode') {
      index += getRenderedTextLength(markdownUnion, item as ESObject)
      continue
    }
    if (!item.children || item.children.length == 0) {
      index = appendSpanBuilderNode(markdownUnion, pluginUnion, item, data, list, index)
      continue
    }
    for (let j = 0; j < item.children.length; j++) {
      const item2 = item.children[j] as TreeNode
      if (item2.type == 'plugin') {
        index = appendInlinePlugin(pluginUnion, item2 as PluginNode, list, index)
      } else {
        index += getRenderedTextLength(markdownUnion, {
          text: (item2 as TextNode).text,
          type: item.type,
          url: item.type == 'link' ? (item as ESObject).url : undefined
        })
      }
    }
  }
  return index
}

function appendTextRenderNode(markdownUnion: string, pluginUnion: string, base: TreeNode,
  list: InlinePluginPlacement[], index: number): number {
  if (base.type == 'text' || base.type == 'inlineCode' || base.type == 'footnoteRef' ||
    base.type == 'inlineHtmlFont') {
    return index + getRenderedTextLength(markdownUnion, base as ESObject)
  }
  if (!base.children || base.children.length == 0) {
    return index
  }
  for (let i = 0; i < base.children.length; i++) {
    const item = base.children[i] as TreeNode
    if (item.type == 'plugin') {
      index = appendInlinePlugin(pluginUnion, item as PluginNode, list, index)
      continue
    }
    if (item.type == 'text' || item.type == 'inlineHtmlFont') {
      index += getRenderedTextLength(markdownUnion, {
        text: (item as TextNode).text,
        type: item.type == 'inlineHtmlFont' ? item.type : base.type,
        url: base.type == 'link' ? (base as ESObject).url : undefined,
        color: item.type == 'inlineHtmlFont' ? (item as ESObject).color : undefined,
        size: item.type == 'inlineHtmlFont' ? (item as ESObject).size : undefined,
        face: item.type == 'inlineHtmlFont' ? (item as ESObject).face : undefined
      })
      continue
    }
    if (item.type == 'inlineCode') {
      index += getRenderedTextLength(markdownUnion, item as ESObject)
      continue
    }
    if (!item.children || item.children.length == 0) {
      index = appendSpanBuilderNode(markdownUnion, pluginUnion, item, base, list, index)
      continue
    }
    for (let j = 0; j < item.children.length; j++) {
      const item2 = item.children[j] as TreeNode
      if (item2.type == 'plugin') {
        index = appendInlinePlugin(pluginUnion, item2 as PluginNode, list, index)
      } else {
        index += getRenderedTextLength(markdownUnion, {
          text: (item2 as TextNode).text,
          type: item.type,
          url: item.type == 'link' ? (item as ESObject).url : undefined
        })
      }
    }
  }
  return index
}

export function buildParagraphInlinePluginPlacements(markdownUnion: string, pluginUnion: string,
  base: TreeNode | undefined): InlinePluginPlacement[] {
  const list: InlinePluginPlacement[] = []
  if (!base || !base.children || base.children.length == 0) {
    return list
  }
  let index = 0
  for (let i = 0; i < base.children.length; i++) {
    const item = base.children[i] as TreeNode
    if (item.type == 'image') {
      index += 1
    } else {
      index = appendSpanBuilderNode(markdownUnion, pluginUnion, item, base, list, index)
    }
  }
  return list
}

export function buildTextInlinePluginPlacements(markdownUnion: string, pluginUnion: string,
  base: TreeNode | undefined): InlinePluginPlacement[] {
  const list: InlinePluginPlacement[] = []
  if (!base) {
    return list
  }
  appendTextRenderNode(markdownUnion, pluginUnion, base, list, 0)
  return list
}

export function buildInlinePluginRects(controller: TextController, placements: InlinePluginPlacement[],
  ctx: UIContext): InlinePluginRect[] {
  const list: InlinePluginRect[] = []
  if (placements.length == 0) {
    return list
  }
  try {
    const layoutManager = controller.getLayoutManager()
    for (let i = 0; i < placements.length; i++) {
      const placement = placements[i]
      const rects = layoutManager.getRectsForRange({ start: placement.start, end: placement.end },
        text.RectWidthStyle.TIGHT, text.RectHeightStyle.TIGHT)
      if (rects.length == 0) {
        continue
      }
      list.push(new InlinePluginRect(placement, {
        left: ctx.px2vp(rects[0].rect.left),
        right: ctx.px2vp(rects[0].rect.right),
        top: ctx.px2vp(rects[0].rect.top),
        bottom: ctx.px2vp(rects[0].rect.bottom)
      }))
    }
  } catch (_err) {
  }
  return list
}
