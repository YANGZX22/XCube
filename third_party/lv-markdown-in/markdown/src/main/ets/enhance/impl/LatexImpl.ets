import { MDBaseController } from '../controller/BaseController';
import { image } from '@kit.ImageKit';

export namespace LatexImpl {
  export function handleLatexMathTextSize(markdownUnion: string): number {
    return MDBaseController.getMarkdownController(markdownUnion).getLatexMathTextSize()
  }

  export function handleLatexMathTextColor(markdownUnion: string): number {
    return MDBaseController.getMarkdownController(markdownUnion).getLatexMathTextColor()
  }

  export function handleClick(markdownUnion: string, text: string, pixelMap: image.PixelMap) {
    let h = MDBaseController.getMarkdownController(markdownUnion).getLatexClickListener()
    h(text, pixelMap)
  }
}
