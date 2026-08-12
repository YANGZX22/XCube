import { Context } from '@kit.AbilityKit'
import { zlib } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { getAppUiState } from '../state/AppUiState'
import {
  getDocumentAttachmentRegistryService,
  RegisteredDocumentAttachment
} from './DocumentAttachmentRegistryService'
import {
  OfficeOpenXmlParseResult,
  OfficeOpenXmlTextParser,
  OfficeWorksheetSource
} from './OfficeOpenXmlTextParser'

export class OfficeAttachmentTextExtractionRequest {
  attachmentId: string = ''
  maxChars: number = 12000
}

export class OfficeAttachmentTextExtractionResult {
  ok: boolean = false
  attachmentId: string = ''
  fileName: string = ''
  text: string = ''
  chars: number = 0
  truncated: boolean = false
  source: string = 'ooxml'
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

export class OfficeTextExtractionResult {
  ok: boolean = false
  text: string = ''
  truncated: boolean = false
  message: string = ''

  constructor(ok: boolean, text: string, truncated: boolean, message: string) {
    this.ok = ok
    this.text = text
    this.truncated = truncated
    this.message = message
  }
}

export class OfficeDocumentTextExtractionService {
  private static instance: OfficeDocumentTextExtractionService | null = null
  private static readonly MAX_UNCOMPRESSED_BYTES: number = 96 * 1024 * 1024
  private static readonly MAX_XML_FILE_BYTES: number = 48 * 1024 * 1024
  private static readonly MAX_WORKSHEETS: number = 200
  private static readonly READ_CHUNK_BYTES: number = 256 * 1024
  private cache: Map<string, OfficeTextExtractionResult> = new Map()
  private parser: OfficeOpenXmlTextParser = new OfficeOpenXmlTextParser()
  private context: Context | null = null

  static getInstance(): OfficeDocumentTextExtractionService {
    if (OfficeDocumentTextExtractionService.instance === null) {
      OfficeDocumentTextExtractionService.instance = new OfficeDocumentTextExtractionService()
    }
    return OfficeDocumentTextExtractionService.instance
  }

  initialize(context: Context): void {
    this.context = context
  }

  async extractForCurrentSession(
    request: OfficeAttachmentTextExtractionRequest,
    extension: string
  ): Promise<OfficeAttachmentTextExtractionResult> {
    const normalizedExtension = extension.toLowerCase()
    const sessionId = getAppUiState().activeChatSessionId.trim()
    if (sessionId === '') {
      return new OfficeAttachmentTextExtractionResult(
        false,
        request.attachmentId,
        '',
        '',
        false,
        '当前没有活动会话'
      )
    }
    const registry = getDocumentAttachmentRegistryService()
    const attachment = registry.getAttachment(sessionId, request.attachmentId)
    if (attachment === null) {
      const documents = registry.listAttachments(sessionId)
      const ids: string[] = []
      for (let index = 0; index < documents.length; index++) {
        if (this.matchesExtension(documents[index], normalizedExtension)) {
          ids.push(`${documents[index].attachmentId}:${documents[index].name}`)
        }
      }
      const label = normalizedExtension === '.docx' ? 'DOCX' : 'XLSX'
      return new OfficeAttachmentTextExtractionResult(
        false,
        request.attachmentId,
        '',
        '',
        false,
        `未找到 ${label} 附件。可用附件: ${ids.join(', ')}`
      )
    }
    return await this.extractAttachment(attachment, normalizedExtension, request.maxChars)
  }

  async extractAttachment(
    attachment: RegisteredDocumentAttachment,
    extension: string,
    maxChars: number
  ): Promise<OfficeAttachmentTextExtractionResult> {
    const normalizedExtension = extension.toLowerCase()
    const label = normalizedExtension === '.docx' ? 'DOCX' : 'XLSX'
    if (normalizedExtension !== '.docx' && normalizedExtension !== '.xlsx') {
      return new OfficeAttachmentTextExtractionResult(
        false,
        attachment.attachmentId,
        attachment.name,
        '',
        false,
        '不支持的 Office 文件格式'
      )
    }
    if (!this.matchesExtension(attachment, normalizedExtension)) {
      return new OfficeAttachmentTextExtractionResult(
        false,
        attachment.attachmentId,
        attachment.name,
        '',
        false,
        `该附件不是 ${label} 文件`
      )
    }
    if (this.context === null) {
      return new OfficeAttachmentTextExtractionResult(
        false,
        attachment.attachmentId,
        attachment.name,
        '',
        false,
        'Office 文档解析服务尚未初始化'
      )
    }
    const normalizedMaxChars = Math.max(1000, maxChars > 0 ? maxChars : 12000)
    const result = await this.extract(
      this.context,
      attachment.filePath,
      normalizedExtension,
      normalizedMaxChars
    )
    return new OfficeAttachmentTextExtractionResult(
      result.ok,
      attachment.attachmentId,
      attachment.name,
      result.text,
      result.truncated,
      result.message
    )
  }

