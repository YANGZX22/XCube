import { MDBaseController } from '../controller/BaseController';
import { CodeBlockImpl } from '../impl/CodeBlockImpl';
import { TableImpl } from '../impl/TableImpl';
import { TableCellNode, TableNode, TableRowNode, TreeNode } from '../model/TreeNode';
import { Logger } from '../utils/Logger';
import { ParagraphRender } from './ParagraphRender';

const TAG = "TableRender"

@Component
export struct TableRender {
  @Consume markdownUnion: string
  @State base: TableNode | undefined = undefined
  @State cellWidthArrayIndexed: number[] = []

  aboutToAppear(): void {
    const headerCount = (this.base?.header || []).length
    const cachedWidths = TableImpl.getTableWidths(this.base)
    if (cachedWidths && cachedWidths.length === headerCount) {
      this.cellWidthArrayIndexed = cachedWidths
      return
    }

    const initialWidths: number[] = []
    for (let i = 0; i < headerCount; i++) {
      initialWidths.push(140)
    }
    this.cellWidthArrayIndexed = initialWidths
    TableImpl.setTableWidths(this.base, initialWidths)
  }

  private getTableCopyClickListener(): ((rawTableMarkdown: string) => void) | undefined {
    return MDBaseController.getMarkdownController(this.markdownUnion).getTableCopyClickListener()
  }

  private getTableDownloadClickListener(): ((rawTableMarkdown: string) => void) | undefined {
    return MDBaseController.getMarkdownController(this.markdownUnion).getTableDownloadClickListener()
  }

  private getTableExpandClickListener(): ((rawTableMarkdown: string) => void) | undefined {
    return MDBaseController.getMarkdownController(this.markdownUnion).getTableExpandClickListener()
  }

  private hasTableAction(): boolean {
    return this.getTableCopyClickListener() !== undefined ||
      this.getTableDownloadClickListener() !== undefined ||
      this.getTableExpandClickListener() !== undefined
  }

  private getTableContentWidth(): number {
    let contentWidth = 0
    const columnCount = (this.base?.header || []).length
    for (let index = 0; index < columnCount; index++) {
      contentWidth += this.cellWidthArrayIndexed[index] || 140
    }
    return contentWidth
  }

  private handleTableCopy(): void {
    const listener = this.getTableCopyClickListener()
    if (listener) {
      listener(this.base?.rawMarkdown || "")
    }
  }

  private handleTableDownload(): void {
    const listener = this.getTableDownloadClickListener()
    if (listener) {
      listener(this.base?.rawMarkdown || "")
    }
  }

  private handleTableExpand(): void {
    const listener = this.getTableExpandClickListener()
    if (listener) {
      listener(this.base?.rawMarkdown || "")
    }
  }

