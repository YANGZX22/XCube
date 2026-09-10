import { deviceInfo } from '@kit.BasicServicesKit'
import { uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import { getBlurBottomShadow } from './BlurShadowUtils'

// 延迟到版本检查通过后，才访问 ImmersiveStyle 或创建 Material。
export type WrappedMaterialFactory = () => uiMaterial.Material | undefined
// 与 SDK ImmersiveStyle 的数值定义一致，避免组件参数初始化时访问新版本枚举对象。
export const WRAPPED_MATERIAL_THIN: uiMaterial.ImmersiveStyle = 1
export const WRAPPED_MATERIAL_REGULAR: uiMaterial.ImmersiveStyle = 2

export function isWrappedMaterialApiAvailable(): boolean {
  try {
    // apiAvailable 本身也是新接口；缺失、返回 false 或抛错均保守降级。
    return typeof deviceInfo.apiAvailable === 'function' && deviceInfo.apiAvailable('26.0.0')
  } catch (_error) {
    return false
  }
}

export function shouldUseWrappedMaterial(): boolean {
  return !getAppUiState().forceWrappedMaterialBlur && isWrappedMaterialApiAvailable()
}

// 支持材质的设备在降级时显式清除旧材质；低版本不访问 systemMaterial 或 Material.empty。
export class WrappedMaterialModifier implements AttributeModifier<CommonAttribute> {
  private factory: WrappedMaterialFactory
  private useMaterial: boolean
  private fallbackShadow: boolean

  constructor(factory: WrappedMaterialFactory, useMaterial: boolean, fallbackShadow: boolean = false) {
    this.factory = factory
    this.useMaterial = useMaterial
    this.fallbackShadow = fallbackShadow
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    const apiAvailable = isWrappedMaterialApiAvailable()
    if (this.useMaterial && !getAppUiState().forceWrappedMaterialBlur && apiAvailable) {
      instance.systemMaterial(this.factory() ?? uiMaterial.Material.empty)
    } else {
      if (apiAvailable) {
        // undefined 可能跟随系统默认材质；empty 才是组件级明确关闭。
        instance.systemMaterial(uiMaterial.Material.empty)
      }
      instance.backgroundColor(Color.Transparent).backdropBlur(24)
      if (this.fallbackShadow) {
        instance.shadow(getBlurBottomShadow())
      }
    }
  }
}