  async extract(
    context: Context,
    filePath: string,
    extension: string,
    maxCharacters: number
  ): Promise<OfficeTextExtractionResult> {
    this.context = context
    const normalizedExtension = extension.toLowerCase()
    if (normalizedExtension !== '.docx' && normalizedExtension !== '.xlsx') {
      return new OfficeTextExtractionResult(false, '', false, '不支持的 Office 文件格式')
    }
    let sourceSize = 0
    let sourceModifiedAt = 0
    try {
      const sourceStat = fileIo.statSync(filePath)
      sourceSize = sourceStat.size
      sourceModifiedAt = sourceStat.mtime
    } catch (_error) {
      return new OfficeTextExtractionResult(false, '', false, 'Office 文件不存在或无法访问')
    }
    const cacheKey = `${filePath}:${sourceSize}:${sourceModifiedAt}:${normalizedExtension}:ooxml-v1:${maxCharacters}`
    const cached = this.cache.get(cacheKey)
    if (cached !== undefined) {
      return cached
    }

    const token = `${Date.now()}_${Math.floor(Math.random() * 0xFFFFFF).toString(16)}`
    const workDirectory = `${context.cacheDir}/knowledge_ooxml_${token}`
    const archivePath = `${workDirectory}/source.zip`
    const extractedDirectory = `${workDirectory}/content`
    try {
      fileIo.mkdirSync(workDirectory)
      fileIo.mkdirSync(extractedDirectory)
      await fileIo.copyFile(filePath, archivePath)
      const originalSize = await zlib.getOriginalSize(archivePath)
      if (originalSize <= 0) {
        throw new Error('Office 文档压缩包为空')
      }
      if (originalSize > OfficeDocumentTextExtractionService.MAX_UNCOMPRESSED_BYTES) {
        throw new Error('Office 文档解压后超过 96 MB 安全限制')
      }
      const options: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
        pathSeparatorStrategy: zlib.PathSeparatorStrategy.PATH_SEPARATOR_STRATEGY_REPLACE_BACKSLASH
      }
      await zlib.decompressFile(archivePath, extractedDirectory, options)
      let parsed: OfficeOpenXmlParseResult
      if (normalizedExtension === '.docx') {
        parsed = this.parseDocx(extractedDirectory, maxCharacters)
      } else {
        parsed = this.parseXlsx(extractedDirectory, maxCharacters)
      }
      if (parsed.text.trim() === '') {
        throw new Error('Office 文档中没有可建立索引的文字或单元格内容')
      }
      const label = normalizedExtension === '.docx' ? 'DOCX' : 'XLSX'
      const message = parsed.truncated
        ? `${label} 文档已解析，超出本地索引上限的内容已截断`
        : `${label} 文档已完成本地解析`
      const result = new OfficeTextExtractionResult(true, parsed.text, parsed.truncated, message)
      this.cache.set(cacheKey, result)
      return result
    } catch (error) {
      const message = this.safeErrorMessage(error)
      console.error(
        'OfficeDocumentTextExtractionService',
        `Failed to extract ${normalizedExtension}: ${JSON.stringify(error)}`
      )
      return new OfficeTextExtractionResult(
        false,
        '',
        false,
        message.indexOf('Office') >= 0 ? message : `Office 文档解析失败：${message}`
      )
    } finally {
      this.deleteDirectory(workDirectory)
    }
  }

  private matchesExtension(attachment: RegisteredDocumentAttachment, extension: string): boolean {
    const fileName = attachment.name.toLowerCase()
    const mimeType = attachment.mimeType.toLowerCase()
    if (extension === '.docx') {
      return fileName.endsWith('.docx') ||
        mimeType === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    }
    if (extension === '.xlsx') {
      return fileName.endsWith('.xlsx') ||
        mimeType === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    }
    return false
  }

  private parseDocx(extractedDirectory: string, maxCharacters: number): OfficeOpenXmlParseResult {
    const documentPath = `${extractedDirectory}/word/document.xml`
    if (!fileIo.accessSync(documentPath)) {
      throw new Error('文件不是有效的 DOCX：缺少 word/document.xml')
    }
    const documentXml = this.readUtf8File(documentPath)
    const stylesXml = this.readOptionalUtf8File(`${extractedDirectory}/word/styles.xml`)
    return this.parser.parseDocx(documentXml, stylesXml, maxCharacters)
  }

