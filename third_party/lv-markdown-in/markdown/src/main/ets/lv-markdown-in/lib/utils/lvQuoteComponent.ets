import { lvQuote, LvQuote } from '../domain/LvQuote'
import { lvFootnoteController } from './controller/lvFootnoteController'
import { lvCompositeComponent } from './lvCompositeComponent'

@Component
export struct lvQuoteComponent {
  @State text: string = ""
  @State nQuote: LvQuote = lvQuote
  @State dialogController: CustomDialogController | null = null

  build() {
    Column() {
      ft({ text: this.text.trim(), dialogController: this.dialogController })
      // lvTextComponent({
      //   text: this.text.slice(1,)
      // })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .backgroundColor(this.nQuote.getBackgroundColor())
    .padding({
      left: 8,
      top: 12,
      right: 7,
      bottom: 12
    })
    // .borderRadius(3)
    .border({
      color: {
        left: this.nQuote.getBorderColor()
      },
      style: {
        left: BorderStyle.Solid
      },
      width: {
        left: '5',
        right: '0',
        top: '0',
        bottom: '0'
      }
    })
  }
}

@Component
struct ft {
  @State text: string = ""
  @State dialogController: CustomDialogController | null = null

  build() {
    if (this.text.slice(0, 3) == "> >") {
      lvQuoteComponent({ text: this.text.slice(1,).trim(), dialogController: this.dialogController })
    } else {
      lvCompositeComponent({
        dialogController: this.dialogController,
        footnoteController: lvFootnoteController,
        text: this.text.slice(1,)
      })
    }
  }
}

// @Builder
// export default function lvQuoteBuilder(text: string) {
//   Column() {
//     lvTextComponent({
//       text: text.slice(1,)
//     })
//   }
//   .alignItems(HorizontalAlign.Start)
//   .width('100%')
//   .backgroundColor(that.quoteStyle.backgroundColor)
//   .padding({
//     left: 8,
//     top: 12,
//     right: 7,
//     bottom: 12
//   })
//   .border({
//     color: {
//       left: that.quoteStyle.borderColor
//     },
//     style: {
//       left: BorderStyle.Solid
//     },
//     width: {
//       left: '4',
//       right: '0',
//       top: '0',
//       bottom: '0'
//     }
//   })
// }