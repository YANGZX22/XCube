import { PluginNode } from './TreeNode'

export type PluginDisplay = 'inline' | 'block'
export type PluginMatchMode = 'inline-prefix' | 'full-line'
export type PluginRenderer = (node: PluginNode) => void

export interface InlinePluginLayout {
  width: number
  height: number
}

export type PluginInlineLayoutResolver = (node: PluginNode) => InlinePluginLayout

export interface MarkdownPlugin {
  key: string
  display: PluginDisplay
  pattern: string
  flags?: string
  matchMode: PluginMatchMode
  selectable?: boolean
  inlineLayout?: PluginInlineLayoutResolver
  render: PluginRenderer
}

export interface PluginSyntaxManifest {
  key: string
  display: PluginDisplay
  pattern: string
  flags?: string
  matchMode: PluginMatchMode
  selectable?: boolean
}

export function toPluginSyntaxManifestList(plugins: MarkdownPlugin[] | undefined): PluginSyntaxManifest[] {
  const manifests: PluginSyntaxManifest[] = []
  if (!plugins || plugins.length == 0) {
    return manifests
  }
  for (let i = 0; i < plugins.length; i++) {
    manifests.push({
      key: plugins[i].key,
      display: plugins[i].display,
      pattern: plugins[i].pattern,
      flags: plugins[i].flags,
      matchMode: plugins[i].matchMode,
      selectable: plugins[i].selectable,
    })
  }
  return manifests
}
