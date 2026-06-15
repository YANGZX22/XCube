import { AppStorageKeys } from '../config/AppStorageKeys'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { getPreferencesService, PreferenceKeys, PreferencesService } from './PreferencesService'

interface CanvasDocumentStorage {
  title?: string
  content?: string
  updatedAt?: number
  updatedBy?: string
  revision?: number
  activated?: boolean
}

export class CanvasDocumentState {
  title: string = 'Canvas'
  content: string = ''
  updatedAt: number = 0
  updatedBy: string = ''
  revision: number = 0
  activated: boolean = false

  constructor(
    title: string = 'Canvas',
    content: string = '',
    updatedAt: number = 0,
    updatedBy: string = '',
    revision: number = 0,
    activated: boolean = false
  ) {
    this.title = title
    this.content = content
    this.updatedAt = updatedAt
    this.updatedBy = updatedBy
    this.revision = revision
    this.activated = activated
  }
}

export class CanvasDocumentMutationResult {
  ok: boolean = true
  message: string = ''
  document: CanvasDocumentState = new CanvasDocumentState()

  constructor(ok: boolean, message: string, document: CanvasDocumentState) {
    this.ok = ok
    this.message = message
    this.document = document
  }
}

export class CanvasDocumentService {
  private static instance: CanvasDocumentService | null = null
  private preferencesService: PreferencesService = getPreferencesService()
  private cachedDocuments: Map<string, CanvasDocumentState> = new Map()

  static getInstance(): CanvasDocumentService {
    if (CanvasDocumentService.instance === null) {
      CanvasDocumentService.instance = new CanvasDocumentService()
    }
    return CanvasDocumentService.instance
  }

  async loadDocument(documentId: string = ''): Promise<CanvasDocumentState> {
    const resolvedDocumentId = this.resolveDocumentId(documentId)
    const cachedDocument = this.cachedDocuments.get(resolvedDocumentId)
    const raw = await this.preferencesService.getString(this.getDocumentPreferenceKey(resolvedDocumentId), '')
    if (raw.trim() === '') {
      if (cachedDocument !== undefined) {
        return this.cloneDocument(cachedDocument)
      }
      return new CanvasDocumentState('Canvas', '', 0, '', 0, false)
    }
    try {
      const parsed = JSON.parse(raw) as CanvasDocumentStorage
      const document = new CanvasDocumentState(
        this.resolveString(parsed.title, 'Canvas'),
        this.resolveString(parsed.content),
        this.resolveNumber(parsed.updatedAt),
        this.resolveString(parsed.updatedBy),
        this.resolveNumber(parsed.revision),
        this.resolveBoolean(parsed.activated)
      )
      if (cachedDocument !== undefined && (cachedDocument.revision > document.revision ||
        (cachedDocument.revision === document.revision && cachedDocument.updatedAt > document.updatedAt))) {
        return this.cloneDocument(cachedDocument)
      }
      this.cachedDocuments.set(resolvedDocumentId, this.cloneDocument(document))
      return document
    } catch (error) {
      console.error('CanvasDocumentService', `Failed to parse canvas document: ${JSON.stringify(error)}`)
      if (cachedDocument !== undefined) {
        return this.cloneDocument(cachedDocument)
      }
      return new CanvasDocumentState('Canvas', '', 0, '', 0, false)
    }
  }

  async activateDocument(updatedBy: string = 'assistant', documentId: string = ''): Promise<CanvasDocumentState> {
    const resolvedDocumentId = this.resolveDocumentId(documentId)
    const current = await this.loadDocument(resolvedDocumentId)
    if (current.activated) {
      return current
    }
    const next = new CanvasDocumentState(
      current.title,
      current.content,
      Date.now(),
      updatedBy,
      current.revision,
      true
    )
    await this.persist(next, resolvedDocumentId)
    return next
  }

  async saveDocument(
    content: string,
    title: string = '',
    updatedBy: string = 'user',
    documentId: string = ''
  ): Promise<CanvasDocumentState> {
    const resolvedDocumentId = this.resolveDocumentId(documentId)
    const current = await this.loadDocument(resolvedDocumentId)
    const nextTitle = title.trim() !== '' ? title.trim() : current.title
    const next = new CanvasDocumentState(
      nextTitle,
      content,
      Date.now(),
      updatedBy,
      current.revision + 1,
      current.activated || updatedBy === 'assistant' || content.trim() !== '' || nextTitle !== 'Canvas'
    )
    await this.persist(next, resolvedDocumentId)
    return next
  }

