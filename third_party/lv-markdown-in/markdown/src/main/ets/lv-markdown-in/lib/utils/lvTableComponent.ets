import { lvFootnoteController } from './controller/lvFootnoteController'
import handleTableText from './handle/handleTableText'
import { lvCompositeComponent } from './lvCompositeComponent'
import { promptAction } from '@kit.ArkUI'

@Component
export struct lvTableComponent {
  @State text: string = ""
  @State dialogController: CustomDialogController | null = null
  @State cellWidthArrayIndexed: number[] = []

  build() {
    Row() {
      List() {
        ListItem() {
          Column() {
            ForEach(handleTableText(this.text), (item: string, i: number) => {
              Column() {
                if (handleTableText(this.text)[1].split('-').length - 1 < 2) {
                  Text(item).fontSize(15)
                } else {
                  if (i === 0) {
                    this.lvTableHeadBuilder(item, this.dialogController)
                  }
                  if (i > 1 && i < handleTableText(this.text).length - 2) {
                    this.lvTableRowBuilder(item, i, this.dialogController)
                  }
                }
              }
              .alignItems(HorizontalAlign.Start)
            })
          }
        }
      }.listDirection(Axis.Horizontal).margin({ bottom: 5 })
    }.width("100%")
  }

  @Builder
  lvTableHeadBuilder(text: string, dialogController: CustomDialogController | null) {
    Row() {
      ForEach(text.split('|')
        .filter((item: string) => item.trim()), (item: string, index) => {
        lvCompositeComponent({
          footnoteController: lvFootnoteController,
          text: item.trim(),
          fontWeight: FontWeight.Bold,
          textOverflow: TextOverflow.MARQUEE,
          maxLines: 1,
          dialogController
        })
          .align(Alignment.Center)
          .padding({
            top: 8,
            bottom: 8,
            left: 3,
            right: 3
          })
          .width(this.cellWidthArrayIndexed[index] ? this.cellWidthArrayIndexed[index] : 120)
          .onClick(() => {
            promptAction.showToast({ message: item.trim() })
          })
      })
    }
    .backgroundColor("#F5F7FA")
  }

  @Builder
  lvTableRowBuilder(text: string, rowIdx: number, dialogController: CustomDialogController | null) {
    Row() {
      ForEach(text.split('|').filter((item: string) => item.trim()), (item: string, index) => {
        lvCompositeComponent({
          footnoteController: lvFootnoteController,
          text: item.trim(),
          textOverflow: TextOverflow.Ellipsis,
          maxLines: 5,
          dialogController
        })
          .padding({
            top: 8,
            bottom: 8,
            left: 3,
            right: 3
          })
          .constraintSize({
            minWidth: this.cellWidthArrayIndexed[index] ? this.cellWidthArrayIndexed[index] : 120,
            maxWidth: 250
          })
          .onAreaChange((oldValue: Area, newValue: Area) => {
            if (oldValue.width != newValue.width) {
              if (!this.cellWidthArrayIndexed[index] || newValue.width > this.cellWidthArrayIndexed[index]) {
                this.cellWidthArrayIndexed[index] = newValue.width as number
              }
            }
          })
          .onClick(() => {
            promptAction.showToast({ message: item.trim() })
          })
      })
    }.backgroundColor(rowIdx % 2 === 0 ? "#fff" : "#fafafa")
  }
}