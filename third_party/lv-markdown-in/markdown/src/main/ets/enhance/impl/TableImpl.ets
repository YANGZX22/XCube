import { MDBaseController } from '../controller/BaseController';
import { TableNode } from '../model/TreeNode';
import { drawing } from '@kit.ArkGraphics2D';

const tableWidthsCache: WeakMap<TableNode, number[]> = new WeakMap()

export namespace TableImpl {
  export function getTableWidths(table: TableNode | undefined): number[] | undefined {
    const widths = table ? tableWidthsCache.get(table) : undefined
    return widths ? [...widths] : undefined
  }

  export function setTableWidths(table: TableNode | undefined, widths: number[]): void {
    if (table) {
      tableWidthsCache.set(table, [...widths])
    }
  }

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

  export function handleTableActionBackgroundColor(markdownUnion: string): ResourceColor {
    return MDBaseController.getMarkdownController(markdownUnion).getTableActionBackgroundColor()
  }

  export function handleTableActionIconColorFilter(markdownUnion: string): drawing.ColorFilter {
    const controller = MDBaseController.getMarkdownController(markdownUnion)
    controller.getTableActionIconColor()
    return controller.getTableActionIconColorFilter()
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