  async appendContent(
    content: string,
    updatedBy: string = 'assistant',
    documentId: string = ''
  ): Promise<CanvasDocumentState> {
    const resolvedDocumentId = this.resolveDocumentId(documentId)
    const current = await this.loadDocument(resolvedDocumentId)
    const separator = current.content.trim() === '' ? '' : '\n\n'
    return await this.saveDocument(`${current.content}${separator}${content}`, current.title, updatedBy,
      resolvedDocumentId)
  }

  async prependContent(
    content: string,
    updatedBy: string = 'assistant',
    documentId: string = ''
  ): Promise<CanvasDocumentState> {
    const resolvedDocumentId = this.resolveDocumentId(documentId)
    const current = await this.loadDocument(resolvedDocumentId)
    const separator = current.content.trim() === '' ? '' : '\n\n'
    return await this.saveDocument(`${content}${separator}${current.content}`, current.title, updatedBy,
      resolvedDocumentId)
  }

  async replaceFirst(
    target: string,
    replacement: string,
    updatedBy: string = 'assistant',
    documentId: string = ''
  ): Promise<CanvasDocumentMutationResult> {
    const resolvedDocumentId = this.resolveDocumentId(documentId)
    const current = await this.loadDocument(resolvedDocumentId)
    if (target === '') {
      return new CanvasDocumentMutationResult(false, 'target 不能为空', current)
    }
    const index = current.content.indexOf(target)
    if (index < 0) {
      return new CanvasDocumentMutationResult(false, '未找到 target，文档未修改', current)
    }
    const nextContent = current.content.substring(0, index) + replacement +
      current.content.substring(index + target.length)
    const next = await this.saveDocument(nextContent, current.title, updatedBy, resolvedDocumentId)
    return new CanvasDocumentMutationResult(true, '已替换首个匹配片段', next)
  }

  async clearDocument(updatedBy: string = 'assistant', documentId: string = ''): Promise<CanvasDocumentState> {
    const resolvedDocumentId = this.resolveDocumentId(documentId)
    const current = await this.loadDocument(resolvedDocumentId)
    return await this.saveDocument('', current.title, updatedBy, resolvedDocumentId)
  }

  private async persist(document: CanvasDocumentState, documentId: string): Promise<void> {
    this.cachedDocuments.set(documentId, this.cloneDocument(document))
    const serialized = JSON.stringify(document)
    const preferenceKey = this.getDocumentPreferenceKey(documentId)
    await this.preferencesService.setString(preferenceKey, serialized)
    const stored = await this.preferencesService.getString(preferenceKey, '')
    if (stored !== serialized) {
      console.warn('CanvasDocumentService', 'Canvas document preference write did not verify; using in-memory cache')
    }
    setAppUiStateValue(AppStorageKeys.CANVAS_DOCUMENT_REFRESH_AT, Date.now())
  }

  private resolveDocumentId(documentId: string): string {
    const explicitId = documentId.trim()
    if (explicitId !== '') {
      return explicitId
    }
    const activeSessionId = getAppUiState().activeChatSessionId.trim()
    return activeSessionId !== '' ? activeSessionId : '__unbound__'
  }

  private getDocumentPreferenceKey(documentId: string): string {
    return `${PreferenceKeys.CANVAS_DOCUMENT_JSON}_${this.normalizeKeySuffix(documentId)}`
  }

  private normalizeKeySuffix(value: string): string {
    return value.replace(/[^a-zA-Z0-9_-]/g, '_')
  }

  private cloneDocument(document: CanvasDocumentState): CanvasDocumentState {
    return new CanvasDocumentState(
      document.title,
      document.content,
      document.updatedAt,
      document.updatedBy,
      document.revision,
      document.activated
    )
  }

  private resolveString(value: string | undefined, fallback: string = ''): string {
    if (value === undefined || value === null) {
      return fallback
    }
    return `${value}`
  }

  private resolveNumber(value: number | undefined, fallback: number = 0): number {
    if (value === undefined || value === null || !Number.isFinite(value)) {
      return fallback
    }
    return value
  }

  private resolveBoolean(value: boolean | undefined, fallback: boolean = false): boolean {
    if (value === undefined || value === null) {
      return fallback
    }
    return value
  }
}

export function getCanvasDocumentService(): CanvasDocumentService {
  return CanvasDocumentService.getInstance()
}
