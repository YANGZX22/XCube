import { text } from '@kit.ArkGraphics2D'
import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'

export const CHAT_SERIF_FONT_COMMON: string = 'common'
export const CHAT_SERIF_FONT_CUSTOM: string = 'custom'

const COMMON_SERIF_ALIAS: string = 'XCubeCommonSerif'
const SOURCE_HAN_SERIF_SC_ALIAS: string = 'XCubeSourceHanSerifSC'
const IMPORTED_SERIF_ALIAS: string = 'XCubeImportedSerif'
const IMPORTED_SERIF_TTF_FILE: string = 'xcube_imported_serif.ttf'
const IMPORTED_SERIF_OTF_FILE: string = 'xcube_imported_serif.otf'
const IMPORTED_SERIF_NAME_FILE: string = 'xcube_imported_serif_name.txt'

export class ChatSerifFontAvailability {
  commonAvailable: boolean = true
  customAvailable: boolean = false
}

let cachedAvailability: ChatSerifFontAvailability | null = null
let commonSerifRegistered: boolean = false
let sourceHanSerifRegistered: boolean = false
let importedSerifRegistered: boolean = false
let activeImportedSerifAlias: string = IMPORTED_SERIF_ALIAS
let activeImportedSerifName: string = ''

function getStoredImportedFontPath(context: common.UIAbilityContext): string {
  const ttfPath = `${context.filesDir}/${IMPORTED_SERIF_TTF_FILE}`
  if (fileIo.accessSync(ttfPath)) {
    return ttfPath
  }
  const otfPath = `${context.filesDir}/${IMPORTED_SERIF_OTF_FILE}`
  return fileIo.accessSync(otfPath) ? otfPath : ''
}

function tryRegisterStoredImportedSerif(context: common.UIAbilityContext,
  fontCollection: text.FontCollection): boolean {
  const storedPath = getStoredImportedFontPath(context)
  if (storedPath === '') {
    return false
  }
  try {
    fontCollection.loadFontSyncWithCheck(IMPORTED_SERIF_ALIAS, `file://${storedPath}`)
    activeImportedSerifAlias = IMPORTED_SERIF_ALIAS
    activeImportedSerifName = readStoredImportedFontName(context)
    importedSerifRegistered = true
    return true
  } catch (error) {
    console.warn('ChatSerifFontUtils', `Imported serif font unavailable: ${JSON.stringify(error)}`)
    return false
  }
}

function readStoredImportedFontName(context: common.UIAbilityContext): string {
  const namePath = `${context.filesDir}/${IMPORTED_SERIF_NAME_FILE}`
  if (!fileIo.accessSync(namePath)) {
    return ''
  }
  try {
    return fileIo.readTextSync(namePath).trim()
  } catch (error) {
    console.warn('ChatSerifFontUtils', `Imported serif font name unavailable: ${JSON.stringify(error)}`)
    return ''
  }
}

function writeStoredImportedFontName(context: common.UIAbilityContext, displayName: string): void {
  const namePath = `${context.filesDir}/${IMPORTED_SERIF_NAME_FILE}`
  const nameFile = fileIo.openSync(namePath,
    fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
  try {
    fileIo.writeSync(nameFile.fd, displayName)
  } finally {
    fileIo.closeSync(nameFile)
  }
}

function copyFontToPath(sourceUri: string, destinationPath: string): void {
  const sourceFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY)
  let destinationFile: fileIo.File | null = null
  try {
    destinationFile = fileIo.openSync(destinationPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
    fileIo.copyFileSync(sourceFile.fd, destinationFile.fd)
  } finally {
    fileIo.closeSync(sourceFile)
    if (destinationFile !== null) {
      fileIo.closeSync(destinationFile)
    }
  }
}

function getImportedFontExtension(sourceUri: string): string {
  const normalizedUri = sourceUri.toLowerCase().split('?')[0]
  if (normalizedUri.endsWith('.otf')) {
    return '.otf'
  }
  if (normalizedUri.endsWith('.ttf')) {
    return '.ttf'
  }
  throw new Error('Only TTF and OTF font files are supported')
}

function getImportedFontDisplayName(sourceUri: string): string {
  const uriWithoutQuery = sourceUri.split('?')[0].split('#')[0]
  const parts = uriWithoutQuery.split('/')
  const encodedName = parts.length > 0 ? parts[parts.length - 1] : ''
  let decodedName = encodedName
  try {
    decodedName = decodeURIComponent(encodedName)
  } catch (_error) {
  }
  const displayName = decodedName.replace(/\.(ttf|otf)$/i, '').trim()
  return displayName !== '' ? displayName : 'Imported Font'
}

export function importChatSerifFont(uiContext: UIContext, sourceUri: string): void {
  const hostContext = uiContext.getHostContext() as common.UIAbilityContext | undefined
  if (hostContext === undefined || hostContext === null) {
    throw new Error('UI context unavailable')
  }

  const extension = getImportedFontExtension(sourceUri)
  const tempPath = `${hostContext.cacheDir}/xcube_imported_serif_${Date.now().toString()}${extension}`
  const destinationName = extension === '.otf' ? IMPORTED_SERIF_OTF_FILE : IMPORTED_SERIF_TTF_FILE
  const destinationPath = `${hostContext.filesDir}/${destinationName}`
  const otherPath = `${hostContext.filesDir}/${extension === '.otf' ? IMPORTED_SERIF_TTF_FILE : IMPORTED_SERIF_OTF_FILE}`
  const displayName = getImportedFontDisplayName(sourceUri)
  try {
    copyFontToPath(sourceUri, tempPath)
    const fontCollection = text.FontCollection.getGlobalInstance()
    const validationAlias = `${IMPORTED_SERIF_ALIAS}_${Date.now().toString()}`
    fontCollection.loadFontSyncWithCheck(validationAlias, `file://${tempPath}`)
    copyFontToPath(tempPath, destinationPath)
    if (fileIo.accessSync(otherPath)) {
      fileIo.unlinkSync(otherPath)
    }
    writeStoredImportedFontName(hostContext, displayName)
    activeImportedSerifAlias = validationAlias
    activeImportedSerifName = displayName
    importedSerifRegistered = true
    if (cachedAvailability === null) {
      cachedAvailability = new ChatSerifFontAvailability()
    }
    cachedAvailability.customAvailable = true
  } finally {
    if (fileIo.accessSync(tempPath)) {
      fileIo.unlinkSync(tempPath)
    }
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
    availability.customAvailable = importedSerifRegistered ||
      tryRegisterStoredImportedSerif(hostContext, fontCollection)
    cachedAvailability = availability
  }
  return availability
}

export function resolveChatSerifFontFamily(fontId: string): string {
  if (fontId === CHAT_SERIF_FONT_CUSTOM && cachedAvailability?.customAvailable === true) {
    return `${activeImportedSerifAlias},${SOURCE_HAN_SERIF_SC_ALIAS}`
  }
  return `${COMMON_SERIF_ALIAS},${SOURCE_HAN_SERIF_SC_ALIAS}`
}

export function getImportedChatSerifFontName(): string {
  return activeImportedSerifName
}
