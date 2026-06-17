import { refreshAssistantAvatar } from '../services/AssistantAvatarCache'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { ModelIconRenderData, buildModelIconRenderData } from '../utils/ModelIconRenderUtils'
import { TRANSPARENT_BG_COLOR } from '../utils/IconGeneratorUtils'

export const ASSISTANT_AVATAR_MODE_SYMBOL: string = 'symbol'
export const ASSISTANT_AVATAR_MODE_IMAGE: string = 'image'
export const ASSISTANT_AVATAR_MODE_MODEL: string = 'model'

const QQ_AVATAR_PREFIX: string = 'qq:'
const MODEL_AVATAR_PREFIX: string = 'model:'

class AssistantModelAvatarInfo {
  providerId: string = ''
  modelId: string = ''

  constructor(providerId: string = '', modelId: string = '') {
    this.providerId = providerId
    this.modelId = modelId
  }
}

function stripLocalAvatarUriVersion(value: string): string {
  let source = value.trim()
  const fragmentIndex = source.indexOf('#')
  if (fragmentIndex >= 0) {
    source = source.substring(0, fragmentIndex)
  }
  const queryIndex = source.indexOf('?')
  return queryIndex >= 0 ? source.substring(0, queryIndex) : source
}

function appendAssistantAvatarCacheKey(source: string, cacheKey: number): string {
  if (cacheKey <= 0 || source === '') {
    return source
  }
  const fragmentIndex = source.indexOf('#')
  const sourceWithoutFragment = fragmentIndex >= 0 ? source.substring(0, fragmentIndex) : source
  const fragment = fragmentIndex >= 0 ? source.substring(fragmentIndex) : ''
  const separator = sourceWithoutFragment.indexOf('?') >= 0 ? '&' : '?'
  return `${sourceWithoutFragment}${separator}avatarCacheKey=${cacheKey}${fragment}`
}

function getLocalAvatarMimeType(source: string): string {
  const cleanSource = stripLocalAvatarUriVersion(source).toLowerCase()
  if (cleanSource.endsWith('.png')) {
    return 'image/png'
  }
  if (cleanSource.endsWith('.webp')) {
    return 'image/webp'
  }
  if (cleanSource.endsWith('.gif')) {
    return 'image/gif'
  }
  if (cleanSource.endsWith('.bmp')) {
    return 'image/bmp'
  }
  return 'image/jpeg'
}

function resolveLocalAvatarPath(source: string): string {
  const cleanSource = stripLocalAvatarUriVersion(source)
  if (!cleanSource.toLowerCase().startsWith('file://')) {
    return cleanSource
  }
  try {
    return new fileUri.FileUri(cleanSource).path
  } catch (_error) {
    return cleanSource.substring(7)
  }
}

function readLocalAvatarBuffer(source: string): ArrayBuffer | null {
  const localPath = resolveLocalAvatarPath(source)
  try {
    const file = fileIo.openSync(localPath, fileIo.OpenMode.READ_ONLY)
    try {
      const stat = fileIo.statSync(file.fd)
      if (stat.size <= 0) {
        return null
      }
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      return buffer
    } finally {
      fileIo.closeSync(file)
    }
  } catch (_error) {
    return null
  }
}

function resolveLocalAvatarDataSource(source: string): string {
  const buffer = readLocalAvatarBuffer(source)
  if (buffer === null) {
    return stripLocalAvatarUriVersion(source)
  }
  const base64Helper = new util.Base64Helper()
  const encoded = base64Helper.encodeToStringSync(new Uint8Array(buffer))
  return `data:${getLocalAvatarMimeType(source)};base64,${encoded}`
}

export function sanitizeAssistantQqNumber(value: string): string {
  return value.replace(/[^0-9]/g, '')
}

export function buildQqAssistantAvatarUrl(value: string): string {
  const qqNumber = sanitizeAssistantQqNumber(value)
  return qqNumber !== '' ? `http://q1.qlogo.cn/g?b=qq&nk=${qqNumber}&s=640` : ''
}

