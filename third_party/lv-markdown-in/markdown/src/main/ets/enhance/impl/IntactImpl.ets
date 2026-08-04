import { MDBaseController } from '../controller/BaseController';

export namespace IntactImpl {
  export function handleBlockSpacing(markdownUnion: string): ResourceColor | number {
    return MDBaseController.getMarkdownController(markdownUnion).getBlockSpacing()
  }
}