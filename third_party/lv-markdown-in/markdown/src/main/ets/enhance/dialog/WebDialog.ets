import { WebDialogController } from '../controller/WebDialogController'
import { webview } from '@kit.ArkWeb'
import { WebImpl } from '../impl/WebImpl'
import { fileIo as fs } from '@kit.CoreFileKit'

@Builder
export function WebDialogBuilder() {
  WebDialog()
}

@Component
export struct WebDialog {
  controller: WebviewController = new webview.WebviewController()
  @State loading: boolean = true
  @State webSrc: string = ""

  aboutToAppear(): void {
    this.webSrc = this.buildWebSrc()
  }

  private buildWebSrc(): string {
    const dialogController = WebDialogController.getInstance()
    if (dialogController.mode == "html") {
      return this.writeHtmlToCache(dialogController.src)
    }
    return dialogController.src
  }

  private writeHtmlToCache(html: string): string {
    try {
      const filePath = `${getContext().cacheDir}/lv_markdown_web_preview.html`
      const file = fs.openSync(filePath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, html)
      fs.closeSync(file)
      return `file://${filePath}`
    } catch (_err) {
      return ""
    }
  }

  private canLoadWeb(): boolean {
    const dialogController = WebDialogController.getInstance()
    return dialogController.mode == "html" || WebImpl.canBeLoadedAsWebComponentURL(this.webSrc)
  }

  build() {
    Column() {
      Row() {
        Text(WebDialogController.getInstance().title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor("#000")
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width("100%")
      .height(60)
      .padding({ left: 16, right: 16 })

      Stack({ alignContent: Alignment.Center }) {
        if (this.canLoadWeb() && this.webSrc.length > 0) {
          Web({ src: this.webSrc, controller: this.controller })
            .layoutWeight(1)
            .mixedMode(MixedMode.All)
            .domStorageAccess(true)
            .javaScriptAccess(WebDialogController.getInstance().javaScriptAccess)
            .fileAccess(true)
            .overviewModeAccess(false)
            .width("100%")
            .onProgressChange((e) => {
              if (e.newProgress > 70) {
                animateTo({ duration: 200 }, () => {
                  this.loading = false
                })
              }
            })
        } else {
          Column() {
            Text(WebDialogController.getInstance().src)
              .fontColor("#303133")
              .lineHeight(24)
              .onAppear(() => {
                this.loading = false
              })
          }
          .padding(16)
          .width("100%")
          .height("100%")
          .alignItems(HorizontalAlign.Start)
        }
        if (this.loading) {
          Column() {
            LoadingProgress().width(50).height(50).color("#333333")
          }
        }
      }
      .layoutWeight(1)
    }
    .width("100%")
    .height("100%")
  }
}
