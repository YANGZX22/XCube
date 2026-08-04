import { LvText, lvText } from '../domain/LvText'
import { lvFootnoteController } from './controller/lvFootnoteController'
import { lvCompositeComponent } from './lvCompositeComponent'

@Component
export struct lvCheckboxComponent {
  @State text: string = ""
  @State nText: LvText = lvText
  @State dialogController: CustomDialogController | null = null

  build() {
    Row() {
      Toggle({
        type: ToggleType.Checkbox,
        isOn: (this.text.split('- [')[1].split(']')[0] == 'X' || this.text.split('- [')[1].split(']')[0] == 'x') ?
          true : false,
      })
        .enabled(false)
      lvCompositeComponent({
        footnoteController: lvFootnoteController,
        text: this.text.split('- [')[1].split(']')[1],
        dialogController: this.dialogController
      })
      // Text(this.text.split('- [')[1].split(']')[1])
      //   .fontSize(this.nText.getTextSize())
      //   .fontColor(this.nText.getTextColor())
    }
  }
}

// @Builder
// export default function lvCheckboxBuilder(text: string) {
//   Row() {
//     Toggle({
//       type: ToggleType.Checkbox,
//       isOn: (text.split('- [')[1].split(']')[0] == 'X' || text.split('- [')[1].split(']')[0] == 'x') ? true : false
//     })
//     Text(text.split('- [')[1].split(']')[1]).fontSize(lvText.getTextSize()).fontColor(lvText.getTextColor())
//   }
// }