import { MDBaseController } from '../controller/BaseController';

export namespace FootnoteImpl {
  export function handleFootnoteTextColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getFootnoteTextColor()
  }
}