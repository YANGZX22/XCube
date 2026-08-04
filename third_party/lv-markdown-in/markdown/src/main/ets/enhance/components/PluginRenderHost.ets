import { MarkdownPluginRegistry } from '../controller/PluginRegistry'
import { InlinePluginLayout } from '../model/MarkdownPlugin'
import { PluginNode } from '../model/TreeNode'

@Component
export struct PluginBlockRenderHost {
  @Prop node: PluginNode
  @BuilderParam renderer: (node: PluginNode) => void

  build() {
    this.renderer(this.node)
  }
}

@Component
export struct PluginInlineRenderHost {
  @Prop node: PluginNode
  @BuilderParam renderer: (node: PluginNode) => void

  build() {
    this.renderer(this.node)
  }
}

export function getPluginRenderer(pluginUnion: string, node: PluginNode): ((node: PluginNode) => void) | undefined {
  return MarkdownPluginRegistry.getPlugin(pluginUnion, node.pluginKey)?.render
}

export function getPluginInlineLayout(pluginUnion: string, node: PluginNode): InlinePluginLayout | undefined {
  const layout = MarkdownPluginRegistry.getPlugin(pluginUnion, node.pluginKey)?.inlineLayout?.(node)
  if (!layout || layout.width <= 0 || layout.height <= 0) {
    return undefined
  }
  return layout
}

export function hasPluginInlineOverlay(pluginUnion: string, node: PluginNode): boolean {
  return !!getPluginRenderer(pluginUnion, node) && !!getPluginInlineLayout(pluginUnion, node)
}

export function getPluginInlinePlaceholderWidth(pluginUnion: string, node: PluginNode): number {
  return getPluginInlineLayout(pluginUnion, node)?.width || 0
}

export function getPluginInlinePlaceholderHeight(pluginUnion: string, node: PluginNode): number {
  return getPluginInlineLayout(pluginUnion, node)?.height || 0
}

@Builder
export function PluginInlinePlaceholderSpan(pluginUnion: string, node: PluginNode) {
  if (hasPluginInlineOverlay(pluginUnion, node)) {
    ImageSpan("")
      .width(getPluginInlinePlaceholderWidth(pluginUnion, node))
      .height(getPluginInlinePlaceholderHeight(pluginUnion, node))
      .objectFit(ImageFit.Fill)
      .verticalAlign(ImageSpanAlignment.CENTER)
      .opacity(0)
  } else {
    Span(node.raw)
  }
}
