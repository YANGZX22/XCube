import { MDBaseController } from '../controller/BaseController';

export namespace TableImpl {
  export let tableWidthsList: number[][] = []

  export let tableWidthsUnionList: string[] = []

  export function handleTableBackgroundColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getTableBackgroundColor()
  }

  export function handleTableTitleBackgroundColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getTableTitleBackgroundColor()
  }

  export function handleTableTitleTextColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getTableTitleTextColor()
  }

  export function handleTableInterleaveTextColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getTableInterleaveTextColor()
  }

  export function handleTableNormalTextColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getTableNormalTextColor()
  }

  export function handleTableInterleaveBackgroundColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getTableInterleaveBackgroundColor()
  }

  export function handleTableBorderRadius(markdownUnion: string): ResourceStr | number {
    return MDBaseController.getMarkdownController(markdownUnion).getTableBorderRadius()
  }

  export function handleTableOuterBorderColor(markdownUnion: string): ResourceColor | null {
    return MDBaseController.getMarkdownController(markdownUnion).getTableOuterBorderColor()
  }

  export function handleTableOuterBorderWidth(markdownUnion: string): ResourceStr | number {
    return MDBaseController.getMarkdownController(markdownUnion).getTableOuterBorderWidth()
  }

  export function handleTableInnerBorderColor(markdownUnion: string): ResourceColor | null {
    return MDBaseController.getMarkdownController(markdownUnion).getTableInnerBorderColor()
  }

  export function handleTableInnerBorderWidth(markdownUnion: string): ResourceStr | number {
    return MDBaseController.getMarkdownController(markdownUnion).getTableInnerBorderWidth()
  }

  export function handleTableAlign(markdownUnion: string): FlexAlign {
    return MDBaseController.getMarkdownController(markdownUnion).getTableAlign()
  }

  export function handleTextAlign(type: "none" | "left" | "center" | "right" | string | undefined) {
    if (type == "left") {
      return HorizontalAlign.Start
    }
    if (type == "center") {
      return HorizontalAlign.Center
    }
    if (type == "right") {
      return HorizontalAlign.End
    }
    return HorizontalAlign.Start
  }
}