  private parseXlsx(extractedDirectory: string, maxCharacters: number): OfficeOpenXmlParseResult {
    const workbookPath = `${extractedDirectory}/xl/workbook.xml`
    if (!fileIo.accessSync(workbookPath)) {
      throw new Error('文件不是有效的 XLSX：缺少 xl/workbook.xml')
    }
    const worksheetsDirectory = `${extractedDirectory}/xl/worksheets`
    if (!fileIo.accessSync(worksheetsDirectory)) {
      throw new Error('文件不是有效的 XLSX：缺少工作表目录')
    }
    const workbookXml = this.readUtf8File(workbookPath)
    const relationshipsXml = this.readOptionalUtf8File(
      `${extractedDirectory}/xl/_rels/workbook.xml.rels`
    )
    const sharedStringsXml = this.readOptionalUtf8File(
      `${extractedDirectory}/xl/sharedStrings.xml`
    )
    const stylesXml = this.readOptionalUtf8File(`${extractedDirectory}/xl/styles.xml`)
    const fileNames = fileIo.listFileSync(worksheetsDirectory)
      .filter((value: string): boolean => value.toLowerCase().endsWith('.xml'))
      .sort((left: string, right: string): number => this.compareWorksheetNames(left, right))
    if (fileNames.length > OfficeDocumentTextExtractionService.MAX_WORKSHEETS) {
      throw new Error('XLSX 工作表数量超过 200 个安全限制')
    }
    const worksheets: OfficeWorksheetSource[] = []
    for (let index = 0; index < fileNames.length; index++) {
      const relativePath = `xl/worksheets/${fileNames[index]}`
      worksheets.push(new OfficeWorksheetSource(
        relativePath,
        this.readUtf8File(`${extractedDirectory}/${relativePath}`)
      ))
    }
    return this.parser.parseXlsx(
      workbookXml,
      relationshipsXml,
      sharedStringsXml,
      stylesXml,
      worksheets,
      maxCharacters
    )
  }

  private readOptionalUtf8File(filePath: string): string {
    return fileIo.accessSync(filePath) ? this.readUtf8File(filePath) : ''
  }

  private readUtf8File(filePath: string): string {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      if (stat.size > OfficeDocumentTextExtractionService.MAX_XML_FILE_BYTES) {
        throw new Error('Office 文档中的单个 XML 文件超过 48 MB 安全限制')
      }
      const bytes = this.readFileBytes(file.fd, stat.size)
      const decoder = util.TextDecoder.create('utf-8')
      return decoder.decodeToString(bytes, { stream: false })
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private readFileBytes(fileDescriptor: number, size: number): Uint8Array {
    const bytes = new Uint8Array(size)
    let offset = 0
    while (offset < size) {
      const chunkLength = Math.min(
        OfficeDocumentTextExtractionService.READ_CHUNK_BYTES,
        size - offset
      )
      const chunkBuffer = new ArrayBuffer(chunkLength)
      const readBytes = fileIo.readSync(fileDescriptor, chunkBuffer)
      if (readBytes <= 0) {
        throw new Error(`Office XML 读取不完整：期望 ${size} 字节，实际 ${offset} 字节`)
      }
      bytes.set(new Uint8Array(chunkBuffer, 0, readBytes), offset)
      offset += readBytes
    }
    return bytes
  }

  private compareWorksheetNames(left: string, right: string): number {
    const leftNumber = this.worksheetNumber(left)
    const rightNumber = this.worksheetNumber(right)
    if (leftNumber !== rightNumber) {
      return leftNumber - rightNumber
    }
    return left.localeCompare(right)
  }

  private worksheetNumber(value: string): number {
    const lower = value.toLowerCase()
    if (!lower.startsWith('sheet') || !lower.endsWith('.xml')) {
      return Number.MAX_SAFE_INTEGER
    }
    const parsed = Number.parseInt(lower.substring(5, lower.length - 4), 10)
    return Number.isFinite(parsed) ? parsed : Number.MAX_SAFE_INTEGER
  }

  private deleteDirectory(directoryPath: string): void {
    try {
      if (fileIo.accessSync(directoryPath)) {
        this.deleteRecursively(directoryPath)
      }
    } catch (error) {
      console.warn(
        'OfficeDocumentTextExtractionService',
        `Failed to clean parser cache: ${JSON.stringify(error)}`
      )
    }
  }

  private deleteRecursively(path: string): void {
    const children = fileIo.listFileSync(path)
    for (let index = 0; index < children.length; index++) {
      const childPath = `${path}/${children[index]}`
      const stat = fileIo.statSync(childPath)
      if (stat.isDirectory()) {
        this.deleteRecursively(childPath)
      } else {
        fileIo.unlinkSync(childPath)
      }
    }
    fileIo.rmdirSync(path)
  }

  private safeErrorMessage(error: Object): string {
    if (error instanceof Error && error.message.trim() !== '') {
      return error.message
    }
    const serialized = JSON.stringify(error)
    return serialized === '' ? '未知错误' : serialized
  }
}

export function getOfficeDocumentTextExtractionService(): OfficeDocumentTextExtractionService {
  return OfficeDocumentTextExtractionService.getInstance()
}
