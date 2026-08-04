import { LV_TEXT_TYPE, SP_TYPE } from '../constant'
import { lvFootnoteController, LvFootnoteController } from '../controller/lvFootnoteController'

export default function handleTextType(text: string): string[] {
  const regex =
    /(\*\*\*[^(\*\*\*)]+\*\*\*|\_\_\_[^(\_\_\_)]+\_\_\_|\*\*[^(\*\*)]+\*\*|\_\_[^(\_\_)]+\_\_|\*[^(\*)]+\*|\_[^(\_)]+\_|\=\=[^(\=\=)]+\=\=|\~\~[^(\~\~)]+\~\~|\`[^(\`)]+\`|\[[^\]]+\]\([^\)]+\))/g;
  const match = text.split(regex);
  match.forEach((item: string) => {
    let flag = item.trim().slice(0, 2) == '[^' && item.trim().indexOf('](') !== -1 &&
      item.trim().indexOf(')') !== -1
    if (flag && lvFootnoteController) {
      // lvFootnoteController.setFootnoteList(item)
      // footnoteController?.footnoteList.push(item)
      lvFootnoteController.footnoteList += item + SP_TYPE.SPK
    }
  })


  // let res: string
  // let SPK = SP_TYPE.SPK
  // let SPL_S = SP_TYPE.SPL
  // res = text.replace(/\*\*(.*?)\*\*/g, `${SPK}${LV_TEXT_TYPE.L_BOLD}${SPL_S}$1${SPK}`)
  // res = res.replace(/__(.*?)__/g, `${SPK}${LV_TEXT_TYPE.L_BOLD}${SPL_S}$1${SPK}`)
  // res = res.replace(/\*(.*?)\*/g, `${SPK}${LV_TEXT_TYPE.L_ITALIC}${SPL_S}$1${SPK}`)
  // res = res.replace(/_(.*?)_/g, `${SPK}${LV_TEXT_TYPE.L_ITALIC}${SPL_S}$1${SPK}`)
  // res = res.replace(/==(.*?)==/g, `${SPK}${LV_TEXT_TYPE.L_MARK}${SPL_S}$1${SPK}`)
  // res = res.replace(/\~\~(.*?)\~\~/g, `${SPK}${LV_TEXT_TYPE.L_DEL}${SPL_S}$1${SPK}`)
  // res = res.replace(/\`(.*?)\`/g, `${SPK}${LV_TEXT_TYPE.L_PINK}${SPL_S}$1${SPK}`)
  // let result: string[] = res.split(SPK)
  return match
}