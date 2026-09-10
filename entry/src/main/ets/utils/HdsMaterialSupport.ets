import { BlurStrategy, HdsTabsAttribute, SystemMaterialParams } from '@kit.UIDesignKit'
import { shouldUseWrappedMaterial } from './WrappedMaterialSupport'

// HDS 与 ArkUI 包装材质共用自动检测和手动降级策略。
// 使用 SDK 定义的枚举数值，避免低版本分支访问 hdsMaterial 枚举对象。
export function getHdsSystemMaterialEffect(materialType: number = 101,
  materialLevel: number = 10): SystemMaterialParams {
  return {
    materialType: shouldUseWrappedMaterial() ? materialType : 0,
    materialLevel: materialLevel
  }
}

// 透明高斯模糊参数，不使用含白色蒙版的 BlurStyle 材质预设。
// 只在降级分支调用；沉浸分支不要写入 radius: 0 的 backgroundEffect。
export function getHdsFallbackBackgroundEffect(): BackgroundEffectOptions {
  return {
    radius: 24,
    color: Color.Transparent,
    saturation: 1,
    brightness: 1,
    policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
    inactiveColor: Color.Transparent
  }
}

// 必须放在 barFloatingStyle 之后，仅设置 TabBar 背板，不模糊页面或页签文字。
// 用同一 AttributeModifier 管理两种状态，恢复材质时由属性差分清理不再设置的模糊属性。
export class HdsTabsBlurModifier implements AttributeModifier<HdsTabsAttribute> {
  private useMaterial: boolean

  constructor(useMaterial: boolean) {
    this.useMaterial = useMaterial
  }

  applyNormalAttribute(instance: HdsTabsAttribute): void {
    // SDK 枚举数值：ADAPTIVE = 2，ENABLE = 0，避免低版本读取枚举对象。
    const strategy: BlurStrategy = this.useMaterial ? 2 : 0
    instance.blurStrategy(strategy)
    if (!this.useMaterial) {
      instance
        .barBackgroundStyle(undefined)
        .barBackgroundColor(Color.Transparent)
        .barBackgroundBlurStyle(BlurStyle.NONE)
        .barBackgroundEffect(getHdsFallbackBackgroundEffect())
    }
  }
}

export function getHdsMaterialLightColor(color: ResourceColor): ResourceColor | undefined {
  return shouldUseWrappedMaterial() ? color : undefined
}

// 自绘底栏时 HdsTabs 仅保留页面切换能力，隐藏栏不能继续绘制默认明暗渐变或模糊。
export class DrawnTabsContentModifier implements AttributeModifier<HdsTabsAttribute> {
  applyNormalAttribute(instance: HdsTabsAttribute): void {
    instance
      .blurStrategy(1)
      .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: 0 })
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barBackgroundEffect({
        radius: 0,
        color: Color.Transparent,
        saturation: 1,
        brightness: 1
      })
  }
}
