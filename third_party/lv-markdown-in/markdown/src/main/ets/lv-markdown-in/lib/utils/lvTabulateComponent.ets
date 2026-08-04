import { lvText, LvText } from '../domain/LvText'
import lvMarkdownIn from '../Index'
import { lvFootnoteController } from './controller/lvFootnoteController'
import { lvQuoteComponent } from './lvQuoteComponent'
import { lvCompositeComponent } from './lvCompositeComponent'

@Component
export struct lvTabulateComponent {
  @State text: string = ""
  @State nText: LvText = lvText
  @State dialogController: CustomDialogController | null = null

  build() {
    if (this.text.trim().slice(0, 2) == '* ' || this.text.trim().slice(0, 2) == '+ ' ||
      this.text.trim().slice(0, 2) == '- ') {
      Flex() {
        Row() {
          // 符合左间距2-4
          if (this.text.split(this.text.trim().slice(0, 1))[0].length >= 0 &&
            this.text.split(this.text.trim().slice(0, 1))[0].length < 4) {
            Row()
              .width(5)
              .height(5)
              .backgroundColor('#000')
              .borderRadius(100)
              .margin({ left: 20 + this.text.split(this.text.trim().slice(0, 1))[0].length * 5 }) // 此处是符号左侧的间距
          }
          if (this.text.split(this.text.trim().slice(0, 1))[0].length >= 4 &&
            this.text.split(this.text.trim().slice(0, 1))[0].length < 8) {
            Row()
              .width(5)
              .height(5)
              .borderRadius(100)
              .border({
                width: 1
              })
              .margin({ left: 20 + this.text.split(this.text.trim().slice(0, 1))[0].length * 5 }) // 此处是符号左侧的间距
          }
          if (this.text.split(this.text.trim().slice(0, 1))[0].length >= 8) {
            Row()
              .width(5)
              .height(5)
              .backgroundColor('#000')
              .margin({ left: 20 + this.text.split(this.text.trim().slice(0, 1))[0].length * 5 }) // 此处是符号左侧的间距
          }
        }.height(this.nText.getTextLineHeight()).margin({ right: 5 })

        if (this.text.split(this.text.trim().slice(0, 1))[1].trim().slice(0, 2) == "> ") {
          lvQuoteComponent({ text: this.text.trim().slice(2,) })
        } else {
          // Text("11" + this.text.slice(1,))
          // 2.0.13 此处有修改
          // lvCompositeComponent({
          //   footnoteController: lvFootnoteController,
          //   text: this.text.split(this.text.trim().slice(0, 1))[1],
          //   dialogController: this.dialogController
          // })
          // 2.0.14
          lvCompositeComponent({
            footnoteController: lvFootnoteController,
            text: this.text.slice(1,),
            dialogController: this.dialogController
          })
        }
      }
    } else {
      lvCompositeComponent({
        footnoteController: lvFootnoteController,
        text: this.text.trim(),
        dialogController: this.dialogController
      }).margin({ left: 20 })
    }
  }
}

// @Builder
// export default function lvTabulateBuilder(text: string) {
//   if (text.trim().slice(0, 1) == '*') {
//     lvTextComponent({
//       text: text.split('*')[0]
//     })
//     // Text(text.split('*')[0]).fontSize(that.textStyle.textSize).fontColor(that.textStyle.textColor)
//     Row().width(5).height(5).backgroundColor('#000').borderRadius(100)
//     lvTextComponent({
//       text: text.split('*')[1]
//     })
//     // Text(text.split('*')[1]).fontSize(that.textStyle.textSize).fontColor(that.textStyle.textColor)
//   } else if (text.trim().slice(0, 1) == '-') {
//     // Text(text.split('-')[0]).fontSize(that.textStyle.textSize).fontColor(that.textStyle.textColor)
//     lvTextComponent({
//       text: text.split('-')[0]
//     })
//     Row().width(5).height(5).borderRadius(100).border({
//       width: 1
//     })
//     lvTextComponent({
//       text: text.split('-')[1]
//     })
//     // Text(text.split('-')[1]).fontSize(that.textStyle.textSize).fontColor(that.textStyle.textColor)
//   } else {
//     lvTextComponent({
//       text: text.trim()
//     }).margin({
//       left: 20
//     })
//     // Text(text.trim()).margin({
//     //   left: 20
//     // }).fontSize(that.textStyle.textSize).fontColor(that.textStyle.textColor)
//   }
// }