import { fileIo } from '@kit.CoreFileKit'
import { pdfService } from '@kit.PDFKit'
import { getAppUiState } from '../state/AppUiState'
import {
  getDocumentAttachmentRegistryService,
  RegisteredDocumentAttachment
} from './DocumentAttachmentRegistryService'

export class PdfTextExtractionRequest {
  attachmentId: string = ''
  maxChars: number = 12000
}

export class PdfTextExtractionResult {
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

export class PdfTextExtractionService {
  private static instance: PdfTextExtractionService | null = null
  private cache: Map<string, string> = new Map()

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
    return await this.extractAttachment(attachment, request.maxChars)
  }

  async extractAttachment(attachment: RegisteredDocumentAttachment, maxChars: number): Promise<PdfTextExtractionResult> {
    const cacheKey = `${attachment.filePath}:${attachment.size}`
    let text = this.cache.get(cacheKey)
    if (text === undefined) {
      text = await this.extractTextFromPdfPath(attachment.filePath)
      this.cache.set(cacheKey, text)
    }
    const normalizedMaxChars = Math.max(1000, maxChars > 0 ? maxChars : 12000)
    const truncated = text.length > normalizedMaxChars
    const resultText = truncated ? text.substring(0, normalizedMaxChars) : text
    const message = text.trim() === ''
      ? '未提取到文本。该 PDF 可能是扫描件或使用了暂不支持的编码，后续需要 OCR。'
      : '已提取 PDF 文本'
    return new PdfTextExtractionResult(text.trim() !== '', attachment.attachmentId, attachment.name,
      resultText, truncated, message)
  }

  private async extractTextFromPdfPath(filePath: string): Promise<string> {
    try {
      const pdfKitText = this.extractTextWithPdfKit(filePath)
      if (pdfKitText.trim() !== '') {
        return this.normalizeText(pdfKitText)
      }

      const bytes = this.readFileBytes(filePath)
      const latin1 = this.decodeLatin1(bytes)
      const streamTexts = this.extractStreamTexts(latin1)
      const directText = this.extractPdfTextOperators(latin1)
      return this.normalizeText(`${streamTexts}\n${directText}`)
    } catch (error) {
      console.error('PdfTextExtractionService', `Failed to extract PDF text: ${JSON.stringify(error)}`)
      return ''
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
            pageTexts.push(pageText)
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
