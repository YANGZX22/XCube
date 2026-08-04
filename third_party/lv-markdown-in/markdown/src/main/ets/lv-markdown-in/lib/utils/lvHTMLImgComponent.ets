import { LvImage, lvImage } from '../domain/LvImage'
import { mdRegister } from './common'
import { lvFootnoteController } from './controller/lvFootnoteController'
import { lvCompositeComponent } from './lvCompositeComponent'

@Component
export struct lvHTMLImgComponent {
  @State text: string = ""
  @State nImage: LvImage = lvImage
  @State dialogController: CustomDialogController | null = null

  build() {
    Flex({
      wrap: FlexWrap.Wrap,
      direction: FlexDirection.Row
    }) {
      if (this.text.trim().indexOf('<img ') !== -1) {
        Image(this.text.indexOf("<img ") !== -1 ? this.text.slice(this.text.trim().indexOf('src=') + 5)
          .split(this.text.slice(this.text.trim().indexOf('src=') + 4, this.text.trim().indexOf('src=') + 5))[0] : null)
          .width(this.text.indexOf("width=") !== -1 ? this.text.slice(this.text.trim().indexOf('width=') + 7)
            .split(this.text.slice(this.text.trim().indexOf('width=') + 6, this.text.trim().indexOf('width=') + 7))[0] :
            null)
          .height(this.text.indexOf("height=") !== -1 ? this.text.slice(this.text.trim().indexOf('height=') + 8)
            .split(this.text.slice(this.text.trim().indexOf('height=') + 7,
              this.text.trim().indexOf('height=') + 8))[0] : null)
          .objectFit(ImageFit.Auto)
          .borderRadius(5)
          .margin({
            top: 5, bottom: 5
          })
          .onClick(() => {
            let uri = this.text.indexOf("<img ") !== -1 ?
            this.text.slice(this.text.trim().indexOf('src=') + 5)
              .split(this.text.slice(this.text.trim().indexOf('src=') + 4, this.text.trim().indexOf('src=') + 5))[0] :
              ""
            if (mdRegister.HandleHyperlink(uri)) {
              this.nImage.setImgUrl(uri)
              this.dialogController?.open()
            }
          })
      } else {
        lvCompositeComponent({
          footnoteController: lvFootnoteController,
          text: this.text
        })
      }
    }
  }
}

// @Builder
// export default function lvHTMLImgBuilder(text: string, that: ESObject) {
//   Flex({
//     wrap: FlexWrap.Wrap,
//     direction: FlexDirection.Row
//   }) {
//     if (text.trim().indexOf('<img ') !== -1) {
//       Image(text.indexOf("<img ") !== -1 ? text.slice(text.trim().indexOf('src=') + 5)
//         .split(text.slice(text.trim().indexOf('src=') + 4, text.trim().indexOf('src=') + 5))[0] : null)
//         .width(text.indexOf("width=") !== -1 ? text.slice(text.trim().indexOf('width=') + 7)
//           .split(text.slice(text.trim().indexOf('width=') + 6, text.trim().indexOf('width=') + 7))[0] : null)
//         .height(text.indexOf("height=") !== -1 ? text.slice(text.trim().indexOf('height=') + 8)
//           .split(text.slice(text.trim().indexOf('height=') + 7, text.trim().indexOf('height=') + 8))[0] : null)
//         .objectFit(ImageFit.Auto)
//         .borderRadius(5)
//         .margin({
//           top: 5, bottom: 5
//         })
//         .onClick(() => {
//           that.imgUri = text.indexOf("<img ") !== -1 ? text.slice(text.trim().indexOf('src=') + 5)
//             .split(text.slice(text.trim().indexOf('src=') + 4, text.trim().indexOf('src=') + 5))[0] : null
//           that.imgController.open()
//         })
//     } else {
//       lvTextComponent({
//         text: text
//       })
//     }
//   }
// }