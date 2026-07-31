import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { pdfService } from '@kit.PDFKit'
import { textRecognition } from '@kit.CoreVisionKit'
import { getAppUiState } from '../state/AppUiState'
import {
  getDocumentAttachmentRegistryService,
  RegisteredDocumentAttachment
} from './DocumentAttachmentRegistryService'

export class PdfTextExtractionRequest {
  attachmentId: string = ''
  maxChars: number = 12000
  useOcr: boolean = false
}

export class PdfTextExtractionResult {
  ok: boolean = false
  attachmentId: string = ''
  fileName: string = ''
  text: string = ''
  chars: number = 0
  truncated: boolean = false
  source: string = ''
  message: string = ''

  constructor(
    ok: boolean,
    attachmentId: string,
    fileName: string,
    text: string,
    truncated: boolean,
    message: string,
    source: string = ''
  ) {
    this.ok = ok
    this.attachmentId = attachmentId
    this.fileName = fileName
    this.text = text
    this.chars = text.length
    this.truncated = truncated
    this.source = source
    this.message = message
  }
}

class PdfTextExtractionOutput {
  text: string = ''
  source: string = 'none'
  diagnostic: string = ''

  constructor(text: string, source: string, diagnostic: string = '') {
    this.text = text
    this.source = source
    this.diagnostic = diagnostic
  }
}

export class PdfTextExtractionService {
  private static instance: PdfTextExtractionService | null = null
  private static readonly OCR_TARGET_LONG_EDGE: number = 2200
  private static readonly OCR_MAX_SCALE: number = 3
  private cache: Map<string, PdfTextExtractionOutput> = new Map()
  private ocrInitialized: boolean = false

  static getInstance(): PdfTextExtractionService {
    if (PdfTextExtractionService.instance === null) {
      PdfTextExtractionService.instance = new PdfTextExtractionService()
    }
    return PdfTextExtractionService.instance
  }

  async extractForCurrentSession(request: PdfTextExtractionRequest): Promise<PdfTextExtractionResult> {
    const sessionId = getAppUiState().activeChatSessionId.trim()
    if (sessionId === '') {
      return new PdfTextExtractionResult(false, request.attachmentId, '', '', false, '当前没有活动会话')
    }
    const attachment = getDocumentAttachmentRegistryService().getAttachment(sessionId, request.attachmentId)
    if (attachment === null) {
      const documents = getDocumentAttachmentRegistryService().listAttachments(sessionId)
      const ids: string[] = []
      for (let i = 0; i < documents.length; i++) {
        ids.push(`${documents[i].attachmentId}:${documents[i].name}`)
      }
      return new PdfTextExtractionResult(false, request.attachmentId, '', '', false,
        `未找到 PDF 附件。可用附件: ${ids.join(', ')}`)
    }
    return await this.extractAttachment(attachment, request.maxChars, request.useOcr)
  }

  async extractAttachment(
    attachment: RegisteredDocumentAttachment,
    maxChars: number,
    useOcr: boolean = false
  ): Promise<PdfTextExtractionResult> {
    const cacheKey = `${attachment.filePath}:${attachment.size}:${useOcr ? 'ocr-v3' : 'text'}`
    let output = this.cache.get(cacheKey)
    if (output === undefined) {
      output = await this.extractTextFromPdfPath(attachment.filePath, useOcr)
      if (!useOcr || output.source !== 'none') {
        this.cache.set(cacheKey, output)
      }
    }
    const text = output.text
    const normalizedMaxChars = Math.max(1000, maxChars > 0 ? maxChars : 12000)
    const truncated = text.length > normalizedMaxChars
    const resultText = truncated ? text.substring(0, normalizedMaxChars) : text
    let message = '已提取 PDF 文本'
    if (text.trim() === '') {
      message = useOcr
        ? 'OCR 已执行，但未识别到文本。该 PDF 可能没有清晰文字，或当前系统 OCR 暂不可用。'
        : '未提取到文本。该 PDF 可能是扫描件；如需处理扫描件，可由模型判断后使用 useOcr=true 重试。'
    } else if (output.source === 'ocr') {
      message = '已通过 OCR 识别 PDF 文本'
    }
    if (output.diagnostic !== '') {
      message = `${message} 诊断: ${output.diagnostic}`
    }
    return new PdfTextExtractionResult(text.trim() !== '', attachment.attachmentId, attachment.name,
      resultText, truncated, message, output.source)
  }

  private async extractTextFromPdfPath(filePath: string, useOcr: boolean): Promise<PdfTextExtractionOutput> {
    try {
      if (useOcr) {
        return await this.extractTextWithOcr(filePath)
      }

      const pdfKitText = this.extractTextWithPdfKit(filePath)
      if (pdfKitText.trim() !== '') {
        return new PdfTextExtractionOutput(this.normalizeText(pdfKitText), 'text')
      }

      const bytes = this.readFileBytes(filePath)
      const latin1 = this.decodeLatin1(bytes)
      const streamTexts = this.extractStreamTexts(latin1)
      const directText = this.extractPdfTextOperators(latin1)
      const operatorText = this.normalizeText(`${streamTexts}\n${directText}`)
      if (operatorText.trim() !== '') {
        return new PdfTextExtractionOutput(operatorText, 'text')
      }

      return new PdfTextExtractionOutput('', 'none')
    } catch (error) {
      console.error('PdfTextExtractionService', `Failed to extract PDF text: ${JSON.stringify(error)}`)
      return new PdfTextExtractionOutput('', 'none')
    }
  }

