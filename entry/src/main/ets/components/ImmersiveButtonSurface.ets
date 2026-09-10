import { WrappedMaterialFactory } from '../utils/WrappedMaterialSupport'
import { ImmersiveMaterialAnchor } from './ImmersiveMaterialBackdrop'

// 保留原生 Button 及其事件。仅把材质交给合法 TabBar 内的 Row，装饰层占位始终为零。
@ComponentV2
export struct ImmersiveButtonSurface {
  @Param materialFactory: WrappedMaterialFactory | undefined = undefined
  @Param fallbackShadow: boolean = true
  @Param cornerRadius: number | undefined = undefined
  @Local surfaceWidth: number = 0
  @Local surfaceHeight: number = 0
  @BuilderParam content: () => void

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.materialFactory !== undefined) {
        ImmersiveMaterialAnchor({
          surfaceWidth: this.surfaceWidth,
          surfaceHeight: this.surfaceHeight,
          cornerRadius: this.cornerRadius ?? Math.min(this.surfaceWidth, this.surfaceHeight) / 2,
          materialFactory: this.materialFactory,
          fallbackShadow: this.fallbackShadow
        })
      }
      this.content()
    }
    .clip(false)
    .onAreaChange((_oldArea: Area, area: Area) => {
      const width = Number(area.width)
      const height = Number(area.height)
      if (Number.isFinite(width) && width > 0 && Math.abs(width - this.surfaceWidth) > 0.1) {
        this.surfaceWidth = width
      }
      if (Number.isFinite(height) && height > 0 && Math.abs(height - this.surfaceHeight) > 0.1) {
        this.surfaceHeight = height
      }
    })
  }
}
