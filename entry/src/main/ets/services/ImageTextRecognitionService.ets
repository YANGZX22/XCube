import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { textRecognition } from '@kit.CoreVisionKit'
import { getAppUiState } from '../state/AppUiState'
import {
  getDocumentAttachmentRegistryService,
  RegisteredDocumentAttachment
} from './DocumentAttachmentRegistryService'

export class ImageTextRecognitionRequest {
  attachmentId: string = ''
  maxChars: number = 12000
}

export class ImageTextRecognitionResult {
  ok: boolean = false
  attachmentId: string = ''
  fileName: string = ''
  text: string = ''
  chars: number = 0
  truncated: boolean = false
  message: string = ''

  constructor(
    ok: boolean,
    attachmentId: string,
    fileName: string,
    text: string,
    truncated: boolean,
    message: string
  ) {
    this.ok = ok
    this.attachmentId = attachmentId
    this.fileName = fileName
    this.text = text
    this.chars = text.length
    this.truncated = truncated
    this.message = message
  }
}

export class ImageTextRecognitionService {
  private static instance: ImageTextRecognitionService | null = null
  private cache: Map<string, string> = new Map()
  private initialized: boolean = false

  static getInstance(): ImageTextRecognitionService {
    if (ImageTextRecognitionService.instance === null) {
      ImageTextRecognitionService.instance = new ImageTextRecognitionService()
    }
    return ImageTextRecognitionService.instance
  }

  async recognizeForCurrentSession(request: ImageTextRecognitionRequest): Promise<ImageTextRecognitionResult> {
    const sessionId = getAppUiState().activeChatSessionId.trim()
    if (sessionId === '') {
      return new ImageTextRecognitionResult(false, request.attachmentId, '', '', false, '当前没有活动会话')
    }
    const attachment = getDocumentAttachmentRegistryService().getAttachment(sessionId, request.attachmentId)
    if (attachment === null) {
      const documents = getDocumentAttachmentRegistryService().listAttachments(sessionId)
      const ids: string[] = []
      for (let i = 0; i < documents.length; i++) {
        ids.push(`${documents[i].attachmentId}:${documents[i].name}`)
      }
      return new ImageTextRecognitionResult(false, request.attachmentId, '', '', false,
        `未找到图片附件。可用附件: ${ids.join(', ')}`)
    }
    return await this.recognizeAttachment(attachment, request.maxChars)
  }

  async recognizeAttachment(
    attachment: RegisteredDocumentAttachment,
    maxChars: number
  ): Promise<ImageTextRecognitionResult> {
    const cacheKey = `${attachment.filePath}:${attachment.size}`
    let text = this.cache.get(cacheKey)
    if (text === undefined) {
      text = await this.recognizeTextFromImagePath(attachment.filePath)
      this.cache.set(cacheKey, text)
    }
    const normalizedMaxChars = Math.max(1000, maxChars > 0 ? maxChars : 12000)
    const truncated = text.length > normalizedMaxChars
    const resultText = truncated ? text.substring(0, normalizedMaxChars) : text
    const message = text.trim() === ''
      ? '未识别到文本。该图片可能没有清晰文字，或当前系统 OCR 暂不可用。'
      : '已识别图片文本'
    return new ImageTextRecognitionResult(text.trim() !== '', attachment.attachmentId, attachment.name,
      resultText, truncated, message)
  }

  private async recognizeTextFromImagePath(filePath: string): Promise<string> {
    let file: fileIo.File | null = null
    let imageSource: image.ImageSource | null = null
    let pixelMap: image.PixelMap | null = null
    try {
      await this.ensureInitialized()
      file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      imageSource = image.createImageSource(file.fd)
      pixelMap = await imageSource.createPixelMap()
      const visionInfo: textRecognition.VisionInfo = {
        pixelMap: pixelMap
      }
      const configuration: textRecognition.TextRecognitionConfiguration = {
        isDirectionDetectionSupported: false
      }
      const result = await textRecognition.recognizeText(visionInfo, configuration)
      return this.normalizeText(result.value)
    } catch (error) {
      console.error('ImageTextRecognitionService', `Failed to recognize image text: ${JSON.stringify(error)}`)
      return ''
    } finally {
      if (pixelMap !== null) {
        pixelMap.release()
      }
      if (imageSource !== null) {
        imageSource.release()
      }
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private async ensureInitialized(): Promise<void> {
    if (this.initialized) {
      return
    }
    await textRecognition.init()
    this.initialized = true
  }

  private normalizeText(value: string): string {
    return value
      .replace(/\r/g, '\n')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim()
  }
}

export function getImageTextRecognitionService(): ImageTextRecognitionService {
  return ImageTextRecognitionService.getInstance()
}
