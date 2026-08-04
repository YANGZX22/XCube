import { ImageImpl } from '../impl/ImageImpl'
import { ImageNode } from '../model/TreeNode'

/**
 * @deprecated
 */
@Component
export struct ImageRender {
  @Consume markdownUnion: string
  @State image: ImageNode | undefined = undefined

  build() {
    Image(ImageImpl.handleImageSrc(this.markdownUnion, this.image?.url))
      .width(ImageImpl.handleImageWidth(this.markdownUnion, this.image))
      .height(ImageImpl.handleImageHeight(this.markdownUnion, this.image))
      .constraintSize({
        maxWidth: ImageImpl.handleImageMaxWidth(this.markdownUnion, this.image),
        maxHeight: ImageImpl.handleImageMaxHeight(this.markdownUnion, this.image)
      })
      .borderRadius(ImageImpl.handleImageBorderRadius(this.markdownUnion))
      .backgroundColor("#EEE")
  }
}