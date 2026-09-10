import { uiMaterial } from '@kit.ArkUI'
import { IMMERSIVE_MATERIAL_SHADOW_OUTSET } from './ImmersiveMaterialBackdrop'
import { shouldUseWrappedMaterial, WrappedMaterialModifier } from '../utils/WrappedMaterialSupport'

// 输入内容与材质共用一个原生容器，仅开启光照；内部按钮仍有自己的材质交互。
@ComponentV2
export struct ImmersiveInputSurface {
  @Param minSurfaceHeight: number = 52
  @Param maxSurfaceHeight: number = 132
  @Param cornerRadius: number = 24
  @BuilderParam content: () => void
  @Local surfaceWidth: number = 0
  @Local measuredHeight: number = 52

  private get surfaceHeight(): number {
    return Math.max(this.minSurfaceHeight, Math.min(this.maxSurfaceHeight, this.measuredHeight))
  }

  private interceptSurfaceTouch(event: TouchEvent): HitTestMode {
    const touch = event.changedTouches.length > 0 ? event.changedTouches[0] : event.touches[0]
    if (touch && touch.x >= 0 && touch.x < this.surfaceWidth &&
      touch.y >= 0 && touch.y < this.surfaceHeight) {
      return HitTestMode.Transparent
    }
    return HitTestMode.BLOCK_DESCENDANTS
  }

  @Builder
  private MaterialBar() {
    Column() {
      Column() {
        this.content()
      }
      .width(this.surfaceWidth)
      .constraintSize({ minHeight: this.minSurfaceHeight, maxHeight: this.maxSurfaceHeight })
      .backgroundColor(Color.Transparent)
      .borderRadius(this.cornerRadius)
      .attributeModifier(new WrappedMaterialModifier(() => new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN,
        materialColor: Color.Transparent,
        applyShadow: true,
        interactive: false,
        lightEffect: {}
      }), shouldUseWrappedMaterial(), true))
      .clip(false)
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => {
        const height = Number(size.height)
        if (Number.isFinite(height) && height > 0 && Math.abs(height - this.measuredHeight) > 0.1) {
          this.measuredHeight = height
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding(IMMERSIVE_MATERIAL_SHADOW_OUTSET)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Color.Transparent)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .accessibilityLevel('no')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.surfaceWidth > 0) {
        if (shouldUseWrappedMaterial()) {
          Tabs() {
            TabContent() {}
              .tabBar(this.MaterialBar())
          }
          // 宿主始终给足最大测量空间，不能用上一帧的输入高度约束 TextArea。
          .barHeight(this.maxSurfaceHeight + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          .width(this.surfaceWidth + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          .height(this.maxSurfaceHeight + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          .barOverlap(true)
          .barPosition(BarPosition.End)
          .vertical(false)
          .barMode(BarMode.Fixed)
          .scrollable(false)
          .fadingEdge(false)
          .backgroundColor(Color.Transparent)
          .clip(false)
          .divider(null)
          .barBackgroundColor(Color.Transparent)
          .barBackgroundBlurStyle(BlurStyle.NONE)
          .hitTestBehavior(HitTestMode.Transparent)
          .accessibilityLevel('no')
          .position({ x: -IMMERSIVE_MATERIAL_SHADOW_OUTSET, y: -IMMERSIVE_MATERIAL_SHADOW_OUTSET })
        } else {
          // 普通容器提供相同的最大测量空间，降级后 TextArea 仍按原生高度伸缩。
          Stack({ alignContent: Alignment.TopStart }) {
            this.MaterialBar()
          }
          .width(this.surfaceWidth + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          .height(this.maxSurfaceHeight + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          .position({ x: -IMMERSIVE_MATERIAL_SHADOW_OUTSET, y: -IMMERSIVE_MATERIAL_SHADOW_OUTSET })
          .clip(false)
        }
      }
    }
    .width('100%')
    .height(this.surfaceHeight)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .onTouchIntercept((event: TouchEvent): HitTestMode => this.interceptSurfaceTouch(event))
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => {
      const width = Number(size.width)
      if (Number.isFinite(width) && width > 0 && Math.abs(width - this.surfaceWidth) > 0.1) {
        this.surfaceWidth = width
      }
    })
    .accessibilityLevel('no')
  }
}
