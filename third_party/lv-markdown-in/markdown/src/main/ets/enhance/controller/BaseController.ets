import { Logger } from '../utils/Logger';
import { MarkdownController } from './MarkdonwController';

const TAG = "MDBaseController"

@ObservedV2
export class MDBaseController {
  private static markdownController: MarkdownController[] = []

  static setMarkdownController(markdownController: MarkdownController) {
    let idx =
      MDBaseController.markdownController.findIndex((item) => item.getUnion() == markdownController.getUnion())
    if (idx == -1) {
      Logger.info(TAG, "markdownController add.")
      MDBaseController.markdownController.push(markdownController)
    }
  }

  static getMarkdownController(markdownUnion: string) {
    // Logger.info(TAG, "getMarkdownController > " + markdownUnion)
    return MDBaseController.markdownController.find((item) => item.getUnion() == markdownUnion)!
  }

  static destroyMarkdownUnion(markdownUnion: string) {
    let idx =
      MDBaseController.markdownController.findIndex((item) => item.getUnion() == markdownUnion)
    if (idx !== -1) {
      MDBaseController.markdownController.splice(idx, 1)
      Logger.info(TAG, "has markdownUnion destroyed. " + markdownUnion)
    }
  }
}