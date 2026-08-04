import webView from '@ohos.web.webview'
import { LvLink, lvLink } from '../domain/LvLink'

@CustomDialog
export struct WebControl {
  controller: CustomDialogController
  webController: webView.WebviewController = new webView.WebviewController()
  @State mode: MixedMode = MixedMode.All;
  @State loading: boolean = true
  @State nLink: LvLink = lvLink

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Web({ src: this.nLink.getLinkUrl(), controller: this.webController })
        .mixedMode(this.mode)
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .overviewModeAccess(false)
        .width("100%")
        .onPageEnd((e) => {
          this.loading = false
        })

      if (this.loading) {
        Column() {
          LoadingProgress().width(50).height(50).color("#333333")
          Text("加载中").fontSize(15).fontColor("#333333").margin({ top: 3 })
        }
        .padding({
          top: 20,
          bottom: 22,
          left: 30,
          right: 30
        })
        .borderRadius(10)
        .backgroundColor("#fff")
        .shadow({ radius: 21, color: "rgba(0,0,0,0.09)" })
      }
    }
    .backgroundColor("#fff")
    .height('85%')
    .margin(15)
    .borderRadius(15)
    .clip(true)
  }
}