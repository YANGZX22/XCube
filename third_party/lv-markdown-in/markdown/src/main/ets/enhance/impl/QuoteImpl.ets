import { MDBaseController } from '../controller/BaseController';

export namespace QuoteImpl {
  export function handleBorderColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getQuoteBorderColor()
  }

  export function handleBorderWidth(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getQuoteBorderWidth()
  }

  export function handleBorderRadius(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getQuoteBorderRadius()
  }

  export function handleBackgroundColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getQuoteBackgroundColor()
  }

  export function handleQuotePadding(markdownUnion: string): Padding | Length | LocalizedPadding {
    return MDBaseController.getMarkdownController(markdownUnion).getQuotePadding()
  }
}