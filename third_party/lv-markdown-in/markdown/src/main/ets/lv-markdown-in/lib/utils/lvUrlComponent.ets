import lvHyperlinkBuilder, { lvHyperlinkComponent } from './lvHyperlinkComponent'
import handleUrlText from './handle/handleUrlText'
import { LvText, lvText } from '../domain/LvText'
import { LvLink, lvLink } from '../domain/LvLink'
import { mdRegister } from './common'

@Component
export struct lvUrlComponent {
  @State text: string = ""
  @State uri: string = ""
  @State nText: LvText = lvText
  @State fontSize: number | string = ""
  @State fontWeight: FontWeight = FontWeight.Normal
  @State nLink: LvLink = lvLink
  @State dialogController: CustomDialogController | null = null

  build() {
    Text() {
      ForEach(handleUrlText(this.text), (item: string) => {
        if (item.trim().slice(0, 1) == '[' && this.text.trim().indexOf('](') !== -1 &&
          item.trim().indexOf(')') !== -1) {
          // Text(item.split('](')[0].slice(1,)).fontColor("red")
          // Span(String(item.split('](')[1]).split(')')[0] + this.nLink.getTextColor() + this.fontSize + " " +
          // 目前api不支持span组件用component装饰，除非样式发生变化才会渲染
          // lvHyperlinkComponent({
          //   text: String(item.split('](')[0]).split('[')[1],
          //   uri: String(item.split('](')[1]).split(')')[0],
          //   fontSize: this.fontSize,
          //   fontWeight: this.fontWeight,
          //   dialogController: this.dialogController,
          //   nLink: this.nLink
          // })
          lvHyperlinkBuilder(String(item.split('](')[0]).split('[')[1], String(item.split('](')[1]).split(')')[0],
            this.nLink, this.fontSize, this.fontWeight, this.dialogController)
        } else {
          Span(item)
            .fontSize(this.fontSize || this.nText.getTextSize())
            .fontColor(this.nText.getTextColor())
            .fontWeight(this.fontWeight)
        }
      })
    }.lineHeight(this.nText.getTextLineHeight())
  }
}

// @Builder
// export default function lvUrlBuilder(text: string, that: ESObject, fontSize?: number, fontWeight?: FontWeight) {
//   Text() {
//     ForEach(handleUrlText(text), (item: string) => {
//       // Text(handleUrlText(text).toString()).fontColor("red")
//       if (item.trim().slice(0, 1) == '[' && text.trim().indexOf('](') !== -1 && item.trim().indexOf(')') !== -1) {
//         // Text(item.split('](')[0].slice(1,)).fontColor("red")
//         // Text(String(item.split('](')[1]).split(')')[0]).fontColor("blue")
//         lvHyperlinkComponent({
//           text: String(item.split('](')[0]).split('[')[1],
//           uri: String(item.split('](')[1]).split(')')[0],
//           fontSize,
//           fontWeight
//         })
//       } else {
//         // lvTextBuilder(item)
//         Span(item)
//           .fontSize(fontSize || that.textStyle.textSize)
//           .fontColor(that.textStyle.textColor)
//           .fontWeight(fontWeight)
//       }
//     })
//   }
// }