import { getDatabaseService, DatabaseService } from '../services/DatabaseService'
import {
  getAIApiService,
  AIApiService,
  AIApiConfig,
  RequestMessage,
  AIApiResult,
  ToolCallDelta
} from '../services/AIApiService'
import { getAppStateManager, AppStateManager } from './AppStateManager'
import { getAITaskService, AITaskService } from '../services/AITaskService'
import { getAttachmentStorageService, AttachmentStorageService } from '../services/AttachmentStorageService'
import { getToolExecutionService, ToolExecutionService } from '../services/ToolExecutionService'
import {
  getSubAgentService,
  SubAgentRuntimeConfig,
  SUB_AGENT_SOURCE_LABEL_PREFIX,
  SUB_AGENT_TOOL_ID
} from '../services/SubAgentService'
import { getProviderViewModel, ProviderViewModel } from './ProviderViewModel'
import { getAssistantService, AssistantService, AssistantRuntimeConfig } from '../services/AssistantService'
import { getSkillService, SkillConfig } from '../services/SkillService'
import { ChatMessage, ChatSession, MessageRole, ProviderType, ApiStyle, MessageAttachment, AttachmentType, ReasoningLevel, ToolDefinition, ToolCall, ToolResult, SearchReference, ModelParameters } from '../models/ChatModels'
import { WebSearchResult, SearchResult, getWebSearchService } from '../services/WebSearchService'
import { http } from '@kit.NetworkKit'
import { HttpRequestController } from '../services/HttpService'
import { getEffectiveApiKey } from '../config/PresetProviders'
import { getPreferencesService } from '../services/PreferencesService'
import { PreferenceKeys } from '../services/PreferencesService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { setAppUiStateValue } from '../state/AppUiState'
import { ChatSessionStore } from './ChatSessionStore'
import {
  computeActivePath,
  buildLegacyChain,
  getSiblings,
  resolveLeafOfSubtree,
  collectSubtreeIds,
  getVersionInfo,
  MessageVersionInfo,
  shouldBuildLegacyChain
} from '../pages/chat/ChatMessageTreeHelper'
import { createThrottle, ThrottleUtil } from '../utils/ThrottleUtil'
import {
  buildCurrentTimeContext,
  renderSystemPromptTemplate,
  SystemPromptTemplateDefaults
} from '../utils/SystemPromptTemplateUtils'
import {
  cleanSearchQuery as cleanSearchQueryShared,
  normalizeOptimizedSearchQuery,
  normalizeRelativeTimeForSearchQuery as normalizeRelativeTimeForSearchQueryShared
} from '../utils/SearchQueryUtils'
import {
  KNOWLEDGE_SEARCH_MAX_CALLS_PER_USER_TURN,
  KNOWLEDGE_SEARCH_TOOL_ID
} from '../config/KnowledgeSearchTool'

// 标题生成状态
export interface TitleGenerationCallbacks {
  onTitleUpdated?: (title: string) => void
  onTitleGenerating?: (isGenerating: boolean) => void
  onTitleFailed?: () => void
}

// 工具调用回调
export interface ToolCallCallbacks {
  onToolCallStarted?: (toolCalls: ToolCall[]) => void
  onToolCallCompleted?: (results: ToolResult[]) => void
  onSearching?: (query: string) => void
}

// web_search 工具参数接口
interface WebSearchArgs {
  query?: string
  q?: string
  keywords?: string
  url?: string
  page?: number | string
}

// 搜索结果数据接口
interface SearchResultItem {
  title: string
  url: string
  snippet: string
}

interface SearchResultData {
  query: string
  searchEngine: string
  results: SearchResultItem[]
  summary: string
}

interface KnowledgeToolResultHitData {
  documentId?: string
  chunkId?: string
  title?: string
  locator?: string
  score?: number
}

interface KnowledgeToolResultData {
  status?: string
  code?: string
  error?: string
  message?: string
  query?: string
  topK?: number
  truncated?: boolean
  queryTruncated?: boolean
  retrievalMode?: string
  fallbackReason?: string
  knowledgeQueryCount?: number
  remainingKnowledgeQueries?: number
  maxKnowledgeQueries?: number
  continuationGuidance?: string
  hits?: KnowledgeToolResultHitData[]
}

class PersistedKnowledgeToolHit {
  documentId: string = ''
  chunkId: string = ''
  title: string = ''
  locator: string = ''
  score: number = 0

  constructor(source: KnowledgeToolResultHitData) {
    this.documentId = source.documentId === undefined ? '' : source.documentId
    this.chunkId = source.chunkId === undefined ? '' : source.chunkId
    this.title = source.title === undefined ? '' : source.title
    this.locator = source.locator === undefined ? '' : source.locator
    this.score = source.score === undefined ? 0 : source.score
  }
}

class PersistedKnowledgeToolResult {
  status: string = ''
  code: string = ''
  error: string = ''
  message: string = ''
  query: string = ''
  topK: number = 0
  hitCount: number = 0
  truncated: boolean = false
  queryTruncated: boolean = false
  retrievalMode: string = ''
  fallbackReason: string = ''
  knowledgeQueryCount: number = 0
  remainingKnowledgeQueries: number = 0
  maxKnowledgeQueries: number = 0
  continuationGuidance: string = ''
  hits: PersistedKnowledgeToolHit[] = []
}

interface AskUserApprovalAnswer {
  answer?: string
  selected_options?: string[]
  skipped?: boolean
}

interface AskUserApprovalPayload {
  answers?: Record<string, AskUserApprovalAnswer>
}

// 待持久化 AI 消息信息（每请求独立）
interface PendingAIMessageInfo {
  message: ChatMessage
  sessionId: string
  persisted: boolean
}

// 重新生成分叉上下文：本次发送不创建新的用户消息，
// 直接把新的 AI 消息挂到 aiParentId 指向的已存在用户消息下（作为其新版本）。
export interface SendForkContext {
  aiParentId: string
}

// 本次发送的父子关系解析结果
interface SendParentage {
  forkContext: SendForkContext | null
  userParentId: string
}

// 活跃请求信息（每请求独立，用于 stopGeneration 时取消）
interface ActiveRequestInfo {
  httpRequest: http.HttpRequest
  cancelCallback: () => void
}

interface ImageDownloadResult {
  base64Data: string
  mimeType: string
}

// 聊天状态管理
export class ChatViewModel {
  private databaseService: DatabaseService
  private aiApiService: AIApiService
  private appStateManager: AppStateManager
  private aiTaskService: AITaskService
  private attachmentStorageService: AttachmentStorageService
  private toolExecutionService: ToolExecutionService
  private providerViewModel: ProviderViewModel
  private assistantService: AssistantService
  private sessionStore: ChatSessionStore

  // 当前会话
  private currentSession: ChatSession | null = null
  // 下一次发送的分叉上下文（由 regenerate 设置，发送时消费一次后清空）
  private pendingForkContext: SendForkContext | null = null
  // 活跃请求 Map（key = requestId，支持多个并发请求）
  private activeRequests: Map<string, ActiveRequestInfo> = new Map()
  // 待持久化 AI 消息 Map（key = messageId，支持多个并发请求）
  private pendingAIMessages: Map<string, PendingAIMessageInfo> = new Map()
  // 标题生成回调
  private titleCallbacks: TitleGenerationCallbacks | null = null
  // 最大重试次数
  private readonly MAX_TITLE_RETRY = 3
  private readonly DEFAULT_WEB_SEARCH_LIMIT = 5
  private readonly EXTRA_WEB_SEARCH_LIMIT = 5
  // 取消令牌：用于停止”尚未开始发送的请求”（例如退出页面时）
  private cancelToken: number = 0
  // 历史附件懒加载配置
  private readonly MAX_HISTORY_ATTACHMENTS = 5
  private readonly MAX_HISTORY_ATTACHMENT_SIZE = 5 * 1024 * 1024 // 5MB

  constructor() {
    this.databaseService = getDatabaseService()
    this.aiApiService = getAIApiService()
    this.appStateManager = getAppStateManager()
    this.aiTaskService = getAITaskService()
    this.attachmentStorageService = getAttachmentStorageService()
    this.toolExecutionService = getToolExecutionService()
    this.providerViewModel = getProviderViewModel()
    this.assistantService = getAssistantService()
    this.sessionStore = new ChatSessionStore(
      this.databaseService,
      this.appStateManager,
      () => this.generateId(),
      () => this.notifySessionListChanged()
    )
  }

	  private async getRenderedSystemPrompt(): Promise<string> {
	    const prefsService = getPreferencesService()
	    const enabled = await prefsService.getBoolean(PreferenceKeys.SYSTEM_PROMPT_ENABLED, true)
    if (!enabled) {
      return ''
    }
    const template = await prefsService.getString(
      PreferenceKeys.CUSTOM_SYSTEM_PROMPT,
      SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
	    )
	    return renderSystemPromptTemplate(template)
	  }

  private getCurrentAssistantIdForRequest(): string {
    const session = this.sessionStore.getCurrentSession()
    if (session !== null && session.assistantId !== '') {
      return session.assistantId
    }
    return 'default'
  }

  private getOpenAITransportForProvider(providerId: string): string | undefined {
    const provider = this.providerViewModel.getProviderById(providerId)
    if (provider === null) {
      return undefined
    }
    return provider.openaiTransport
  }

	  private async getAssistantRuntimeConfig(): Promise<AssistantRuntimeConfig> {
	    return await this.assistantService.getRuntimeConfig(this.getCurrentAssistantIdForRequest())
	  }

	  private async buildRequestSystemPrompt(extraPrompt: string = ''): Promise<string> {
	    const globalPrompt = await this.getRenderedSystemPrompt()
	    const assistantConfig = await this.getAssistantRuntimeConfig()
	    const basePrompt = this.assistantService.combineSystemPrompts(globalPrompt, assistantConfig.systemPrompt)
	    return this.assistantService.combineSystemPrompts(basePrompt, extraPrompt)
	  }

	  private async getRequestTemperature(): Promise<number> {
	    const assistantConfig = await this.getAssistantRuntimeConfig()
	    if (assistantConfig.temperatureEnabled) {
	      return assistantConfig.temperature
	    }
	    return this.appStateManager.getDefaultTemperature()
	  }

