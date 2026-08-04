import { lvTitle } from '../domain/LvTitle'
import { lvFootnoteController } from './controller/lvFootnoteController'
import calcLevelTile from './handle/calcLevelTile'
import { ITitleStyle } from './interface'
import { lvCompositeComponent } from './lvCompositeComponent'
import { lvUrlComponent } from './lvUrlComponent'

function calcTitleStyle(type: string): string | number {
  let r: string | number = ""
  switch (type) {
    case "level1Tile":
      r = lvTitle.getLevel1Title()
      break;
    case "level2Tile":
      r = lvTitle.getLevel2Title()
      break;
    case "level3Tile":
      r = lvTitle.getLevel3Title()
      break;
    case "level4Tile":
      r = lvTitle.getLevel4Title()
      break;
    case "level5Tile":
      r = lvTitle.getLevel5Title()
      break;
    case "level6Tile":
      r = lvTitle.getLevel6Title()
      break;
    case "levelTitleColor":
      r = lvTitle.getLevelTitleColor()
      break;
  }
  return r
}

@Component
export struct lvTitleComponent {
  @State text: string = ""
  @State dialogController: CustomDialogController | null = null
  @State titleStyle: ITitleStyle = {
    level1Tile: lvTitle.getLevel1Title(),
    level2Tile: lvTitle.getLevel2Title(),
    level3Tile: lvTitle.getLevel3Title(),
    level4Tile: lvTitle.getLevel4Title(),
    level5Tile: lvTitle.getLevel5Title(),
    level6Tile: lvTitle.getLevel6Title(),
    levelTitleColor: lvTitle.getLevelTitleColor()
  }

  build() {
    Column() {
      // if (this.text.slice(calcLevelTile(this.text)).trim().indexOf('[') !== -1 &&
      //   this.text.slice(calcLevelTile(this.text)).trim().indexOf(')') !== -1 &&
      //   this.text.slice(calcLevelTile(this.text)).trim().indexOf('](') !== -1) {
      //   lvUrlComponent({
      //     text: this.text.slice(calcLevelTile(this.text)).trim(),
      //     fontSize: Number(calcTitleStyle(Object.keys(titleStyle)[calcLevelTile(this.text) - 1])),
      //     fontWeight: FontWeight.Bold,
      //     dialogController: this.dialogController
      //   })
      // } else {
      //   lvCompositeComponent({
      //     text: this.text.slice(calcLevelTile(this.text)).trim(),
      //     footnoteController: lvFootnoteController,
      //     fontSize: calcTitleStyle(Object.keys(titleStyle)[calcLevelTile(this.text) - 1]),
      //     fontWeight: FontWeight.Bold
      //   })
      //   // Text(this.text.slice(calcLevelTile(this.text)).trim())
      //   //   .fontSize(calcTitleStyle(Object.keys(titleStyle)[calcLevelTile(this.text) - 1]))
      //   //   .fontWeight(FontWeight.Bold)
      //   //   .textAlign(TextAlign.Start)
      //   //   .fontColor(titleStyle.levelTileColor)
      // }
      lvCompositeComponent({
        text: this.text.slice(calcLevelTile(this.text)).trim(),
        footnoteController: lvFootnoteController,
        fontSize: calcTitleStyle(Object.keys(this.titleStyle)[calcLevelTile(this.text) - 1]),
        fontWeight: FontWeight.Bold,
        fontColor: this.titleStyle.levelTitleColor
      })
    }.alignItems(HorizontalAlign.Start).width('100%').margin({ top: 10 })
  }
}

// @Builder
// export default function lvTitleBuilder(text: string, that: ESObject) {
//   Column() {
//     if (text.slice(calcLevelTile(text)).trim().indexOf('[') !== -1 &&
//       text.slice(calcLevelTile(text)).trim().indexOf(')') !== -1 &&
//       text.slice(calcLevelTile(text)).trim().indexOf('](') !== -1) {
//       lvUrlComponent({
//         text: text.slice(calcLevelTile(text)).trim(),
//         fontSize: Number(calcTitleStyle(Object.keys(titleStyle)[calcLevelTile(text) - 1])),
//         fontWeight: FontWeight.Bold
//       })
//       // lvUrlBuilder(text.slice(calcLevelTile(text)).trim(), that,
//       //   Number(calcTitleStyle(Object.keys(titleStyle)[calcLevelTile(text) - 1])), FontWeight.Bold)
//       // lvHyperlinkBuilder(String(text.split('](')[0]).split('[')[1], String(text.split('](')[1]).split(')')[0])
//     } else {
//       Text(text.slice(calcLevelTile(text)).trim())
//         .fontSize(calcTitleStyle(Object.keys(titleStyle)[calcLevelTile(text) - 1]))
//         .fontWeight(FontWeight.Bold)
//         .textAlign(TextAlign.Start)
//         .fontColor(titleStyle.levelTileColor)
//     }
//   }.alignItems(HorizontalAlign.Start).width('100%')
// }