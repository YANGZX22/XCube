import { lvText, LvText } from '../domain/LvText'
import { lvFootnoteController } from './controller/lvFootnoteController'
import { lvCompositeComponent } from './lvCompositeComponent'

@Component
export struct lvHTMLFontComponent {
  @State text: string = ""
  @State nText: LvText = lvText

  build() {
    Flex({
      wrap: FlexWrap.Wrap,
      direction: FlexDirection.Row
    }) {
      if (this.text.trim().indexOf('<font') !== -1 && this.text.trim().indexOf('font>') !== -1) {
        Text(this.text.indexOf(">") !== -1 ?
        this.text.slice(this.text.trim().indexOf('>') + 1, this.text.trim().slice(5,).indexOf('<') + 5) :
          null)
          .fontColor(this.text.indexOf("color=") !== -1 ? this.text.slice(this.text.trim().indexOf('color=') + 7)
            .split(this.text.slice(this.text.trim().indexOf('color=') + 6, this.text.trim().indexOf('color=') + 7))[0] :
          this.nText.getTextColor())
          .fontSize(this.text.indexOf("size=") !== -1 ?
            9 + (Number(this.text.slice(this.text.trim().indexOf('size=') + 6)
              .split(this.text.slice(this.text.trim().indexOf('size=') + 5,
                this.text.trim().indexOf('size=') + 6))[0]) - 1) * 3 :
          this.nText.getTextSize())
      } else {
        lvCompositeComponent({
          footnoteController: lvFootnoteController,
          text: this.text
        })
      }
    }
  }
}

// @Builder
// export default function lvHTMLImgBuilder(text: string, that: ESObject) {
//   Flex({
//     wrap: FlexWrap.Wrap,
//     direction: FlexDirection.Row
//   }) {
//     if (text.trim().indexOf('<font') !== -1 && text.trim().indexOf('font>') !== -1) {
//       Text(text.indexOf(">") !== -1 ? text.slice(text.trim().indexOf('>') + 1, text.trim().slice(5,).indexOf('<') + 5) :
//         null)
//         .fontColor(text.indexOf("color=") !== -1 ? text.slice(text.trim().indexOf('color=') + 7)
//           .split(text.slice(text.trim().indexOf('color=') + 6, text.trim().indexOf('color=') + 7))[0] :
//         that.textStyle.textColor)
//         .fontSize(text.indexOf("size=") !== -1 ? 9 + (Number(text.slice(text.trim().indexOf('size=') + 6)
//           .split(text.slice(text.trim().indexOf('size=') + 5, text.trim().indexOf('size=') + 6))[0]) - 1) * 3 :
//         that.textStyle.textSize)
//     } else {
//       lvTextComponent({
//         text: text
//       })
//     }
//   }
// }