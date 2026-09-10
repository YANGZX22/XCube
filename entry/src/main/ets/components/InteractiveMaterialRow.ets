import { uiMaterial } from '@kit.ArkUI'
import { IMMERSIVE_MATERIAL_SHADOW_OUTSET } from './ImmersiveMaterialBackdrop'
import { shouldUseWrappedMaterial, WrappedMaterialModifier } from '../utils/WrappedMaterialSupport'

// 整组工具栏共用一个原生材质 Row；子 Button 保留自己的事件，Row 不绑定业务点击。
@ComponentV2
export struct InteractiveMaterialRow {
  @Param surfaceWidth: number = 0
  @Param surfaceHeight: number = 34
  @Param spacing: number = 2
  @Param horizontalPadding: number = 3
  @BuilderParam content: () => void

  private interceptSurfaceTouch(event: TouchEvent): HitTestMode {
    const touch = event.changedTouches.length > 0 ? event.changedTouches[0] : event.touches[0]
    if (touch && Number.isFinite(this.surfaceWidth) && Number.isFinite(this.surfaceHeight) &&
      touch.x >= 0 && touch.x < this.surfaceWidth && touch.y >= 0 && touch.y < this.surfaceHeight) {
      return HitTestMode.Transparent
    }
    return HitTestMode.BLOCK_DESCENDANTS
  }

  @Builder
  private MaterialBar() {
    Row() {
      Row({ space: this.spacing }) {
        this.content()
      }
      .width(this.surfaceWidth)
      .height(this.surfaceHeight)
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
      .alignItems(VerticalAlign.Center)
      .borderRadius(this.surfaceHeight / 2)
      .backgroundColor(Color.Transparent)
      .attributeModifier(new WrappedMaterialModifier(() => new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN,
        materialColor: Color.Transparent,
        interactive: true,
        lightEffect: {},
        applyShadow: true
      }), shouldUseWrappedMaterial(), true))
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .accessibilityLevel('no')
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
          .barOverlap(true)
          .barPosition(BarPosition.End)
          .vertical(false)
          .barMode(BarMode.Fixed)
          .scrollable(false)
          .fadingEdge(false)
          .width(this.surfaceWidth + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          .height(this.surfaceHeight + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          .backgroundColor(Color.Transparent)
          .clip(false)
          .divider(null)
          .barBackgroundColor(Color.Transparent)
          .barBackgroundBlurStyle(BlurStyle.NONE)
          .hitTestBehavior(HitTestMode.Transparent)
          .accessibilityLevel('no')
          .position({ x: -IMMERSIVE_MATERIAL_SHADOW_OUTSET, y: -IMMERSIVE_MATERIAL_SHADOW_OUTSET })
        } else {
          this.MaterialBar()
        }
      }
    }
    .width(this.surfaceWidth)
    .height(this.surfaceHeight)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .onTouchIntercept((event: TouchEvent): HitTestMode => this.interceptSurfaceTouch(event))
    .accessibilityLevel('no')
  }
}
