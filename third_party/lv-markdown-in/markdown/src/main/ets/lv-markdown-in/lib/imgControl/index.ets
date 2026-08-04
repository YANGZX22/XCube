import { LvImage, lvImage } from '../domain/LvImage'

@CustomDialog
export struct ImgControl {
  controller: CustomDialogController
  @State nImage: LvImage = lvImage

  build() {
    Column() {
      List() {
        ListItem() {
          Image(this.nImage.getImgUrl()).width("100%").objectFit(ImageFit.Auto).interpolation(ImageInterpolation.Medium)
        }
      }
    }.height("100%").justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.controller.close()
    })
  }
}