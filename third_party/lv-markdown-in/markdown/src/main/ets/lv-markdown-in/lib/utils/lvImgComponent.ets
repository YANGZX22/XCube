import { lvImage, LvImage } from '../domain/LvImage'
import { mdRegister } from './common'
import { lvFootnoteController } from './controller/lvFootnoteController'
import handleImgText from './handle/handleImgText'
import { lvCompositeComponent } from './lvCompositeComponent'

@Component
export struct lvImgComponent {
  @State text: string = ""
  @State nImage: LvImage = lvImage
  @State dialogController: CustomDialogController | null = null
  @State imgWidth: number | string = this.nImage.getImgWidth()
  @State imgHeight: number | string | null = this.nImage.getImgHeight()

  build() {
    Flex({
      wrap: FlexWrap.Wrap,
      direction: FlexDirection.Row
    }) {
      ForEach(handleImgText(this.text), (item: string) => {
        if (item.trim().slice(0, 2) == '![' && item.trim().slice(-1) == ')' && item.trim().indexOf('](') !== -1) {
          Image(item.split('](')[1].slice(0, -1))
            .alt($rawfile("imgs/imgErr.png"))
            .interpolation(ImageInterpolation.Medium)
            .width(this.imgWidth)
            .height(this.imgHeight)
            .objectFit(ImageFit.Auto)
            .borderRadius(5)
            .margin({
              top: 5, bottom: 5
            })
            .onClick(() => {
              let uri = item.split('](')[1].slice(0, -1)
              if (mdRegister.HandleImage(uri)) {
                this.nImage.setImgUrl(uri)
                this.dialogController?.open()
              }
            })
            .onError(() => {
              this.imgWidth = 20
              this.imgHeight = 20
            })
        } else {
          lvCompositeComponent({
            footnoteController: lvFootnoteController,
            text: item
          })
          // Text(item).fontSize(this.textStyle.textSize).fontColor(this.textStyle.textColor)
        }
      })
    }
  }
}

// @Builder
// export default function lvImgBuilder(text: string, that: ESObject) {
//   Flex({
//     wrap: FlexWrap.Wrap,
//     direction: FlexDirection.Row
//   }) {
//     ForEach(handleImgText(text), (item: string) => {
//       if (item.trim().slice(0, 2) == '![' && item.trim().slice(-1) == ')' && item.trim().indexOf('](') !== -1) {
//         Image(item.split('](')[1].slice(0, -1))
//           .interpolation(ImageInterpolation.Medium)
//           .width(that.imgStyle.imgWidth)
//           .height(that.imgStyle.imgHeight)
//           .objectFit(ImageFit.Auto)
//           .borderRadius(that.state.radius)
//           .margin({
//             top: 5, bottom: 5
//           })
//           .onClick(() => {
//             let uri = item.split('](')[1].slice(0, -1)
//             if (mdRegister.HandleImage(uri)) {
//               that.imgUri = uri
//               that.imgController.open()
//             }
//           })
//       } else {
//         lvTextComponent({
//           text: item
//         })
//         // Text(item).fontSize(this.textStyle.textSize).fontColor(this.textStyle.textColor)
//       }
//     })
//   }
// }