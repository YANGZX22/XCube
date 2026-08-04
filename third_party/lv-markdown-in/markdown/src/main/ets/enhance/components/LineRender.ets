import { LineImpl } from '../impl/LineImpl'

@Component
export struct LineRender {
  @Consume markdownUnion: string

  build() {
    Row()
      .width("100%")
      .height(0.8)
      .backgroundColor(LineImpl.handleLineColor(this.markdownUnion))
      .margin({ top: 2, bottom: 2 })
  }
}