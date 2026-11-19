import { getThinMenuOptions } from './WrappedMaterialSupport'

// 菜单本身支持原生系统材质，不需要为其包装 Navigation 或 Tabs。
export function getLvMarkdownSelectionMenuOptions(): MenuOptions {
  return getThinMenuOptions()
}
