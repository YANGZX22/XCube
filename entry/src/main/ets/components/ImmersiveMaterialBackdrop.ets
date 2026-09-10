import { uiMaterial } from '@kit.ArkUI'
import { shouldUseWrappedMaterial, WrappedMaterialFactory, WRAPPED_MATERIAL_THIN } from '../utils/WrappedMaterialSupport'
import { getBlurBottomShadow } from '../utils/BlurShadowUtils'

export const IMMERSIVE_MATERIAL_SHADOW_OUTSET = 24

// 用底部 TabBar 为内部 Row 提供材质生效区域；不使用浮动 TabBar 的胶囊背板。
// 仅绘制背景，调用方将它绝对定位在原有前景后面，不迁移输入、点击或业务 builder。
@ComponentV2
export struct ImmersiveMaterialBackdrop {
  @Param surfaceWidth: number = 0
  @Param surfaceHeight: number = 0
  @Param cornerRadius: number | BorderRadiuses = 20
  @Param materialStyle: uiMaterial.ImmersiveStyle = WRAPPED_MATERIAL_THIN
  @Param materialColor: ResourceColor = Color.Transparent
  @Param applyShadow: boolean = true
  @Param materialFactory: WrappedMaterialFactory | undefined = undefined

  @Builder
  private MaterialBar() {
    Row() {
      Row() {}
        .width(this.surfaceWidth)
        .height(this.surfaceHeight)
        .borderRadius(this.cornerRadius)
        .systemMaterial(this.materialFactory !== undefined ? this.materialFactory() : new uiMaterial.ImmersiveMaterial({
          style: this.materialStyle,
          materialColor: this.materialColor,
          applyShadow: this.applyShadow
        }))
        .clip(false)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .clip(false)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.surfaceWidth > 0 && this.surfaceHeight > 0) {
        if (shouldUseWrappedMaterial()) {
          Tabs() {
            TabContent() {}
              .tabBar(this.MaterialBar())
          }
          .barHeight(this.surfaceHeight + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          // 普通底部 TabBar 已满足内部 Row 的材质作用域，无需与空内容区重叠。
          // true 会先给整个矩形宿主注入 COMPONENT_THICK，再清除时可能出现首帧背景。
          .barOverlap(false)
          .barPosition(BarPosition.End)
          .vertical(false)
          .barMode(BarMode.Fixed)
          .scrollable(false)
          .fadingEdge(false)
          // 透明宿主四周留白，材质 Row 的实际宽高、圆角均不被扩大或裁剪。
          .width(this.surfaceWidth + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          .height(this.surfaceHeight + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          .backgroundColor(Color.Transparent)
          .clip(false)
          .divider(null)
          .barBackgroundColor(Color.Transparent)
          // 宿主始终无普通模糊；唯一材质来自上面的圆角 Row。
          .barBackgroundBlurStyle(BlurStyle.NONE)
          // None 只跳过当前节点；必须连同内部 TabBar 一起退出触摸命中，避免外扩留白抢走邻近按钮点击。
          .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
          .focusable(false)
          .accessibilityLevel('no-hide-descendants')
          .position({ x: -IMMERSIVE_MATERIAL_SHADOW_OUTSET, y: -IMMERSIVE_MATERIAL_SHADOW_OUTSET })
        } else {
          Row() {}
            .width(this.surfaceWidth)
            .height(this.surfaceHeight)
            .backgroundColor(Color.Transparent)
            .borderRadius(this.cornerRadius)
            .backdropBlur(24)
            .shadow(getBlurBottomShadow(this.applyShadow))
            .clip(false)
        }
      }
    }
    .width(this.surfaceWidth)
    .height(this.surfaceHeight)
    .clip(false)
    .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
    .focusable(false)
    .accessibilityLevel('no-hide-descendants')
  }
}

// 装饰层不参与父容器的固有尺寸计算，避免上一次背板高度锁住前景的原生自适应布局。
@ComponentV2
export struct ImmersiveMaterialAnchor {
  @Param surfaceWidth: number = 0
  @Param surfaceHeight: number = 0
  @Param cornerRadius: number | BorderRadiuses = 20
  @Param materialFactory: WrappedMaterialFactory | undefined = undefined
  @Param fallbackShadow: boolean = true

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ImmersiveMaterialBackdrop({
        surfaceWidth: this.surfaceWidth,
        surfaceHeight: this.surfaceHeight,
        cornerRadius: this.cornerRadius,
        materialFactory: this.materialFactory,
        applyShadow: this.fallbackShadow
      })
        .position({ x: 0, y: 0 })
    }
    .width(0)
    .height(0)
    .position({ x: 0, y: 0 })
    .clip(false)
    .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
    .focusable(false)
    .accessibilityLevel('no-hide-descendants')
  }
}