export function extractQqFromAssistantAvatar(value: string): string {
  const avatar = value.trim()
  const lower = avatar.toLowerCase()
  if (lower.startsWith(QQ_AVATAR_PREFIX)) {
    return sanitizeAssistantQqNumber(avatar.substring(QQ_AVATAR_PREFIX.length))
  }
  const qlogoMatch = avatar.match(/[?&]nk=([0-9]+)/)
  if (qlogoMatch !== null && qlogoMatch.length > 1) {
    return sanitizeAssistantQqNumber(qlogoMatch[1])
  }
  return ''
}

export function isQqAssistantAvatar(value: string): boolean {
  return extractQqFromAssistantAvatar(value) !== ''
}

export function isDirectImageAssistantAvatar(value: string): boolean {
  const lower = value.trim().toLowerCase()
  return lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('file://') ||
  lower.startsWith('data:image/')
}

export function isImageAssistantAvatar(value: string): boolean {
  return isQqAssistantAvatar(value) || isDirectImageAssistantAvatar(value)
}

export function isModelAssistantAvatar(value: string): boolean {
  return value.trim().toLowerCase().startsWith(MODEL_AVATAR_PREFIX)
}

export function buildAssistantModelAvatarValue(providerId: string, modelId: string): string {
  return `${MODEL_AVATAR_PREFIX}${providerId.trim()}:${modelId.trim()}`
}

function parseAssistantModelAvatar(value: string): AssistantModelAvatarInfo {
  const avatar = value.trim()
  if (!isModelAssistantAvatar(avatar)) {
    return new AssistantModelAvatarInfo()
  }
  const payload = avatar.substring(MODEL_AVATAR_PREFIX.length)
  const separatorIndex = payload.indexOf(':')
  if (separatorIndex < 0) {
    return new AssistantModelAvatarInfo(payload, '')
  }
  return new AssistantModelAvatarInfo(payload.substring(0, separatorIndex), payload.substring(separatorIndex + 1))
}

export function resolveAssistantAvatarImageSource(value: string): string {
  const qqNumber = extractQqFromAssistantAvatar(value)
  if (qqNumber !== '') {
    return buildQqAssistantAvatarUrl(qqNumber)
  }
  const source = value.trim()
  if (source.toLowerCase().startsWith('file://')) {
    return stripLocalAvatarUriVersion(source)
  }
  return source
}

export function resolveAssistantAvatarRenderSource(value: string, cacheKey: number = 0): string {
  const source = resolveAssistantAvatarImageSource(value)
  if (cacheKey <= 0 || source === '') {
    return source
  }
  const lower = source.toLowerCase()
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return appendAssistantAvatarCacheKey(source, cacheKey)
  }
  return source
}

export function refreshAssistantAvatarCache(value: string): void {
  if (isModelAssistantAvatar(value)) {
    return
  }
  const source = resolveAssistantAvatarImageSource(value)
  const lower = source.toLowerCase()
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    refreshAssistantAvatar(source)
  }
}

export function getAssistantAvatarInputMode(value: string): string {
  if (isModelAssistantAvatar(value)) {
    return ASSISTANT_AVATAR_MODE_MODEL
  }
  if (isQqAssistantAvatar(value) || isDirectImageAssistantAvatar(value)) {
    return ASSISTANT_AVATAR_MODE_IMAGE
  }
  return ASSISTANT_AVATAR_MODE_SYMBOL
}

export function normalizeAssistantAvatarValue(value: string): string {
  const avatar = value.trim()
  if (avatar === '' || avatar === QQ_AVATAR_PREFIX) {
    return 'AI'
  }
  if (isModelAssistantAvatar(avatar)) {
    const modelInfo = parseAssistantModelAvatar(avatar)
    return buildAssistantModelAvatarValue(modelInfo.providerId, modelInfo.modelId)
  }
  const qqNumber = extractQqFromAssistantAvatar(avatar)
  if (qqNumber !== '') {
    return buildQqAssistantAvatarUrl(qqNumber)
  }
  return avatar
}

export function getAssistantAvatarFallbackText(value: string): string {
  if (isModelAssistantAvatar(value)) {
    return 'AI'
  }
  if (isQqAssistantAvatar(value)) {
    return 'QQ'
  }
  if (isDirectImageAssistantAvatar(value)) {
    return 'IMG'
  }
  return normalizeAssistantAvatarValue(value)
}

