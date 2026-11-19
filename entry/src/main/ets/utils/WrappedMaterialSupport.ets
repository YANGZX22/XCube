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

export function createStaticRegularMaterial(materialColor: ResourceColor = Color.Transparent): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.REGULAR,
    materialColor: materialColor,
    interactive: false,
    lightEffect: null
  })
}

export function getStaticSheetMaterial(): uiMaterial.Material | undefined {
  return shouldUseWrappedMaterial() ? createStaticRegularMaterial() : undefined
}

export function getPopupMaterial(): uiMaterial.Material | undefined {
  if (shouldUseWrappedMaterial()) {
    return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK })
  }
  return isWrappedMaterialApiAvailable() ? uiMaterial.Material.empty : undefined
}

export function getImmersiveMenuOptions(onDisappear?: () => void): MenuOptions {
  const options: MenuOptions = { systemMaterial: getPopupMaterial(), onDisappear: onDisappear }
  if (!shouldUseWrappedMaterial()) {
    options.backgroundColor = Color.Transparent
    options.backgroundBlurStyle = BlurStyle.NONE
    options.backgroundEffect = { radius: 24, saturation: 1, brightness: 1, color: Color.Transparent }
  }
  return options
}

function createThinMenuMaterial(): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    materialColor: Color.Transparent
  })
}

let deviceSupportsThinMaterial: boolean | undefined = undefined

function shouldUseThinMenuMaterial(): boolean {
  if (!shouldUseWrappedMaterial()) return false
  if (deviceSupportsThinMaterial === undefined) {
    try {
      // 流畅档的原生菜单会使用系统底色，走透明模糊分支。
      deviceSupportsThinMaterial = uiMaterial.isImmersiveMaterialSupported() &&
        uiMaterial.getGlobalMaterialLevel() !== uiMaterial.MaterialLevel.SMOOTH
    } catch (_error) {
      deviceSupportsThinMaterial = false
    }
  }
  return deviceSupportsThinMaterial
}

function getThinMenuBlurEffect(): BackgroundEffectOptions {
  return {
    radius: 12,
    saturation: 1,
    brightness: 1,
    color: Color.Transparent,
    policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
    inactiveColor: Color.Transparent
  }
}

export function getThinMenuOptions(onDisappear?: () => void): MenuOptions {
  const options: MenuOptions = {
    backgroundColor: Color.Transparent,
    backgroundBlurStyle: BlurStyle.NONE,
    onDisappear: onDisappear
  }
  if (shouldUseThinMenuMaterial()) {
    options.systemMaterial = createThinMenuMaterial()
  } else {
    options.systemMaterial = isWrappedMaterialApiAvailable() ? uiMaterial.Material.empty : undefined
    options.backgroundEffect = getThinMenuBlurEffect()
  }
  return options
}

export class ThinSelectModifier implements AttributeModifier<SelectAttribute> {
  private readonly useMaterial: boolean = shouldUseThinMenuMaterial()
  private readonly trigger: 'thin' | 'plain'

  constructor(trigger: 'thin' | 'plain' = 'thin') {
    this.trigger = trigger
  }

  applyNormalAttribute(select: SelectAttribute): void {
    select.backgroundColor(Color.Transparent)
    select.menuBackgroundColor(Color.Transparent)
    if (this.useMaterial) {
      select.backgroundBlurStyle(BlurStyle.NONE)
      select.menuBackgroundBlurStyle(BlurStyle.NONE)
      select.systemMaterial(this.trigger === 'plain' ? uiMaterial.Material.empty : new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN,
        materialColor: Color.Transparent,
        applyShadow: false,
        interactive: false,
        lightEffect: null
      }))
      select.menuSystemMaterial(createThinMenuMaterial())
      return
    }

    if (isWrappedMaterialApiAvailable()) {
      select.systemMaterial(uiMaterial.Material.empty)
      select.menuSystemMaterial(uiMaterial.Material.empty)
      select.menuBackgroundBlurStyle(BlurStyle.NONE)
      select.menuBackgroundEffect(getThinMenuBlurEffect())
    } else {
      // 旧版 Select 没有独立的自定义弹窗模糊接口。
      select.menuBackgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    }
    select.backgroundBlurStyle(this.trigger === 'plain' ? BlurStyle.NONE : BlurStyle.COMPONENT_THIN)
    if (this.trigger === 'thin') {
      select.shadow(getBlurBottomShadow())
    }
  }
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
