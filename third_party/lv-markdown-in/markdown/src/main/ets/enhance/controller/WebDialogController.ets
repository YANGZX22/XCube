import { ComponentContent, window } from '@kit.ArkUI'
import { WebDialogBuilder } from '../dialog/WebDialog'

export type WebDialogMode = "url" | "html" | "text"

export class WebDialogController {
  private static instance: WebDialogController
  private baseContentNode: ComponentContent<Object> | undefined = undefined
  title: string = ""
  src: string = ""
  mode: WebDialogMode = "url"
  javaScriptAccess: boolean = true

  /**
   * 打开模态框
   */
  async openBindSheet(title: string, src: string) {
    this.title = title
    this.src = src
    this.mode = "url"
    this.javaScriptAccess = true
    await this.openSheet()
  }

  async openHtmlBindSheet(title: string, html: string, javaScriptAccess: boolean = true) {
    this.title = title
    this.src = html
    this.mode = "html"
    this.javaScriptAccess = javaScriptAccess
    await this.openSheet()
  }

  async openTextBindSheet(title: string, text: string) {
    this.title = title
    this.src = text
    this.mode = "text"
    this.javaScriptAccess = false
    await this.openSheet()
  }

  private async openSheet() {
    const sheetOptions: SheetOptions = {
      showClose: false,
      backgroundColor: "#FFF",
      dragBar: true,
      height: SheetSize.LARGE,
      preferType: SheetType.CENTER
    }
    const windowClass: window.Window = await window.getLastWindow(getContext())
    const builder: WrappedBuilder<[]> = wrapBuilder<[]>(WebDialogBuilder)
    this.baseContentNode = new ComponentContent(windowClass.getUIContext(), builder)
    windowClass.getUIContext().openBindSheet(this.baseContentNode, sheetOptions)
  }

  /**
   * 关闭模态弹窗
   */
  async closeBindSheet() {
    const windowClass = await window.getLastWindow(getContext())
    windowClass.getUIContext().closeBindSheet(this.baseContentNode)
  }

  static getInstance(): WebDialogController {
    if (!WebDialogController.instance) {
      WebDialogController.instance = new WebDialogController();
    }
    return WebDialogController.instance;
  }
}
