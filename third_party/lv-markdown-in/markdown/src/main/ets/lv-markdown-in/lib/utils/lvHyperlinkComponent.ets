import { LvLink, lvLink } from '../domain/LvLink'
import { mdRegister } from './common'

@Component
export struct lvHyperlinkComponent {
  @Prop text: string = ""
  @Prop uri: string = ""
  @Prop nLink: LvLink = lvLink
  @Prop fontSize: number | string = ""
  @Prop fontWeight: FontWeight = FontWeight.Normal
  @Prop dialogController: CustomDialogController | null = null

  build() {
    Span(this.text || this.uri)
      .fontColor(this.nLink.getTextColor())
      .fontSize(this.fontSize || this.nLink.getTextSize())
      .fontWeight(this.fontWeight)
      .onClick(() => {
        if (mdRegister.HandleHyperlink(this.uri)) {
          // 超链接加载的地址
          this.nLink.setLinkUrl(this.uri)
          this.dialogController?.open()
        }
      })
  }
}

@Builder
export default function lvHyperlinkBuilder(text: string, uri: string, nLink: LvLink, fontSize: number | string,
  fontWeight: FontWeight, dialogController: CustomDialogController | null) {
  Span(text || uri)
    .fontColor(nLink.getTextColor())
    .fontSize(fontSize || nLink.getTextSize())
    .fontWeight(fontWeight)
    .onClick(() => {
      if (mdRegister.HandleHyperlink(uri)) {
        // 超链接加载的地址
        nLink.setLinkUrl(uri)
        dialogController?.open()
      }
    })
}