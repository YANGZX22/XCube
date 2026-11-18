import { ImmersiveListSurface } from './ImmersiveListSurface'

// 背板限定在可视区内，滚动只移动前景的模型行。
@ComponentV2
export struct ModelListMaterialHost {
  @Param useMaterial: boolean = true
  @BuilderParam content: () => void

  build() {
    Column() {
      if (this.useMaterial) {
        ImmersiveListSurface({ isImmersive: true, cornerRadius: 16 }) {
          Column() {
            this.content()
          }
          .width('100%')
          .height('100%')
          .borderRadius(16)
          .clip(true)
        }
      } else {
        this.content()
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: this.useMaterial ? 16 : 0, right: this.useMaterial ? 16 : 0 })
  }
}