  build() {
    Row() {
      Column() {
        if (this.hasTableAction()) {
          Row({ space: 4 }) {
            if (this.getTableCopyClickListener()) {
              Button() {
                Image($rawfile('imgs/share.png'))
                  .width(18)
                  .height(18)
                  .colorFilter(TableImpl.handleTableActionIconColorFilter(this.markdownUnion))
                  .syncLoad(true)
                  .interpolation(ImageInterpolation.Medium)
                  .draggable(false)
              }
              .width(32)
              .height(32)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.handleTableCopy()
              })
            }
            if (this.getTableDownloadClickListener()) {
              Button() {
                Image($rawfile('imgs/download.png'))
                  .width(18)
                  .height(18)
                  .colorFilter(TableImpl.handleTableActionIconColorFilter(this.markdownUnion))
                  .syncLoad(true)
                  .interpolation(ImageInterpolation.Medium)
                  .draggable(false)
              }
              .width(32)
              .height(32)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.handleTableDownload()
              })
            }
            if (this.getTableExpandClickListener()) {
              Button() {
                Image($rawfile('imgs/expand.png'))
                  .width(18)
                  .height(18)
                  .colorFilter(TableImpl.handleTableActionIconColorFilter(this.markdownUnion))
                  .syncLoad(true)
                  .interpolation(ImageInterpolation.Medium)
                  .draggable(false)
              }
              .width(32)
              .height(32)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.handleTableExpand()
              })
            }
          }
          .width(this.getTableContentWidth())
          .constraintSize({ maxWidth: "100%" })
          .height(40)
          .padding({ right: 4 })
          .justifyContent(FlexAlign.End)
          .backgroundColor(TableImpl.handleTableActionBackgroundColor(this.markdownUnion))
          .border({
            width: {
              top: 0,
              left: 0,
              right: 0,
              bottom: TableImpl.handleTableOuterBorderWidth(this.markdownUnion)
            },
            color: TableImpl.handleTableOuterBorderColor(this.markdownUnion)
          })
        }

        List() {
          ListItem() {
            Column() {
              TableHeadRender({
                base: this.base,
                cellWidthArrayIndexed: this.cellWidthArrayIndexed
              })
              TableRowRender({
                base: this.base,
                cellWidthArrayIndexed: this.cellWidthArrayIndexed
              })
            }
            .alignItems(HorizontalAlign.Start)
          }
        }
        .borderRadius(this.hasTableAction() ? 0 : TableImpl.handleTableBorderRadius(this.markdownUnion))
        .clip(true)
        .backgroundColor(TableImpl.handleTableBackgroundColor(this.markdownUnion))
        .listDirection(Axis.Horizontal)
        .edgeEffect(EdgeEffect.None)
        .border({
          width: this.hasTableAction() ? 0 : TableImpl.handleTableOuterBorderWidth(this.markdownUnion),
          color: TableImpl.handleTableOuterBorderColor(this.markdownUnion)
        })
      }
      .alignItems(HorizontalAlign.End)
      .constraintSize({ maxWidth: "100%" })
      .borderRadius(this.hasTableAction() ? TableImpl.handleTableBorderRadius(this.markdownUnion) : 0)
      .clip(this.hasTableAction())
      .border({
        width: this.hasTableAction() ? TableImpl.handleTableOuterBorderWidth(this.markdownUnion) : 0,
        color: TableImpl.handleTableOuterBorderColor(this.markdownUnion)
      })
    }
    .width("100%")
    .justifyContent(TableImpl.handleTableAlign(this.markdownUnion))
  }
}

@Component
struct TableHeadRender {
  @Consume markdownUnion: string
  @State base: TableNode | undefined = undefined
  @Link cellWidthArrayIndexed: number[]

  aboutToAppear(): void {
    const header = this.base?.header || []
    header.forEach((cell: TableCellNode) => {
      const paragraphs = cell?.children || []
      paragraphs.forEach((paragraph) => {
        if (!paragraph) {
          return
        }
        CodeBlockImpl.setExtend(paragraph, ["tableCell", true])
        const children = paragraph.children || []
        children.forEach((item) => {
          if (item) {
            CodeBlockImpl.setExtend(item, ["tableCell", true])
          }
        })
      })
    })
  }

  build() {
    Row() {
      ForEach(this.base?.header || [], (item: TableCellNode, index: number) => {
        if (item?.type == "tableCell") {
          if ((item?.children || []).length == 0) {
            // 修复行数据渲染时格子数据为空时，格子没渲染的问题
            Column()
              .border({
                width: {
                  top: 0,
                  left: (index > 0 && index < (this.base?.header.length || 0)) ?
                    TableImpl.handleTableInnerBorderWidth(this.markdownUnion) : 0,
                  right: 0,
                  bottom: 0
                },
                color: TableImpl.handleTableInnerBorderColor(this.markdownUnion)
              })
              .width(this.cellWidthArrayIndexed[index] ? this.cellWidthArrayIndexed[index] : 140)
          } else {
            ForEach(item?.children || [], (paragraph: TreeNode) => {
              Column() {
                ParagraphRender({ base: paragraph })
              }
              .alignItems(TableImpl.handleTextAlign(this.base?.align?.[index]))
              .padding({
                top: 8,
                bottom: 8,
                left: 12,
                right: 12
              })
              .border({
                width: {
                  top: 0,
                  left: (index > 0 && index < (this.base?.header.length || 0)) ?
                    TableImpl.handleTableInnerBorderWidth(this.markdownUnion) : 0,
                  right: 0,
                  bottom: 0
                },
                color: TableImpl.handleTableInnerBorderColor(this.markdownUnion)
              })
              .width(this.cellWidthArrayIndexed[index] ? this.cellWidthArrayIndexed[index] : 140)
            })
          }
        }
      })
    }
    .backgroundColor(TableImpl.handleTableTitleBackgroundColor(this.markdownUnion))
  }
}

