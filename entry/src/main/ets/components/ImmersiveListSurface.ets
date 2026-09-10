import { uiMaterial } from '@kit.ArkUI'
import { ImmersiveMaterialAnchor } from './ImmersiveMaterialBackdrop'

// 与列表左右两侧 56vp 圆形侧滑按钮的半径一致。
export const LIST_MATERIAL_CARD_RADIUS: number = 28

// 列表只替换背板，前景和原生点击、长按、侧滑仍留在原有 Row/ListItem 上。
@ComponentV2
export struct ImmersiveListSurface {
  @Param isImmersive: boolean = false
  @Param layoutWidth: Length = '100%'
  @Param cornerRadius: number | BorderRadiuses = LIST_MATERIAL_CARD_RADIUS
  @Local surfaceWidth: number = 0
  @Local surfaceHeight: number = 0
  @BuilderParam content: () => void

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.isImmersive && this.surfaceWidth > 0 && this.surfaceHeight > 0) {
        ImmersiveMaterialAnchor({
          surfaceWidth: this.surfaceWidth,
          surfaceHeight: this.surfaceHeight,
          cornerRadius: this.cornerRadius,
          materialFactory: () => new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR,
            materialColor: Color.Transparent,
            applyShadow: true,
            interactive: false
          })
        })
      }
      this.content()
    }
    .width(this.layoutWidth)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .accessibilityLevel('no')
    // 零占位背板不影响前景测量；高度随原生内容、字号和可用宽度伸缩。
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
