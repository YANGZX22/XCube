import { ComponentContent, promptAction, window } from '@kit.ArkUI'
import { ImageDialogBuilder } from '../dialog/ImageDialog'

@ObservedV2
export class ImageDialogController {
  private static instance: ImageDialogController
  private baseContentNode: ComponentContent<Object> | undefined = undefined
  src: string = ""
  markdownUnion: string = ""
  @Trace pageOpacity: number = 0
  @Trace imageViewShowState = false
  @Trace bgc = "#00ffffff"

  /**
   * 打开模态框
   */
  async openBindSheet(markdownUnion: string, src: string) {
    this.src = src
    this.markdownUnion = markdownUnion
    const sheetOptions: promptAction.BaseDialogOptions = {
      maskColor: "#00000000",
      transition: TransitionEffect.OPACITY.animation({ duration: 0 }),
      onWillDismiss: () => {
        this.closeBindSheet()
      }
    }
    const windowClass: window.Window = await window.getLastWindow(getContext())
    const builder: WrappedBuilder<[]> = wrapBuilder<[]>(ImageDialogBuilder)
    this.baseContentNode = new ComponentContent(windowClass.getUIContext(), builder)
    windowClass.getUIContext().getPromptAction().openCustomDialog(this.baseContentNode, sheetOptions)
  }

  /**
   * 关闭模态弹窗
   */
  async closeBindSheet() {
    animateTo({
      duration: 250, onFinish: async () => {
        const windowClass = await window.getLastWindow(getContext())
        windowClass.getUIContext().getPromptAction().closeCustomDialog(this.baseContentNode)
      }
    }, () => {
      ImageDialogController.getInstance().imageViewShowState = false
      ImageDialogController.getInstance().bgc = "#00ffffff"
      ImageDialogController.getInstance().pageOpacity = 0
    })
  }

  static getInstance(): ImageDialogController {
    if (!ImageDialogController.instance) {
      ImageDialogController.instance = new ImageDialogController();
    }
    return ImageDialogController.instance;
  }
}