import { LvLink, lvLink } from '../domain/LvLink'
import { LvText, lvText } from '../domain/LvText'
import { mdRegister } from './common'
import { SP_TYPE } from './constant'
import { LvFootnoteController, lvFootnoteController } from './controller/lvFootnoteController'

interface IFootnoteText {
  content: string,
  biz: string
  nName: string
}

function getFootnoteText(item: string): IFootnoteText {
  const regex = /\[([^\]]+)\]\(([^)]+)\)/;
  const match: string[] = item.match(regex) || [];
  let content = ""
  let biz = ""
  let nName = ""
  if (match.length > 0) {
    content = match[1].slice(1,);
    if ((match[2].indexOf('"') !== -1) || (match[2].indexOf(`'`) !== -1)) {
      biz = match[2].slice(0, match[2].indexOf('"') || match[2].indexOf(`'`));
    } else {
      biz = match[2]
    }

    const matchNName: string[] = match[2].match(/"([^"]+)"/) || [];
    if (matchNName.length > 0) {
      nName = matchNName[1]
    }
  }
  return { content, biz, nName }
}

// @Component
// export struct lvFootnoteComponent {
//   @State text: string = ""
//   @State uri: string = ""
//   @State dialogController: CustomDialogController | null = null
//   @State nText: LvText = lvText
//   @State nLink: LvLink = lvLink
//   footnoteController: LvFootnoteController = lvFootnoteController
//
//   isFootnote(item: string) {
//     let flag = item.trim().slice(0, 2) == '[^' && item.trim().indexOf('](') !== -1 &&
//       item.trim().indexOf(')') !== -1
//     if (flag) {
//       return flag
//     }
//     return false
//   }
//
//   openUrl(uri: string) {
//     if (mdRegister.HandleHyperlink(uri)) {
//       this.nLink.setLinkUrl(uri)
//       this.dialogController?.open()
//     }
//   }
//
//   build() {
//     Text() {
//       ForEach(handleFootnoteText(this.text), (item: string) => {
//         if (this.isFootnote(item)) {
//           Span(getFootnoteText(item).content)
//             .fontColor("#F56C6C")
//             .fontWeight(FontWeight.Bold)
//             .onClick(() => {
//               if (getFootnoteText(item).biz.trim().slice(0, 4) == "http") {
//                 this.openUrl(getFootnoteText(item).biz.trim())
//               }
//             })
//           Span(` [${lvFootnoteController.footnoteList.indexOf(item) + 1}] `)
//             .fontColor("#F56C6C")
//             .fontSize(10)
//             .onClick(() => {
//               if (getFootnoteText(item).biz.trim().slice(0, 4) == "http") {
//                 this.openUrl(getFootnoteText(item).biz.trim())
//               }
//             })
//         } else {
//           if (item.trim()) {
//             // Span(item)
//             //   .fontColor(this.nText.getTextColor())
//             lvTextReBuilder(item, this.nText, FontWeight.Normal)
//           }
//         }
//       })
//     }
//     .fontSize(this.nText.getTextSize())
//     .lineHeight(this.nText.getTextLineHeight())
//   }
// }

@Component
export struct lvFootnoteView {
  @State footnoteController: LvFootnoteController = lvFootnoteController
  @State dialogController: CustomDialogController | null = null
  @State nText: LvText = lvText
  @State nLink: LvLink = lvLink

  openUrl(uri: string) {
    if (mdRegister.HandleHyperlink(uri)) {
      this.nLink.setLinkUrl(uri)
      this.dialogController?.open()
    }
  }

  build() {
    if (this.footnoteController.getFootnoteList()) {
      Column() {
        ForEach(this.footnoteController.getFootnoteList().split(SP_TYPE.SPK), (item: string, i: number) => {
          if (item) {
            Row() {
              Text(`[${i + 1}]`)
                .fontColor("#ff9b9b9b")
                .fontSize(13)
                .width(30)
                .lineHeight(this.nText.getTextLineHeight())
                .fontWeight(FontWeight.Lighter)
              Row() {
                Text() {
                  Span((getFootnoteText(item).nName || getFootnoteText(item).content) + ": ")
                    .fontColor("#FFFF490F")
                  Span(getFootnoteText(item).biz)
                    .fontColor(this.nText.getTextColor())
                    .fontStyle(FontStyle.Italic)
                    .onClick(() => {
                      if (getFootnoteText(item).biz.trim().slice(0, 4) == "http") {
                        this.openUrl(getFootnoteText(item).biz.trim())
                      }
                    })
                }
                .lineHeight(this.nText.getTextLineHeight())
                .fontSize(this.nText.getTextSize())
              }.layoutWeight(1)
            }.alignItems(VerticalAlign.Top)
          }
        })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 30, bottom: 10 })
    }
  }
}