  private notifySessionListChanged(): void {
    setAppUiStateValue(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
  }

  private cloneAttachments(attachments: MessageAttachment[]): MessageAttachment[] {
    const cloned: MessageAttachment[] = []
    for (let i = 0; i < attachments.length; i++) {
      const attachment = new MessageAttachment(
        attachments[i].id,
        attachments[i].type,
        attachments[i].name,
        attachments[i].filePath,
        attachments[i].mimeType,
        attachments[i].size
      )
      attachment.base64Data = attachments[i].base64Data
      cloned.push(attachment)
    }
    return cloned
  }

  cloneAttachmentsForNewMessage(attachments: MessageAttachment[]): MessageAttachment[] {
    const cloned: MessageAttachment[] = []
    for (let i = 0; i < attachments.length; i++) {
      const attachment = new MessageAttachment(
        this.generateId(),
        attachments[i].type,
        attachments[i].name,
        attachments[i].filePath,
        attachments[i].mimeType,
        attachments[i].size
      )
      attachment.base64Data = attachments[i].base64Data
      cloned.push(attachment)
    }
    return cloned
  }

  private async ensureAttachmentBase64Data(attachment: MessageAttachment): Promise<boolean> {
    if (attachment.base64Data !== '') {
      return true
    }
    if (attachment.filePath === '') {
      console.warn('ChatViewModel', `Attachment missing file path: ${attachment.id}`)
      return false
    }
    try {
      const base64Data = await this.attachmentStorageService.readAsBase64(attachment.filePath)
      if (base64Data === '') {
        console.warn('ChatViewModel', `Attachment base64 empty after read: ${attachment.id}`)
        return false
      }
      attachment.base64Data = base64Data
      console.info('ChatViewModel', `Prepared attachment for request: ${attachment.id}`)
      return true
    } catch (error) {
      console.error('ChatViewModel', `Failed to prepare attachment ${attachment.id}: ${JSON.stringify(error)}`)
      return false
    }
  }

  private async prepareOutgoingAttachments(attachments: MessageAttachment[]): Promise<MessageAttachment[]> {
    const clonedAttachments = this.cloneAttachments(attachments)
    for (let i = 0; i < clonedAttachments.length; i++) {
      await this.ensureAttachmentBase64Data(clonedAttachments[i])
    }
    return clonedAttachments
  }

  private filterNativeUnsupportedAttachments(
    attachments: MessageAttachment[],
    modelSupportsDocuments: boolean,
    modelSupportsVision: boolean
  ): MessageAttachment[] {
    const filtered: MessageAttachment[] = []
    for (let i = 0; i < attachments.length; i++) {
      const attachment = attachments[i]
      if (!modelSupportsDocuments && this.isPdfAttachment(attachment)) {
        continue
      }
      if (!modelSupportsVision && this.isImageAttachment(attachment)) {
        continue
      }
      filtered.push(attachment)
    }
    return filtered
  }

  private filterNativeUnsupportedAttachmentsInMessages(
    messages: RequestMessage[],
    modelSupportsDocuments: boolean,
    modelSupportsVision: boolean
  ): void {
    for (let i = 0; i < messages.length; i++) {
      if (messages[i].attachments.length === 0) {
        continue
      }
      messages[i].attachments = this.filterNativeUnsupportedAttachments(
        messages[i].attachments,
        modelSupportsDocuments,
        modelSupportsVision
      )
    }
  }

  private isPdfAttachment(attachment: MessageAttachment): boolean {
    const mimeType = attachment.mimeType.toLowerCase()
    const name = attachment.name.toLowerCase()
    return mimeType === 'application/pdf' || name.endsWith('.pdf')
  }

  private isImageAttachment(attachment: MessageAttachment): boolean {
    const mimeType = attachment.mimeType.toLowerCase()
    const name = attachment.name.toLowerCase()
    return attachment.type === AttachmentType.IMAGE || mimeType.startsWith('image/') ||
      name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') ||
      name.endsWith('.webp') || name.endsWith('.bmp') || name.endsWith('.gif')
  }

  private buildDraftTitle(content: string): string {
    const normalized = content.replace(/\s+/g, ' ').trim()
    if (normalized.length === 0) {
      return '新对话'
    }
    if (normalized.length <= 20) {
      return normalized
    }
    return normalized.substring(0, 20) + '...'
  }

  private buildDraftPreview(content: string, attachments: MessageAttachment[]): string {
    const normalized = content.replace(/\s+/g, ' ').trim()
    if (normalized !== '') {
      if (normalized.length <= 48) {
        return normalized
      }
      return normalized.substring(0, 48) + '...'
    }
    if (attachments.length === 0) {
      return ''
    }
    return attachments[0].name !== '' ? attachments[0].name : ''
  }

  private isFirstRoundSession(session: ChatSession | null): boolean {
    return session !== null && session.messages.length === 0
  }

  private appendMessageToSessionIfMissing(session: ChatSession | null, message: ChatMessage): void {
    if (session === null) {
      return
    }
    for (let i = 0; i < session.messages.length; i++) {
      if (session.messages[i].id === message.id) {
        return
      }
    }
    session.messages.push(message)
    if (session.messageCount < session.messages.length) {
      session.messageCount = session.messages.length
      return
    }
    session.messageCount = session.messageCount + 1
  }

  // 设置下一次发送的分叉上下文（由重新生成调用，发送时消费一次）
  setPendingForkContext(context: SendForkContext | null): void {
    this.pendingForkContext = context
  }

  // 消费分叉上下文并解析本次发送的父子关系。
  // messages 是 UI 传入的当前活跃路径，末条消息即新用户消息的父节点。
  private resolveSendParentage(messages: ChatMessage[]): SendParentage {
    const forkContext = this.pendingForkContext
    this.pendingForkContext = null
    let userParentId = ''
    if (messages.length > 0) {
      userParentId = messages[messages.length - 1].id
    }
    return { forkContext, userParentId }
  }

  // 构建本次请求的历史来源。
  // 分叉模式（重新生成）下，messages 是当前活跃路径，需截断到被复用用户消息(aiParentId)之前，
  // 因为该用户消息的内容会作为本轮 user 消息单独发送，避免历史中重复出现。
  private buildForkAwareHistorySource(messages: ChatMessage[], forkContext: SendForkContext | null): ChatMessage[] {
    if (forkContext === null) {
      return messages
    }
    for (let i = 0; i < messages.length; i++) {
      if (messages[i].id === forkContext.aiParentId) {
        return messages.slice(0, i)
      }
    }
    return messages
  }

  // AI 消息持久化后，推进会话活跃叶子指针
  private async advanceActiveLeaf(session: ChatSession | null, sessionId: string, leafId: string): Promise<void> {
    if (session !== null) {
      session.activeLeafId = leafId
    }
    if (sessionId !== '' && leafId !== '') {
      await this.databaseService.updateSessionActiveLeaf(sessionId, leafId)
    }
  }

  private mergePendingAIMessagesIntoMessages(sessionId: string, messages: ChatMessage[]): ChatMessage[] {
    this.pendingAIMessages.forEach((info: PendingAIMessageInfo) => {
      if (info.sessionId !== sessionId) {
        return
      }
      let exists = false
      for (let i = 0; i < messages.length; i++) {
        if (messages[i].id === info.message.id) {
          exists = true
          break
        }
      }
      if (!exists) {
        messages.push(info.message)
      }
    })
    return messages
  }

  private finalizeLoadedSession(sessionId: string, session: ChatSession | null): ChatSession | null {
    if (session === null) {
      return null
    }
    session.messages = this.mergePendingAIMessagesIntoMessages(sessionId, session.messages)
    if (session.messageCount < session.messages.length) {
      session.messageCount = session.messages.length
    }
    // 旧数据惰性建链：仅未初始化 activeLeafId 的会话按时间串成单链并回写
    this.migrateLegacyChainIfNeeded(session)
    this.currentSession = session
    this.sessionStore.setCurrentSession(session)
    return session
  }

  // 旧数据迁移：
  // - activeLeafId 为空：旧会话还没有对话树结构。
  // 多个根消息可能是编辑首条消息产生的合法版本，不能据此判定为断链。
  // 按 timestamp 升序把全部消息串成单链，并把 parentId / activeLeafId 回写数据库。
  private migrateLegacyChainIfNeeded(session: ChatSession): void {
    if (!shouldBuildLegacyChain(session.messages, session.activeLeafId)) {
      return
    }
    const result = buildLegacyChain(session.messages)
    const fixById = new Map<string, string>()
    for (let i = 0; i < result.fixes.length; i++) {
      fixById.set(result.fixes[i].messageId, result.fixes[i].parentId)
    }
    // 内存即时生效
    for (let i = 0; i < session.messages.length; i++) {
      const newParent = fixById.get(session.messages[i].id)
      if (newParent !== undefined) {
        session.messages[i].parentId = newParent
      }
    }
    session.activeLeafId = result.leafId
    // 异步回写，不阻塞首屏
    const sessionId = session.id
    const fixes = result.fixes
    const leafId = result.leafId
    ;(async () => {
      try {
        for (let i = 0; i < fixes.length; i++) {
          await this.databaseService.updateMessageParentId(fixes[i].messageId, fixes[i].parentId)
        }
        await this.databaseService.updateSessionActiveLeaf(sessionId, leafId)
      } catch (e) {
        console.error('ChatViewModel', `Failed to migrate legacy chain: ${JSON.stringify(e)}`)
      }
    })()
  }

  // 计算当前会话的活跃展示路径（从 activeLeafId 回溯）
  getActivePath(): ChatMessage[] {
    if (this.currentSession === null) {
      return []
    }
    return computeActivePath(this.currentSession.messages, this.currentSession.activeLeafId)
  }

  // 计算指定会话的活跃展示路径
  getActivePathForSession(session: ChatSession): ChatMessage[] {
    return computeActivePath(session.messages, session.activeLeafId)
  }

  private isCancelled(snapshot: number): boolean {
    return snapshot !== this.cancelToken
  }

  private addPendingAIMessage(message: ChatMessage, sessionId: string): void {
    this.pendingAIMessages.set(message.id, {
      message: message,
      sessionId: sessionId,
      persisted: false
    } as PendingAIMessageInfo)
  }

  private clearPendingAIMessageIfMatches(messageId: string): void {
    this.pendingAIMessages.delete(messageId)
  }

  private markPendingAIMessagePersisted(messageId: string): void {
    const info = this.pendingAIMessages.get(messageId)
    if (info !== undefined) {
      info.persisted = true
    }
  }

  // 当 AI 消息内容完全为空时，填充一条兜底提示，避免出现空气泡
  private fillEmptyAIContentPlaceholder(aiMessage: ChatMessage, errorHint: string = ''): void {
    if (aiMessage.content.trim() !== '') {
      return
    }
    if (aiMessage.reasoningContent.trim() !== '') {
      return
    }
    if (aiMessage.attachments.length > 0) {
      return
    }
    if (aiMessage.toolCalls.length > 0 || aiMessage.toolResults.length > 0) {
      return
    }
    if (errorHint !== '') {
      aiMessage.content = errorHint
    } else {
      aiMessage.content = '[模型未返回内容]'
    }
  }

  private buildConversationRequestHistory(messages: ChatMessage[], contextStartIndex: number): RequestMessage[] {
    const historyMessages: RequestMessage[] = []
    for (let i = contextStartIndex; i < messages.length; i++) {
      const msg = messages[i]
      if (msg.role === MessageRole.SYSTEM) {
        continue
      }
      const requestMessage = new RequestMessage(msg.role, msg.content, this.cloneAttachments(msg.attachments))
      requestMessage.reasoningContent = msg.reasoningContent
      historyMessages.push(requestMessage)
    }
    return historyMessages
  }

  // 判断待持久化消息是否包含有效内容（空占位消息不应跨会话残留）
  private hasMeaningfulPendingMessageContent(message: ChatMessage): boolean {
    if (message.content.trim() !== '') {
      return true
    }
    if (message.reasoningContent.trim() !== '') {
      return true
    }
    if (message.attachments.length > 0) {
      return true
    }
    if (message.searchReferences.length > 0) {
      return true
    }
    if (message.toolCalls.length > 0) {
      return true
    }
    if (message.toolResults.length > 0) {
      return true
    }
    return false
  }

  // 丢弃指定待持久化 AI 消息（用于 stop 后清理空占位）
  discardPendingAIMessage(messageId: string): void {
    this.clearPendingAIMessageIfMatches(messageId)
  }

  private persistPendingAIMessageIfNeeded(): void {
    const entries: PendingAIMessageInfo[] = []
    const discardMessageIds: string[] = []
    this.pendingAIMessages.forEach((info: PendingAIMessageInfo) => {
      if (info.persisted || info.sessionId === '') {
        return
      }
      if (!this.hasMeaningfulPendingMessageContent(info.message)) {
        discardMessageIds.push(info.message.id)
        return
      }
      // stop 后持久化的消息应结束生成/搜索状态
      info.message.isGenerating = false
      info.message.isSearching = false
      entries.push(info)
    })

    for (let i = 0; i < discardMessageIds.length; i++) {
      this.clearPendingAIMessageIfMatches(discardMessageIds[i])
      console.info('ChatViewModel', `Discard empty pending AI message on stop: ${discardMessageIds[i]}`)
    }

    for (let i = 0; i < entries.length; i++) {
      const info = entries[i]
      // 避免重复插入
      info.persisted = true

      const msgToSave = info.message
      const sessionId = info.sessionId
      const messageId = msgToSave.id
      ;(async () => {
        try {
          await this.databaseService.addMessage(sessionId, msgToSave)
          // 中断保存的 AI 消息同样推进活跃叶子，保证退出后回来展示这条分支
          await this.databaseService.updateSessionActiveLeaf(sessionId, messageId)
          if (this.currentSession !== null && this.currentSession.id === sessionId) {
            this.currentSession.activeLeafId = messageId
          }
          this.clearPendingAIMessageIfMatches(messageId)
          console.info('ChatViewModel', `Pending AI message persisted on stop: ${messageId}`)
        } catch (e) {
          console.error('ChatViewModel', `Failed to persist pending AI message: ${JSON.stringify(e)}`)
          // 失败时允许后续再尝试
          const failedInfo = this.pendingAIMessages.get(messageId)
          if (failedInfo !== undefined) {
            failedInfo.persisted = false
          }
        }
      })()
    }
  }

  private registerActiveRequest(requestId: string, httpRequest: http.HttpRequest, cancelCallback: () => void): void {
    this.activeRequests.set(requestId, {
      httpRequest: httpRequest,
      cancelCallback: cancelCallback
    } as ActiveRequestInfo)
  }

  private unregisterActiveRequest(requestId: string): void {
    this.activeRequests.delete(requestId)
  }

  private async prepareProviderDocumentsForRequest(
    apiConfig: AIApiConfig,
    requestMessages: RequestMessage[],
    cancelSnapshot: number
  ): Promise<void> {
    const controller = new HttpRequestController()
    const requestId = `document_prepare_${this.generateId()}`
    const placeholderHttp = http.createHttp()
    this.registerActiveRequest(requestId, placeholderHttp, (): void => {
      controller.cancelAll()
    })

    try {
      await this.aiApiService.prepareProviderDocumentMessages(apiConfig, requestMessages, controller)
    } catch (error) {
      if (this.isCancelled(cancelSnapshot) || controller.isCancelled()) {
        console.info('ChatViewModel', 'Provider document preparation cancelled')
        return
      }
      if (error instanceof Error) {
        throw error
      }
      throw new Error(JSON.stringify(error))
    } finally {
      this.unregisterActiveRequest(requestId)
      try {
        placeholderHttp.destroy()
      } catch (_error) {}
    }
  }

  // 创建新会话
	  async createNewSession(
	    title: string = '',
	    assistantId: string = 'default',
	    modelIdSeed: string = '',
	    providerIdSeed: string = ''
	  ): Promise<ChatSession> {
	    const session = await this.sessionStore.createNewSession(title, assistantId, modelIdSeed, providerIdSeed)
	    this.currentSession = this.sessionStore.getCurrentSession()
	    return session
	  }

	  // 创建待持久化的会话（仅内存中，不保存到数据库）
	  createPendingSession(
	    title: string = '',
	    assistantId: string = 'default',
	    modelIdSeed: string = '',
	    providerIdSeed: string = ''
	  ): ChatSession {
	    const session = this.sessionStore.createPendingSession(title, assistantId, modelIdSeed, providerIdSeed)
	    this.currentSession = this.sessionStore.getCurrentSession()
	    return session
	  }

  // 持久化待处理的会话
  private async persistPendingSession(): Promise<void> {
    await this.sessionStore.persistPendingSession()
    this.currentSession = this.sessionStore.getCurrentSession()
  }

  async saveSessionDraft(content: string, attachments: MessageAttachment[]): Promise<ChatSession | null> {
    const hasDraftContent = content.trim() !== '' || attachments.length > 0
	    if (this.currentSession === null) {
	      if (!hasDraftContent) {
	        return null
	      }
	      const assistant = await this.assistantService.getCurrentAssistantForNewChat()
	      this.createPendingSession('', assistant.id, assistant.defaultModelId, assistant.defaultProviderId)
	    }
    if (hasDraftContent && this.sessionStore.isCurrentSessionPending()) {
      await this.persistPendingSession()
    }

    this.currentSession = this.sessionStore.getCurrentSession()
    if (this.currentSession === null) {
      return null
    }

    this.currentSession.draftText = content
    this.currentSession.draftAttachments = this.cloneAttachments(attachments)
    if (this.currentSession.messages.length === 0) {
      this.currentSession.title = this.buildDraftTitle(content)
      this.currentSession.lastMessagePreview = this.buildDraftPreview(content, attachments)
      this.currentSession.updatedAt = Date.now()
    }

    if (this.sessionStore.isCurrentSessionPending()) {
      return this.currentSession
    }

    await this.databaseService.updateSessionDraft(this.currentSession.id, content, attachments)
    return this.currentSession
  }

  // 加载会话
  async loadSession(sessionId: string): Promise<ChatSession | null> {
    return this.finalizeLoadedSession(sessionId, await this.sessionStore.loadSession(sessionId))
  }

  // 获取所有会话
  async getAllSessions(): Promise<ChatSession[]> {
    return await this.sessionStore.getAllSessions()
  }

  // 删除会话
  async deleteSession(sessionId: string): Promise<void> {
    await this.sessionStore.deleteSession(sessionId)
    this.currentSession = this.sessionStore.getCurrentSession()
  }

  // 获取当前会话
  getCurrentSession(): ChatSession | null {
    this.currentSession = this.sessionStore.getCurrentSession()
    return this.currentSession
  }

  async toggleSessionFavorite(sessionId: string): Promise<boolean> {
    const isFavorite = await this.sessionStore.toggleSessionFavorite(sessionId)
    this.currentSession = this.sessionStore.getCurrentSession()
    return isFavorite
  }

  async updateCurrentSessionModelSelection(modelId: string, providerId: string): Promise<boolean> {
    const updated = await this.sessionStore.updateCurrentSessionModelSelection(modelId, providerId)
    this.currentSession = this.sessionStore.getCurrentSession()
    return updated
  }

  // 发送消息并获取 AI 回复
  async sendMessage(
    content: string,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    attachments: MessageAttachment[] = [],
    contextStartIndex: number = 0,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    modelSupportsDocuments: boolean = true,
    modelSupportsVision: boolean = true,
    requestContent: string = '',
    userDocumentToolHint: string = '',
    apiPath?: string,  // 可选的自定义 API 路径
    customHeadersJson?: string
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    this.toolExecutionService.resetWebSearchQueryState()
    getWebSearchService().resetSearchResultDedup()
    // 首次发送消息时，先持久化待处理的会话
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 如果仍然没有当前会话，创建新的
	    if (this.currentSession === null) {
	      const assistant = await this.assistantService.getCurrentAssistantForNewChat()
	      await this.createNewSession('', assistant.id, assistant.defaultModelId, assistant.defaultProviderId)
	    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession，避免并发请求时会话被覆盖
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)
    // 解析对话树父子关系（分叉模式下不创建新用户消息）
    const parentage = this.resolveSendParentage(messages)
    // 分叉模式下 messages 末条是被重发的用户消息，构建历史时需排除它（其内容作为本轮 user 消息）
    const historySource = this.buildForkAwareHistorySource(messages, parentage.forkContext)
    const historyMessages = this.buildConversationRequestHistory(historySource, contextStartIndex)
    const requestAttachments = await this.prepareOutgoingAttachments(attachments)
    const effectiveRequestContent = requestContent !== '' ? requestContent : content
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 创建用户消息（分叉模式下复用已存在的用户消息，不新建）
    let userMessage: ChatMessage | null = null
    if (parentage.forkContext === null) {
      userMessage = new ChatMessage(
        this.generateId(),
        MessageRole.USER,
        content,
        ''
      )
      userMessage.parentId = parentage.userParentId
      // 添加附件到用户消息
      if (attachments.length > 0) {
        for (let i = 0; i < attachments.length; i++) {
          userMessage.attachments.push(attachments[i])
        }
      }
      userMessage.documentToolHint = userDocumentToolHint
      if (userDocumentToolHint !== '') {
        userMessage.searchSource = 'document_tool_hint'
        userMessage.searchQuery = userDocumentToolHint
      }
      // 通知 UI 添加用户消息（优先渲染，避免”返回再进来只剩用户消息/无模型信息”）
      onUserMessageAdded(userMessage)
    }

    // 提前创建 AI 消息占位符：如果用户在模型响应前退出页面，stopGeneration 仍能持久化该消息
    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.parentId = parentage.forkContext !== null ? parentage.forkContext.aiParentId : (userMessage !== null ? userMessage.id : '')
    aiMessage.isGenerating = true
    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    // 保存用户消息到数据库
    if (snapshotSession !== null && userMessage !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
      // 先把活跃叶子推进到新用户消息，保证中途中断也展示新分支
      await this.advanceActiveLeaf(snapshotSession, snapshotSessionId, userMessage.id)
      if (shouldAutoGenerateTitle) {
        const title = content.length > 20 ? content.substring(0, 20) + '...' : content
        snapshotSession.title = title
        await this.databaseService.updateSessionTitle(snapshotSessionId, title)
        this.notifySessionListChanged()
      }
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    // 构建请求消息列表（从上下文起始位置开始，过滤掉上下文清空标记）
	    const requestMessages: RequestMessage[] = []
	    const renderedSystemPrompt = await this.buildRequestSystemPrompt()
	    if (renderedSystemPrompt !== '') {
	      requestMessages.push(new RequestMessage('system', renderedSystemPrompt))
	    }
    for (let i = 0; i < historyMessages.length; i++) {
      requestMessages.push(historyMessages[i])
    }
    requestMessages.push(new RequestMessage('user', effectiveRequestContent, requestAttachments))

    // 懒加载历史附件
    await this.prepareHistoryAttachments(requestMessages)
    if (!modelSupportsDocuments || !modelSupportsVision) {
      this.filterNativeUnsupportedAttachmentsInMessages(requestMessages, modelSupportsDocuments, modelSupportsVision)
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建 API 配置
    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: getEffectiveApiKey(providerId, apiKey),
      baseUrl: baseUrl,
      apiPath: apiPath,
      openaiTransport: this.getOpenAITransportForProvider(providerId),
      customHeadersJson: customHeadersJson
    }

    const modelParams = this.getCurrentModelParameters(providerId, modelId)
    if (modelParams !== null) {
      apiConfig.topP = modelParams.topP
      apiConfig.presencePenalty = modelParams.presencePenalty
      apiConfig.frequencyPenalty = modelParams.frequencyPenalty
    }
    apiConfig.modelReasoningStrategyOverride = this.getCurrentModelReasoningStrategyOverride(providerId, modelId)
    apiConfig.modelSupportsReasoning = this.getCurrentModelSupportsReasoning(providerId, modelId)
    await this.prepareProviderDocumentsForRequest(apiConfig, requestMessages, cancelSnapshot)

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let hasReceivedFirstChunk = false
    const localFirstChunkThrottle = createThrottle(50)
    const localContentThrottle = createThrottle(150)
    const localReasoningThrottle = createThrottle(150)
    const requestId = this.generateId()

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 发送流式请求
	    const requestTemperature = await this.getRequestTemperature()
	    const httpRequest = this.aiApiService.streamChatRequest(
      apiConfig,
      requestMessages,
      modelId,
      (contentChunk: string) => {
        if (cancelled) {
          return
        }
        if (!hasReceivedFirstChunk) {
          localFirstChunkThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
            hasReceivedFirstChunk = true
          })
        } else {
          localContentThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          })
        }
      },
      async () => {
        if (cancelled) {
          return
        }
        // 刷新节流器
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })

        this.fillEmptyAIContentPlaceholder(aiMessage)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        if (snapshotSession !== null) {
          await this.databaseService.addMessage(snapshotSessionId, aiMessage)
          this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
          await this.advanceActiveLeaf(snapshotSession, snapshotSessionId, aiMessage.id)
          this.markPendingAIMessagePersisted(aiMessage.id)
          this.clearPendingAIMessageIfMatches(aiMessage.id)

          if (shouldAutoGenerateTitle) {
            this.generateSmartTitle(snapshotSession)
          }
        }
        this.unregisterActiveRequest(requestId)
        onComplete()
      },
      (error: string) => {
        if (cancelled) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        this.fillEmptyAIContentPlaceholder(aiMessage, error)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        if (userCancelled) {
          console.info('ChatViewModel', 'Request cancelled by user')
          onComplete()
        } else {
          onError(error)
        }
        this.clearPendingAIMessageIfMatches(aiMessage.id)
        this.unregisterActiveRequest(requestId)
      },
	      requestTemperature,
      this.appStateManager.getDefaultMaxTokens(),
      (reasoningContent: string) => {
        if (cancelled) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (cancelled) {
            return
          }
          aiMessage.reasoningContent += throttledContent
          onAIMessageUpdated(aiMessage)
        })
      },
      async (base64Data: string, mimeType: string) => {
        if (cancelled) {
          return
        }
        try {
          await this.saveAIGeneratedImage(base64Data, mimeType, aiMessage, onAIMessageUpdated)
        } catch (error) {
          console.error('ChatViewModel', `Failed to save AI generated image: ${JSON.stringify(error)}`)
        }
      },
      reasoningLevel
    )

    // 注册到活跃请求 Map
    this.registerActiveRequest(requestId, httpRequest, () => {
      cancelled = true
      userCancelled = true
      localFirstChunkThrottle.reset()
      localContentThrottle.reset()
      localReasoningThrottle.reset()
    })
  }

  // 带网页上下文发送消息
  async sendMessageWithWebContext(
    content: string,
    webContext: WebSearchResult,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    attachments: MessageAttachment[],
    contextStartIndex: number,
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    apiPath?: string,
    customHeadersJson?: string
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    if (this.currentSession === null) {
	      const assistant = await this.assistantService.getCurrentAssistantForNewChat()
	      await this.createNewSession('', assistant.id, assistant.defaultModelId, assistant.defaultProviderId)
	    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)
    // 解析对话树父子关系（分叉模式下不创建新用户消息）
    const parentage = this.resolveSendParentage(messages)
    // 分叉模式下 messages 末条是被重发的用户消息，构建历史时需排除它
    const historySource = this.buildForkAwareHistorySource(messages, parentage.forkContext)
    const historyMessages = this.buildConversationRequestHistory(historySource, contextStartIndex)
    const requestAttachments = await this.prepareOutgoingAttachments(attachments)
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建系统提示（包含网页内容）
    const systemPrompt = `用户提供了以下网页内容供参考：

标题：${webContext.title}
来源：${webContext.url}
正文：
${webContext.content}

请基于以上网页内容回答用户的问题。如果网页内容不完整或无法回答，请告知用户。`

    // 创建用户消息（分叉模式下复用已存在的用户消息，不新建）
    let userMessage: ChatMessage | null = null
    if (parentage.forkContext === null) {
      userMessage = new ChatMessage(
        this.generateId(),
        MessageRole.USER,
        content,
        ''
      )
      userMessage.parentId = parentage.userParentId
      for (let i = 0; i < attachments.length; i++) {
        userMessage.attachments.push(attachments[i])
      }
      onUserMessageAdded(userMessage)
    }

    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.parentId = parentage.forkContext !== null ? parentage.forkContext.aiParentId : (userMessage !== null ? userMessage.id : '')
    aiMessage.isGenerating = true
    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    if (snapshotSession !== null && userMessage !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
      await this.advanceActiveLeaf(snapshotSession, snapshotSessionId, userMessage.id)
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    // 构建请求消息列表
	    const requestMessages: RequestMessage[] = []
	    const finalSystemPromptWeb = await this.buildRequestSystemPrompt(systemPrompt)
	    requestMessages.push(new RequestMessage('system', finalSystemPromptWeb))
    for (let i = 0; i < historyMessages.length; i++) {
      requestMessages.push(historyMessages[i])
    }
    requestMessages.push(new RequestMessage('user', content, requestAttachments))

    await this.prepareHistoryAttachments(requestMessages)
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: apiKey,
      baseUrl: baseUrl,
      apiPath: apiPath,
      openaiTransport: this.getOpenAITransportForProvider(providerId),
      customHeadersJson: customHeadersJson
    }
    apiConfig.modelReasoningStrategyOverride = this.getCurrentModelReasoningStrategyOverride(providerId, modelId)
    apiConfig.modelSupportsReasoning = this.getCurrentModelSupportsReasoning(providerId, modelId)
    await this.prepareProviderDocumentsForRequest(apiConfig, requestMessages, cancelSnapshot)

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let hasReceivedFirstChunk = false
    const localFirstChunkThrottle = createThrottle(50)
    const localContentThrottle = createThrottle(150)
    const localReasoningThrottle = createThrottle(150)
    const requestId = this.generateId()

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    const requestTemperature = await this.getRequestTemperature()
	    const httpRequest = this.aiApiService.streamChatRequest(
      apiConfig,
      requestMessages,
      modelId,
      (contentChunk: string) => {
        if (cancelled) {
          return
        }
        if (!hasReceivedFirstChunk) {
          localFirstChunkThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
            hasReceivedFirstChunk = true
          })
        } else {
          localContentThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          })
        }
      },
      async () => {
        if (cancelled) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        this.fillEmptyAIContentPlaceholder(aiMessage)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)
        if (snapshotSession !== null) {
          await this.databaseService.addMessage(snapshotSessionId, aiMessage)
          this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
          await this.advanceActiveLeaf(snapshotSession, snapshotSessionId, aiMessage.id)
          this.markPendingAIMessagePersisted(aiMessage.id)
          this.clearPendingAIMessageIfMatches(aiMessage.id)
          if (shouldAutoGenerateTitle) {
            this.generateSmartTitle(snapshotSession)
          }
        }
        this.unregisterActiveRequest(requestId)
        onComplete()
      },
      (error: string) => {
        if (cancelled) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        this.fillEmptyAIContentPlaceholder(aiMessage, error)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        if (userCancelled) {
          console.info('ChatViewModel', 'Request cancelled by user')
          onComplete()
        } else {
          onError(error)
        }
        this.clearPendingAIMessageIfMatches(aiMessage.id)
        this.unregisterActiveRequest(requestId)
      },
	      requestTemperature,
      this.appStateManager.getDefaultMaxTokens(),
      (reasoningContent: string) => {
        if (cancelled) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (cancelled) {
            return
          }
          aiMessage.reasoningContent += throttledContent
          onAIMessageUpdated(aiMessage)
        })
      },
      async (base64Data: string, mimeType: string) => {
        if (cancelled) {
          return
        }
        try {
          await this.saveAIGeneratedImage(base64Data, mimeType, aiMessage, onAIMessageUpdated)
        } catch (error) {
          console.error('ChatViewModel', `Failed to save AI generated image: ${JSON.stringify(error)}`)
        }
      }
    )

    // 注册到活跃请求 Map
    this.registerActiveRequest(requestId, httpRequest, () => {
      cancelled = true
      userCancelled = true
      localFirstChunkThrottle.reset()
      localContentThrottle.reset()
      localReasoningThrottle.reset()
    })
  }

  // 带搜索结果上下文发送消息（新版）
  async sendMessageWithSearchResult(
    content: string,
    searchResult: SearchResult,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    attachments: MessageAttachment[],
    contextStartIndex: number,
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    apiPath?: string,
    customHeadersJson?: string
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    if (this.currentSession === null) {
	      const assistant = await this.assistantService.getCurrentAssistantForNewChat()
	      await this.createNewSession('', assistant.id, assistant.defaultModelId, assistant.defaultProviderId)
	    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)
    // 解析对话树父子关系（分叉模式下不创建新用户消息）
    const parentage = this.resolveSendParentage(messages)
    // 分叉模式下 messages 末条是被重发的用户消息，构建历史时需排除它
    const historySource = this.buildForkAwareHistorySource(messages, parentage.forkContext)
    const historyMessages = this.buildConversationRequestHistory(historySource, contextStartIndex)
    const requestAttachments = await this.prepareOutgoingAttachments(attachments)
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建系统提示（包含搜索内容和当前时间）
    const currentTime = this.getCurrentTimeContext()
    const limitedSearchContext = this.limitSearchContextForPrompt(searchResult.contentForAI, 5000)
    const systemPrompt = `当前时间: ${currentTime}

用户进行了联网搜索,以下是搜索结果供参考:

${limitedSearchContext}

回答规则(非常重要):
1. 如果搜索结果/抓取正文中已经包含回答所需的信息(例如天气的温度/风力/AQI等具体数值),请直接整理并回答,不要再让用户去别的网站查询。
2. 只有当搜索结果中确实缺少关键数据时,才说明"未找到"并建议进一步查询。
3. 如果用户询问"今天"、"现在"等相对时间,请使用上述当前时间作为参考。
4. 若回答中需要写出"今天是X年X月X日",必须与"当前时间"保持一致,不得改成其他日期。
5. 如果搜索上下文显示 URL 读取失败或网页正文为空,请明确说明未读取到页面正文和错误原因。`

    console.info('ChatViewModel', `[搜索上下文] 当前时间: ${currentTime}`)
    console.info('ChatViewModel', `[搜索上下文] 搜索查询: ${searchResult.query}`)
    console.info('ChatViewModel', `[搜索上下文] 系统提示长度: ${systemPrompt.length} 字符`)
    console.info('ChatViewModel', `[搜索上下文] 预览: ${systemPrompt.substring(0, 240)}...`)

    // 创建用户消息（分叉模式下复用已存在的用户消息，不新建）
    let userMessage: ChatMessage | null = null
    if (parentage.forkContext === null) {
      userMessage = new ChatMessage(
        this.generateId(),
        MessageRole.USER,
        content,
        ''
      )
      userMessage.parentId = parentage.userParentId
      for (let i = 0; i < attachments.length; i++) {
        userMessage.attachments.push(attachments[i])
      }
      // 添加搜索引用数据和查询内容
      userMessage.searchQuery = searchResult.query
      userMessage.searchEngine = searchResult.searchEngine || 'Web'
      userMessage.searchSource = 'manual'
      userMessage.isSearching = false  // 搜索已完成
      for (let i = 0; i < searchResult.references.length; i++) {
        userMessage.searchReferences.push(searchResult.references[i])
      }
      onUserMessageAdded(userMessage)
    }

    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.parentId = parentage.forkContext !== null ? parentage.forkContext.aiParentId : (userMessage !== null ? userMessage.id : '')
    aiMessage.isGenerating = true

    // 将搜索引用数据复制到 AI 消息，确保 SearchReferenceCard 可以正确显示
    aiMessage.searchQuery = searchResult.query
    aiMessage.searchEngine = searchResult.searchEngine || 'Web'
    aiMessage.searchSource = 'manual'
    for (let i = 0; i < searchResult.references.length; i++) {
      aiMessage.searchReferences.push(searchResult.references[i])
    }

    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    if (snapshotSession !== null && userMessage !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
      await this.advanceActiveLeaf(snapshotSession, snapshotSessionId, userMessage.id)
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    // 构建请求消息列表
	    const requestMessages: RequestMessage[] = []
	    const finalSystemPromptSearch = await this.buildRequestSystemPrompt(systemPrompt)
	    requestMessages.push(new RequestMessage('system', finalSystemPromptSearch))
    for (let i = 0; i < historyMessages.length; i++) {
      requestMessages.push(historyMessages[i])
    }
    requestMessages.push(new RequestMessage('user',
      this.buildSearchResultRequestContent(content, searchResult),
      requestAttachments))

    await this.prepareHistoryAttachments(requestMessages)
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: apiKey,
      baseUrl: baseUrl,
      apiPath: apiPath,
      openaiTransport: this.getOpenAITransportForProvider(providerId),
      customHeadersJson: customHeadersJson
    }
    apiConfig.modelReasoningStrategyOverride = this.getCurrentModelReasoningStrategyOverride(providerId, modelId)
    apiConfig.modelSupportsReasoning = this.getCurrentModelSupportsReasoning(providerId, modelId)
    await this.prepareProviderDocumentsForRequest(apiConfig, requestMessages, cancelSnapshot)

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let hasReceivedFirstChunk = false
    const localFirstChunkThrottle = createThrottle(50)
    const localContentThrottle = createThrottle(150)
    const localReasoningThrottle = createThrottle(150)
    const requestId = this.generateId()

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    const requestTemperature = await this.getRequestTemperature()
	    const httpRequest = this.aiApiService.streamChatRequest(
      apiConfig,
      requestMessages,
      modelId,
      (contentChunk: string) => {
        if (cancelled) {
          return
        }
        if (!hasReceivedFirstChunk) {
          localFirstChunkThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
            hasReceivedFirstChunk = true
          })
        } else {
          localContentThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (cancelled) {
              return
            }
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          })
        }
      },
      async () => {
        if (cancelled) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        this.fillEmptyAIContentPlaceholder(aiMessage)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)
        if (snapshotSession !== null) {
          await this.databaseService.addMessage(snapshotSessionId, aiMessage)
          this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
          await this.advanceActiveLeaf(snapshotSession, snapshotSessionId, aiMessage.id)
          this.markPendingAIMessagePersisted(aiMessage.id)
          this.clearPendingAIMessageIfMatches(aiMessage.id)
          if (shouldAutoGenerateTitle) {
            this.generateSmartTitle(snapshotSession)
          }
        }
        this.unregisterActiveRequest(requestId)
        onComplete()
      },
      (error: string) => {
        if (cancelled) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (cancelled) {
            return
          }
          if (throttledReasoning !== '') {
            aiMessage.reasoningContent += throttledReasoning
            onAIMessageUpdated(aiMessage)
          }
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (cancelled) {
            return
          }
          if (throttledContent !== '') {
            aiMessage.content += throttledContent
            onAIMessageUpdated(aiMessage)
          }
        })
        this.fillEmptyAIContentPlaceholder(aiMessage, error)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        if (userCancelled) {
          console.info('ChatViewModel', 'Request cancelled by user')
          onComplete()
        } else {
          onError(error)
        }
        this.clearPendingAIMessageIfMatches(aiMessage.id)
        this.unregisterActiveRequest(requestId)
      },
	      requestTemperature,
      this.appStateManager.getDefaultMaxTokens(),
      (reasoningContent: string) => {
        if (cancelled) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (cancelled) {
            return
          }
          aiMessage.reasoningContent += throttledContent
          onAIMessageUpdated(aiMessage)
        })
      },
      async (base64Data: string, mimeType: string) => {
        if (cancelled) {
          return
        }
        try {
          await this.saveAIGeneratedImage(base64Data, mimeType, aiMessage, onAIMessageUpdated)
        } catch (error) {
          console.error('ChatViewModel', `Failed to save AI generated image: ${JSON.stringify(error)}`)
        }
      },
      reasoningLevel
    )

    // 注册到活跃请求 Map
    this.registerActiveRequest(requestId, httpRequest, () => {
      cancelled = true
      userCancelled = true
      localFirstChunkThrottle.reset()
      localContentThrottle.reset()
      localReasoningThrottle.reset()
    })
  }

  // 发送消息并使用 Function Calling 工具
  async sendMessageWithTools(
    content: string,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    attachments: MessageAttachment[] = [],
    contextStartIndex: number = 0,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    tools: ToolDefinition[] = [],
    toolCallbacks?: ToolCallCallbacks,
    modelSupportsDocuments: boolean = true,
    modelSupportsVision: boolean = true,
    requestContent: string = '',
    userDocumentToolHint: string = '',
    apiPath?: string,
    customHeadersJson?: string
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    // 首次发送消息时，先持久化待处理的会话
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 如果仍然没有当前会话，创建新的
	    if (this.currentSession === null) {
	      const assistant = await this.assistantService.getCurrentAssistantForNewChat()
	      await this.createNewSession('', assistant.id, assistant.defaultModelId, assistant.defaultProviderId)
	    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)
    // 解析对话树父子关系（分叉模式下不创建新用户消息）
    const parentage = this.resolveSendParentage(messages)
    // 分叉模式下 messages 末条是被重发的用户消息，构建历史时需排除它（其内容作为本轮 user 消息）
    const historySource = this.buildForkAwareHistorySource(messages, parentage.forkContext)
    const historyMessages = this.buildConversationRequestHistory(historySource, contextStartIndex)
    const requestAttachments = await this.prepareOutgoingAttachments(attachments)
    const effectiveRequestContent = requestContent !== '' ? requestContent : content
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 创建用户消息（分叉模式下复用已存在的用户消息，不新建）
    let userMessage: ChatMessage | null = null
    if (parentage.forkContext === null) {
      userMessage = new ChatMessage(
        this.generateId(),
        MessageRole.USER,
        content,
        ''
      )
      userMessage.parentId = parentage.userParentId
      // 添加附件到用户消息
      if (attachments.length > 0) {
        for (let i = 0; i < attachments.length; i++) {
          userMessage.attachments.push(attachments[i])
        }
      }
      userMessage.documentToolHint = userDocumentToolHint
      if (userDocumentToolHint !== '') {
        userMessage.searchSource = 'document_tool_hint'
        userMessage.searchQuery = userDocumentToolHint
      }
      // 通知 UI 添加用户消息（优先渲染）
      onUserMessageAdded(userMessage)
    }

    // 提前创建 AI 消息占位符，确保中途退出页面也能恢复模型信息/重新生成
    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.parentId = parentage.forkContext !== null ? parentage.forkContext.aiParentId : (userMessage !== null ? userMessage.id : '')
    aiMessage.isGenerating = true

    // 检测启用了哪些工具（用于构建 system prompt）
    let hasWebSearchTool = false
    let hasAskUserTool = false
    let hasSkillTool = false
    let hasSubAgentTool = false
    let hasKnowledgeSearchTool = false
    for (let i = 0; i < tools.length; i++) {
      if (tools[i].function.name === 'web_search') {
        hasWebSearchTool = true
      }
      if (tools[i].function.name === 'ask_user') {
        hasAskUserTool = true
      }
      if (tools[i].function.name === 'use_skill') {
        hasSkillTool = true
      }
      if (tools[i].function.name === SUB_AGENT_TOOL_ID) {
        hasSubAgentTool = true
      }
      if (tools[i].function.name === KNOWLEDGE_SEARCH_TOOL_ID) {
        hasKnowledgeSearchTool = true
      }
    }

    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    // 保存用户消息到数据库
    if (snapshotSession !== null && userMessage !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
      await this.advanceActiveLeaf(snapshotSession, snapshotSessionId, userMessage.id)
      if (shouldAutoGenerateTitle) {
        const title = content.length > 20 ? content.substring(0, 20) + '...' : content
        snapshotSession.title = title
        await this.databaseService.updateSessionTitle(snapshotSessionId, title)
        this.notifySessionListChanged()
      }
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建请求消息列表
    const requestMessages: RequestMessage[] = []
    const currentTime = this.getCurrentTimeContext()
    let toolUsageSystemPrompt = `当前时间: ${currentTime}

你是一个智能助手。你的首要任务是直接完成用户请求，只在确实需要访问外部信息或外部系统时才调用工具。

工具使用规则(非常重要):
- 绝大多数普通问答不需要调用工具，请优先用自身知识直接回答。
- 只有在用户请求明确依赖外部实时信息、外部文档、外部仓库、外部笔记或其他外部系统状态时才调用工具。
- 对外部系统有副作用的工具（例如创建、修改、删除、提交、上传）必须先确认用户意图与目标对象，不要擅自操作。
- 编程、写作、翻译、数学、创意等纯生成任务，若不依赖外部状态，绝对不要调用任何工具。`
    if (hasWebSearchTool) {
      toolUsageSystemPrompt += `
- 针对同一个用户问题，默认最多调用 web_search ${this.DEFAULT_WEB_SEARCH_LIMIT} 次。达到上限后，如果已有信息足够，请直接整理最终回答；不要把搜索摘要或工具结果原样返回给用户。
- 如果达到 ${this.DEFAULT_WEB_SEARCH_LIMIT} 次后仍确实需要继续搜索，并且 ask_user 可用，必须先调用 ask_user 询问用户是否允许额外最多 ${this.EXTRA_WEB_SEARCH_LIMIT} 次联网搜索；用户同意后才继续搜索。用户不同意、跳过或 ask_user 不可用时，必须基于已有信息直接回答并说明不确定性。
- 生成 web_search.query 时优先保留用户原始关键词，不要擅自改写实体、地点和时间。
- 如果需要继续搜索，必须主动更换搜索词角度，优先换关键词而不是只增加 page；不要连续提交完全相同或只差空格/标点的 query。
- 多次搜索同一问题时，每次 query 应尽量覆盖不同信息源或不同角度，例如: 精确短语、官方/作品页、歌词/资料站、作者/制作人、排除百科字典类结果、site: 限定站点。
- 当工具提示结果为空、重复或已无更多新结果时，下一次 web_search 必须换一组更具体的关键词，或加入 site:/-site:/引号短语等约束来寻找不同来源。
- 当用户输入只包含一个 URL，或明确要求读取、总结、分析某个网页时，必须调用 web_search。
- URL 读取场景下，web_search.query 必须原样传入该 URL，不要改写成标题、关键词或搜索语句。`
    }
    if (hasAskUserTool) {
      toolUsageSystemPrompt += `
- 当用户需求存在关键歧义，且自行假设会导致明显返工时，可以调用 ask_user 一次性向用户提出 1-3 个澄清问题。
- 不要为了无关紧要的偏好或可以合理默认的细节调用 ask_user；能继续完成时优先继续完成。`
    }
    if (hasSubAgentTool) {
      toolUsageSystemPrompt += `
- 当任务能拆成多个彼此独立、可并行的子任务（例如多主题调研、多来源对比、多份材料分别处理）时，可调用 sub_agent 一次性派出 1-3 个子智能体并行处理，再汇总它们的结果作答。
- 子智能体看不到本对话历史，每个任务的 prompt 必须自包含：写清目标、必要背景、约束和期望输出。
- 简单任务或强依赖前后顺序的任务不要使用 sub_agent，自己直接完成更快。`
    }
    if (hasKnowledgeSearchTool) {
      toolUsageSystemPrompt += `
- 以下知识库规则优先级高于前面的“普通问答不调用工具”和“纯生成任务不调用工具”规则。
- 用户已开启知识库。在本次回答的第一步，必须先调用 knowledge_search，根据用户当前问题生成独立、具体的 query。
- 首次 knowledge_search 返回之前，禁止直接回答用户，禁止以自然语言文本代替工具调用，也不要输出伪造的工具调用标记。
- 只能通过模型的正式 function call 调用 knowledge_search，arguments 必须是符合工具 schema 的有效 JSON。`
    }
    if (hasSkillTool) {
      const skillContext = await this.buildEnabledSkillSystemContext()
      if (skillContext !== '') {
        toolUsageSystemPrompt += skillContext
      }
    }
    toolUsageSystemPrompt += `
- 若用户提到“今天/昨天/明天/现在/最新”等相对时间，请以当前时间为基准理解，不要编造不一致的绝对日期。
- 工具返回后必须给出最终回答，不要在没有必要的情况下重复调用工具。`
    const finalToolUsageSystemPrompt = await this.buildRequestSystemPrompt(toolUsageSystemPrompt)
    requestMessages.push(new RequestMessage('system', finalToolUsageSystemPrompt))
    for (let i = 0; i < historyMessages.length; i++) {
      requestMessages.push(historyMessages[i])
    }
    requestMessages.push(new RequestMessage('user', effectiveRequestContent, requestAttachments))

    // 懒加载历史附件
    await this.prepareHistoryAttachments(requestMessages)
    if (!modelSupportsDocuments || !modelSupportsVision) {
      this.filterNativeUnsupportedAttachmentsInMessages(requestMessages, modelSupportsDocuments, modelSupportsVision)
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建 API 配置
    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: getEffectiveApiKey(providerId, apiKey),
      baseUrl: baseUrl,
      apiPath: apiPath,
      openaiTransport: this.getOpenAITransportForProvider(providerId),
      customHeadersJson: customHeadersJson
    }

    const modelParams = this.getCurrentModelParameters(providerId, modelId)
    if (modelParams !== null) {
      apiConfig.topP = modelParams.topP
      apiConfig.presencePenalty = modelParams.presencePenalty
      apiConfig.frequencyPenalty = modelParams.frequencyPenalty
    }
    apiConfig.modelReasoningStrategyOverride = this.getCurrentModelReasoningStrategyOverride(providerId, modelId)
    apiConfig.modelSupportsReasoning = this.getCurrentModelSupportsReasoning(providerId, modelId)
    await this.prepareProviderDocumentsForRequest(apiConfig, requestMessages, cancelSnapshot)

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let toolExecutionCancelled = false
    let hasReceivedFirstChunk = false
    const localFirstChunkThrottle = createThrottle(50)
    const localContentThrottle = createThrottle(150)
    const localReasoningThrottle = createThrottle(150)
    const requestId = this.generateId()

	    if (this.isCancelled(cancelSnapshot)) {
	      return
	    }
	    const requestTemperature = await this.getRequestTemperature()

	    // 先注册到活跃请求 Map（使用占位 httpRequest，executeToolCallLoop 内部会更新实际引用）
    // 必须在 await 之前注册，否则 stopGeneration 无法取消正在执行的请求
    const placeholderHttp = http.createHttp()
    this.registerActiveRequest(requestId, placeholderHttp, () => {
      cancelled = true
      userCancelled = true
      toolExecutionCancelled = true
      localFirstChunkThrottle.reset()
      localContentThrottle.reset()
      localReasoningThrottle.reset()
    })

    // 每个子智能体拥有独立的联网搜索/知识库预算记录，
    // 不与主对话或其他子智能体相互扣减。
    const subAgentBudgetMessages: Map<string, ChatMessage> = new Map()

    // 注入子智能体运行时：sub_agent 工具被调用时使用与本次请求相同的模型、参数与工具集
    getSubAgentService().configureRuntime(new SubAgentRuntimeConfig(
      apiConfig,
      modelId,
      requestTemperature,
      this.appStateManager.getDefaultMaxTokens(),
      reasoningLevel,
      tools,
      currentTime,
      async (
        toolCall: ToolCall,
        allowedFunctionNames: string[],
        budgetKey: string
      ): Promise<ToolResult> => {
        let budgetMessage = subAgentBudgetMessages.get(budgetKey)
        if (budgetMessage === undefined) {
          budgetMessage = new ChatMessage(
            `sub_agent_budget_${budgetKey}`,
            MessageRole.ASSISTANT,
            '',
            modelName,
            modelId
          )
          subAgentBudgetMessages.set(budgetKey, budgetMessage)
        }
        budgetMessage.toolCalls.push(toolCall)
        const subToolResults = await this.executeToolCallsWithSearchBudgets(
          [toolCall],
          budgetMessage,
          allowedFunctionNames,
          true
        )
        const subToolResult = subToolResults[0]
        // 先写入该子智能体的独立预算上下文，再释放工具互斥锁。
        budgetMessage.toolResults.push(subToolResult)
        // 主消息仍保留镜像结果，供实时预览、交互卡片和持久化使用。
        aiMessage.toolResults.push(subToolResult)
        onAIMessageUpdated(aiMessage)
        return subToolResult
      },
      // 镜像子智能体的工具调用到主对话消息：ask_user 结果栏、图表由此渲染并可交互，
      // 普通工具卡片会按“子智能体”来源标签在 MessageBubble 中隐藏（活动见实时预览面板）；
      // 配对与图表提取均按 toolCallId 关联
      (subToolCall: ToolCall): void => {
        aiMessage.toolCalls.push(subToolCall)
        onAIMessageUpdated(aiMessage)
      },
      (subToolCall: ToolCall, subToolResult: ToolResult): void => {
        if (snapshotSession !== null) {
          this.databaseService.saveToolEvent(
            snapshotSessionId,
            aiMessage.id,
            subToolCall.id,
            subToolCall.functionName,
            subToolCall.displayName,
            subToolCall.sourceLabel,
            subToolCall.sourceType,
            subToolCall.permissionLevel,
            subToolCall.arguments,
            this.buildPersistedToolResult(subToolCall.functionName, subToolResult.content),
            subToolResult.isError ? 'failed' : 'completed'
          ).catch((error: Object): void => {
            console.warn('ChatViewModel', `Failed to persist sub-agent tool event: ${JSON.stringify(error)}`)
          })
        }
      },
      () => toolExecutionCancelled
    ))

    // 开始工具调用循环
    await this.executeToolCallLoop(
      apiConfig,
      requestMessages,
      modelId,
      aiMessage,
      onAIMessageUpdated,
      onComplete,
      onError,
      tools,
	      toolCallbacks,
	      reasoningLevel,
	      requestTemperature,
	      0,  // 初始迭代次数
      snapshotSessionId,
      snapshotSession,
      shouldAutoGenerateTitle,
      requestId,
      () => cancelled,
      () => userCancelled,
      () => toolExecutionCancelled,
      (v: boolean) => { userCancelled = v },
      () => hasReceivedFirstChunk,
      (v: boolean) => { hasReceivedFirstChunk = v },
      localFirstChunkThrottle,
      localContentThrottle,
      localReasoningThrottle
    )
  }

  private async buildEnabledSkillSystemContext(): Promise<string> {
    try {
      const skills = await getSkillService().getEnabledSkills()
      if (skills.length === 0) {
        return ''
      }
      let result = `

已启用 Skill（非常重要）:
- use_skill 可读取用户在设置中维护的 Skill。若用户问题与某个 Skill 的名称、简介或正文预览相关，优先调用 use_skill 读取完整 SKILL.md 后再回答。
- 下面是当前已启用 Skill 的清单和正文预览，设置修改后会随请求实时更新。`
      const maxSkillCount = Math.min(skills.length, 8)
      for (let i = 0; i < maxSkillCount; i++) {
        result += this.buildSingleSkillSystemContext(skills[i])
      }
      if (skills.length > maxSkillCount) {
        result += `
- 其余 ${skills.length - maxSkillCount} 个 Skill 未在提示中展开；需要时先空参调用 use_skill 查看完整清单。`
      }
      return result
    } catch (error) {
      console.warn('ChatViewModel', `Failed to build skill context: ${JSON.stringify(error)}`)
      return ''
    }
  }

  private buildSingleSkillSystemContext(skill: SkillConfig): string {
    const maxPreviewChars = 1400
    const content = skill.content.trim()
    const preview = content.length > maxPreviewChars
      ? `${content.substring(0, maxPreviewChars)}...`
      : content
    return `
- ${skill.name} (${skill.id}/SKILL.md)
  简介: ${skill.description.trim() !== '' ? skill.description.trim() : '无'}
  正文预览:
${preview}`
  }

  private fillFallbackFromSearchSummaryIfNeeded(aiMessage: ChatMessage): void {
    if (aiMessage.content.trim() !== '' || aiMessage.toolResults.length === 0) {
      return
    }

    const entries: SearchResultItem[] = []
    const seenUrls: string[] = []
    for (let i = 0; i < aiMessage.toolResults.length; i++) {
      try {
        const data = JSON.parse(aiMessage.toolResults[i].content) as Record<string, Object>
        const results = data.results
        if (Array.isArray(results as Array<Object>)) {
          const resultItems = results as Array<SearchResultItem>
          for (let j = 0; j < resultItems.length; j++) {
            const item = resultItems[j]
            const url = `${item.url ?? ''}`.trim()
            if (url === '' || seenUrls.includes(url)) {
              continue
            }
            seenUrls.push(url)
            entries.push(item)
            if (entries.length >= 5) {
              break
            }
          }
        }
        if (entries.length >= 5) {
          break
        }
      } catch (_error) {
        // ignore
      }
    }

    if (entries.length > 0) {
      const lines: string[] = []
      for (let i = 0; i < entries.length; i++) {
        const item = entries[i]
        const title = `${item.title ?? ''}`.trim()
        const snippet = `${item.snippet ?? ''}`.trim()
        const url = `${item.url ?? ''}`.trim()
        const brief = snippet.length > 120 ? `${snippet.substring(0, 120).trimEnd()}...` : snippet
        lines.push(`${i + 1}. ${title !== '' ? title : '未命名来源'}${brief !== '' ? `：${brief}` : ''}${url !== '' ? `\n   ${url}` : ''}`)
      }
      aiMessage.content = `我查到了一些线索，但还不足以形成非常确定的结论。先把可用信息整理如下：\n\n${lines.join('\n\n')}\n\n基于这些结果，我建议换更具体的关键词或指定你想确认的点，我再继续缩小范围。`
      return
    }

    for (let i = aiMessage.toolResults.length - 1; i >= 0; i--) {
      try {
        const data = JSON.parse(aiMessage.toolResults[i].content) as Record<string, Object>
        const summary = `${data.summary ?? ''}`.trim()
        if (summary !== '') {
          let preview = summary.replace(/^以下是搜索结果[:：]?\s*/g, '').trim()
          if (preview.length > 900) {
            preview = `${preview.substring(0, 900).trimEnd()}...`
          }
          aiMessage.content = `我查到的信息还不够完整，暂时只能给出这份整理：\n\n${preview}\n\n如果你愿意，可以补充更具体的对象、时间或来源范围，我再继续查。`
          return
        }
      } catch (_error) {
        // ignore
      }
    }
  }

  private async finalizeAIMessage(
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    snapshotSessionId: string,
    snapshotSession: ChatSession | null,
    shouldAutoGenerateTitle: boolean,
    requestId: string
  ): Promise<void> {
    this.fillFallbackFromSearchSummaryIfNeeded(aiMessage)
    this.fillEmptyAIContentPlaceholder(aiMessage)
    aiMessage.isGenerating = false
    aiMessage.isSearching = false
    onAIMessageUpdated(aiMessage)

    if (snapshotSession !== null) {
      await this.databaseService.addMessage(snapshotSessionId, aiMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
      await this.advanceActiveLeaf(snapshotSession, snapshotSessionId, aiMessage.id)
      this.markPendingAIMessagePersisted(aiMessage.id)
      this.clearPendingAIMessageIfMatches(aiMessage.id)
      if (shouldAutoGenerateTitle) {
        this.generateSmartTitle(snapshotSession)
      }
    }
    this.unregisterActiveRequest(requestId)
    onComplete()
  }

  private async executeToolCallsWithSearchBudgets(
    toolCalls: ToolCall[],
    aiMessage: ChatMessage,
    allowedFunctionNames: string[],
    includeSubAgentCalls: boolean = false
  ): Promise<ToolResult[]> {
    const results: ToolResult[] = []
    let executedSearchesInBatch = 0
    let executedKnowledgeQueriesInBatch = 0
    for (let i = 0; i < toolCalls.length; i++) {
      const toolCall = toolCalls[i]
      if (this.isWebSearchFunction(toolCall.functionName)) {
        const usedSearchCount =
          this.countCompletedWebSearchCalls(aiMessage, includeSubAgentCalls) + executedSearchesInBatch
        const limit = this.getCurrentWebSearchLimit(aiMessage, includeSubAgentCalls)
        if (usedSearchCount >= limit) {
          results.push(this.buildWebSearchBudgetResult(
            toolCall,
            usedSearchCount,
            limit,
            aiMessage,
            includeSubAgentCalls
          ))
          continue
        }
        const result = await this.toolExecutionService.executeToolCall(toolCall, allowedFunctionNames)
        results.push(result)
        if (!this.isWebSearchBudgetResult(result)) {
          executedSearchesInBatch += 1
        }
        continue
      }
      if (this.isKnowledgeSearchFunction(toolCall.functionName)) {
        const usedKnowledgeQueryCount =
          this.countCompletedKnowledgeSearchCalls(aiMessage, includeSubAgentCalls) + executedKnowledgeQueriesInBatch
        if (usedKnowledgeQueryCount >= KNOWLEDGE_SEARCH_MAX_CALLS_PER_USER_TURN) {
          results.push(this.buildKnowledgeSearchBudgetResult(toolCall, usedKnowledgeQueryCount))
          continue
        }
        const result = await this.toolExecutionService.executeToolCall(toolCall, allowedFunctionNames)
        executedKnowledgeQueriesInBatch += 1
        this.decorateKnowledgeSearchResult(result, usedKnowledgeQueryCount + 1)
        results.push(result)
        continue
      }
      results.push(await this.toolExecutionService.executeToolCall(toolCall, allowedFunctionNames))
    }
    return results
  }

  private buildAllowedToolFunctionNames(tools: ToolDefinition[]): string[] {
    const functionNames: string[] = []
    for (let i = 0; i < tools.length; i++) {
      const functionName = tools[i].function.name.trim()
      if (functionName !== '' && !functionNames.includes(functionName)) {
        functionNames.push(functionName)
      }
    }
    return functionNames
  }

  private isKnowledgeSearchFunction(functionName: string): boolean {
    return functionName.trim() === KNOWLEDGE_SEARCH_TOOL_ID
  }

  private hasCanonicalKnowledgeSearchCall(toolCalls: ToolCall[]): boolean {
    for (let i = 0; i < toolCalls.length; i++) {
      if (this.isKnowledgeSearchFunction(toolCalls[i].functionName)) {
        return true
      }
    }
    return false
  }

  private hasKnowledgeSearchTool(tools: ToolDefinition[]): boolean {
    for (let i = 0; i < tools.length; i++) {
      if (this.isKnowledgeSearchFunction(tools[i].function.name)) {
        return true
      }
    }
    return false
  }

  private getOnlyKnowledgeSearchTools(tools: ToolDefinition[]): ToolDefinition[] {
    const knowledgeTools: ToolDefinition[] = []
    for (let i = 0; i < tools.length; i++) {
      if (this.isKnowledgeSearchFunction(tools[i].function.name)) {
        knowledgeTools.push(tools[i])
      }
    }
    return knowledgeTools
  }

  private getToolsWithoutKnowledgeSearch(tools: ToolDefinition[]): ToolDefinition[] {
    const remainingTools: ToolDefinition[] = []
    for (let i = 0; i < tools.length; i++) {
      if (!this.isKnowledgeSearchFunction(tools[i].function.name)) {
        remainingTools.push(tools[i])
      }
    }
    return remainingTools
  }

  /**
   * knowledge_search 的完整片段只用于当前工具续轮。
   * 持久化仅保留引用元数据，避免把私有知识正文复制进 chatbox.db。
   */
  private buildPersistedToolResult(functionName: string, resultContent: string): string {
    if (!this.isKnowledgeSearchFunction(functionName)) {
      return resultContent
    }

    const persisted = new PersistedKnowledgeToolResult()
    try {
      const source = JSON.parse(resultContent) as KnowledgeToolResultData
      persisted.status = source.status === undefined ? '' : source.status
      persisted.code = source.code === undefined ? '' : source.code
      persisted.error = source.error === undefined ? '' : source.error
      persisted.message = source.message === undefined ? '' : source.message
      persisted.query = source.query === undefined ? '' : source.query
      persisted.topK = source.topK === undefined ? 0 : source.topK
      persisted.truncated = source.truncated === true
      persisted.queryTruncated = source.queryTruncated === true
      persisted.retrievalMode = source.retrievalMode === undefined ? '' : source.retrievalMode
      persisted.fallbackReason = source.fallbackReason === undefined ? '' : source.fallbackReason
      persisted.knowledgeQueryCount =
        source.knowledgeQueryCount === undefined ? 0 : source.knowledgeQueryCount
      persisted.remainingKnowledgeQueries =
        source.remainingKnowledgeQueries === undefined ? 0 : source.remainingKnowledgeQueries
      persisted.maxKnowledgeQueries =
        source.maxKnowledgeQueries === undefined ? 0 : source.maxKnowledgeQueries
      persisted.continuationGuidance =
        source.continuationGuidance === undefined ? '' : source.continuationGuidance
      const hits = source.hits === undefined ? [] : source.hits
      persisted.hitCount = hits.length
      for (let i = 0; i < hits.length; i++) {
        persisted.hits.push(new PersistedKnowledgeToolHit(hits[i]))
      }
    } catch (_error) {
      persisted.status = 'redacted'
      persisted.code = 'KNOWLEDGE_RESULT_METADATA_ONLY'
      persisted.message = '知识库工具结果正文未持久化'
    }
    return JSON.stringify(persisted)
  }

  private countCompletedWebSearchCalls(
    aiMessage: ChatMessage,
    includeSubAgentCalls: boolean = false
  ): number {
    let count = 0
    for (let i = 0; i < aiMessage.toolCalls.length; i++) {
      const toolCall = aiMessage.toolCalls[i]
      if (!includeSubAgentCalls && toolCall.sourceLabel.startsWith(SUB_AGENT_SOURCE_LABEL_PREFIX)) {
        continue
      }
      if (!this.isWebSearchFunction(toolCall.functionName)) {
        continue
      }
      const result = this.findToolResult(aiMessage, toolCall.id)
      if (result !== null && !this.isWebSearchBudgetResult(result)) {
        count += 1
      }
    }
    return count
  }

  private countCompletedKnowledgeSearchCalls(
    aiMessage: ChatMessage,
    includeSubAgentCalls: boolean = false
  ): number {
    let count = 0
    for (let i = 0; i < aiMessage.toolCalls.length; i++) {
      const toolCall = aiMessage.toolCalls[i]
      if (!includeSubAgentCalls && toolCall.sourceLabel.startsWith(SUB_AGENT_SOURCE_LABEL_PREFIX)) {
        continue
      }
      if (!this.isKnowledgeSearchFunction(toolCall.functionName)) {
        continue
      }
      const result = this.findToolResult(aiMessage, toolCall.id)
      if (result !== null && !this.isKnowledgeSearchBudgetResult(result)) {
        count += 1
      }
    }
    return count
  }

  private decorateKnowledgeSearchResult(result: ToolResult, completedCount: number): void {
    try {
      const data = JSON.parse(result.content) as Record<string, Object>
      const remaining = Math.max(0, KNOWLEDGE_SEARCH_MAX_CALLS_PER_USER_TURN - completedCount)
      data['knowledgeQueryCount'] = completedCount
      data['remainingKnowledgeQueries'] = remaining
      data['maxKnowledgeQueries'] = KNOWLEDGE_SEARCH_MAX_CALLS_PER_USER_TURN
      if (remaining <= 0) {
        data['continuationGuidance'] =
          '知识库查询次数已达上限。停止调用 knowledge_search，基于已有证据直接回答；证据不足时明确说明。'
      } else if (data['truncated'] === true) {
        data['continuationGuidance'] =
          'truncated 仅表示本次返回受长度预算截断。若当前证据已足够，立即回答；仅在能指出明确缺口且下一条 query 能更聚焦地补齐时续查，禁止重复或仅同义改写。'
      } else {
        data['continuationGuidance'] =
          '若当前证据已完整命中，立即回答；仅在存在明确证据缺口时使用更聚焦且不重复的 query 续查。'
      }
      result.content = JSON.stringify(data)
    } catch (_error) {
      // knowledge_search 的标准结果始终为 JSON；异常结果仍计入查询上限。
    }
  }

  private buildKnowledgeSearchBudgetResult(toolCall: ToolCall, usedQueryCount: number): ToolResult {
    toolCall.toolId = KNOWLEDGE_SEARCH_TOOL_ID
    toolCall.displayName = '知识库检索'
    if (!toolCall.sourceLabel.startsWith(SUB_AGENT_SOURCE_LABEL_PREFIX)) {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = 'read'
    return new ToolResult(
      toolCall.id,
      JSON.stringify({
        status: 'error',
        error: 'knowledge_search_budget_exhausted',
        code: 'KNOWLEDGE_SEARCH_BUDGET_EXHAUSTED',
        knowledgeQueryCount: usedQueryCount,
        remainingKnowledgeQueries: 0,
        maxKnowledgeQueries: KNOWLEDGE_SEARCH_MAX_CALLS_PER_USER_TURN,
        message: '本次用户提问的知识库查询已达 5 次上限。不要继续调用 knowledge_search；请基于已有结果直接回答，证据不足时明确说明。',
        continuationGuidance: '停止查询并完成最终回答。'
      }),
      true,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  private getCurrentWebSearchLimit(
    aiMessage: ChatMessage,
    includeSubAgentCalls: boolean = false
  ): number {
    if (this.hasApprovedExtraWebSearch(aiMessage, includeSubAgentCalls)) {
      return this.DEFAULT_WEB_SEARCH_LIMIT + this.EXTRA_WEB_SEARCH_LIMIT
    }
    return this.DEFAULT_WEB_SEARCH_LIMIT
  }

  private buildWebSearchBudgetResult(
    toolCall: ToolCall,
    usedSearchCount: number,
    limit: number,
    aiMessage: ChatMessage,
    includeSubAgentCalls: boolean = false
  ): ToolResult {
    const extraApproved = this.hasApprovedExtraWebSearch(aiMessage, includeSubAgentCalls)
    toolCall.toolId = 'web_search'
    toolCall.displayName = '联网搜索'
    if (!toolCall.sourceLabel.startsWith(SUB_AGENT_SOURCE_LABEL_PREFIX)) {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = 'read'
    return new ToolResult(
      toolCall.id,
      JSON.stringify({
        error: 'web_search_budget_exhausted',
        code: 'WEB_SEARCH_BUDGET_EXHAUSTED',
        webSearchCount: usedSearchCount,
        limit: limit,
        defaultLimit: this.DEFAULT_WEB_SEARCH_LIMIT,
        extraLimit: this.EXTRA_WEB_SEARCH_LIMIT,
        canRequestMore: !extraApproved,
        message: extraApproved
          ? '额外联网搜索次数也已用完。请不要继续调用 web_search，必须根据已有搜索结果直接回答用户，并说明必要的不确定性。'
          : `默认联网搜索次数已用完。如确有必要继续搜索，请先调用 ask_user 询问用户是否允许额外最多 ${this.EXTRA_WEB_SEARCH_LIMIT} 次联网搜索；否则必须根据已有搜索结果直接回答用户。不要把搜索摘要或工具 JSON 原样返回。`,
        suggestedAskUserJson: `{"questions":[{"id":"allow_extra_web_search","question":"当前已完成 ${this.DEFAULT_WEB_SEARCH_LIMIT} 次联网搜索。是否允许我额外最多再搜索 ${this.EXTRA_WEB_SEARCH_LIMIT} 次来提高把握？","selection_type":"single","options":["同意追加搜索","不追加，直接回答"]}]}`
      }),
      true,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  private findToolResult(aiMessage: ChatMessage, toolCallId: string): ToolResult | null {
    for (let i = 0; i < aiMessage.toolResults.length; i++) {
      if (aiMessage.toolResults[i].toolCallId === toolCallId) {
        return aiMessage.toolResults[i]
      }
    }
    return null
  }

  private findToolCall(aiMessage: ChatMessage, toolCallId: string): ToolCall | null {
    for (let i = 0; i < aiMessage.toolCalls.length; i++) {
      if (aiMessage.toolCalls[i].id === toolCallId) {
        return aiMessage.toolCalls[i]
      }
    }
    return null
  }

  private isWebSearchBudgetResult(result: ToolResult): boolean {
    try {
      const data = JSON.parse(result.content) as Record<string, Object>
      return `${data.code ?? ''}` === 'WEB_SEARCH_BUDGET_EXHAUSTED' ||
        `${data.error ?? ''}` === 'web_search_budget_exhausted'
    } catch (_error) {
      return false
    }
  }

  private isKnowledgeSearchBudgetResult(result: ToolResult): boolean {
    try {
      const data = JSON.parse(result.content) as Record<string, Object>
      return `${data.code ?? ''}` === 'KNOWLEDGE_SEARCH_BUDGET_EXHAUSTED' ||
        `${data.error ?? ''}` === 'knowledge_search_budget_exhausted'
    } catch (_error) {
      return false
    }
  }

  private hasCancelledToolResult(results: ToolResult[]): boolean {
    for (let i = 0; i < results.length; i++) {
      try {
        const data = JSON.parse(results[i].content) as Record<string, Object>
        if (data.cancelled === true) {
          return true
        }
      } catch (_error) {}
    }
    return false
  }

  private hasApprovedExtraWebSearch(
    aiMessage: ChatMessage,
    includeSubAgentCalls: boolean = false
  ): boolean {
    for (let i = 0; i < aiMessage.toolResults.length; i++) {
      const result = aiMessage.toolResults[i]
      const toolCall = this.findToolCall(aiMessage, result.toolCallId)
      if (!includeSubAgentCalls && toolCall !== null &&
        toolCall.sourceLabel.startsWith(SUB_AGENT_SOURCE_LABEL_PREFIX)) {
        continue
      }
      if (this.isWebSearchBudgetResult(result)) {
        continue
      }
      if (this.isExtraSearchApprovalResult(result.content)) {
        return true
      }
    }
    return false
  }

  private isExtraSearchApprovalResult(content: string): boolean {
    try {
      const payload = JSON.parse(content) as AskUserApprovalPayload
      if (payload.answers === undefined) {
        return false
      }
      const answer = payload.answers['allow_extra_web_search']
      if (answer === undefined || answer.skipped === true) {
        return false
      }
      const textParts: string[] = []
      if (answer.answer !== undefined) {
        textParts.push(answer.answer)
      }
      if (answer.selected_options !== undefined) {
        for (let i = 0; i < answer.selected_options.length; i++) {
          textParts.push(answer.selected_options[i])
        }
      }
      return this.isExtraSearchApprovalText(textParts.join(' '))
    } catch (_error) {
      return this.isExtraSearchApprovalText(content)
    }
  }

  private isExtraSearchApprovalText(text: string): boolean {
    const normalized = text.toLowerCase().trim()
    if (normalized === '') {
      return false
    }
    const rejectWords: string[] = ['不追加', '直接回答', '不同意', '拒绝', 'no', 'skip', '跳过']
    for (let i = 0; i < rejectWords.length; i++) {
      if (normalized.includes(rejectWords[i])) {
        return false
      }
    }
    const approveWords: string[] = ['同意', '允许', '可以', '继续', '追加搜索', 'approve', 'yes', 'allow']
    for (let i = 0; i < approveWords.length; i++) {
      if (normalized.includes(approveWords[i])) {
        return true
      }
    }
    return false
  }

  // 工具调用循环
  private async executeToolCallLoop(
    apiConfig: AIApiConfig,
    requestMessages: RequestMessage[],
    modelId: string,
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
	    tools: ToolDefinition[],
	    toolCallbacks: ToolCallCallbacks | undefined,
	    reasoningLevel: ReasoningLevel,
	    requestTemperature: number,
	    iteration: number,
    snapshotSessionId: string,
    snapshotSession: ChatSession | null,
    shouldAutoGenerateTitle: boolean,
    requestId: string,
    isCancelledFn: () => boolean,
    isUserCancelledFn: () => boolean,
    isToolCancelledFn: () => boolean,
    setUserCancelled: (v: boolean) => void,
    getHasReceivedFirstChunk: () => boolean,
    setHasReceivedFirstChunk: (v: boolean) => void,
    localFirstChunkThrottle: ThrottleUtil,
    localContentThrottle: ThrottleUtil,
    localReasoningThrottle: ThrottleUtil
  ): Promise<void> {
    if (isCancelledFn()) {
      return
    }

    const completedKnowledgeQueryCount = this.countCompletedKnowledgeSearchCalls(aiMessage)
    const requestHasKnowledgeSearch = this.hasKnowledgeSearchTool(tools)
    const forceKnowledgeSearchInThisRound =
      requestHasKnowledgeSearch && completedKnowledgeQueryCount === 0
    // DashScope 等 OpenAI 兼容接口在 Thinking 模式下拒绝 required tool_choice。
    // 首轮只负责让模型生成知识库 query，因此临时关闭该轮 Thinking；拿到 tool result
    // 后的续轮会恢复用户原本选择的推理级别。
    const reasoningLevelForThisRound =
      forceKnowledgeSearchInThisRound ? ReasoningLevel.OFF : reasoningLevel
    let toolsForThisRound: ToolDefinition[] = []
    let toolChoiceForThisRound = 'none'
    if (forceKnowledgeSearchInThisRound) {
      toolsForThisRound = this.getOnlyKnowledgeSearchTools(tools)
      toolChoiceForThisRound = 'required'
    } else if (requestHasKnowledgeSearch &&
      completedKnowledgeQueryCount >= KNOWLEDGE_SEARCH_MAX_CALLS_PER_USER_TURN) {
      toolsForThisRound = this.getToolsWithoutKnowledgeSearch(tools)
      toolChoiceForThisRound = toolsForThisRound.length > 0 ? 'auto' : 'none'
    } else {
      toolsForThisRound = tools
      toolChoiceForThisRound = toolsForThisRound.length > 0 ? 'auto' : 'none'
    }
    const toolsEnabledInThisRound = toolsForThisRound.length > 0
    const requestMessagesForRound = forceKnowledgeSearchInThisRound && iteration > 0
      ? requestMessages.concat([new RequestMessage(
        'system',
        '重试指令：上一次输出没有包含必需的 knowledge_search function call。' +
          '这一轮不要输出任何最终回答或解释；必须立即调用当前唯一提供的 knowledge_search，' +
          '并传入符合 schema 的 JSON arguments。'
      )])
      : requestMessages

    console.info('ChatViewModel', `Tool call loop iteration ${iteration + 1}`)
    let roundContentBuffer = ''
    let roundReasoningBuffer = ''
    let toolContinuationReasoningContent = ''
    let roundHasToolCallDelta = false
    let streamedContentLength = 0
    let streamedReasoningLength = 0

    const rollbackStreamedRoundOutput = (): void => {
      if (streamedContentLength > 0 && aiMessage.content.length >= streamedContentLength) {
        aiMessage.content = aiMessage.content.substring(0, aiMessage.content.length - streamedContentLength)
        streamedContentLength = 0
      }
      if (streamedReasoningLength > 0 && aiMessage.reasoningContent.length >= streamedReasoningLength) {
        aiMessage.reasoningContent = aiMessage.reasoningContent.substring(
          0,
          aiMessage.reasoningContent.length - streamedReasoningLength
        )
        streamedReasoningLength = 0
      }
    }

    const markCurrentRoundAsToolCall = (): void => {
      if (roundHasToolCallDelta) {
        return
      }
      roundHasToolCallDelta = true
      if (streamedReasoningLength > 0 && aiMessage.reasoningContent.length >= streamedReasoningLength) {
        toolContinuationReasoningContent = aiMessage.reasoningContent.substring(
          aiMessage.reasoningContent.length - streamedReasoningLength
        )
      }
      rollbackStreamedRoundOutput()
      onAIMessageUpdated(aiMessage)
    }

    const appendRoundContent = (content: string): void => {
      if (content === '') {
        return
      }
      if (roundHasToolCallDelta) {
        roundContentBuffer += content
        return
      }
      aiMessage.content += content
      streamedContentLength += content.length
      onAIMessageUpdated(aiMessage)
    }

    const appendRoundReasoning = (content: string): void => {
      if (content === '') {
        return
      }
      if (roundHasToolCallDelta) {
        roundReasoningBuffer += content
        return
      }
      aiMessage.reasoningContent += content
      streamedReasoningLength += content.length
      onAIMessageUpdated(aiMessage)
    }

    const flushBufferedRoundOutput = (): void => {
      if (roundContentBuffer !== '') {
        aiMessage.content += roundContentBuffer
        roundContentBuffer = ''
      }
      if (roundReasoningBuffer !== '') {
        aiMessage.reasoningContent += roundReasoningBuffer
        roundReasoningBuffer = ''
      }
    }

    // 检查是否已取消
    if (isToolCancelledFn()) {
      console.info('ChatViewModel', 'Tool execution cancelled by user')
      aiMessage.isGenerating = false
      onAIMessageUpdated(aiMessage)
      onComplete()
      return
    }

    // 设置取消检查回调
    this.toolExecutionService.setCancelCheckCallback(isToolCancelledFn)

    // 发送流式请求（带工具）
    const httpRequest = this.aiApiService.streamChatRequestWithTools(
      apiConfig,
      requestMessagesForRound,
      modelId,
      (contentChunk: string) => {
        if (isCancelledFn()) {
          return
        }
        if (!getHasReceivedFirstChunk()) {
          localFirstChunkThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (isCancelledFn()) {
              return
            }
            appendRoundContent(throttledContent)
            setHasReceivedFirstChunk(true)
          })
        } else {
          localContentThrottle.throttle(contentChunk, (throttledContent: string) => {
            if (isCancelledFn()) {
              return
            }
            appendRoundContent(throttledContent)
          })
        }
      },
      async (toolCalls: ToolCall[]) => {
        if (isCancelledFn()) {
          return
        }
        // 刷新节流器
        localContentThrottle.flush((throttledContent: string) => {
          if (isCancelledFn()) {
            return
          }
          appendRoundContent(throttledContent)
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (isCancelledFn()) {
            return
          }
          appendRoundReasoning(throttledReasoning)
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (isCancelledFn()) {
            return
          }
          appendRoundContent(throttledContent)
        })
        setHasReceivedFirstChunk(false)

        if (forceKnowledgeSearchInThisRound && !this.hasCanonicalKnowledgeSearchCall(toolCalls)) {
          rollbackStreamedRoundOutput()
          roundContentBuffer = ''
          roundReasoningBuffer = ''
          if (iteration === 0) {
            console.warn('ChatViewModel', 'Required knowledge_search was not called; retrying once with explicit instruction')
            aiMessage.content = ''
            aiMessage.reasoningContent = ''
            onAIMessageUpdated(aiMessage)
            await this.executeToolCallLoop(
              apiConfig,
              requestMessages,
              modelId,
              aiMessage,
              onAIMessageUpdated,
              onComplete,
              onError,
	            tools,
	            toolCallbacks,
	            reasoningLevel,
	            requestTemperature,
	            iteration + 1,
              snapshotSessionId,
              snapshotSession,
              shouldAutoGenerateTitle,
              requestId,
              isCancelledFn,
              isUserCancelledFn,
              isToolCancelledFn,
              setUserCancelled,
              getHasReceivedFirstChunk,
              setHasReceivedFirstChunk,
              localFirstChunkThrottle,
              localContentThrottle,
              localReasoningThrottle
            )
            return
          }
          const requiredToolError =
            '当前模型未按要求调用知识库。请重试，或切换到完整支持 OpenAI 工具调用的模型。'
          aiMessage.content = requiredToolError
          aiMessage.isGenerating = false
          aiMessage.isSearching = false
          onAIMessageUpdated(aiMessage)
          this.clearPendingAIMessageIfMatches(aiMessage.id)
          this.unregisterActiveRequest(requestId)
          this.toolExecutionService.clearCancelCheckCallback()
          onError(requiredToolError)
          return
        }

        // 检查是否有工具调用
        if (toolCalls.length > 0 && toolsEnabledInThisRound) {
          console.info('ChatViewModel', `[Function Calling] Received ${toolCalls.length} tool calls`)
          const latestUserQuery = this.getLatestUserQueryFromRequestMessages(requestMessages)
          markCurrentRoundAsToolCall()

          // tools 回合的正文是中间态，不应展示成一条正式回答。
          roundContentBuffer = ''
          roundReasoningBuffer = ''

          // 保存工具调用到 AI 消息
          for (let i = 0; i < toolCalls.length; i++) {
            if (this.isWebSearchFunction(toolCalls[i].functionName)) {
              const normalizedSearchQuery = this.normalizeWebSearchToolCallQuery(toolCalls[i], latestUserQuery)
              if (normalizedSearchQuery !== '') {
                console.info('ChatViewModel', `[Function Calling] normalized web_search query="${normalizedSearchQuery}"`)
              }
            }
            aiMessage.toolCalls.push(toolCalls[i])
          }
          onAIMessageUpdated(aiMessage)

          // 通知工具调用开始
          if (toolCallbacks !== undefined && toolCallbacks.onToolCallStarted !== undefined) {
            toolCallbacks.onToolCallStarted(toolCalls)
          }

          // 检查是否是搜索工具，更新搜索状态
          for (let i = 0; i < toolCalls.length; i++) {
            if (this.isWebSearchFunction(toolCalls[i].functionName)) {
              aiMessage.searchSource = 'tool'
              aiMessage.isSearching = true
              try {
                const args = JSON.parse(toolCalls[i].arguments) as WebSearchArgs
                const displayQuery = this.resolveWebSearchArgsQuery(args)
                aiMessage.searchQuery = displayQuery
                console.info('ChatViewModel', `[Function Calling] web_search(query="${displayQuery}")`)
                if (toolCallbacks !== undefined && toolCallbacks.onSearching !== undefined) {
                  toolCallbacks.onSearching(displayQuery)
                }
              } catch (e) {
                console.warn('ChatViewModel', `Failed to parse web_search args: ${JSON.stringify(e)}`)
              }
              onAIMessageUpdated(aiMessage)
              break
            }
          }

          // 执行工具调用
          const toolResults = await this.executeToolCallsWithSearchBudgets(
            toolCalls,
            aiMessage,
            this.buildAllowedToolFunctionNames(toolsForThisRound)
          )
          if (isCancelledFn()) {
            return
          }

          // 检查工具执行是否被取消
          if (this.hasCancelledToolResult(toolResults)) {
            console.info('ChatViewModel', 'Tool execution was cancelled')
            aiMessage.isGenerating = false
            onAIMessageUpdated(aiMessage)
            onComplete()
            this.toolExecutionService.clearCancelCheckCallback()
            return
          }

          // 保存工具结果到 AI 消息
          for (let i = 0; i < toolResults.length; i++) {
            aiMessage.toolResults.push(toolResults[i])
          }
          // 持久化工具事件到数据库（使用快照 sessionId）
          if (snapshotSession !== null) {
            for (let i = 0; i < toolCalls.length; i++) {
              if (isCancelledFn()) {
                return
              }
              const result = i < toolResults.length ? toolResults[i] : null
              const status = result !== null ? (result.isError ? 'failed' : 'completed') : 'pending'
              await this.databaseService.saveToolEvent(
                snapshotSessionId,
                aiMessage.id,
                toolCalls[i].id,
                toolCalls[i].functionName,
                toolCalls[i].displayName,
                toolCalls[i].sourceLabel,
                toolCalls[i].sourceType,
                toolCalls[i].permissionLevel,
                toolCalls[i].arguments,
                this.buildPersistedToolResult(
                  toolCalls[i].functionName,
                  result !== null ? result.content : ''
                ),
                status
              )
            }
          }

          // 处理搜索结果，提取引用
          for (let i = 0; i < toolCalls.length; i++) {
            if (this.isWebSearchFunction(toolCalls[i].functionName)) {
              const result = toolResults[i]
              try {
                const searchData = JSON.parse(result.content) as SearchResultData
                if (searchData.results !== undefined) {
                  if (searchData.query !== undefined && searchData.query !== '') {
                    aiMessage.searchQuery = searchData.query
                  }
                  aiMessage.searchEngine = searchData.searchEngine || 'Web'
                  aiMessage.searchSource = 'tool'
                  if (searchData.query !== undefined && searchData.query !== '') {
                    console.info('ChatViewModel', `[Function Calling] web_search result query="${searchData.query}"`)
                  }
                  for (let j = 0; j < searchData.results.length; j++) {
                    const item = searchData.results[j]
                    const ref = new SearchReference(
                      `ref_${Date.now()}_${j}`,
                      item.title,
                      item.url,
                      item.snippet
                    )
                    aiMessage.searchReferences.push(ref)
                  }
                }
              } catch (e) {
                console.warn('ChatViewModel', `Failed to parse search result: ${JSON.stringify(e)}`)
              }
              aiMessage.isSearching = false
              break
            }
          }
          onAIMessageUpdated(aiMessage)

          // 通知工具调用完成
          if (toolCallbacks !== undefined && toolCallbacks.onToolCallCompleted !== undefined) {
            toolCallbacks.onToolCallCompleted(toolResults)
          }

          // 构建下一轮请求消息
          const assistantMsg = RequestMessage.createAssistantWithToolCalls(aiMessage.content, toolCalls)
          assistantMsg.reasoningContent = toolContinuationReasoningContent
          requestMessages.push(assistantMsg)

          for (let i = 0; i < toolResults.length; i++) {
            const toolResultMsg = RequestMessage.createToolResultMessage(
              toolResults[i].toolCallId,
              toolResults[i].content
            )
            requestMessages.push(toolResultMsg)
          }

          // 清空 AI 消息内容，准备接收新的回复
          aiMessage.content = ''
          onAIMessageUpdated(aiMessage)

          // 继续下一轮
          await this.executeToolCallLoop(
            apiConfig,
            requestMessages,
            modelId,
            aiMessage,
            onAIMessageUpdated,
            onComplete,
            onError,
	            tools,
	            toolCallbacks,
	            reasoningLevel,
	            requestTemperature,
	            iteration + 1,
            snapshotSessionId,
            snapshotSession,
            shouldAutoGenerateTitle,
            requestId,
            isCancelledFn,
            isUserCancelledFn,
            isToolCancelledFn,
            setUserCancelled,
            getHasReceivedFirstChunk,
            setHasReceivedFirstChunk,
            localFirstChunkThrottle,
            localContentThrottle,
            localReasoningThrottle
          )
        } else {
          if (toolCalls.length > 0) {
            console.warn('ChatViewModel', `Ignored ${toolCalls.length} tool calls because tools are disabled in this round`)
          }
          // 没有工具调用，完成
          flushBufferedRoundOutput()
          await this.finalizeAIMessage(
            aiMessage,
            onAIMessageUpdated,
            onComplete,
            snapshotSessionId,
            snapshotSession,
            shouldAutoGenerateTitle,
            requestId
          )
        }
      },
      (error: string) => {
        if (isCancelledFn()) {
          return
        }
        localContentThrottle.flush((throttledContent: string) => {
          if (isCancelledFn()) {
            return
          }
          appendRoundContent(throttledContent)
        })
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (isCancelledFn()) {
            return
          }
          appendRoundReasoning(throttledReasoning)
        })
        localFirstChunkThrottle.flush((throttledContent: string) => {
          if (isCancelledFn()) {
            return
          }
          appendRoundContent(throttledContent)
        })
        flushBufferedRoundOutput()
        this.fillEmptyAIContentPlaceholder(aiMessage, error)
        aiMessage.isGenerating = false
        aiMessage.isSearching = false
        onAIMessageUpdated(aiMessage)

        if (isUserCancelledFn()) {
          setUserCancelled(false)
          console.info('ChatViewModel', 'Request cancelled by user')
          onComplete()
        } else {
          onError(error)
        }
        this.clearPendingAIMessageIfMatches(aiMessage.id)
        this.unregisterActiveRequest(requestId)
      },
	      requestTemperature,
      this.appStateManager.getDefaultMaxTokens(),
      (reasoningContent: string) => {
        if (isCancelledFn()) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (isCancelledFn()) {
            return
          }
          appendRoundReasoning(throttledContent)
        })
      },
      async (base64Data: string, mimeType: string) => {
        if (isCancelledFn()) {
          return
        }
        try {
          await this.saveAIGeneratedImage(base64Data, mimeType, aiMessage, onAIMessageUpdated)
        } catch (error) {
          console.error('ChatViewModel', `Failed to save AI generated image: ${JSON.stringify(error)}`)
        }
      },
      reasoningLevelForThisRound,
      toolsEnabledInThisRound ? toolsForThisRound : undefined,
      toolChoiceForThisRound,
      (toolCallDeltas: ToolCallDelta[]) => {
        if (isCancelledFn() || !toolsEnabledInThisRound || toolCallDeltas.length <= 0) {
          return
        }
        markCurrentRoundAsToolCall()
      }
    )

    // 更新活跃请求中的 httpRequest 引用（每轮循环可能创建新的 httpRequest）
    const existingInfo = this.activeRequests.get(requestId)
    if (existingInfo !== undefined) {
      existingInfo.httpRequest = httpRequest
    } else {
      this.registerActiveRequest(requestId, httpRequest, () => {
        // cancel 回调由 sendMessageWithTools 中注册的回调处理
      })
    }
  }

  // 根据 MIME 类型获取文件扩展名
  private getExtensionFromMimeType(mimeType: string): string {
    const mimeToExt: Record<string, string> = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'image/bmp': '.bmp',
      'image/svg+xml': '.svg'
    }
    return mimeToExt[mimeType] || '.png'
  }

  private isImageUrl(data: string): boolean {
    return data.startsWith('http://') || data.startsWith('https://')
  }

  private async downloadImageAsBase64(url: string): Promise<ImageDownloadResult> {
    const httpRequest = http.createHttp()
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 60000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      })
      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`)
      }

      const buffer = response.result as ArrayBuffer
      const bytes = new Uint8Array(buffer)
      const base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
      let base64 = ''
      for (let i = 0; i < bytes.length; i += 3) {
        const b0 = bytes[i]
        const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0
        const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0
        base64 += base64Chars.charAt(b0 >> 2)
        base64 += base64Chars.charAt(((b0 & 3) << 4) | (b1 >> 4))
        base64 += (i + 1 < bytes.length) ? base64Chars.charAt(((b1 & 15) << 2) | (b2 >> 6)) : '='
        base64 += (i + 2 < bytes.length) ? base64Chars.charAt(b2 & 63) : '='
      }

      let mimeType = 'image/png'
      const contentType = response.header?.['content-type'] as string | undefined
      if (contentType !== undefined && contentType !== '') {
        const semi = contentType.indexOf(';')
        mimeType = semi >= 0 ? contentType.substring(0, semi).trim() : contentType.trim()
      } else {
        const lowerUrl = url.toLowerCase()
        if (lowerUrl.includes('.jpg') || lowerUrl.includes('.jpeg')) {
          mimeType = 'image/jpeg'
        } else if (lowerUrl.includes('.webp')) {
          mimeType = 'image/webp'
        } else if (lowerUrl.includes('.gif')) {
          mimeType = 'image/gif'
        }
      }

      const result: ImageDownloadResult = { base64Data: base64, mimeType: mimeType }
      return result
    } finally {
      httpRequest.destroy()
    }
  }

  async saveAIGeneratedImage(
    imageData: string,
    mimeType: string,
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void
  ): Promise<void> {
    let finalBase64 = imageData
    let finalMimeType = mimeType

    if (this.isImageUrl(imageData)) {
      console.info('ChatViewModel', `Downloading image from URL: ${imageData.substring(0, 100)}...`)
      const downloaded = await this.downloadImageAsBase64(imageData)
      finalBase64 = downloaded.base64Data
      finalMimeType = downloaded.mimeType
    }

    console.info('ChatViewModel', `Saving AI generated image: ${finalMimeType}, size: ${finalBase64.length}`)

    const attachmentId = `ai_img_${Date.now()}`
    const ext = this.getExtensionFromMimeType(finalMimeType)
    const fileName = `generated_${Date.now()}${ext}`

    const attachment = new MessageAttachment(
      attachmentId,
      AttachmentType.IMAGE,
      fileName,
      '',
      finalMimeType,
      Math.floor(finalBase64.length * 0.75)
    )
    attachment.base64Data = finalBase64

    if (this.attachmentStorageService.isReady()) {
      const filePath = await this.attachmentStorageService.saveAttachment(attachment)
      attachment.filePath = filePath
      console.info('ChatViewModel', `AI generated image saved to: ${filePath}`)
    } else {
      console.warn('ChatViewModel', 'AttachmentStorageService not ready, image not persisted to file')
    }

    aiMessage.addAttachment(attachment)
    onAIMessageUpdated(aiMessage)
  }

  // 删除消息
  async deleteMessage(messageId: string): Promise<void> {
    await this.databaseService.deleteMessage(messageId)
    if (this.currentSession !== null) {
      const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageId)
      if (index >= 0) {
        this.currentSession.messages.splice(index, 1)
        this.currentSession.messageCount = Math.max(0, this.currentSession.messageCount - 1)
      }
    }
  }

  // 批量删除消息（用于重新生成功能）
  async deleteMessagesFromIndex(messageIds: string[]): Promise<void> {
    await this.databaseService.deleteMessagesByIds(messageIds)
    if (this.currentSession !== null) {
      // 从 currentSession.messages 中移除这些消息
      for (let i = 0; i < messageIds.length; i++) {
        this.clearPendingAIMessageIfMatches(messageIds[i])
        const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageIds[i])
        if (index >= 0) {
          this.currentSession.messages.splice(index, 1)
          this.currentSession.messageCount = Math.max(0, this.currentSession.messageCount - 1)
        }
      }
    }
  }

  // ============ 消息级对话树版本 ============

  // 计算某消息在其兄弟版本中的序号信息
  getMessageVersionInfo(message: ChatMessage): MessageVersionInfo {
    if (this.currentSession === null) {
      return { index: 0, count: 1 }
    }
    return getVersionInfo(this.currentSession.messages, message)
  }

  /**
   * 在指定消息的兄弟版本之间切换（delta=±1），返回切换后的新活跃路径。
   * 切换逻辑：选中目标兄弟 → 沿其子树最新分支走到叶子 → 更新 activeLeafId。
   */
  async switchMessageVersion(message: ChatMessage, delta: number): Promise<ChatMessage[] | null> {
    if (this.currentSession === null || delta === 0) {
      return null
    }
    const all = this.currentSession.messages
    const siblings = getSiblings(all, message)
    if (siblings.length <= 1) {
      return null
    }
    let currentIndex = 0
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i].id === message.id) {
        currentIndex = i
        break
      }
    }
    const targetIndex = currentIndex + delta
    if (targetIndex < 0 || targetIndex >= siblings.length) {
      return null
    }
    const targetSibling = siblings[targetIndex]
    const leaf = resolveLeafOfSubtree(all, targetSibling)
    this.currentSession.activeLeafId = leaf.id
    await this.databaseService.updateSessionActiveLeaf(this.currentSession.id, leaf.id)
    return computeActivePath(all, leaf.id)
  }

  /**
   * 删除某条消息及其整条子树（其全部后代）。
   * 删除后把活跃叶子修正到被删消息的父节点（若父节点存在），否则回退到时间线最后一条。
   * 返回删除后的新活跃路径。
   */
  async deleteMessageSubtree(message: ChatMessage): Promise<ChatMessage[] | null> {
    if (this.currentSession === null) {
      return null
    }
    const all = this.currentSession.messages
    const idsToDelete = collectSubtreeIds(all, message)
    if (idsToDelete.length === 0) {
      return null
    }
    await this.databaseService.deleteMessagesByIds(idsToDelete)
    const deleteSet = new Set<string>(idsToDelete)
    // 从内存移除
    for (let i = all.length - 1; i >= 0; i--) {
      if (deleteSet.has(all[i].id)) {
        this.clearPendingAIMessageIfMatches(all[i].id)
        all.splice(i, 1)
      }
    }
    this.currentSession.messageCount = all.length
    // 修正活跃叶子
    const parentId = message.parentId
    let newLeafId = ''
    if (parentId !== '') {
      const parentExists = all.some((m: ChatMessage) => m.id === parentId)
      if (parentExists) {
        newLeafId = parentId
      }
    }
    this.currentSession.activeLeafId = newLeafId
    await this.databaseService.updateSessionActiveLeaf(this.currentSession.id, newLeafId)
    return computeActivePath(all, this.currentSession.activeLeafId)
  }

  // 更新消息内容
  async updateMessageContent(messageId: string, content: string): Promise<void> {
    await this.databaseService.updateMessageContent(messageId, content)
    if (this.currentSession !== null) {
      const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageId)
      if (index >= 0) {
        this.currentSession.messages[index].content = content
      }
    }
  }

  async updateMessageTranslation(messageId: string, translatedText: string, translatedLang: string): Promise<void> {
    await this.databaseService.updateMessageTranslation(messageId, translatedText, translatedLang)
    if (this.currentSession !== null) {
      const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageId)
      if (index >= 0) {
        this.currentSession.messages[index].translatedText = translatedText
        this.currentSession.messages[index].translatedLang = translatedLang
      }
    }
  }

  // 更新消息内容和附件
  async updateMessageContentAndAttachments(
    messageId: string,
    content: string,
    attachments: MessageAttachment[]
  ): Promise<void> {
    // 更新数据库
    await this.databaseService.updateMessageContent(messageId, content)
    await this.databaseService.updateMessageAttachments(messageId, attachments)

    // 更新内存中的会话
    if (this.currentSession !== null) {
      const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageId)
      if (index >= 0) {
        this.currentSession.messages[index].content = content
        this.currentSession.messages[index].attachments = attachments.slice()
      }
    }
  }

  // 添加消息到数据库
  async addMessage(message: ChatMessage): Promise<void> {
    if (this.currentSession === null) {
      console.error('ChatViewModel', 'Cannot add message: no current session')
      return
    }
    await this.databaseService.addMessage(this.currentSession.id, message)
  }

  // 停止生成
  stopGeneration(): void {
    // 取消令牌前移：确保”仍在准备阶段的发送流程”也能被终止
    this.cancelToken = this.cancelToken + 1
    this.toolExecutionService.cancelAllPendingAskUserAnswers()

    // 停止前持久化所有待处理的 AI 消息
    this.persistPendingAIMessageIfNeeded()

    // 遍历所有活跃请求，调用取消回调并销毁 HTTP 请求
    this.activeRequests.forEach((info: ActiveRequestInfo) => {
      info.cancelCallback()
      try {
        info.httpRequest.destroy()
      } catch (e) {
        // ignore destroy errors
      }
    })
    this.activeRequests.clear()

    // 重置 AIApiService 的解析状态（MiniMax 缓冲区等）
    this.aiApiService.resetThinkingState()

    console.info('ChatViewModel', 'Generation stopped and all buffers reset')
  }

  // 检查是否有活跃的请求
  hasActiveRequest(): boolean {
    return this.activeRequests.size > 0
  }

  // 检查指定会话是否存在活跃请求（用于页面恢复后还原发送/停止按钮状态）
  hasActiveRequestForSession(sessionId: string): boolean {
    if (sessionId === '') {
      return false
    }
    let found = false
    this.pendingAIMessages.forEach((info: PendingAIMessageInfo) => {
      if (info.sessionId === sessionId && (info.message.isGenerating || info.message.isSearching)) {
        found = true
      }
    })
    return found
  }

  // 生成唯一ID
  private generateId(): string {
    return Date.now().toString() + Math.random().toString(36).substring(2, 9)
  }

  // 获取格式化的当前时间信息
  private getCurrentTimeContext(): string {
    return buildCurrentTimeContext()
  }

  private limitSearchContextForPrompt(content: string, maxChars: number): string {
    const trimmed = content.trim()
    if (trimmed.length <= maxChars) {
      return trimmed
    }
    return trimmed.substring(0, maxChars) + '\n\n[搜索上下文已截断]'
  }

  private isUrlLikeText(text: string): boolean {
    const trimmed = text.trim()
    if (trimmed === '' || /\s/.test(trimmed)) {
      return false
    }
    return /^https?:\/\/[^\s]+$/i.test(trimmed) ||
      /^[\w\-]+\.[\w\-]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=]*)?$/i.test(trimmed)
  }

  private buildSearchResultRequestContent(content: string, searchResult: SearchResult): string {
    if (this.isUrlLikeText(content) || this.isUrlLikeText(searchResult.query)) {
      const targetUrl = content.trim() !== '' ? content.trim() : searchResult.query.trim()
      if (this.isUrlFetchFailureContext(searchResult.contentForAI)) {
        return `请说明这个链接的读取结果：${targetUrl}`
      }
      return `请基于已抓取的网页内容分析这个链接：${targetUrl}`
    }
    return content
  }

  private isUrlFetchFailureContext(contentForAI: string): boolean {
    return contentForAI.includes('URL 读取结果:') && contentForAI.includes('状态: 失败')
  }

  private isWebSearchFunction(functionName: string): boolean {
    const raw = functionName as string | null | undefined
    if (raw === undefined || raw === null) {
      return false
    }
    const normalized = raw.trim().toLowerCase().replace(/[\s\-]+/g, '_')
    return normalized === 'web_search' || normalized === 'exa_search' || normalized === 'websearch'
      || normalized === 'search_web' || normalized === 'internet_search' || normalized === 'web_search_exa'
  }

  private isLyricsSearchQuery(text: string): boolean {
    const normalized = text.toLowerCase()
    return normalized.includes('歌词') || normalized.includes('lyric') || normalized.includes('lyrics')
      || normalized.includes('作词') || normalized.includes('作曲')
  }

  private normalizeLyricsTerm(text: string): string {
    return text
      .replace(/[“”"']/g, '')
      .replace(/(的)?(歌词|lyrics?|lyric|作词|作曲)/gi, '')
      .replace(/\s+/g, ' ')
      .trim()
  }

  private getLyricsCoreTerms(text: string): string[] {
    const terms: string[] = []
    const normalized = this.normalizeLyricsTerm(text)
    const byMatch = /^(.+?)\s+by\s+(.+)$/i.exec(normalized)
    if (byMatch && byMatch[1] !== undefined && byMatch[2] !== undefined) {
      const song = this.normalizeLyricsTerm(byMatch[1])
      const artist = this.normalizeLyricsTerm(byMatch[2])
      if (song !== '') {
        terms.push(song)
      }
      if (artist !== '') {
        terms.push(artist)
      }
      return terms
    }

    if (normalized.includes('太阳之子')) {
      terms.push('太阳之子')
    }
    if (normalized.includes('周杰伦')) {
      terms.push('周杰伦')
    }
    return terms
  }

  private shouldUseLatestLyricsQuery(candidateQuery: string, latestUserQuery: string): boolean {
    if (candidateQuery === '') {
      return true
    }
    if (candidateQuery.includes('site:') || candidateQuery.includes('"') || candidateQuery.includes('“')) {
      return false
    }

    const coreTerms = this.getLyricsCoreTerms(latestUserQuery)
    if (coreTerms.length === 0) {
      return false
    }

    const normalizedCandidate = this.normalizeLyricsTerm(candidateQuery)
    const compactCandidate = normalizedCandidate.replace(/\s+/g, '')
    if (compactCandidate.length <= 2) {
      return true
    }
    for (let i = 0; i < coreTerms.length; i++) {
      if (candidateQuery.includes(coreTerms[i])) {
        return false
      }
    }
    // 只在明显被模型截断成短片段时回退。像“方文山 黄俊郎”这类虽不含歌名/歌手、
    // 但属于模型主动换角度的关键词，应保留给工具真实搜索。
    return compactCandidate.length <= 4
  }

  private isObviouslyFragmentSearchQuery(query: string): boolean {
    const compact = query.replace(/\s+/g, '').trim()
    if (compact === '') {
      return true
    }
    if (/^[\u4e00-\u9fff]$/.test(compact)) {
      return true
    }
    return false
  }

  private getLatestUserQueryFromRequestMessages(requestMessages: RequestMessage[]): string {
    for (let i = requestMessages.length - 1; i >= 0; i--) {
      const msg = requestMessages[i]
      if (msg.role === 'user' && msg.content.trim() !== '') {
        return msg.content
      }
    }
    return ''
  }

  private resolveWebSearchArgsQuery(args: WebSearchArgs): string {
    const candidates: string[] = []
    if (args.url !== undefined) {
      candidates.push(args.url)
    }
    if (args.query !== undefined) {
      candidates.push(args.query)
    }
    if (args.q !== undefined) {
      candidates.push(args.q)
    }
    if (args.keywords !== undefined) {
      candidates.push(args.keywords)
    }
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i].trim()
      if (candidate !== '') {
        return candidate
      }
    }
    return ''
  }

  private resolveWebSearchArgsPage(args: WebSearchArgs): number {
    if (args.page === undefined) {
      return 0
    }
    if (typeof args.page === 'number') {
      return args.page > 0 ? args.page : 0
    }
    const parsed = Number(args.page)
    if (Number.isNaN(parsed) || parsed <= 0) {
      return 0
    }
    return parsed
  }

  private normalizeWebSearchToolCallQuery(toolCall: ToolCall, latestUserQuery: string): string {
    let parsedQuery = ''
    let parsedPage = 0
    try {
      const args = JSON.parse(toolCall.arguments) as WebSearchArgs
      parsedQuery = this.cleanSearchQuery(this.resolveWebSearchArgsQuery(args))
      parsedPage = this.resolveWebSearchArgsPage(args)
    } catch (error) {
      parsedQuery = ''
      console.warn('ChatViewModel', `Failed to parse search tool args before normalize: ${JSON.stringify(error)}`)
    }

    let finalQuery = parsedQuery
    if (latestUserQuery !== '') {
      finalQuery = normalizeOptimizedSearchQuery(latestUserQuery, parsedQuery)
      if (!this.isObviouslyFragmentSearchQuery(parsedQuery) && this.isLyricsSearchQuery(latestUserQuery) &&
        this.shouldUseLatestLyricsQuery(parsedQuery, latestUserQuery)) {
        finalQuery = this.cleanSearchQuery(latestUserQuery)
      }
    }
    if (latestUserQuery !== '') {
      finalQuery = this.normalizeRelativeTimeForSearchQuery(latestUserQuery, finalQuery)
    }
    if (finalQuery === '' && latestUserQuery !== '') {
      finalQuery = this.cleanSearchQuery(latestUserQuery)
    }

    toolCall.functionName = 'web_search'
    if (parsedPage > 0) {
      toolCall.arguments = JSON.stringify({ query: finalQuery, page: parsedPage })
    } else {
      toolCall.arguments = JSON.stringify({ query: finalQuery })
    }
    return finalQuery
  }

  // 简单清洗搜索查询（去除口语化前缀、多余空格）
  cleanSearchQuery(query: string): string {
    return cleanSearchQueryShared(query)
  }

  normalizeRelativeTimeForSearchQuery(userQuery: string, candidateQuery: string): string {
    return normalizeRelativeTimeForSearchQueryShared(userQuery, candidateQuery)
  }

  private isWeatherIntent(text: string): boolean {
    const t = text.replace(/\s+/g, '')
    const keywords: string[] = [
      '天气', '天气预报', '气温', '温度', '降雨', '降水', '湿度', '风速', '风力', '空气质量', 'AQI', 'PM2.5'
    ]
    for (let i = 0; i < keywords.length; i++) {
      if (t.includes(keywords[i])) {
        return true
      }
    }
    return false
  }

  private isTravelIntent(text: string): boolean {
    const t = text.replace(/\s+/g, '')
    const keywords: string[] = [
      '旅游', '攻略', '自由行', '景点', '美食', '酒店', '住宿', '行程', '路线', 'CityWalk', 'City Walk'
    ]
    for (let i = 0; i < keywords.length; i++) {
      if (t.includes(keywords[i])) {
        return true
      }
    }
    return false
  }

  // 清洗模型输出：取第一行、去掉前缀/引号，保证可直接用于搜索
  private cleanOptimizedSearchQuery(text: string): string {
    let cleaned = text.trim()
    const lines = cleaned.split(/\r?\n/)
    cleaned = ''
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line !== '') {
        cleaned = line
        break
      }
    }
    if (cleaned === '') {
      return ''
    }

    cleaned = cleaned.replace(/^(优化后的(?:搜索)?关键词|搜索关键词|关键词|search query)\s*[:：]\s*/i, '')
    cleaned = cleaned.replace(/^[\"“'‘]+/, '').replace(/[\"”'’]+$/, '')
    return cleaned.trim()
  }

  private isOptimizedQueryAcceptable(userQuery: string, optimizedQuery: string): boolean {
    // 防止模型输出过长或跑题；必要时直接回退到用户原始输入
    if (optimizedQuery.trim() === '') {
      return false
    }
    if (optimizedQuery.length > 80) {
      return false
    }
    // 若用户明确问“天气/气温”等，优化结果也必须保持同一意图
    if (this.isWeatherIntent(userQuery) && !this.isWeatherIntent(optimizedQuery)) {
      return false
    }
    // 避免把“天气”等明确意图误改写为“旅游攻略”等
    if (this.isWeatherIntent(userQuery) && !this.isTravelIntent(userQuery) && this.isTravelIntent(optimizedQuery)) {
      return false
    }
    return true
  }

  // 优化搜索查询关键词：在调用搜索服务之前，将口语化输入改写为更适合检索的关键词
  async optimizeSearchQuery(
    userQuery: string,
    recentMessages: ChatMessage[],
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    customHeadersJson?: string
  ): Promise<string> {
    try {
      const cleanedUserQuery = this.cleanSearchQuery(userQuery)

      // 构建上下文（最近3条消息）
      let context = ''
      const contextMessages = recentMessages.slice(-3)
      for (let i = 0; i < contextMessages.length; i++) {
        const msg = contextMessages[i]
        context += `${msg.role === MessageRole.USER ? '用户' : 'AI'}: ${msg.content}\n`
      }

      const currentTime = this.getCurrentTimeContext()

      // 构建优化提示
      const systemPrompt = `你是一个“搜索关键词优化助手”。你的任务是将用户的口语化查询转换为适合搜索引擎的关键词。

