import { MDBaseController } from '../controller/BaseController'

@Component
export struct RichBlockSurface {
  @Consume markdownUnion: string
  @Prop inset: number = 0
  @BuilderParam content: () => void

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (MDBaseController.getMarkdownController(this.markdownUnion).richBlockBackdrop) {
        MDBaseController.getMarkdownController(this.markdownUnion).richBlockBackdrop!.builder(14)
      }
      Column() {
        this.content()
      }
      .width('100%')
      .padding(this.inset)
    }
    .width('100%')
    .height(LayoutPolicy.wrapContent)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .accessibilityLevel('no')
  }
}
