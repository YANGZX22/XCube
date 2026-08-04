import { MDBaseController } from '../controller/BaseController'
import { ImageDialogController } from '../controller/ImageDialogController'
import { ImageNode } from '../model/TreeNode'

export namespace ImageImpl {
  export function handleImageSrc(markdownUnion: string, src?: string): ResourceStr {
    if (checkRawfileUri(src)) {
      return handleRawfileImage(src)
    }
    // 仅支持 http, https 协议的图片设置加载代理，$rawfile 不支持设置代理。
    return MDBaseController.getMarkdownController(markdownUnion).getImageLoadProxy(src || "")
  }

  function checkRawfileUri(src?: string) {
    if (src && src.indexOf("$rawfile(") !== -1) {
      return true
    }
    return false
  }

  export function handleRawfileImage(src?: string): Resource | "" {
    if (!src) {
      return ""
    }
    // 使用正则表达式匹配引号中的内容
    const result = src.match(/"([^"]+)"/);
    // 提取捕获组中的内容（索引1）
    const content = result ? result[1] : '';
    return $rawfile(content)
  }

  export function handleClick(markdownUnion: string, src: string) {
    let h = MDBaseController.getMarkdownController(markdownUnion).getImageClickListener()
    if (!h(src)) {
      ImageDialogController.getInstance().openBindSheet(markdownUnion, src)
    }
  }

  export function handleImageWidth(markdownUnion: string, image?: ImageNode): number | ResourceStr | null {
    if (image?.width) {
      return image.width
    }
    return MDBaseController.getMarkdownController(markdownUnion).getImageWidth()
  }

  export function handleImageMaxWidth(markdownUnion: string, image?: ImageNode): number | ResourceStr | null {
    if (image?.width) {
      return image.width
    }
    return MDBaseController.getMarkdownController(markdownUnion).getImageMaxWidth()
  }

  export function handleImageHeight(markdownUnion: string, image?: ImageNode): number | ResourceStr | null {
    if (image?.height) {
      return image.height
    }
    return MDBaseController.getMarkdownController(markdownUnion).getImageHeight()
  }

  export function handleImageMaxHeight(markdownUnion: string, image?: ImageNode): number | ResourceStr | null {
    if (image?.height) {
      return null
    }
    return MDBaseController.getMarkdownController(markdownUnion).getImageMaxHeight()
  }

  export function handleImageBorderRadius(markdownUnion: string): number | ResourceStr {
    return MDBaseController.getMarkdownController(markdownUnion).getImageBorderRadius()
  }
}