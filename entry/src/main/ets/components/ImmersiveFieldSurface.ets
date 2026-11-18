import { uiMaterial } from '@kit.ArkUI'
import { ImmersiveMaterialAnchor } from './ImmersiveMaterialBackdrop'

// 表单输入只使用静态材质背板；原生输入留在前景，保持焦点、键盘与密码显隐行为。
@ComponentV2
export struct ImmersiveFieldSurface {
  @Param cornerRadius: number = 16
  @Param fillHeight: boolean = false
  @Param layoutWidth: Length = '100%'
  @Param layoutWeightValue: number = 0
  @Param layoutMargin: Margin | Length = 0
  @BuilderParam content: () => void
  @Local surfaceWidth: number = 0
  @Local surfaceHeight: number = 0

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.surfaceWidth > 0 && this.surfaceHeight > 0) {
        ImmersiveMaterialAnchor({
          surfaceWidth: this.surfaceWidth,
          surfaceHeight: this.surfaceHeight,
          cornerRadius: this.cornerRadius,
          // 兼容模糊沿用统一的轻量底部阴影。
          fallbackShadow: true,
          materialFactory: () => new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR,
            materialColor: Color.Transparent,
            applyShadow: false,
            interactive: false,
            lightEffect: null
          })
        })
      }
      this.content()
    }
    .width(this.layoutWidth)
    .height(this.fillHeight ? '100%' : undefined)
    .layoutWeight(this.layoutWeightValue)
    .margin(this.layoutMargin)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .accessibilityLevel('no')
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => {
      const width = Number(size.width)
      const height = Number(size.height)
      if (Number.isFinite(width) && width >= 0 && Math.abs(width - this.surfaceWidth) > 0.1) {
        this.surfaceWidth = width
      }
      if (Number.isFinite(height) && height >= 0 && Math.abs(height - this.surfaceHeight) > 0.1) {
        this.surfaceHeight = height
      }
    })
  }
}
