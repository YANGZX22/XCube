import { ImageImpl } from '../impl/ImageImpl';
import { ImageNode } from '../model/TreeNode';

const TAG = "ImageBuilder"

@Builder
export function ImageBuilder(markdownUnion: string, item: ImageNode) {
  ImageSpan(ImageImpl.handleImageSrc(markdownUnion, item.url))
    .width(ImageImpl.handleImageWidth(markdownUnion, item))
    .height(ImageImpl.handleImageHeight(markdownUnion, item))
    .constraintSize({
      maxWidth: ImageImpl.handleImageMaxWidth(markdownUnion, item),
      maxHeight: ImageImpl.handleImageMaxHeight(markdownUnion, item)
    })
    .objectFit(ImageFit.Contain)
    .borderRadius(ImageImpl.handleImageBorderRadius(markdownUnion))
    .margin({ top: 4, bottom: 4 })
    .onClick(() => {
      ImageImpl.handleClick(markdownUnion, item.url)
    })
}