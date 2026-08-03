import { text } from '@kit.ArkGraphics2D'
import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'

export const CHAT_SERIF_FONT_COMMON: string = 'common'
export const CHAT_SERIF_FONT_ANTHROPIC: string = 'anthropic'

const COMMON_SERIF_ALIAS: string = 'XCubeCommonSerif'
const ANTHROPIC_SERIF_ALIAS: string = 'XCubeAnthropicSerifText'
const ANTHROPIC_SERIF_ITALIC_ALIAS: string = 'XCubeAnthropicSerifTextItalic'
const SOURCE_HAN_SERIF_SC_ALIAS: string = 'XCubeSourceHanSerifSC'
const ANTHROPIC_REGULAR_RAWFILE: string = 'fonts/AnthropicSerif-Text-Regular-Static.otf'
const ANTHROPIC_ITALIC_RAWFILE: string = 'fonts/AnthropicSerif-Text-RegularItalic-Static.otf'

export class ChatSerifFontAvailability {
  commonAvailable: boolean = true
  anthropicAvailable: boolean = false
}

let cachedAvailability: ChatSerifFontAvailability | null = null
let commonSerifRegistered: boolean = false
let sourceHanSerifRegistered: boolean = false
let anthropicSerifRegistered: boolean = false

function writeRawFontToCache(context: common.UIAbilityContext, rawFileName: string,
  cacheFileName: string): string {
  const rawData = context.resourceManager.getRawFileContentSync(rawFileName)
  const cachePath = `${context.cacheDir}/${cacheFileName}`
  const cacheFile = fileIo.openSync(cachePath,
    fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
  try {
    fileIo.writeSync(cacheFile.fd, rawData.buffer)
  } finally {
    fileIo.closeSync(cacheFile)
  }
  return `file://${cachePath}`
}

function tryRegisterPrivateAnthropicSerif(context: common.UIAbilityContext,
  fontCollection: text.FontCollection): boolean {
  try {
    const regularPath = writeRawFontToCache(context, ANTHROPIC_REGULAR_RAWFILE,
      'xcube_anthropic_serif_regular.otf')
    const italicPath = writeRawFontToCache(context, ANTHROPIC_ITALIC_RAWFILE,
      'xcube_anthropic_serif_italic.otf')
    fontCollection.loadFontSync(ANTHROPIC_SERIF_ALIAS, regularPath)
    fontCollection.loadFontSync(ANTHROPIC_SERIF_ITALIC_ALIAS, italicPath)
    anthropicSerifRegistered = true
    return true
  } catch (error) {
    console.info('ChatSerifFontUtils', `Private serif font unavailable: ${JSON.stringify(error)}`)
    return false
  }
}

export function detectAndRegisterChatSerifFonts(uiContext: UIContext): ChatSerifFontAvailability {
  if (cachedAvailability !== null) {
    return cachedAvailability
  }

  const fontCollection = text.FontCollection.getGlobalInstance()
  if (!commonSerifRegistered) {
    fontCollection.loadFontSync(COMMON_SERIF_ALIAS, $rawfile('fonts/CommonSerif-Regular.ttf'))
    commonSerifRegistered = true
  }
  if (!sourceHanSerifRegistered) {
    fontCollection.loadFontSync(SOURCE_HAN_SERIF_SC_ALIAS, $rawfile('fonts/SourceHanSerifSC-Regular.otf'))
    sourceHanSerifRegistered = true
  }

  const availability = new ChatSerifFontAvailability()
  const hostContext = uiContext.getHostContext() as common.UIAbilityContext | undefined
  if (hostContext !== undefined && hostContext !== null) {
    availability.anthropicAvailable = anthropicSerifRegistered ||
      tryRegisterPrivateAnthropicSerif(hostContext, fontCollection)
    cachedAvailability = availability
  }
  return availability
}

export function resolveChatSerifFontFamily(fontId: string): string {
  if (fontId === CHAT_SERIF_FONT_ANTHROPIC && cachedAvailability?.anthropicAvailable === true) {
    return `${ANTHROPIC_SERIF_ALIAS},${SOURCE_HAN_SERIF_SC_ALIAS}`
  }
  return `${COMMON_SERIF_ALIAS},${SOURCE_HAN_SERIF_SC_ALIAS}`
}
