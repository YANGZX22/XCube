import { uiMaterial } from '@kit.ArkUI'
import { isWrappedMaterialApiAvailable, shouldUseWrappedMaterial } from './WrappedMaterialSupport'

// 菜单本身支持原生系统材质，不需要为其包装 Navigation 或 Tabs。
export function getLvMarkdownSelectionMenuOptions(): MenuOptions {
  if (shouldUseWrappedMaterial()) {
    return {
      systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK })
    }
  }

  const options: MenuOptions = {
    backgroundColor: Color.Transparent,
    backgroundBlurStyle: BlurStyle.NONE,
    backgroundEffect: { radius: 24, saturation: 1, brightness: 1, color: Color.Transparent }
  }
  if (isWrappedMaterialApiAvailable()) {
    options.systemMaterial = uiMaterial.Material.empty
  }
  return options
}
