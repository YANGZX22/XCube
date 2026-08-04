import { lvLink, LvLink } from '../domain/LvLink'
import { lvText, LvText } from '../domain/LvText'
import { mdRegister } from './common'
import { SP_TYPE } from './constant'
import { lvFootnoteController, LvFootnoteController } from './controller/lvFootnoteController'
import handleTextType from './handle/handleTextType'
import lvHyperlinkBuilder, { lvHyperlinkComponent } from './lvHyperlinkComponent'

interface IFootnoteText {
  content: string,
  biz: string
  nName: string
}

function isItalicText(text: string) {
  const regex = /^\*[^\*]+\*|^\_[^\_]+\_/;
  return regex.test(text);
}

function isBoldText(text: string) {
  const regex = /^\*\*[^\*\*]+\*\*|^\_\_[^\_\_]+\_\_/;
  return regex.test(text);
}

function isBoldItalicText(text: string) {
  const regex = /^\*\*\*[^\*\*\*]+\*\*\*|^\_\_\_[^\_\_\_]+\_\_\_/;
  return regex.test(text);
}

function isMarkText(text: string) {
  const regex = /^\=\=.*\=\=$/;
  return regex.test(text);
}

function isDelText(text: string) {
  const regex = /^\~\~.*\~\~$/;
  return regex.test(text);
}

function isCodeText(text: string) {
  const regex = /^\`.*\`$/;
  return regex.test(text);
}

function isFootnoteText(text: string) {
  let flag = (text.trim().slice(0, 2) == '[^' && text.trim().indexOf('](') !== -1 &&
    text.trim().indexOf(')') !== -1)
  return flag
}

function isUrlText(text: string) {
  let flag = (text.trim().slice(0, 1) == '[' && text.trim().slice(0, 2) !== '[^' && text.trim().indexOf('](') !== -1 &&
    text.trim().indexOf(')') !== -1)
  return flag
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

@Component
export struct lvCompositeComponent {
  @State text: string = ""
  @State nText: LvText = lvText
  @State fontWeight: FontWeight = FontWeight.Normal
  @State maxLines: number | null = null
  @State textOverflow: TextOverflow = TextOverflow.None
  @State nLink: LvLink = lvLink
  @State dialogController: CustomDialogController | null = null
  @ObjectLink footnoteController: LvFootnoteController
  @State fontSize: number | string = ""
  @State fontColor: number | string = ""

  openUrl(uri: string) {
    if (mdRegister.HandleHyperlink(uri)) {
      this.nLink.setLinkUrl(uri)
      this.dialogController?.open()
    }
  }

  getLineHeight() {
    if (this.fontSize > this.nText.getTextLineHeight()) {
      if (typeof this.fontSize == "string" &&
        (this.fontSize.indexOf("px") !== -1 || this.fontSize.indexOf("vp") !== -1)) {
        let px = Number(this.fontSize.split("px")[0]) || 0
        let vp = Number(this.fontSize.split("vp")[0]) || 0
        return (vp || px2vp(px)) + 6
      }
      return Number(this.fontSize) + 6
    } else {
      return this.nText.getTextLineHeight()
    }
  }

  build() {
    Text() {
      ForEach(handleTextType(this.text), (item: string) => {
        if (isBoldItalicText(item)) {
          Span(item.slice(3, -3))
            .fontStyle(FontStyle.Italic)
            .fontSize(this.fontSize || this.nText.getTextSize())
            .fontColor(this.fontColor || this.nText.getTextColor())
            .lineHeight(this.getLineHeight())
            .fontWeight(FontWeight.Bold)
        } else if (isBoldText(item)) {
          Span(item.slice(2, -2))
            .fontWeight(FontWeight.Bold)
            .fontSize(this.fontSize || this.nText.getTextSize())
            .fontColor(this.fontColor || this.nText.getTextColor())
            .lineHeight(this.getLineHeight())
        } else if (isItalicText(item)) {
          Span(item.slice(1, -1))
            .fontStyle(FontStyle.Italic)
            .fontSize(this.fontSize || this.nText.getTextSize())
            .fontColor(this.fontColor || this.nText.getTextColor())
            .lineHeight(this.getLineHeight())
            .fontWeight(this.fontWeight)
        } else if (isMarkText(item)) {
          Span(item.slice(2, -2))
            .backgroundColor(this.nText.getTextMarkBackground())
            .borderRadius(3)
            .padding({ left: 3, right: 3, top: 1 })
            .fontSize(this.fontSize || this.nText.getTextSize())
            .fontColor("#E6A23C")
            .lineHeight(this.getLineHeight())
            .fontWeight(this.fontWeight)
        } else if (isDelText(item)) {
          Span(item.slice(2, -2))
            .decoration({ type: TextDecorationType.LineThrough })
            .fontSize(this.fontSize || this.nText.getTextSize())
            .fontColor(this.fontColor || this.nText.getTextColor())
            .lineHeight(this.getLineHeight())
            .fontWeight(this.fontWeight)
        } else if (isCodeText(item)) {
          Span(item.slice(1, -1))
            .fontSize(this.fontSize || this.nText.getTextSize())
            .fontColor("#FD0200")
            .lineHeight(this.getLineHeight())
            .fontWeight(this.fontWeight)
        } else if (isFootnoteText(item)) {
          Span(getFootnoteText(item).content)
            .fontColor("#FFFF490F")
            .fontWeight(FontWeight.Bold)
            .lineHeight(this.getLineHeight())
            .onClick(() => {
              if (getFootnoteText(item).biz.trim().slice(0, 4) == "http") {
                this.openUrl(getFootnoteText(item).biz.trim())
              }
            })
          Span(` [${lvFootnoteController.footnoteList.split(SP_TYPE.SPK).indexOf(item) + 1}] `)
            .fontColor("#FFFF490F")
            .fontSize(this.fontSize || 10)
            .lineHeight(this.getLineHeight())
            .onClick(() => {
              if (getFootnoteText(item).biz.trim().slice(0, 4) == "http") {
                this.openUrl(getFootnoteText(item).biz.trim())
              }
            })
        } else if (isUrlText(item)) {
          lvHyperlinkBuilder(String(item.split('](')[0]).split('[')[1], String(item.split('](')[1]).split(')')[0],
            this.nLink, this.fontSize || this.nText.getTextSize(), this.fontWeight, this.dialogController)
        } else {
          Span(item)
            .fontSize(this.fontSize || this.nText.getTextSize())
            .fontColor(this.fontColor || this.nText.getTextColor())
            .lineHeight(this.getLineHeight())
            .fontWeight(this.fontWeight)
        }
      })
    }
    .textOverflow({ overflow: this.textOverflow })
    .maxLines(this.maxLines)
  }
}

// @Builder
// export default function lvTextBuilder(text: string, that: ESObject) {
//   Text() {
//     ForEach(handleTextType(text), (item: string) => {
//       if (item.split(SP_TYPE.SPL).length == 1) {
//         Span(item).fontSize(that.textStyle.textSize).fontColor(that.textStyle.textColor)
//       } else {
//         lvTextReBuilder(item, that)
//       }
//     })
//   }
// }