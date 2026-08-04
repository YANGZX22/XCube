import { MDBaseController } from '../controller/BaseController';

export namespace LineImpl {
  export function handleLineColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getLineColor()
  }
}