@ComponentV2
export struct AssistantAvatarView {
  @Param value: string = 'AI'
  @Param color: string = '#4E6F9E'
  @Param avatarSize: number = 44
  @Param radius: number = 15
  @Param fontSize: number = 23
  @Param cacheKey: number = 0
  @Param modelProviderId: string = ''
  @Param modelId: string = ''
  @Param modelName: string = ''
  @Param avatarBorderWidth: number = 0
  @Param avatarBorderColor: ResourceColor = Color.Transparent

  @Computed
  get renderImageSource(): string {
    const source = resolveAssistantAvatarImageSource(this.value)
    if (source.toLowerCase().startsWith('file://')) {
      return resolveLocalAvatarDataSource(source)
    }
    return resolveAssistantAvatarRenderSource(this.value, this.cacheKey)
  }

  @Computed
  get modelIconRenderData(): ModelIconRenderData {
    const modelInfo = parseAssistantModelAvatar(this.value)
    const providerId = this.modelProviderId !== '' ? this.modelProviderId : modelInfo.providerId
    const modelId = this.modelId !== '' ? this.modelId : modelInfo.modelId
    return buildModelIconRenderData(modelId, providerId, this.modelName)
  }

  private isTransparentTextAvatar(): boolean {
    return this.color === TRANSPARENT_BG_COLOR
  }

  private getTextAvatarBackgroundColor(): ResourceColor {
    return this.isTransparentTextAvatar() ? Color.Transparent : this.color
  }

  private getTextAvatarFontColor(): ResourceColor {
    return this.isTransparentTextAvatar() ? $r('app.color.text_primary') : Color.White
  }

  private getAvatarBorderWidth(): number {
    return this.avatarBorderWidth > 0 ? this.avatarBorderWidth : (this.isTransparentTextAvatar() ? 1 : 0)
  }

  private getAvatarBorderColor(): ResourceColor {
    return this.avatarBorderWidth > 0 ? this.avatarBorderColor :
      (this.isTransparentTextAvatar() ? $r('app.color.divider') : Color.Transparent)
  }

  @Builder
  private AvatarImage() {
    Image(this.renderImageSource)
      .width(this.avatarSize)
      .height(this.avatarSize)
      .objectFit(ImageFit.Cover)
      .syncLoad(true)
      .sourceSize({
        width: this.avatarSize,
        height: this.avatarSize
      })
      .interpolation(ImageInterpolation.High)
      .borderRadius(this.radius)
      .clip(true)
  }

  @Builder
  private AvatarModelIcon() {
    Column() {
      if (this.modelIconRenderData.hasIcon()) {
        if (this.modelIconRenderData.isRawfile()) {
          Image($rawfile(this.modelIconRenderData.resourcePath))
            .width(this.avatarSize * 0.72)
            .height(this.avatarSize * 0.72)
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.High)
        } else {
          Image(this.modelIconRenderData.resourcePath)
            .width(this.avatarSize * 0.72)
            .height(this.avatarSize * 0.72)
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.High)
        }
      } else {
        SymbolGlyph($r('sys.symbol.ai_edit'))
          .fontSize(this.avatarSize * 0.5)
          .fontColor([$r('app.color.text_tertiary')])
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .borderRadius(this.radius)
    .backgroundColor($r('app.color.model_icon_bg'))
    .border({ width: this.avatarBorderWidth, color: this.avatarBorderColor })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .clip(true)
  }

  build() {
    if (isModelAssistantAvatar(this.value)) {
      this.AvatarModelIcon()
    } else if (isImageAssistantAvatar(this.value)) {
      Stack() {
        if (this.cacheKey % 2 === 0) {
          this.AvatarImage()
        } else {
          this.AvatarImage()
        }
      }
      .width(this.avatarSize)
      .height(this.avatarSize)
      .borderRadius(this.radius)
      .border({ width: this.avatarBorderWidth, color: this.avatarBorderColor })
      .clip(true)
    } else {
      Stack() {
        Text(getAssistantAvatarFallbackText(this.value))
          .fontSize(this.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getTextAvatarFontColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: this.avatarSize - 8 })
      }
      .width(this.avatarSize)
      .height(this.avatarSize)
      .backgroundColor(this.getTextAvatarBackgroundColor())
      .borderRadius(this.radius)
      .border({
        width: this.getAvatarBorderWidth(),
        color: this.getAvatarBorderColor()
      })
      .clip(true)
    }
  }
}
