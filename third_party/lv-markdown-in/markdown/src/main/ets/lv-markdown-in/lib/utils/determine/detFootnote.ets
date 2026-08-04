import { LvFootnoteController } from '../controller/lvFootnoteController'

export function determineFootnote(text: string, footnoteController: LvFootnoteController): boolean {
  let check = text.trim().indexOf('[') !== -1 && text.trim().indexOf('](') !== -1 && text.trim().indexOf(')') !== -1 &&
    text.trim().substring(text.trim().indexOf('[') + 1, text.trim().indexOf('[') + 2) == "^"

  if (check) {
    let resList = text.split(/(\[\^[^\]]+\]\([^\)]+\))/g)
    resList.forEach((item: string) => {
      let flag = item.trim().slice(0, 2) == '[^' && item.trim().indexOf('](') !== -1 &&
        item.trim().indexOf(')') !== -1
      if (flag) {
        // footnoteController.footnoteList.push(item)
      }
    })
  }

  return check
}
