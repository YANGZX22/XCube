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
    Logger.info(TAG, "tableWidthsList > " + JSON.stringify(TableImpl.tableWidthsList))
    Logger.info(TAG, "tableWidthsUnionList > " + JSON.stringify(TableImpl.tableWidthsUnionList))

    // 优先使用缓存的表格宽度
    const tableId = this.base?.tableId || 0;
    if (TableImpl.tableWidthsList[tableId] &&
      this.base?.header.length == TableImpl.tableWidthsList[tableId].length &&
      this.markdownUnion == TableImpl.tableWidthsUnionList[tableId]) {
      this.cellWidthArrayIndexed = TableImpl.tableWidthsList[tableId];
      Logger.info("TableRowRender",
        "读取已有tableWidthInfos, " + this.markdownUnion + ", " + TableImpl.tableWidthsList.length +
          ", " + tableId)
      Logger.info("TableRowRender",
        "读取已有tableWidthInfos, " + JSON.stringify(TableImpl.tableWidthsList[tableId]))
    } else {
      // 初始化表格宽度数组
      this.cellWidthArrayIndexed = [];
      for (let i = 0; i < (this.base?.header.length || 0); i++) {
        this.cellWidthArrayIndexed[i] = 140; // 默认宽度
      }
      // 初始化缓存
      TableImpl.tableWidthsList[tableId] = this.cellWidthArrayIndexed;
      TableImpl.tableWidthsUnionList[tableId] = this.markdownUnion;
    }
  }

  build() {
    Row() {
      Row() {
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
        .borderRadius(TableImpl.handleTableBorderRadius(this.markdownUnion))
        .clip(true)
        .backgroundColor(TableImpl.handleTableBackgroundColor(this.markdownUnion))
        .listDirection(Axis.Horizontal)
        .edgeEffect(EdgeEffect.None)
        .border({
          width: TableImpl.handleTableOuterBorderWidth(this.markdownUnion),
          color: TableImpl.handleTableOuterBorderColor(this.markdownUnion)
        })
      }
      .constraintSize({ maxWidth: "100%" })
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
    this.base?.header.forEach((item: TableCellNode) => {
      item.children.forEach((paragraph) => {
        CodeBlockImpl.setExtend(paragraph, ["tableCell", true])
        paragraph.children.forEach((item) => {
          CodeBlockImpl.setExtend(item, ["tableCell", true])
        })
      })
    })
  }

  build() {
    Row() {
      ForEach(this.base?.header, (item: TableCellNode, index: number) => {
        if (item.type == "tableCell") {
          if (item.children && item.children.length == 0) {
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
            ForEach(item.children, (paragraph: TreeNode) => {
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
    this.base?.rows.forEach((item: TableRowNode, index: number) => {
      item.children.forEach((paragraph) => {
        CodeBlockImpl.setExtend(paragraph, ["tableRow", true], ["interleaveText", index % 2 === 0])
        paragraph.children.forEach((item) => {
          CodeBlockImpl.setExtend(item, ["tableRow", true], ["interleaveText", index % 2 === 0])
        })
      })
    })
  }

  build() {
    Column() {
      ForEach(this.base?.rows, (item: TableRowNode, index: number) => {
        Row() {
          if (item.type == "tableRow") {
            ForEach(item.children, (paragraph: TreeNode, colIdx: number) => {
              if (paragraph.children && paragraph.children.length == 0) {
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
                  const tableId = this.base?.tableId || 0;
                  // 表格渲染时，如果有一行的列宽度为最大限制，则直接停止，无需再计算
                  if (this.cellWidthArrayIndexed[colIdx] == 260) {
                    return
                  }
                  if (oldWidth != newWidth && newWidth != 140 && newWidth <= 260) {
                    // 新行的列宽大于上一次赋值则使用新值
                    if (!this.cellWidthArrayIndexed[colIdx] || newWidth > this.cellWidthArrayIndexed[colIdx]) {
                      this.cellWidthArrayIndexed[colIdx] = newWidth
                      Logger.info("TableRowRender",
                        "覆盖已有tableWidthInfos, " + TableImpl.tableWidthsList.length + ", " + tableId)
                      // 深拷贝数组，避免引用问题
                      TableImpl.tableWidthsList[tableId] = [...this.cellWidthArrayIndexed]
                      TableImpl.tableWidthsUnionList[tableId] = this.markdownUnion
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