@Component
struct TableRowRender {
  @Consume markdownUnion: string
  @State base: TableNode | undefined = undefined
  @Link cellWidthArrayIndexed: number[]

  aboutToAppear(): void {
    Logger.info("TableRowRender", "table base > " + JSON.stringify(this.base))
    const rows = this.base?.rows || []
    rows.forEach((row: TableRowNode, index: number) => {
      const cells = row?.children || []
      cells.forEach((cell) => {
        if (!cell) {
          return
        }
        CodeBlockImpl.setExtend(cell, ["tableRow", true], ["interleaveText", index % 2 === 0])
        const children = cell.children || []
        children.forEach((item) => {
          if (item) {
            CodeBlockImpl.setExtend(item, ["tableRow", true], ["interleaveText", index % 2 === 0])
          }
        })
      })
    })
  }

  build() {
    Column() {
      ForEach(this.base?.rows || [], (item: TableRowNode, index: number) => {
        Row() {
          if (item?.type == "tableRow") {
            ForEach(item?.children || [], (paragraph: TreeNode, colIdx: number) => {
              if ((paragraph?.children || []).length == 0) {
                // 修复行数据渲染时格子数据为空时，格子没渲染的问题
                Column()
                  .border({
                    width: {
                      top: 0,
                      left: (colIdx > 0 && colIdx < item.children.length) ?
                        TableImpl.handleTableInnerBorderWidth(this.markdownUnion) : 0,
                      right: 0,
                      bottom: 0
                    },
                    color: TableImpl.handleTableInnerBorderColor(this.markdownUnion)
                  })
                  .constraintSize({
                    minWidth: this.cellWidthArrayIndexed[colIdx] || 140,
                    maxWidth: 260
                  })
              } else {
                Column() {
                  ParagraphRender({ base: paragraph })
                }
                .alignItems(TableImpl.handleTextAlign(this.base?.align?.[colIdx]))
                .padding({
                  top: 8,
                  bottom: 8,
                  left: 12,
                  right: 12
                })
                .border({
                  width: {
                    top: 0,
                    left: (colIdx > 0 && colIdx < item.children.length) ?
                      TableImpl.handleTableInnerBorderWidth(this.markdownUnion) : 0,
                    right: 0,
                    bottom: 0
                  },
                  color: TableImpl.handleTableInnerBorderColor(this.markdownUnion)
                })
                .constraintSize({ minWidth: this.cellWidthArrayIndexed[colIdx] || 140, maxWidth: 260 })
                .onAreaChange((oldValue: Area, newValue: Area) => {
                  let oldWidth: number = Math.ceil(oldValue.width as number)
                  let newWidth: number = Math.ceil(newValue.width as number)
                  // 表格渲染时，如果有一行的列宽度为最大限制，则直接停止，无需再计算
                  if (this.cellWidthArrayIndexed[colIdx] == 260) {
                    return
                  }
                  if (oldWidth != newWidth && newWidth != 140 && newWidth <= 260) {
                    // 新行的列宽大于上一次赋值则使用新值
                    if (!this.cellWidthArrayIndexed[colIdx] || newWidth > this.cellWidthArrayIndexed[colIdx]) {
                      const nextCellWidths = [...this.cellWidthArrayIndexed]
                      nextCellWidths[colIdx] = newWidth
                      this.cellWidthArrayIndexed = nextCellWidths
                      TableImpl.setTableWidths(this.base, nextCellWidths)
                    }
                  }
                })

                // .clip(true)
              }
            })
          }
        }
        .border({
          width: {
            top: TableImpl.handleTableInnerBorderWidth(this.markdownUnion),
            left: 0,
            right: 0,
            bottom: 0
          },
          color: TableImpl.handleTableInnerBorderColor(this.markdownUnion)
        })
        .backgroundColor(index % 2 === 0 ? TableImpl.handleTableBackgroundColor(this.markdownUnion) :
          TableImpl.handleTableInterleaveBackgroundColor(this.markdownUnion))
      })
    }
    .alignItems(HorizontalAlign.Start)
  }
}