规则（非常重要）:
1. 只做轻量优化：去口语化/补全指代/补全时间，不要改变用户意图，不要引入无关主题
2. 必须保留用户查询中的关键实体/地点/产品名/主题词（例如：天气/价格/汇率/新闻/教程等）
3. 如用户查询本身已是关键词（例如“西安天气”），直接原样输出
4. 解析指代词（如“那里”“这个”），结合对话历史替换为具体内容
5. 将相对时间（如“今天”“现在”）转换为具体日期
6. 输出要求：只输出“一行”关键词；不要解释、不要加引号、不要加序号或前缀

当前时间: ${currentTime}

对话历史:
${context !== '' ? context : '(无历史对话)'}

用户查询: ${cleanedUserQuery}

请直接输出优化后的搜索关键词:`

      console.info('ChatViewModel', `[关键词优化] 原始查询: ${userQuery}`)

      const apiConfig: AIApiConfig = {
        providerId: providerId,
        providerType: providerType,
        apiStyle: apiStyle,
        apiKey: apiKey,
        baseUrl: baseUrl,
        openaiTransport: this.getOpenAITransportForProvider(providerId),
        customHeadersJson: customHeadersJson
      }

      const messages: RequestMessage[] = [
        new RequestMessage('system', systemPrompt),
        new RequestMessage('user', cleanedUserQuery)
      ]

      // 使用非流式请求获取优化后的关键词
      const result = await this.aiApiService.sendChatRequest(apiConfig, messages, modelId, 0.3, 200)

      if (result.success && result.content.trim() !== '') {
        const optimized = this.cleanOptimizedSearchQuery(result.content)
        const normalizedOptimized = normalizeOptimizedSearchQuery(cleanedUserQuery, optimized)
        if (!this.isOptimizedQueryAcceptable(cleanedUserQuery, normalizedOptimized)) {
          console.warn('ChatViewModel', `[关键词优化] 结果不可靠,回退原始查询. 原始: ${cleanedUserQuery}, 优化: ${optimized}`)
          return cleanedUserQuery
        }
        const finalQuery = this.cleanSearchQuery(normalizedOptimized)
        console.info('ChatViewModel', `[关键词优化] 优化后查询: ${finalQuery}`)
        return finalQuery !== '' ? finalQuery : cleanedUserQuery
      }

      console.warn('ChatViewModel', `[关键词优化] 优化失败,使用原始查询: ${result.errorMessage}`)
      return cleanedUserQuery
    } catch (error) {
      console.error('ChatViewModel', `[关键词优化] 异常: ${JSON.stringify(error)}`)
      return this.cleanSearchQuery(userQuery)
    }
  }

  // 设置标题生成回调
  setTitleCallbacks(callbacks: TitleGenerationCallbacks | null): void {
    this.titleCallbacks = callbacks
  }

  // 生成智能标题（带重试机制）
  private async generateSmartTitle(session: ChatSession, retryCount: number = 0): Promise<void> {
    // 通知开始生成
    if (this.titleCallbacks !== null && this.titleCallbacks.onTitleGenerating !== undefined) {
      this.titleCallbacks.onTitleGenerating(true)
    }

    try {
      // 构建对话内容
      let content = ''
      for (let i = 0; i < session.messages.length; i++) {
        const msg = session.messages[i]
        content += `${msg.role}: ${msg.content}\n`
      }

      // 调用 AI 任务服务生成标题（自动检测语言）
      const title = await this.aiTaskService.generateTitle(content)
      if (title !== '' && this.currentSession !== null && this.currentSession.id === session.id) {
        this.currentSession.title = title
        await this.databaseService.updateSessionTitle(this.currentSession.id, title)
        this.notifySessionListChanged()
        console.info('ChatViewModel', 'Smart title generated: ' + title)

        // 通知标题更新成功
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleUpdated !== undefined) {
          this.titleCallbacks.onTitleUpdated(title)
        }
      } else if (title === '') {
        // 生成失败（配置问题或 API 返回空），通知失败
        console.warn('ChatViewModel', 'Title generation returned empty string')
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleFailed !== undefined) {
          this.titleCallbacks.onTitleFailed()
        }
      }

      // 通知生成结束
      if (this.titleCallbacks !== null && this.titleCallbacks.onTitleGenerating !== undefined) {
        this.titleCallbacks.onTitleGenerating(false)
      }
    } catch (error) {
      console.error('ChatViewModel', 'Failed to generate smart title: ' + JSON.stringify(error))

      // 检查是否可以重试（网络错误等可重试，配置错误不重试）
      const errorStr = JSON.stringify(error)
      const isConfigError = errorStr.includes('API Key') || errorStr.includes('未配置') || errorStr.includes('not configured')

      if (!isConfigError && retryCount < this.MAX_TITLE_RETRY) {
        // 指数退避重试：2秒、4秒、8秒
        const delayMs = Math.pow(2, retryCount + 1) * 1000
        console.info('ChatViewModel', `Retrying title generation in ${delayMs}ms (attempt ${retryCount + 1}/${this.MAX_TITLE_RETRY})`)

        setTimeout(() => {
          this.generateSmartTitle(session, retryCount + 1)
        }, delayMs)
      } else {
        // 重试次数用尽或配置错误，通知失败
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleGenerating !== undefined) {
          this.titleCallbacks.onTitleGenerating(false)
        }
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleFailed !== undefined) {
          this.titleCallbacks.onTitleFailed()
        }
      }
    }
  }

  // 手动重新生成标题
  async regenerateTitle(): Promise<void> {
    if (this.currentSession === null) {
      return
    }
    if (this.currentSession.messages.length === 0) {
      console.warn('ChatViewModel', 'Cannot generate title: no messages in session')
      return
    }
    await this.generateSmartTitle(this.currentSession, 0)
  }

  // 手动更新会话标题
  async updateSessionTitle(title: string): Promise<void> {
    const updated = await this.sessionStore.updateCurrentSessionTitle(title)
    this.currentSession = this.sessionStore.getCurrentSession()
    if (!updated) {
      return
    }

    // 通知标题更新
    if (this.titleCallbacks !== null && this.titleCallbacks.onTitleUpdated !== undefined) {
      this.titleCallbacks.onTitleUpdated(title)
    }
  }

  // 获取当前会话标题
  getCurrentSessionTitle(): string {
    return this.sessionStore.getCurrentSessionTitle()
  }

  // 获取当前模型的参数配置
  private getCurrentModelParameters(providerId: string, modelId: string): ModelParameters | null {
    const provider = this.providerViewModel.getProviderById(providerId)
    if (provider === null) {
      return null
    }

    for (let i = 0; i < provider.models.length; i++) {
      if (provider.models[i].id === modelId) {
        return provider.models[i].parameters
      }
    }

    return null
  }

  private getCurrentModelReasoningStrategyOverride(providerId: string, modelId: string): string {
    const provider = this.providerViewModel.getProviderById(providerId)
    if (provider === null) {
      return ''
    }

    for (let i = 0; i < provider.models.length; i++) {
      if (provider.models[i].id === modelId) {
        if (!provider.models[i].capabilities.supportsReasoning) {
          return ''
        }
        return provider.models[i].reasoningStrategyOverride
      }
    }

    return ''
  }

  private getCurrentModelSupportsReasoning(providerId: string, modelId: string): boolean {
    const provider = this.providerViewModel.getProviderById(providerId)
    if (provider === null) {
      return false
    }

    for (let i = 0; i < provider.models.length; i++) {
      if (provider.models[i].id === modelId) {
        return provider.models[i].capabilities.supportsReasoning
      }
    }

    return false
  }

  // 懒加载历史附件（从后向前扫描，只加载最后 N 条用户消息的附件）
  private async prepareHistoryAttachments(messages: RequestMessage[]): Promise<void> {
    let loadedCount = 0
    let totalSize = 0

    // 从后向前扫描，只加载最后 N 条用户消息的附件
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i]
      if (msg.role === 'user' && msg.attachments.length > 0) {
        if (loadedCount >= this.MAX_HISTORY_ATTACHMENTS) {
          break
        }

        for (let j = 0; j < msg.attachments.length; j++) {
          const att = msg.attachments[j]
          if (att.base64Data !== '') {
            continue
          }

          const estimatedSize = att.size > 0 ? att.size : (1024 * 1024)
          if (totalSize + estimatedSize > this.MAX_HISTORY_ATTACHMENT_SIZE) {
            console.warn('ChatViewModel', `Attachment size limit reached, skipping ${att.id}`)
            continue
          }

          if (await this.ensureAttachmentBase64Data(att)) {
            totalSize += estimatedSize
          }
        }
        loadedCount++
      }
    }

    console.info('ChatViewModel', `Prepared history attachments: ${loadedCount} messages, ${totalSize} bytes`)
  }
}

let chatViewModelInstance: ChatViewModel | null = null

// 导出创建实例方法
export function createChatViewModel(): ChatViewModel {
  if (chatViewModelInstance === null) {
    chatViewModelInstance = new ChatViewModel()
  }
  return chatViewModelInstance
}