  private extractTextWithPdfKit(filePath: string): string {
    const document = new pdfService.PdfDocument()
    let loaded = false
    try {
      const parseResult = document.loadDocument(filePath)
      if (parseResult !== pdfService.ParseResult.PARSE_SUCCESS) {
        console.warn('PdfTextExtractionService', `PDFKit parse failed: ${parseResult}`)
        return ''
      }
      loaded = true
      const pageTexts: string[] = []
      const pageCount = document.getPageCount()
      for (let i = 0; i < pageCount; i++) {
        const page = document.getPage(i)
        try {
          const pageText = page.getTextContent()
          if (pageText.trim() !== '') {
            pageTexts.push(`[第 ${i + 1} 页]\n${pageText}`)
          }
        } finally {
          page.release()
        }
      }
      return pageTexts.join('\n\n')
    } catch (error) {
      console.warn('PdfTextExtractionService', `PDFKit extraction failed: ${JSON.stringify(error)}`)
      return ''
    } finally {
      if (loaded) {
        document.releaseDocument()
      }
    }
  }

  private async extractTextWithOcr(filePath: string): Promise<PdfTextExtractionOutput> {
    const document = new pdfService.PdfDocument()
    let loaded = false
    const diagnostics: string[] = []
    try {
      await this.ensureOcrInitialized()
      const parseResult = document.loadDocument(filePath)
      if (parseResult !== pdfService.ParseResult.PARSE_SUCCESS) {
        console.warn('PdfTextExtractionService', `PDFKit parse for OCR failed: ${parseResult}`)
        return new PdfTextExtractionOutput('', 'none', `parse=${parseResult}`)
      }
      loaded = true
      const pageTexts: string[] = []
      const pageCount = document.getPageCount()
      diagnostics.push(`pages=${pageCount}`)
      for (let i = 0; i < pageCount; i++) {
        const page = document.getPage(i)
        let renderedPixelMap: image.PixelMap | null = null
        let pixelMap: image.PixelMap | null = null
        try {
          renderedPixelMap = this.createPagePixelMapForOcr(page)
          pixelMap = await this.normalizePixelMapForOcr(renderedPixelMap)
          if (pixelMap !== renderedPixelMap) {
            renderedPixelMap.release()
            renderedPixelMap = null
          }
          const pageText = await this.recognizePixelMapText(pixelMap)
          const imageInfo = pixelMap.getImageInfoSync()
          diagnostics.push(`p${i + 1}:${imageInfo.size.width}x${imageInfo.size.height}/${pageText.length}`)
          console.info('PdfTextExtractionService',
            `PDF page OCR result: page=${i + 1}, width=${imageInfo.size.width}, height=${imageInfo.size.height}, chars=${pageText.length}`)
          if (pageText.trim() !== '') {
            pageTexts.push(`[第 ${i + 1} 页]\n${pageText}`)
          }
        } catch (error) {
          diagnostics.push(`p${i + 1}:error`)
          console.warn('PdfTextExtractionService', `PDF page OCR failed: page=${i + 1}, error=${JSON.stringify(error)}`)
        } finally {
          if (pixelMap !== null) {
            pixelMap.release()
          }
          if (renderedPixelMap !== null) {
            renderedPixelMap.release()
          }
          page.release()
        }
      }
      const text = this.normalizeText(pageTexts.join('\n\n'))
      return new PdfTextExtractionOutput(text, text.trim() !== '' ? 'ocr' : 'none', diagnostics.join(', '))
    } catch (error) {
      console.warn('PdfTextExtractionService', `PDF OCR extraction failed: ${JSON.stringify(error)}`)
      diagnostics.push('error')
      return new PdfTextExtractionOutput('', 'none', diagnostics.join(', '))
    } finally {
      if (loaded) {
        document.releaseDocument()
      }
    }
  }

  private createPagePixelMapForOcr(page: pdfService.PdfPage): image.PixelMap {
    const pageWidth = Math.max(1, page.getWidth())
    const pageHeight = Math.max(1, page.getHeight())
    const longEdge = Math.max(pageWidth, pageHeight)
    const scale = Math.min(PdfTextExtractionService.OCR_MAX_SCALE,
      Math.max(1, PdfTextExtractionService.OCR_TARGET_LONG_EDGE / longEdge))
    const bitmapWidth = Math.max(1, Math.round(pageWidth * scale))
    const bitmapHeight = Math.max(1, Math.round(pageHeight * scale))

    const matrix = new pdfService.PdfMatrix()
    matrix.x = 0
    matrix.y = 0
    matrix.width = pageWidth
    matrix.height = pageHeight
    matrix.rotate = 0

    const options = new pdfService.PixelOptions()
    options.isGray = false
    options.drawAnnotations = true
    options.isTransparent = false

    try {
      return page.getAreaPixelMapWithOptions(matrix, bitmapWidth, bitmapHeight, options)
    } catch (error) {
      console.warn('PdfTextExtractionService',
        `High resolution PDF page render failed, fallback to default render: ${JSON.stringify(error)}`)
      return page.getPagePixelMap()
    }
  }

