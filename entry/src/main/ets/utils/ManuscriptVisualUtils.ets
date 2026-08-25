import { text } from '@kit.ArkGraphics2D'

const CORMORANT_ALIAS: string = 'XCubeCormorantGaramond'
const LORA_ALIAS: string = 'XCubeLora'
const MANUSCRIPT_CJK_ALIAS: string = 'XCubeManuscriptCJK'

export const MANUSCRIPT_HEADING_FONT: string = `${CORMORANT_ALIAS},${MANUSCRIPT_CJK_ALIAS}`
export const MANUSCRIPT_BODY_FONT: string = `${LORA_ALIAS},${MANUSCRIPT_CJK_ALIAS}`
export const MANUSCRIPT_COMPACT_BAR_HEIGHT: number = 36
export const MANUSCRIPT_COMPOSER_TOOLBAR_HEIGHT: number = 28
export const MANUSCRIPT_BOTTOM_TOOLBAR_HEIGHT: number = 48
// 星标行高度。生成时钉在输入区、结束后落回列表末尾，两处共用同一高度，
// 交接时列表内容不会因为高度差而位移。
export const MANUSCRIPT_END_MARK_ROW_HEIGHT: number = 38

let manuscriptFontsRegistered: boolean = false

export function ensureManuscriptFonts(): void {
  if (manuscriptFontsRegistered) {
    return
  }
  const fontCollection = text.FontCollection.getGlobalInstance()
  fontCollection.loadFontSync(
    CORMORANT_ALIAS,
    $rawfile('fonts/Manuscript/CormorantGaramond-SemiBold.ttf')
  )
  fontCollection.loadFontSync(LORA_ALIAS, $rawfile('fonts/Manuscript/Lora-Regular.ttf'))
  fontCollection.loadFontSync(LORA_ALIAS, $rawfile('fonts/Manuscript/Lora-Italic.ttf'))
  fontCollection.loadFontSync(MANUSCRIPT_CJK_ALIAS, $rawfile('fonts/SourceHanSerifSC-Regular.otf'))
  fontCollection.loadFontSync(MANUSCRIPT_CJK_ALIAS, $rawfile('fonts/SourceHanSerifSC-Bold.otf'))
  fontCollection.loadFontSync(MANUSCRIPT_CJK_ALIAS, $rawfile('fonts/SourceHanSerifSC-Italic.ttf'))
  fontCollection.loadFontSync(MANUSCRIPT_CJK_ALIAS, $rawfile('fonts/SourceHanSerifSC-ItalicBold.ttf'))
  manuscriptFontsRegistered = true
}

export function getManuscriptAccent(isDark: boolean): string {
  return isDark ? '#C99A52' : '#B68235'
}

export function toRomanNumeral(value: number): string {
  if (!Number.isInteger(value) || value <= 0 || value > 999) {
    return value.toString()
  }
  const values: number[] = [900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
  const numerals: string[] = ['CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I']
  let remaining = value
  let result = ''
  for (let i = 0; i < values.length; i++) {
    while (remaining >= values[i]) {
      result += numerals[i]
      remaining -= values[i]
    }
  }
  return result
}
