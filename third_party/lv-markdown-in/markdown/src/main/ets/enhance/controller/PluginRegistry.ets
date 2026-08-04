import { MarkdownPlugin } from '../model/MarkdownPlugin'

export class MarkdownPluginRegistry {
  private static pluginMap: Map<string, Map<string, MarkdownPlugin>> = new Map()

  static registerPlugins(pluginUnion: string, plugins: MarkdownPlugin[]) {
    const pluginRegistry: Map<string, MarkdownPlugin> = new Map()
    for (let i = 0; i < plugins.length; i++) {
      pluginRegistry.set(plugins[i].key, plugins[i])
    }
    MarkdownPluginRegistry.pluginMap.set(pluginUnion, pluginRegistry)
  }

  static getPlugin(pluginUnion: string, pluginKey: string): MarkdownPlugin | undefined {
    return MarkdownPluginRegistry.pluginMap.get(pluginUnion)?.get(pluginKey)
  }

  static destroy(pluginUnion: string) {
    MarkdownPluginRegistry.pluginMap.delete(pluginUnion)
  }
}
