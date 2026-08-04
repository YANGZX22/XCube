import { ComponentContent, window } from '@kit.ArkUI'
import { CodeDialogBuilder } from '../dialog/CodeDialog'

export class CodeDialogController {
  private static instance: CodeDialogController
  private baseContentNode: ComponentContent<Object> | undefined = undefined
  markdownUnion: string = ""
  lang: string = "code"
  text: string = ""

  async openBindSheet(markdownUnion: string, lang: string, text: string) {
    this.markdownUnion = markdownUnion
    this.lang = lang || "code"
    this.text = text
    const sheetOptions: SheetOptions = {
      showClose: false,
      backgroundColor: "#FFF",
      dragBar: true,
      height: SheetSize.LARGE,
      preferType: SheetType.CENTER
    }
    const windowClass: window.Window = await window.getLastWindow(getContext())
    const builder: WrappedBuilder<[]> = wrapBuilder<[]>(CodeDialogBuilder)
    this.baseContentNode = new ComponentContent(windowClass.getUIContext(), builder)
    windowClass.getUIContext().openBindSheet(this.baseContentNode, sheetOptions)
  }

  async closeBindSheet() {
    const windowClass = await window.getLastWindow(getContext())
    windowClass.getUIContext().closeBindSheet(this.baseContentNode)
  }

  static getInstance(): CodeDialogController {
    if (!CodeDialogController.instance) {
      CodeDialogController.instance = new CodeDialogController()
    }
    return CodeDialogController.instance
  }
}
