import { uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import { VisualEffectsMode } from '../models/ThemeColors'
import { isWrappedMaterialApiAvailable, shouldUseWrappedMaterial } from './WrappedMaterialSupport'

export function shouldUseDrawnNavigation(): boolean {
  return getAppUiState().visualEffectsMode !== VisualEffectsMode.MANUSCRIPT && !shouldUseWrappedMaterial()
}

export function getDrawnNavigationBorder(): BorderOptions {
  return { width: 0.5, color: getAppUiState().isDarkMode ? '#40FFFFFF' : '#35FFFFFF' }
}

// 自绘导航按钮只保留普通点击，不继承系统材质或材质形变；不再叠一层模糊。
export class PlainNavigationButtonModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(instance: CommonAttribute): void {
    if (isWrappedMaterialApiAvailable()) {
      instance.systemMaterial(uiMaterial.Material.empty)
    }
  }
}
