import { MDBaseController } from '../controller/BaseController';
import { TextImpl } from './TextImpl';

export namespace UlImpl {
  export function handleTodoSelectedColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getTodoSelectedColor()
  }

  export function handleTodoSelectedSize(markdownUnion: string): ResourceStr | number {
    return MDBaseController.getMarkdownController(markdownUnion).getTodoSelectSize()
  }

  export function handleUlPointSize(markdownUnion: string): ResourceStr | number {
    return MDBaseController.getMarkdownController(markdownUnion).getUlPointSize()
  }

  export function handleUlPointColor(markdownUnion: string, item: ESObject): ResourceColor {
    let ulPointColor = MDBaseController.getMarkdownController(markdownUnion).getUlPointColor()
    if (ulPointColor) {
      return ulPointColor
    } else {
      return TextImpl.handleFontColor(markdownUnion, item)
    }
  }
}
