import { uiMaterial } from '@kit.ArkUI'
import { IMMERSIVE_MATERIAL_SHADOW_OUTSET } from './ImmersiveMaterialBackdrop'
import { shouldUseWrappedMaterial, WrappedMaterialModifier, WRAPPED_MATERIAL_THIN } from '../utils/WrappedMaterialSupport'
import { getBlurBottomShadow } from '../utils/BlurShadowUtils'

// TabBar 提供材质生效区域，真正的 Button 承载材质、内容和点击。
// 不再将可交互背板嵌入另一个 Button，避免子 TabBar 与祖先 Button 竞争点击。
@ComponentV2
export struct InteractiveMaterialButton {
  @Param surfaceWidth: number = 0
  @Param surfaceHeight: number = 0
  @Param buttonType: ButtonType = ButtonType.Normal
  @Param buttonPadding: number = 0
  @Param isEnabled: boolean = true
  @Param interactive: boolean = true
  @Param materialStyle: uiMaterial.ImmersiveStyle = WRAPPED_MATERIAL_THIN
  @Param materialColor: ResourceColor = Color.Transparent
  @Param applyShadow: boolean = false
  @Param buttonShadow: ShadowOptions | undefined = undefined
  @Param responsePadding: number = 0
  @Event onActivate: () => void = (): void => {}
  @BuilderParam content: () => void

  private get hitPadding(): number {
    return Number.isFinite(this.responsePadding)
      ? Math.min(Math.max(this.responsePadding, 0), IMMERSIVE_MATERIAL_SHADOW_OUTSET) : 0
  }

  private interceptSurfaceTouch(event: TouchEvent): HitTestMode {
    const touch = event.changedTouches.length > 0 ? event.changedTouches[0] : event.touches[0]
    // clip(false) 允许材质形变越界绘制，但不能让透明留白重新抢走相邻控件的触摸。
    if (this.isEnabled && touch && Number.isFinite(this.surfaceWidth) && Number.isFinite(this.surfaceHeight) &&
      this.surfaceWidth > 0 && this.surfaceHeight > 0 &&
      touch.x >= -this.hitPadding && touch.x < this.surfaceWidth + this.hitPadding &&
      touch.y >= -this.hitPadding && touch.y < this.surfaceHeight + this.hitPadding) {
      return HitTestMode.Transparent
    }
    return HitTestMode.BLOCK_DESCENDANTS
  }

  @Builder
  private MaterialBar() {
    Row() {
      Button({ type: this.buttonType, stateEffect: false }) {
        this.content()
      }
        .width(this.surfaceWidth)
        .height(this.surfaceHeight)
        .padding(this.buttonPadding)
        .backgroundColor(Color.Transparent)
        .borderRadius(Math.min(this.surfaceWidth, this.surfaceHeight) / 2)
        .attributeModifier(new WrappedMaterialModifier(() => new uiMaterial.ImmersiveMaterial({
          style: this.materialStyle,
          materialColor: this.materialColor,
          applyShadow: this.applyShadow,
          interactive: this.interactive,
          lightEffect: {}
        }), shouldUseWrappedMaterial()))
        .clip(false)
        .shadow(this.buttonShadow ?? (!shouldUseWrappedMaterial() && this.applyShadow ? getBlurBottomShadow() : undefined))
        .enabled(this.isEnabled)
        .responseRegion({
          x: -this.hitPadding,
          y: -this.hitPadding,
          width: this.surfaceWidth + this.hitPadding * 2,
          height: this.surfaceHeight + this.hitPadding * 2
        })
        .onClick(() => {
          if (this.isEnabled) {
            this.onActivate()
          }
        })
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
          // 水平底部 TabBar 已提供材质作用域，不需要与空内容区重叠。
          // 避免 overlap 注入宿主厚模糊，导致回顶/回底等动态按钮出现时闪底色。
          .barOverlap(false)
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
          // 保留子 Button 的原生命中和手势，不全局拒绝内建识别器，也不隐藏按钮无障碍节点。
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