  private async normalizePixelMapForOcr(source: image.PixelMap): Promise<image.PixelMap> {
    let packer: image.ImagePacker | null = null
    let imageSource: image.ImageSource | null = null
    try {
      packer = image.createImagePacker()
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: 95
      }
      const imageData = await packer.packToData(source, packOpts)
      imageSource = image.createImageSource(imageData)
      return await imageSource.createPixelMap()
    } catch (error) {
      console.warn('PdfTextExtractionService',
        `PDF OCR image normalization failed, use rendered pixelmap directly: ${JSON.stringify(error)}`)
      return source
    } finally {
      if (imageSource !== null) {
        imageSource.release()
      }
      if (packer !== null) {
        packer.release()
      }
    }
  }

  private async recognizePixelMapText(pixelMap: image.PixelMap): Promise<string> {
    const visionInfo: textRecognition.VisionInfo = {
      pixelMap: pixelMap
    }
    const configuration: textRecognition.TextRecognitionConfiguration = {
      isDirectionDetectionSupported: true
    }
    const result = await textRecognition.recognizeText(visionInfo, configuration)
    return this.normalizeText(result.value)
  }

  private async ensureOcrInitialized(): Promise<void> {
    if (this.ocrInitialized) {
      return
    }
    await textRecognition.init()
    this.ocrInitialized = true
  }

  private readFileBytes(filePath: string): Uint8Array {
    const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
    const stat = fileIo.statSync(file.fd)
    const buffer = new ArrayBuffer(stat.size)
    fileIo.readSync(file.fd, buffer)
    fileIo.closeSync(file)
    return new Uint8Array(buffer)
  }

  private decodeLatin1(bytes: Uint8Array): string {
    let result = ''
    const chunkSize = 4096
    for (let i = 0; i < bytes.length; i += chunkSize) {
      const chunk = bytes.subarray(i, Math.min(bytes.length, i + chunkSize))
      let chunkText = ''
      for (let j = 0; j < chunk.length; j++) {
        chunkText += String.fromCharCode(chunk[j])
      }
      result += chunkText
    }
    return result
  }

  private extractStreamTexts(pdfText: string): string {
    const texts: string[] = []
    const streamPattern = /<<(?![\s\S]*?\/FlateDecode)[\s\S]*?>>\s*stream\r?\n([\s\S]*?)\r?\nendstream/g
    let match: RegExpExecArray | null = streamPattern.exec(pdfText)
    while (match !== null) {
      texts.push(this.extractPdfTextOperators(match[1]))
      match = streamPattern.exec(pdfText)
    }
    return texts.join('\n')
  }

  private extractPdfTextOperators(content: string): string {
    const texts: string[] = []
    const arrayTextPattern = /\[((?:.|\n|\r)*?)\]\s*TJ/g
    let arrayMatch: RegExpExecArray | null = arrayTextPattern.exec(content)
    while (arrayMatch !== null) {
      texts.push(this.extractLiteralStrings(arrayMatch[1]))
      arrayMatch = arrayTextPattern.exec(content)
    }

    const singleTextPattern = /\(([^()]*(?:\\.[^()]*)*)\)\s*Tj/g
    let singleMatch: RegExpExecArray | null = singleTextPattern.exec(content)
    while (singleMatch !== null) {
      texts.push(this.unescapePdfString(singleMatch[1]))
      singleMatch = singleTextPattern.exec(content)
    }

    const quoteTextPattern = /\(([^()]*(?:\\.[^()]*)*)\)\s*'/g
    let quoteMatch: RegExpExecArray | null = quoteTextPattern.exec(content)
    while (quoteMatch !== null) {
      texts.push(this.unescapePdfString(quoteMatch[1]))
      quoteMatch = quoteTextPattern.exec(content)
    }
    return texts.join('\n')
  }

  private extractLiteralStrings(value: string): string {
    const parts: string[] = []
    const literalPattern = /\(([^()]*(?:\\.[^()]*)*)\)/g
    let match: RegExpExecArray | null = literalPattern.exec(value)
    while (match !== null) {
      parts.push(this.unescapePdfString(match[1]))
      match = literalPattern.exec(value)
    }
    return parts.join('')
  }

  private unescapePdfString(value: string): string {
    return value
      .replace(/\\n/g, '\n')
      .replace(/\\r/g, '\r')
      .replace(/\\t/g, '\t')
      .replace(/\\b/g, '\b')
      .replace(/\\f/g, '\f')
      .replace(/\\\(/g, '(')
      .replace(/\\\)/g, ')')
      .replace(/\\\\/g, '\\')
  }

  private normalizeText(value: string): string {
    return value
      .replace(/\r/g, '\n')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim()
  }
}

export function getPdfTextExtractionService(): PdfTextExtractionService {
  return PdfTextExtractionService.getInstance()
}
